// Byte helpers the link protocol needs. Everything here is platform-neutral:
// the same file runs in the ArkTS runtime and in Node for the interop tests.

export function utf8Encode(text: string): Uint8Array {
  const out: number[] = []
  for (let i = 0; i < text.length; i++) {
    let code = text.charCodeAt(i)
    if (code >= 0xd800 && code <= 0xdbff && i + 1 < text.length) {
      const next = text.charCodeAt(i + 1)
      if (next >= 0xdc00 && next <= 0xdfff) {
        code = 0x10000 + ((code - 0xd800) << 10) + (next - 0xdc00)
        i++
      }
    }
    if (code < 0x80) out.push(code)
    else if (code < 0x800) out.push(0xc0 | (code >> 6), 0x80 | (code & 0x3f))
    else if (code < 0x10000) out.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f))
    else out.push(0xf0 | (code >> 18), 0x80 | ((code >> 12) & 0x3f), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f))
  }
  return new Uint8Array(out)
}

export function utf8Decode(bytes: Uint8Array): string {
  let out = ''
  let i = 0
  while (i < bytes.length) {
    const b = bytes[i]!
    let code: number
    if (b < 0x80) { code = b; i += 1 }
    else if (b < 0xe0) { code = ((b & 0x1f) << 6) | (bytes[i + 1]! & 0x3f); i += 2 }
    else if (b < 0xf0) { code = ((b & 0x0f) << 12) | ((bytes[i + 1]! & 0x3f) << 6) | (bytes[i + 2]! & 0x3f); i += 3 }
    else {
      code = ((b & 0x07) << 18) | ((bytes[i + 1]! & 0x3f) << 12) | ((bytes[i + 2]! & 0x3f) << 6) | (bytes[i + 3]! & 0x3f)
      i += 4
    }
    if (code >= 0x10000) {
      code -= 0x10000
      out += String.fromCharCode(0xd800 + (code >> 10), 0xdc00 + (code & 0x3ff))
    } else out += String.fromCharCode(code)
  }
  return out
}

const B64_ALPHA = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

export function toBase64(bytes: Uint8Array): string {
  let out = ''
  let i = 0
  for (; i + 3 <= bytes.length; i += 3) {
    const n = (bytes[i]! << 16) | (bytes[i + 1]! << 8) | bytes[i + 2]!
    out += B64_ALPHA[(n >> 18) & 63] + B64_ALPHA[(n >> 12) & 63] + B64_ALPHA[(n >> 6) & 63] + B64_ALPHA[n & 63]
  }
  const rest = bytes.length - i
  if (rest === 1) {
    const n = bytes[i]! << 16
    out += B64_ALPHA[(n >> 18) & 63] + B64_ALPHA[(n >> 12) & 63] + '=='
  } else if (rest === 2) {
    const n = (bytes[i]! << 16) | (bytes[i + 1]! << 8)
    out += B64_ALPHA[(n >> 18) & 63] + B64_ALPHA[(n >> 12) & 63] + B64_ALPHA[(n >> 6) & 63] + '='
  }
  return out
}

function b64Index(char: string): number {
  const code = char.charCodeAt(0)
  if (code >= 65 && code <= 90) return code - 65
  if (code >= 97 && code <= 122) return code - 97 + 26
  if (code >= 48 && code <= 57) return code - 48 + 52
  if (char === '+') return 62
  if (char === '/') return 63
  return -1
}

export function fromBase64(value: string): Uint8Array {
  const clean = value.replace(/[\r\n\s]/g, '')
  const out: number[] = []
  let buffer = 0
  let bits = 0
  for (let i = 0; i < clean.length; i++) {
    const ch = clean.charAt(i)
    if (ch === '=' || ch === '-') continue
    const v = b64Index(ch)
    if (v < 0) throw new Error('invalid base64')
    buffer = (buffer << 6) | v
    bits += 6
    if (bits >= 8) {
      bits -= 8
      out.push((buffer >> bits) & 0xff)
    }
  }
  return new Uint8Array(out)
}

export function toBase64Url(bytes: Uint8Array): string {
  return toBase64(bytes).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '')
}

export function fromBase64Url(value: string): Uint8Array {
  const normalized = value.replaceAll('-', '+').replaceAll('_', '/')
  const padded = normalized + '='.repeat((4 - (normalized.length % 4)) % 4)
  return fromBase64(padded)
}

export function toHex(bytes: Uint8Array): string {
  let out = ''
  for (const byte of bytes) out += byte.toString(16).padStart(2, '0')
  return out
}

export function fromHex(value: string): Uint8Array {
  const out = new Uint8Array(Math.floor(value.length / 2))
  for (let i = 0; i < out.length; i++) out[i] = parseInt(value.slice(i * 2, i * 2 + 2), 16)
  return out
}

export function bytesEqual(left: Uint8Array, right: Uint8Array): boolean {
  if (left.byteLength !== right.byteLength) return false
  let different = 0
  for (let i = 0; i < left.byteLength; i++) different |= left[i]! ^ right[i]!
  return different === 0
}

export function concatBytes(...parts: Uint8Array[]): Uint8Array {
  let total = 0
  for (const part of parts) total += part.byteLength
  const out = new Uint8Array(total)
  let at = 0
  for (const part of parts) { out.set(part, at); at += part.byteLength }
  return out
}

export function sliceBytes(bytes: Uint8Array, start: number, end?: number): Uint8Array {
  return bytes.subarray(start, end ?? bytes.byteLength).slice()
}

// A UUID in the RFC 4122 v4 shape, like crypto.randomUUID. Random comes from the
// injected source (see random.ts), so this file never touches platform APIs.
export function uuidOf(random16: Uint8Array): string {
  random16[6] = (random16[6]! & 0x0f) | 0x40
  random16[8] = (random16[8]! & 0x3f) | 0x80
  const hex = toHex(random16)
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`
}

export function utf8ByteLength(text: string): number {
  return utf8Encode(text).byteLength
}
