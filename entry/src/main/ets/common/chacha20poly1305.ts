// ChaCha20-Poly1305 (RFC 8439), hand-written so the Noise channel needs no
// platform cipher. The Node tests run the RFC test vectors and cross-check
// against @noble/ciphers.

const ROTL = (x: number, n: number): number => ((x << n) | (x >>> (32 - n))) | 0

function quarterRound(s: Int32Array, a: number, b: number, c: number, d: number): void {
  s[a] = (s[a]! + s[b]!) | 0; s[d] = ROTL(s[d]! ^ s[a]!, 16)
  s[c] = (s[c]! + s[d]!) | 0; s[b] = ROTL(s[b]! ^ s[c]!, 12)
  s[a] = (s[a]! + s[b]!) | 0; s[d] = ROTL(s[d]! ^ s[a]!, 8)
  s[c] = (s[c]! + s[d]!) | 0; s[b] = ROTL(s[b]! ^ s[c]!, 7)
}

function chachaBlock(state: Int32Array, out: Uint8Array, outOffset: number): void {
  const x = new Int32Array(16)
  for (let i = 0; i < 16; i++) x[i] = state[i]!
  for (let round = 0; round < 10; round++) {
    quarterRound(x, 0, 4, 8, 12)
    quarterRound(x, 1, 5, 9, 13)
    quarterRound(x, 2, 6, 10, 14)
    quarterRound(x, 3, 7, 11, 15)
    quarterRound(x, 0, 5, 10, 15)
    quarterRound(x, 1, 6, 11, 12)
    quarterRound(x, 2, 7, 8, 13)
    quarterRound(x, 3, 4, 9, 14)
  }
  for (let i = 0; i < 16; i++) {
    const mixed = (x[i]! + state[i]!) | 0
    out[outOffset + i * 4] = mixed & 0xff
    out[outOffset + i * 4 + 1] = (mixed >>> 8) & 0xff
    out[outOffset + i * 4 + 2] = (mixed >>> 16) & 0xff
    out[outOffset + i * 4 + 3] = (mixed >>> 24) & 0xff
  }
}

function readInt(bytes: Uint8Array, at: number): number {
  return (bytes[at]! | (bytes[at + 1]! << 8) | (bytes[at + 2]! << 16) | (bytes[at + 3]! << 24)) | 0
}

function initState(key: Uint8Array, nonce: Uint8Array, counter: number): Int32Array {
  const state = new Int32Array(16)
  state[0] = 0x61707865; state[1] = 0x3320646e; state[2] = 0x79622d32; state[3] = 0x6b206574
  for (let i = 0; i < 8; i++) state[4 + i] = readInt(key, i * 4)
  state[12] = counter | 0
  state[13] = readInt(nonce, 0)
  state[14] = readInt(nonce, 4)
  state[15] = readInt(nonce, 8)
  return state
}

export function chacha20(key: Uint8Array, nonce: Uint8Array, counter: number, data: Uint8Array): Uint8Array {
  const out = new Uint8Array(data.byteLength)
  const state = initState(key, nonce, counter)
  let at = 0
  while (at < data.byteLength) {
    const block = new Uint8Array(64)
    chachaBlock(state, block, 0)
    const take = Math.min(64, data.byteLength - at)
    for (let i = 0; i < take; i++) out[at + i] = data[at + i]! ^ block[i]!
    at += take
    state[12] = (state[12]! + 1) | 0
  }
  return out
}

// AEAD mac (RFC 8439 section 2.8): mac data is AAD | zero-pad16 | ciphertext |
// zero-pad16 | len64(AAD) | len64(CT), and every 16-byte block — including a
// zero-padded remainder — carries the 2^128 pad bit. Worked out on plain
// little-endian BigInts; the Node tests cross-check every path against noble.
const P130 = (1n << 130n) - 5n

function leInt(bytes: Uint8Array, at: number, length: number): bigint {
  let value = 0n
  for (let i = length - 1; i >= 0; i--) value = (value << 8n) | BigInt(bytes[at + i] ?? 0)
  return value
}

function poly1305(polyKey: Uint8Array, aad: Uint8Array, ciphertext: Uint8Array): Uint8Array {
  const r = leInt(polyKey, 0, 16)
    & 0x0ffffffc0ffffffc0ffffffc0fffffffn
  let h = 0n
  const absorb = (data: Uint8Array, at: number, length: number): void => {
    const padded = length === 16 ? data : data  // caller zero-pads; see feedPadded
    void padded
    h = ((h + leInt(data, at, length) + (1n << 128n)) * r) % P130
  }
  const feedPadded = (data: Uint8Array): void => {
    const rest = data.byteLength % 16
    if (rest === 0) {
      for (let at = 0; at < data.byteLength; at += 16) absorb(data, at, 16)
      return
    }
    const padded = new Uint8Array(data.byteLength + (16 - rest))
    padded.set(data, 0)
    for (let at = 0; at < padded.byteLength; at += 16) absorb(padded, at, 16)
  }
  feedPadded(aad)
  feedPadded(ciphertext)
  const lens = new Uint8Array(16)
  // RFC 8439: both lengths are 64-bit little-endian.
  const aadLen = BigInt(aad.byteLength)
  const ctLen = BigInt(ciphertext.byteLength)
  for (let i = 0; i < 8; i++) {
    lens[i] = Number((aadLen >> BigInt(8 * i)) & 255n)
    lens[8 + i] = Number((ctLen >> BigInt(8 * i)) & 255n)
  }
  absorb(lens, 0, 16)
  const s = leInt(polyKey, 16, 16)
  let tag = (h + s) & ((1n << 128n) - 1n)
  const out = new Uint8Array(16)
  for (let i = 0; i < 16; i++) { out[i] = Number(tag & 255n); tag >>= 8n }
  return out
}

export function chacha20Poly1305Encrypt(key: Uint8Array, nonce: Uint8Array, aad: Uint8Array, plaintext: Uint8Array): Uint8Array {
  const cipher = chacha20(key, nonce, 1, plaintext)
  const polyKey = chacha20(key, nonce, 0, new Uint8Array(32))
  const tag = poly1305(polyKey, aad, cipher)
  const out = new Uint8Array(cipher.byteLength + 16)
  out.set(cipher, 0)
  out.set(tag, cipher.byteLength)
  return out
}

export function chacha20Poly1305Decrypt(key: Uint8Array, nonce: Uint8Array, aad: Uint8Array, ciphertext: Uint8Array): Uint8Array {
  if (ciphertext.byteLength < 16) throw new Error('The encrypted message is too short')
  const body = ciphertext.subarray(0, ciphertext.byteLength - 16)
  const tag = ciphertext.subarray(ciphertext.byteLength - 16)
  const polyKey = chacha20(key, nonce, 0, new Uint8Array(32))
  const expected = poly1305(polyKey, aad, body)
  let diff = 0
  for (let i = 0; i < 16; i++) diff |= expected[i]! ^ tag[i]!
  if (diff !== 0) throw new Error('The message could not be decrypted: the tag does not match')
  return chacha20(key, nonce, 1, body).slice()
}

// One-time random source, filled by the platform layer at startup and by the
// tests with a deterministic source.
export interface RandomSource {
  fill(bytes: Uint8Array): void
}

let source: RandomSource = { fill: () => { throw new Error('No random source was installed') } }

export function installRandom(next: RandomSource): void {
  source = next
}

export function randomBytes(length: number): Uint8Array {
  // Zero-length asks never reach the platform RNG — cryptoFramework's
  // generateRandomSync rejects them with "generateRandom failed!".
  if (length <= 0) return new Uint8Array(0)
  const bytes = new Uint8Array(length)
  source.fill(bytes)
  return bytes
}

export function randomUuid(): string {
  const bytes = randomBytes(16)
  bytes[6] = (bytes[6]! & 0x0f) | 0x40
  bytes[8] = (bytes[8]! & 0x3f) | 0x80
  const hex = Array.from(bytes, byte => byte.toString(16).padStart(2, '0')).join('')
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`
}
