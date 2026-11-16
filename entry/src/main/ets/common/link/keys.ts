// DS Bot link protocol keys: X25519 identity pairs, device ids, fingerprints.
// Port of link/src/keys.ts with the platform base64/atob replaced.
import { sha256 } from '../sha256.ts'
import { x25519PublicKey } from '../x25519.ts'
import { randomBytes, installRandom, type RandomSource } from '../chacha20poly1305.ts'
import { toBase64Url, fromBase64Url } from '../bytes.ts'

export interface KeyPair {
  publicKey: string
  privateKey: string
}

export function generateKeyPair(privateKeyBytes?: Uint8Array): KeyPair {
  const privateKey = privateKeyBytes ?? randomBytes(32)
  if (privateKey.byteLength !== 32) throw new Error('X25519 private keys must be 32 bytes')
  return {
    privateKey: toBase64Url(privateKey),
    publicKey: toBase64Url(x25519PublicKey(privateKey)),
  }
}

/** Short code both screens show at pairing, so the user can see they hold the same key. */
export function identityFingerprint(publicKey: string): string {
  return Array.from(sha256(fromBase64Url(publicKey)).slice(0, 6), byte => byte.toString(16).padStart(2, '0'))
    .join('')
    .toUpperCase()
}

/** A device's id is derived from its identity key, so the Server can check one against the other. */
export function deviceIdFor(publicKey: string): string {
  const key = fromBase64Url(publicKey)
  if (key.byteLength !== 32) throw new Error('X25519 public keys must be 32 bytes')
  return `d-${toBase64Url(sha256(key).slice(0, 16))}`
}

export function randomToken(bytes = 32): string {
  return toBase64Url(randomBytes(bytes))
}

export { installRandom, type RandomSource, toBase64Url, fromBase64Url }
