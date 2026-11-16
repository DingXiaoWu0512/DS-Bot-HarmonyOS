// Noise IK with the fixed suite Noise_IK_25519_ChaChaPoly_SHA256, matching the
// computer's clatterjs handshake byte for byte:
//
//   pre-message:  <- s
//   message 1:    -> e, es, s, ss   (32 + 48 + payload + 16 bytes)
//   message 2:    <- e, ee, se      (32 + payload + 16 bytes)
//   transport:    split() into two ChaChaPoly states, nonces from 0.
//
// The phone always initiates; the responder side exists for the interop tests.
import { sha256, hkdf2 } from '../sha256.ts'
import { x25519, x25519PublicKey } from '../x25519.ts'
import { chacha20Poly1305Encrypt, chacha20Poly1305Decrypt, randomBytes } from '../chacha20poly1305.ts'
import { concatBytes, fromBase64Url, utf8Encode } from '../bytes.ts'

export const NOISE_IK_PROTOCOL = 'Noise_IK_25519_ChaChaPoly_SHA256'

/** Everything the handshake needs: both static keys are base64url strings. */
export interface NoiseIkSessionOptions {
  role: 'initiator' | 'responder'
  localPrivateKey: string
  localPublicKey: string
  remotePublicKey: string
  /** Binds the handshake to one connection; from createNoisePrologue. */
  prologue: Uint8Array
}

export class NoiseSessionError extends Error {
  readonly code: string

  constructor(code: string, message: string) {
    super(message)
    this.code = code
  }
}

interface CipherState {
  key: Uint8Array
  nonce: number
}

// The protocol name is exactly 32 bytes, so per the Noise spec it seeds ck and h
// directly, without hashing.
function protocolNameBytes(): Uint8Array {
  const bytes = utf8Encode(NOISE_IK_PROTOCOL)
  if (bytes.byteLength !== 32) throw new NoiseSessionError('NOISE_SUITE_MISMATCH', 'The Noise protocol name is not 32 bytes.')
  return bytes
}

function nonceBytes(value: number): Uint8Array {
  // Noise: bytes 0..3 are zero and the 32-bit counter is little-endian in bytes 4..7.
  const bytes = new Uint8Array(12)
  bytes[4] = value & 0xff
  bytes[5] = (value >>> 8) & 0xff
  bytes[6] = (value >>> 16) & 0xff
  bytes[7] = (value >>> 24) & 0xff
  return bytes
}

function mixHash(h: Uint8Array, data: Uint8Array): Uint8Array {
  return sha256(h, data)
}

function mixKey(chainingKey: Uint8Array, shared: Uint8Array): { ck: Uint8Array; k: Uint8Array } {
  const [ck, k] = hkdf2(chainingKey, shared)
  return { ck, k }
}

function requireKey32(value: string, label: string): Uint8Array {
  const bytes = fromBase64Url(value)
  if (bytes.byteLength !== 32) throw new NoiseSessionError('INVALID_KEY', `${label} must be a 32-byte X25519 key.`)
  return bytes
}

/** A Noise IK handshake and its two transport ciphers, in one class. */
export class NoiseIkSession {
  private h: Uint8Array
  private ck: Uint8Array
  private k: CipherState | null = null
  private sendState: CipherState | null = null
  private recvState: CipherState | null = null
  private readonly initiator: boolean
  private readonly localPrivate: Uint8Array
  private readonly localPublic: Uint8Array
  private readonly remoteStatic: Uint8Array
  private ePrivate: Uint8Array | null = null
  private handshakeDone = false
  private steps = 0
  private destroyed = false

  constructor(options: NoiseIkSessionOptions) {
    this.initiator = options.role === 'initiator'
    this.localPrivate = requireKey32(options.localPrivateKey, 'local private key')
    this.localPublic = requireKey32(options.localPublicKey, 'local public key')
    this.remoteStatic = requireKey32(options.remotePublicKey, 'remote public key')
    this.h = protocolNameBytes()
    this.ck = this.h.slice()
    // The prologue, then the pre-message <- s: the responder's static key.
    this.h = mixHash(this.h, options.prologue)
    this.h = mixHash(this.h, this.initiator ? this.remoteStatic : this.localPublic)
  }

  get complete(): boolean {
    return this.handshakeDone
  }

  /** True when the next handshake step is a write (message 1 for the initiator). */
  get isWriteTurn(): boolean {
    if (this.handshakeDone) return false
    return this.initiator ? this.steps === 0 : this.steps === 1
  }

  writeHandshake(payload: Uint8Array): Uint8Array {
    this.assertHandshake(false)
    if (!this.initiator) {
      // Responder message 2: e, ee, se, then the encrypted payload.
      const ePrivate = randomBytes(32)
      const ePublic = x25519PublicKey(ePrivate)
      this.ePrivate = ePrivate
      this.h = mixHash(this.h, ePublic)
      this.mixDh(ePrivate, this.ePublicSeen!) // ee
      this.mixDh(ePrivate, this.remoteStatic) // se: responder ephemeral × initiator static
      const body = this.encryptAndHash(payload)
      this.finish()
      this.steps = 2
      return concatBytes(ePublic, body)
    }
    // Initiator message 1: e, es, s, ss, then the encrypted hello.
    const ePrivate = randomBytes(32)
    const ePublic = x25519PublicKey(ePrivate)
    this.ePrivate = ePrivate
    this.h = mixHash(this.h, ePublic)
    this.mixDh(ePrivate, this.remoteStatic) // es
    const sBody = this.encryptAndHash(this.localPublic) // s (48 bytes)
    this.mixDh(this.localPrivate, this.remoteStatic) // ss
    const helloBody = this.encryptAndHash(payload)
    this.steps = 1
    return concatBytes(ePublic, sBody, helloBody)
  }

  readHandshake(message: Uint8Array): Uint8Array {
    this.assertHandshake(true)
    if (this.initiator) {
      // Message 2: e (32), encrypted payload.
      if (message.byteLength < 32) throw new NoiseSessionError('NOISE_SHORT_MESSAGE', 'The handshake message is too short.')
      const re = message.subarray(0, 32)
      this.h = mixHash(this.h, re)
      this.mixDh(this.ePrivate!, re) // ee
      this.mixDh(this.localPrivate, re) // se
      const plain = this.decryptAndHash(message.subarray(32))
      this.finish()
      this.steps = 2
      return plain
    }
    // Responder reads message 1: e (32), s+tag (48), encrypted hello.
    if (message.byteLength < 80) throw new NoiseSessionError('NOISE_SHORT_MESSAGE', 'The handshake message is too short.')
    const re = message.subarray(0, 32)
    this.ePublicSeen = re.slice()
    this.h = mixHash(this.h, re)
    this.mixDh(this.localPrivate, re) // es
    const sBody = message.subarray(32, 80)
    const sPlain = this.decryptAndHash(sBody)
    if (sPlain.byteLength !== 32) throw new NoiseSessionError('PEER_IDENTITY_MISMATCH', 'The peer static key is malformed.')
    const remoteStatic = sPlain.slice()
    if (!constantTimeEqual(remoteStatic, this.remoteStatic)) {
      this.destroy()
      throw new NoiseSessionError('PEER_IDENTITY_MISMATCH', 'The peer key does not match the paired key.')
    }
    this.mixDh(this.localPrivate, remoteStatic) // ss
    this.steps = 1
    return this.decryptAndHash(message.subarray(80))
  }

  encrypt(plaintext: Uint8Array): Uint8Array {
    if (!this.complete || this.sendState === null) throw new NoiseSessionError('NOISE_NOT_READY', 'The Noise handshake is not complete.')
    return encryptWithAd(this.sendState, new Uint8Array(0), plaintext)
  }

  decrypt(ciphertext: Uint8Array): Uint8Array {
    if (!this.complete || this.recvState === null) throw new NoiseSessionError('NOISE_NOT_READY', 'The Noise handshake is not complete.')
    return decryptWithAd(this.recvState, new Uint8Array(0), ciphertext)
  }

  destroy(): void {
    this.destroyed = true
    this.k = null
    this.sendState = null
    this.recvState = null
  }

  private ePublicSeen: Uint8Array | null = null

  private mixDh(localPrivate: Uint8Array, remotePublic: Uint8Array): void {
    const shared = x25519(localPrivate, remotePublic)
    const next = mixKey(this.ck, shared)
    this.ck = next.ck
    this.k = { key: next.k, nonce: 0 }
  }

  private encryptAndHash(plaintext: Uint8Array): Uint8Array {
    if (this.k === null) throw new NoiseSessionError('NOISE_NOT_READY', 'The handshake has no key yet.')
    const body = encryptWithAd(this.k, this.h, plaintext)
    this.h = mixHash(this.h, body)
    return body
  }

  private decryptAndHash(body: Uint8Array): Uint8Array {
    if (this.k === null) throw new NoiseSessionError('NOISE_NOT_READY', 'The handshake has no key yet.')
    const plain = decryptWithAd(this.k, this.h, body)
    this.h = mixHash(this.h, body)
    return plain
  }

  private finish(): void {
    const [c1, c2] = hkdf2(this.ck, new Uint8Array(0))
    this.sendState = { key: this.initiator ? c1 : c2, nonce: 0 }
    this.recvState = { key: this.initiator ? c2 : c1, nonce: 0 }
    this.k = null
    this.handshakeDone = true
  }

  private assertHandshake(reading: boolean): void {
    if (this.destroyed) throw new NoiseSessionError('NOISE_DESTROYED', 'The Noise session is closed.')
    if (this.handshakeDone) throw new NoiseSessionError('NOISE_ALREADY_READY', 'The Noise handshake is already complete.')
    // The initiator writes then reads; the responder reads then writes.
    const expectRead = this.initiator ? this.steps === 1 : this.steps === 0
    if (reading !== expectRead) throw new NoiseSessionError('NOISE_HANDSHAKE_ORDER', 'The Noise handshake message arrived out of order.')
  }
}

function encryptWithAd(state: CipherState, ad: Uint8Array, plaintext: Uint8Array): Uint8Array {
  const body = chacha20Poly1305Encrypt(state.key, nonceBytes(state.nonce), ad, plaintext)
  state.nonce += 1
  return body
}

function decryptWithAd(state: CipherState, ad: Uint8Array, ciphertext: Uint8Array): Uint8Array {
  const plain = chacha20Poly1305Decrypt(state.key, nonceBytes(state.nonce), ad, ciphertext)
  state.nonce += 1
  return plain
}

function constantTimeEqual(left: Uint8Array, right: Uint8Array): boolean {
  if (left.byteLength !== right.byteLength) return false
  let different = 0
  for (let index = 0; index < left.byteLength; index += 1) different |= left[index]! ^ right[index]!
  return different === 0
}

/** Binds the handshake to one connection between two known devices. */
export function createNoisePrologue(connectionId: string, hostDeviceId: string, clientDeviceId: string): Uint8Array {
  for (const value of [connectionId, hostDeviceId, clientDeviceId]) {
    if (value.length === 0 || value.includes('\0')) throw new TypeError('A Noise prologue part is empty or contains NUL')
  }
  return utf8Encode(`DS-BOT-LINK\0v=1\0connection=${connectionId}\0host=${hostDeviceId}\0client=${clientDeviceId}`)
}
