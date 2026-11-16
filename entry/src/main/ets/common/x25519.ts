// X25519 (RFC 7748) on BigInt, with the division-free reduction mod 2^255-19
// that keeps the handshake fast. Keygen, public key and shared secret match
// @noble/curves — the Node tests prove it key by key.

const P = (1n << 255n) - 19n
const BASE = 9n
const A24 = 121665n

function reduce(x: bigint): bigint {
  let v = x
  // 2^255 ≡ 19 (mod p), so the part above bit 255 folds back with weight 19.
  while (v >= P) {
    const hi = v >> 255n
    v = (v & ((1n << 255n) - 1n)) + 19n * hi
    if (v >= P) v -= P
  }
  return v
}

function mul(a: bigint, b: bigint): bigint {
  return reduce(a * b)
}

function add(a: bigint, b: bigint): bigint {
  return reduce(a + b)
}

function sub(a: bigint, b: bigint): bigint {
  return reduce(a - b)
}

function powVet(value: bigint, exponent: bigint): bigint {
  let result = 1n
  let base = value
  let e = exponent
  while (e > 0n) {
    if ((e & 1n) === 1n) result = mul(result, base)
    base = mul(base, base)
    e >>= 1n
  }
  return result
}

function inverse(value: bigint): bigint {
  // p-2, by Fermat's little theorem.
  return powVet(value, P - 2n)
}

function decodeScalar(bytes: Uint8Array): bigint {
  if (bytes.byteLength !== 32) throw new Error('X25519 private keys must be 32 bytes')
  const copy = new Uint8Array(bytes)
  copy[0] = copy[0]! & 248
  copy[31] = (copy[31]! & 127) | 64
  let value = 0n
  for (let i = 31; i >= 0; i--) value = (value << 8n) | BigInt(copy[i]!)
  return value
}

function decodePoint(bytes: Uint8Array): bigint {
  if (bytes.byteLength !== 32) throw new Error('X25519 public keys must be 32 bytes')
  const copy = new Uint8Array(bytes)
  copy[31] = copy[31]! & 127 // The top bit is masked on the way in, like the RFC says.
  let value = 0n
  for (let i = 31; i >= 0; i--) value = (value << 8n) | BigInt(copy[i]!)
  return value
}

function encodePoint(value: bigint): Uint8Array {
  const out = new Uint8Array(32)
  let v = value
  for (let i = 0; i < 32; i++) {
    out[i] = Number(v & 255n)
    v >>= 8n
  }
  return out
}

// RFC 7748 section 5: the Montgomery ladder, one swap per secret bit.
function ladder(scalar: bigint, point: bigint): bigint {
  const x1 = point
  let x2 = 1n, z2 = 0n, x3 = point, z3 = 1n
  let swap = 0n
  for (let t = 254; t >= 0; t--) {
    const kT = (scalar >> BigInt(t)) & 1n
    swap ^= kT
    if (swap === 1n) {
      const tx = x2; x2 = x3; x3 = tx
      const tz = z2; z2 = z3; z3 = tz
    }
    swap = kT
    const a = add(x2, z2)
    const aa = mul(a, a)
    const b = sub(x2, z2)
    const bb = mul(b, b)
    const e = sub(aa, bb)
    const c = add(x3, z3)
    const d = sub(x3, z3)
    const da = mul(d, a)
    const cb = mul(c, b)
    x3 = mul(add(da, cb), add(da, cb))
    z3 = mul(x1, mul(sub(da, cb), sub(da, cb)))
    x2 = mul(aa, bb)
    z2 = mul(e, add(aa, mul(A24, e)))
  }
  if (swap === 1n) {
    const tx = x2; x2 = x3; x3 = tx
    const tz = z2; z2 = z3; z3 = tz
  }
  return mul(x2, inverse(z2))
}

export function x25519(privateKeyBytes: Uint8Array, publicKeyBytes: Uint8Array): Uint8Array {
  const scalar = decodeScalar(privateKeyBytes)
  const point = decodePoint(publicKeyBytes)
  const out = ladder(scalar, point)
  if (out === 0n) throw new Error('X25519 gave an all-zero shared secret')
  return encodePoint(out)
}

// The private key arrives as random bytes (clamped inside); the public one is
// the scalar times the base point.
export function x25519PublicKey(privateKeyBytes: Uint8Array): Uint8Array {
  const scalar = decodeScalar(privateKeyBytes)
  return encodePoint(ladder(scalar, BASE))
}
