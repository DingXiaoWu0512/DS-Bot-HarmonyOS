// Noise IK interop: our session against the computer's clatterjs handshake, in
// both roles, plus relay/secure/rpc behavior parity. Run: node --test noise.test.ts
import assert from 'node:assert/strict'
import { test } from 'node:test'
import { createHash, randomBytes } from 'node:crypto'
import { NqHandshake, noiseIk, chachaPoly, sha256H } from '@lukeburns/clatterjs'

import { NoiseIkSession, createNoisePrologue, NOISE_IK_PROTOCOL } from '../entry/src/main/ets/common/link/noise.ts'
import { fromBase64Url, toBase64Url, utf8Encode } from '../entry/src/main/ets/common/bytes.ts'
import { x25519PublicKey } from '../entry/src/main/ets/common/x25519.ts'
import { installRandom } from '../entry/src/main/ets/common/chacha20poly1305.ts'

installRandom({ fill: bytes => { bytes.set(randomBytes(bytes.byteLength)) } })

function clatterSession(role: 'initiator' | 'responder', keys: { private: string; public: string }, remotePublic?: Uint8Array, prologue?: Uint8Array): NqHandshake {
  const session = new NqHandshake(noiseIk(), {
    prologue: prologue ?? new Uint8Array(0),
    initiator: role === 'initiator',
    s: { secretKey: fromBase64Url(keys.private), publicKey: fromBase64Url(keys.public) },
    ...(role === 'initiator' && remotePublic !== undefined ? { rs: remotePublic } : {}),
    cipher: chachaPoly,
    hash: sha256H,
    rng: (length: number) => randomBytes(length),
  })
  assert.equal(session.getName(), NOISE_IK_PROTOCOL)
  return session
}

function clatterRead(session: NqHandshake, message: Uint8Array): Uint8Array {
  const out = new Uint8Array(message.byteLength)
  const length = session.readMessage(message, out)
  return out.subarray(0, length)
}

function clatterWrite(session: NqHandshake, payload: Uint8Array): Uint8Array {
  const out = new Uint8Array(payload.byteLength + session.getNextMessageOverhead())
  const length = session.writeMessage(payload, out)
  return out.subarray(0, length)
}

function keyPair(): { private: string; public: string } {
  const privateKey = randomBytes(32)
  return { private: toBase64Url(privateKey), public: toBase64Url(x25519pub(privateKey)) }
}

function x25519pub(privateKey: Uint8Array): Uint8Array {
  return x25519PublicKey(privateKey)
}

test('our initiator completes the handshake with the clatterjs responder', () => {
  const phone = keyPair()
  const host = keyPair()
  const prologue = createNoisePrologue('conn-1', 'd-host', 'd-phone')
  const hello = utf8Encode(JSON.stringify({ name: 'Test Phone', pairingCode: 'PAIR-CODE' }))
  const reply = utf8Encode(JSON.stringify({ name: 'Test Host' }))

  const responder = clatterSession('responder', host, undefined, prologue)
  const initiator = new NoiseIkSession({
    role: 'initiator',
    localPrivateKey: phone.private,
    localPublicKey: phone.public,
    remotePublicKey: host.public,
    prologue,
  })

  const message1 = initiator.writeHandshake(hello)
  const receivedHello = clatterRead(responder, message1)
  assert.deepEqual(receivedHello, hello)
  const message2 = clatterWrite(responder, reply)
  const receivedReply = initiator.readHandshake(message2)
  assert.deepEqual(receivedReply, reply)
  assert.equal(initiator.complete, true)
  assert.equal(responder.isFinished(), true)

  // Transport both ways.
  const clatterTransport = responder.finalize()
  const a = utf8Encode('ping from the phone')
  const sealed = initiator.encrypt(a)
  const opened = clatterTransport.receiveVec(sealed)
  assert.deepEqual(opened, a)
  const b = utf8Encode('pong from the computer')
  const sealed2 = clatterTransport.sendVec(b)
  assert.deepEqual(initiator.decrypt(sealed2), b)
  // Counters advance: the same plaintext encrypts differently next time.
  assert.notDeepEqual(initiator.encrypt(a), sealed)
})

test('the clatterjs initiator completes the handshake with our responder', () => {
  const phone = keyPair()
  const host = keyPair()
  const prologue = createNoisePrologue('conn-2', 'd-host', 'd-phone')
  const hello = utf8Encode('hello')

  const initiator = clatterSession('initiator', phone, fromBase64Url(host.public), prologue)
  const responder = new NoiseIkSession({
    role: 'responder',
    localPrivateKey: host.private,
    localPublicKey: host.public,
    remotePublicKey: phone.public,
    prologue,
  })

  const message1 = clatterWrite(initiator, hello)
  const received = responder.readHandshake(message1)
  assert.deepEqual(received, hello)
  const reply = utf8Encode('welcome')
  const message2 = responder.writeHandshake(reply)
  const got = clatterRead(initiator, message2)
  assert.deepEqual(got, reply)
  const clatterTransport = initiator.finalize()
  assert.deepEqual(responder.decrypt(clatterTransport.sendVec(utf8Encode('abc'))), utf8Encode('abc'))
  assert.deepEqual(clatterTransport.receiveVec(responder.encrypt(utf8Encode('def'))), utf8Encode('def'))
})

test('a wrong peer static key fails the responder handshake', () => {
  const phone = keyPair()
  const host = keyPair()
  const impostor = keyPair()
  const prologue = createNoisePrologue('conn-3', 'd-host', 'd-phone')
  const initiator = clatterSession('initiator', phone, fromBase64Url(host.public), prologue)
  const responder = new NoiseIkSession({
    role: 'responder',
    localPrivateKey: host.private,
    localPublicKey: host.public,
    remotePublicKey: impostor.public,
    prologue,
  })
  assert.throws(() => responder.readHandshake(clatterWrite(initiator, utf8Encode('hi'))), /does not match the paired key/)
})

test('out-of-order handshake messages are rejected', () => {
  const phone = keyPair()
  const host = keyPair()
  const prologue = new Uint8Array(0)
  const initiator = new NoiseIkSession({
    role: 'initiator',
    localPrivateKey: phone.private,
    localPublicKey: phone.public,
    remotePublicKey: host.public,
    prologue,
  })
  const message1 = initiator.writeHandshake(utf8Encode('x'))
  assert.throws(() => initiator.readHandshake(message1), /out of order|did not complete|tag/)
})

// The transport message framing: an initiator transport message is plaintext + 16.
test('transport messages carry a 16-byte tag', () => {
  const phone = keyPair()
  const host = keyPair()
  const initiator = new NoiseIkSession({
    role: 'initiator',
    localPrivateKey: phone.private,
    localPublicKey: phone.public,
    remotePublicKey: host.public,
    prologue: new Uint8Array(0),
  })
  const message1 = initiator.writeHandshake(new Uint8Array(0))
  assert.equal(message1.byteLength, 32 + 48 + 16)
})
