// The full-stack integration test: the real Relay Server and HostLink from the
// DS Bot repo, with this port's RelayTransport → SecureTransport → RpcClient as
// the phone. Pairing goes through the same pairing code the computer would show.
import assert from 'node:assert/strict'
import { test } from 'node:test'
import { WebSocket as WsClient } from 'ws'
import { randomBytes as nodeRandom } from 'node:crypto'

import { startRelayServer } from '../../DS-Bot/link/server/server.ts'
import { HostLink } from '../../DS-Bot/link/src/host.ts'
import { DeviceRegistry, parsePairingUri, pairingUri } from '../../DS-Bot/link/src/pairing.ts'
import { deviceIdFor, generateKeyPair, randomToken } from '../../DS-Bot/link/src/keys.ts'

import { installSocketFactory, type RelaySocket } from '../entry/src/main/ets/common/link/transport.ts'
import { RelayTransport } from '../entry/src/main/ets/common/link/relay-transport.ts'
import { SecureTransport } from '../entry/src/main/ets/common/link/secure-transport.ts'
import { RpcClient } from '../entry/src/main/ets/common/link/rpc-client.ts'
import { installRandom } from '../entry/src/main/ets/common/chacha20poly1305.ts'

installRandom({ fill: bytes => { bytes.set(nodeRandom(bytes.byteLength)) } })

// The phone's WebSocket, made from Node's ws.
class PhoneSocket implements RelaySocket {
  readonly socket: WsClient
  readonly handlers = {
    open: new Set<() => void>(),
    message: new Set<(data: string) => void>(),
    error: new Set<() => void>(),
    close: new Set<() => void>(),
  }
  bufferedAmount = 0
  readyState = 0

  constructor(url: string) {
    this.socket = new WsClient(url)
    this.socket.on('open', () => { this.readyState = 1; for (const cb of this.handlers.open) cb() })
    this.socket.on('message', data => { for (const cb of this.handlers.message) cb(String(data)) })
    this.socket.on('error', () => { for (const cb of this.handlers.error) cb() })
    this.socket.on('close', () => { this.readyState = 3; for (const cb of this.handlers.close) cb() })
  }

  open(): void {}
  sendText(text: string): void { this.socket.send(text) }
  close(): void { this.socket.close() }
  onOpen(cb: () => void): () => void { this.handlers.open.add(cb); return () => this.handlers.open.delete(cb) }
  onMessage(cb: (data: string) => void): () => void { this.handlers.message.add(cb); return () => this.handlers.message.delete(cb) }
  onError(cb: () => void): () => void { this.handlers.error.add(cb); return () => this.handlers.error.delete(cb) }
  onClose(cb: () => void): () => void { this.handlers.close.add(cb); return () => this.handlers.close.delete(cb) }
}

installSocketFactory(url => new PhoneSocket(url))

test('phone links to the real computer stack end to end', { timeout: 20_000 }, async () => {
  const server = await startRelayServer()
  try {
    const hostIdentity = generateKeyPair()
    const host = {
      deviceId: deviceIdFor(hostIdentity.publicKey),
      publicKey: hostIdentity.publicKey,
      privateKey: hostIdentity.privateKey,
    }
    const phoneIdentity = generateKeyPair()
    const phone = {
      deviceId: deviceIdFor(phoneIdentity.publicKey),
      publicKey: phoneIdentity.publicKey,
      privateKey: phoneIdentity.privateKey,
      accessToken: randomToken(),
    }

    const registry = new DeviceRegistry()
    const handled: string[] = []
    const link = new HostLink({
      url: server.url,
      identity: host,
      accessToken: randomToken(),
      name: 'Test Computer',
      admits: (deviceId, identityKey) => registry.admits(deviceId, identityKey),
      authorize: (deviceId, identityKey, hello) => registry.authorize(deviceId, identityKey, hello),
      handle: async method => {
        handled.push(method)
        return { method, done: true }
      },
      createSocket: url => new WsClient(url) as unknown as WebSocket,
      retryMs: [50, 200],
    })
    link.start()
    await link.waitOnline()

    // The computer shows a pairing code; the phone scans it.
    const { code } = registry.openPairing()
    const offer = parsePairingUri(pairingUri({
      server: server.url,
      hostDeviceId: host.deviceId,
      hostKey: host.publicKey,
      code,
      name: 'Test Computer',
    }))

    const relay = new RelayTransport(offer.server, {
      deviceId: phone.deviceId,
      identityKey: phone.publicKey,
      accessToken: phone.accessToken,
      targetDeviceId: offer.hostDeviceId,
      handshakeTimeoutMs: 5_000,
    })
    const secure = new SecureTransport(relay, phone, {
      deviceId: offer.hostDeviceId,
      identityKey: offer.hostKey,
    }, { hello: { name: 'HarmonyOS Phone', pairingCode: offer.code }, handshakeTimeoutMs: 5_000 })
    const client = new RpcClient(secure, 5_000)
    await client.connect()

    assert.equal(secure.hostHello()?.name, 'Test Computer')
    const answer = await client.rpc<{ method: string; done: boolean }>('bot', { endpoint: 'ping', payload: {} })
    assert.equal(answer.method, 'bot')
    assert.equal(answer.done, true)
    assert.ok(handled.includes('bot'))
    // A big payload crosses the fragmented secure channel both ways.
    const big = 'z'.repeat(300_000)
    assert.deepEqual(await client.rpc('bot', { endpoint: 'big', payload: { big } }), { method: 'bot', done: true })

    await client.close()
    await link.stop()
  } finally {
    await server.close()
  }
})
