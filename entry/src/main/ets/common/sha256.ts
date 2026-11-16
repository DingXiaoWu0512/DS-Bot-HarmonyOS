// SHA-256 (FIPS 180-4), HMAC-SHA256 and HKDF, hand-written so the Noise
// handshake stays synchronous and byte-identical on every platform. The Node
// tests check every one against the standard library.

const K = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
]

const rotr = (x: number, n: number): number => (x >>> n) | (x << (32 - n))

export function sha256(...chunks: Uint8Array[]): Uint8Array {
  let total = 0
  for (const chunk of chunks) total += chunk.byteLength
  const padded = new Uint8Array(((total + 9 + 63) >> 6) << 6)
  let at = 0
  for (const chunk of chunks) { padded.set(chunk, at); at += chunk.byteLength }
  padded[at] = 0x80
  const bits = total * 8
  const view = padded
  // The 64-bit big-endian bit length sits in the last eight bytes.
  const last = padded.byteLength - 4
  view[last] = (bits >>> 24) & 0xff
  view[last + 1] = (bits >>> 16) & 0xff
  view[last + 2] = (bits >>> 8) & 0xff
  view[last + 3] = bits & 0xff
  let h0 = 0x6a09e667, h1 = 0xbb67ae85, h2 = 0x3c6ef372, h3 = 0xa54ff53a
  let h4 = 0x510e527f, h5 = 0x9b05688c, h6 = 0x1f83d9ab, h7 = 0x5be0cd19
  const w = new Int32Array(64)
  for (let block = 0; block < padded.byteLength; block += 64) {
    for (let i = 0; i < 16; i++) {
      const j = block + i * 4
      w[i] = (view[j]! << 24) | (view[j + 1]! << 16) | (view[j + 2]! << 8) | view[j + 3]!
    }
    for (let i = 16; i < 64; i++) {
      const s0 = rotr(w[i - 15]!, 7) ^ rotr(w[i - 15]!, 18) ^ (w[i - 15]! >>> 3)
      const s1 = rotr(w[i - 2]!, 17) ^ rotr(w[i - 2]!, 19) ^ (w[i - 2]! >>> 10)
      w[i] = (w[i - 16]! + s0 + w[i - 7]! + s1) | 0
    }
    let a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, hh = h7
    for (let i = 0; i < 64; i++) {
      const s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
      const ch = (e & f) ^ (~e & g)
      const t1 = (hh + s1 + ch + K[i]! + w[i]!) | 0
      const s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
      const maj = (a & b) ^ (a & c) ^ (b & c)
      const t2 = (s0 + maj) | 0
      hh = g; g = f; f = e
      e = (d + t1) | 0
      d = c; c = b; b = a
      a = (t1 + t2) | 0
    }
    h0 = (h0 + a) | 0; h1 = (h1 + b) | 0; h2 = (h2 + c) | 0; h3 = (h3 + d) | 0
    h4 = (h4 + e) | 0; h5 = (h5 + f) | 0; h6 = (h6 + g) | 0; h7 = (h7 + hh) | 0
  }
  const out = new Uint8Array(32)
  const hs = [h0, h1, h2, h3, h4, h5, h6, h7]
  for (let i = 0; i < 8; i++) {
    out[i * 4] = (hs[i]! >>> 24) & 0xff
    out[i * 4 + 1] = (hs[i]! >>> 16) & 0xff
    out[i * 4 + 2] = (hs[i]! >>> 8) & 0xff
    out[i * 4 + 3] = hs[i]! & 0xff
  }
  return out
}

export function hmacSha256(key: Uint8Array, ...chunks: Uint8Array[]): Uint8Array {
  let block = key
  if (block.byteLength > 64) block = sha256(block)
  const ipad = new Uint8Array(64)
  const opad = new Uint8Array(64)
  for (let i = 0; i < 64; i++) {
    const byte = i < block.byteLength ? block[i]! : 0
    ipad[i] = byte ^ 0x36
    opad[i] = byte ^ 0x5c
  }
  return sha256(opad, sha256(ipad, ...chunks))
}

const ALREADY = new Uint8Array(0)

// Noise's HKDF: HMAC(chainingKey, input) is the salt of the expansion, and the
// chaining key itself is the first output. Two or three 32-byte outputs.
export function hkdf2(chainingKey: Uint8Array, input: Uint8Array): [Uint8Array, Uint8Array] {
  const tempKey = hmacSha256(chainingKey, input)
  const one = hmacSha256(tempKey, ALREADY, new Uint8Array([0x01]))
  const two = hmacSha256(tempKey, one, new Uint8Array([0x02]))
  return [one, two]
}

export function hkdf3(chainingKey: Uint8Array, input: Uint8Array): [Uint8Array, Uint8Array, Uint8Array] {
  const tempKey = hmacSha256(chainingKey, input)
  const one = hmacSha256(tempKey, ALREADY, new Uint8Array([0x01]))
  const two = hmacSha256(tempKey, one, new Uint8Array([0x02]))
  const three = hmacSha256(tempKey, two, new Uint8Array([0x03]))
  return [one, two, three]
}
