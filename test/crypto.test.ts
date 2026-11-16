// Crypto primitive tests: our hand-written SHA-256/HMAC/X25519/ChaCha20-Poly1305
// against RFC vectors and @noble. Run: node --test crypto.test.ts
import assert from 'node:assert/strict'
import { test } from 'node:test'
import { createHash, createHmac, randomBytes } from 'node:crypto'
import { x25519 as nobleX25519 } from '@noble/curves/ed25519.js'
import { chacha20poly1305 as nobleChacha } from '@noble/ciphers/chacha.js'

import { sha256, hmacSha256, hkdf2, hkdf3 } from '../entry/src/main/ets/common/sha256.ts'
import { x25519, x25519PublicKey } from '../entry/src/main/ets/common/x25519.ts'
import { chacha20Poly1305Encrypt, chacha20Poly1305Decrypt, installRandom } from '../entry/src/main/ets/common/chacha20poly1305.ts'
import { toHex, toBase64Url, fromBase64Url, fromHex, utf8Encode, utf8Decode, toBase64, fromBase64 } from '../entry/src/main/ets/common/bytes.ts'

installRandom({ fill: bytes => { const r = randomBytes(bytes.byteLength); bytes.set(r) } })

test('sha256 matches node crypto', () => {
  for (const text of ['', 'abc', 'DS-BOT-LINK\0v=1\0connection=1', 'x'.repeat(200), '中文字符串测试']) {
    assert.equal(toHex(sha256(utf8Encode(text))), createHash('sha256').update(text).digest('hex'))
  }
  // Multi-chunk equals one-shot.
  const a = randomBytes(100), b = randomBytes(50)
  assert.equal(toHex(sha256(a, b)), createHash('sha256').update(a).update(b).digest('hex'))
})

test('hmacSha256 matches node crypto', () => {
  const cases: string[][] = [['key', 'hello'], ['x'.repeat(100), 'long key'], ['中', '文']]
  for (const pair of cases) {
    const key = pair[0]!
    const text = pair[1]!
    assert.equal(
      toHex(hmacSha256(utf8Encode(key), utf8Encode(text))),
      createHmac('sha256', utf8Encode(key)).update(text).digest('hex'),
    )
  }
})

test('hkdf2/hkdf3 match RFC 5869 vectors', () => {
  const ikm = fromHex('0b'.repeat(22))
  const salt = fromHex('000102030405060708090a0b0c')
  const info = fromHex('f0f1f2f3f4f5f6f7f8f9')
  // PRK = HMAC-SHA256(salt, ikm); T1/T2 with the chaining key = salt's HMAC.
  const prk = createHmac('sha256', salt).update(ikm).digest()
  const t1 = createHmac('sha256', prk).update(Buffer.from([1])).digest()
  const t2 = createHmac('sha256', prk).update(Buffer.concat([t1, Buffer.from([2])])).digest()
  const t3 = createHmac('sha256', prk).update(Buffer.concat([t2, Buffer.from([3])])).digest()
  assert.deepEqual(hkdf2(salt, ikm), [new Uint8Array(t1), new Uint8Array(t2)])
  assert.deepEqual(hkdf3(salt, ikm), [new Uint8Array(t1), new Uint8Array(t2), new Uint8Array(t3)])
})

test('x25519 matches RFC 7748 vectors', () => {
  const alicePriv = fromHex('77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a')
  const bobPriv = fromHex('5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb')
  const alicePub = fromHex('8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a')
  const bobPub = fromHex('de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f')
  const shared = fromHex('4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742')
  assert.equal(toHex(x25519PublicKey(alicePriv)), toHex(alicePub))
  assert.equal(toHex(x25519PublicKey(bobPriv)), toHex(bobPub))
  assert.equal(toHex(x25519(alicePriv, bobPub)), toHex(shared))
  assert.equal(toHex(x25519(bobPriv, alicePub)), toHex(shared))
  assert.deepEqual(nobleX25519.getPublicKey(alicePriv), x25519PublicKey(alicePriv))
})

test('x25519 keygen and DH match noble on random keys', () => {
  for (let i = 0; i < 20; i++) {
    const priv = randomBytes(32)
    const pub = x25519PublicKey(priv)
    assert.equal(toHex(pub), toHex(nobleX25519.getPublicKey(priv)))
    const peer = randomBytes(32)
    const peerPub = nobleX25519.getPublicKey(peer)
    assert.equal(toHex(x25519(priv, peerPub)), toHex(nobleX25519.scalarMult(peer, pub)))
  }
})

test('chacha20-poly1305 matches RFC 8439 section 2.8.2', () => {
  const key = fromHex('808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f')
  const nonce = fromHex('070000004041424344454647')
  const aad = fromHex('50515253c0c1c2c3c4c5c6c7')
  const plaintext = utf8Encode("Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it.")
  const out = chacha20Poly1305Encrypt(key, nonce, aad, plaintext)
  assert.equal(toHex(out.subarray(out.byteLength - 16)), '1ae10b594f09e26a7e902ecbd0600691')
  assert.deepEqual(chacha20Poly1305Decrypt(key, nonce, aad, out), plaintext)
})

test('chacha20-poly1305 matches noble on random inputs', () => {
  for (let i = 0; i < 30; i++) {
    const key = randomBytes(32)
    const nonce = randomBytes(12)
    const aad = randomBytes(i * 7 % 40)
    const text = randomBytes(i === 0 ? 100_000 : (i * 133) % 3000)
    const sealed = nobleChacha(key, nonce, aad).encrypt(text)
    assert.equal(toHex(chacha20Poly1305Decrypt(key, nonce, aad, sealed)), toHex(text))
    const ours = chacha20Poly1305Encrypt(key, nonce, aad, text)
    assert.equal(toHex(ours), toHex(sealed))
    const broken = ours.slice()
    broken[0] = (broken[0]! ^ 1)
    assert.throws(() => chacha20Poly1305Decrypt(key, nonce, aad, broken))
  }
})

test('base64 and base64url round trip', () => {
  for (let len = 0; len < 70; len++) {
    const bytes = randomBytes(len)
    assert.deepEqual(fromBase64(toBase64(bytes)), new Uint8Array(bytes))
    assert.deepEqual(fromBase64Url(toBase64Url(bytes)), new Uint8Array(bytes))
  }
  assert.equal(toBase64Url(fromHex('fbff')), '-_8')
  assert.deepEqual(fromBase64Url('-_8'), fromHex('fbff'))
})

test('utf8 round trips surrogate pairs', () => {
  for (const text of ['', 'hello', '你好，世界 🐋', 'emoji 👨‍👩‍👧‍👦 mix éè']) {
    assert.equal(utf8Decode(utf8Encode(text)), text)
  }
  assert.equal(toHex(utf8Encode('€')), 'e282ac')
})
