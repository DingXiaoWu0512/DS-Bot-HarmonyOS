// Pairing offers, handshake hellos, and the dsbot://pair URI. Port of pairing.ts.
import { utf8Encode, utf8Decode } from '../bytes.ts'
import { deviceIdFor, randomToken } from './keys.ts'
import { sha256 } from '../sha256.ts'

/** What each side tells the other inside the encrypted handshake. */
export interface HandshakeHello {
  name?: string
  pairingCode?: string
}

export interface PairedDevice {
  deviceId: string
  identityKey: string
  name: string
  pairedAt: number
}

/** What the computer's pairing QR code carries to the phone. */
export interface PairingOffer {
  server: string
  hostDeviceId: string
  hostKey: string
  code: string
  name: string
}

const MAX_NAME = 64
const MAX_CODE = 128
const PAIRING_SCHEME = 'dsbot:'

export function encodeHandshakeHello(hello: HandshakeHello): Uint8Array {
  return utf8Encode(JSON.stringify(checkHello(hello)))
}

export function decodeHandshakeHello(data: Uint8Array): HandshakeHello {
  if (data.byteLength === 0) return {}
  return checkHello(JSON.parse(utf8Decode(data)) as HandshakeHello)
}

function checkHello(value: unknown): HandshakeHello {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) throw new Error('The handshake hello is invalid.')
  const { name, pairingCode } = value as Record<string, unknown>
  const hello: HandshakeHello = {}
  if (name !== undefined) {
    if (typeof name !== 'string' || name.length > MAX_NAME) throw new Error('The device name is invalid.')
    hello.name = name
  }
  if (pairingCode !== undefined) {
    if (typeof pairingCode !== 'string' || pairingCode.length === 0 || pairingCode.length > MAX_CODE) {
      throw new Error('The pairing code is invalid.')
    }
    hello.pairingCode = pairingCode
  }
  return hello
}

// A URLSearchParams-equivalent builder over the few fields a pairing URI needs.
function uriQuery(fields: [string, string][]): string {
  const escape = (value: string): string => {
    let out = ''
    for (const char of value) {
      const code = char.charCodeAt(0)
      if (/[A-Za-z0-9\-_.~]/.test(char)) out += char
      else if (char === ' ') out += '%20'
      else {
        const bytes = utf8Encode(char)
        for (const byte of bytes) out += `%${byte.toString(16).toUpperCase().padStart(2, '0')}`
      }
      void code
    }
    return out
  }
  return fields.map(([name, value]) => `${escape(name)}=${escape(value)}`).join('&')
}

// Minimal query parsing: split on & then =, and percent-decode each part.
function parseQuery(query: string): Map<string, string> {
  const fields = new Map<string, string>()
  for (const part of query.split('&')) {
    if (part === '') continue
    const at = part.indexOf('=')
    const name = at === -1 ? part : part.slice(0, at)
    const value = at === -1 ? '' : part.slice(at + 1)
    fields.set(percentDecode(name), percentDecode(value))
  }
  return fields
}

function percentDecode(value: string): string {
  if (!value.includes('%') && !value.includes('+')) return value
  const bytes: number[] = []
  for (let i = 0; i < value.length; i++) {
    const char = value.charAt(i)
    if (char === '%' && i + 2 < value.length + 1 && /^[0-9a-fA-F]{2}$/.test(value.slice(i + 1, i + 3))) {
      bytes.push(parseInt(value.slice(i + 1, i + 3), 16))
      i += 2
    } else if (char === '+') bytes.push(0x20)
    else bytes.push(...Array.from(utf8Encode(char)))
  }
  return utf8Decode(new Uint8Array(bytes))
}

export function pairingUri(offer: PairingOffer): string {
  const query = uriQuery([
    ['v', '1'],
    ['server', offer.server],
    ['host', offer.hostDeviceId],
    ['key', offer.hostKey],
    ['code', offer.code],
    ['name', offer.name],
  ])
  return `${PAIRING_SCHEME}//pair?${query}`
}

export function parsePairingUri(uri: string): PairingOffer {
  const schemeEnd = uri.indexOf('//')
  if (schemeEnd === -1 || uri.slice(0, schemeEnd) !== PAIRING_SCHEME) throw new Error('This is not a DS Bot pairing code.')
  const rest = uri.slice(schemeEnd + 2)
  const queryAt = rest.indexOf('?')
  const host = queryAt === -1 ? rest : rest.slice(0, queryAt)
  const query = queryAt === -1 ? '' : rest.slice(queryAt + 1)
  if (host !== 'pair' || parseQuery(query).get('v') !== '1') {
    throw new Error('This is not a DS Bot pairing code.')
  }
  const fields = parseQuery(query)
  const field = (name: string): string => {
    const value = fields.get(name)
    if (value === undefined || value.length === 0) throw new Error(`The pairing code has no ${name}.`)
    return value
  }
  const server = field('server')
  if (!/^wss?:/.test(server)) throw new Error('The pairing code names an invalid Server.')
  const offer: PairingOffer = {
    server,
    hostDeviceId: field('host'),
    hostKey: field('key'),
    code: field('code'),
    name: (fields.get('name') ?? '').slice(0, MAX_NAME),
  }
  if (deviceIdFor(offer.hostKey) !== offer.hostDeviceId) throw new Error('The pairing code does not match its computer.')
  return offer
}

interface OpenPairing {
  code: string
  expiresAt: number
  misses: number
}

/**
 * The phones a computer trusts, and the one pairing code it may have open.
 * (Host side; kept for the protocol tests.)
 */
export class DeviceRegistry {
  private readonly devices = new Map<string, PairedDevice>()
  private pairing?: OpenPairing
  private readonly onChange?: (devices: PairedDevice[]) => void
  private readonly now: () => number

  constructor(devices: PairedDevice[] = [], onChange?: (devices: PairedDevice[]) => void, now: () => number = Date.now) {
    for (const device of devices) this.devices.set(device.deviceId, { ...device })
    this.onChange = onChange
    this.now = now
  }

  list(): PairedDevice[] {
    return [...this.devices.values()].map(device => ({ ...device }))
  }

  openPairing(ttlMs = 5 * 60_000): { code: string; expiresAt: number } {
    this.pairing = { code: randomToken(18), expiresAt: this.now() + ttlMs, misses: 0 }
    return { code: this.pairing.code, expiresAt: this.pairing.expiresAt }
  }

  closePairing(): void {
    this.pairing = undefined
  }

  pairingOpen(): boolean {
    if (this.pairing !== undefined && this.now() >= this.pairing.expiresAt) this.pairing = undefined
    return this.pairing !== undefined
  }

  /** Whether a device may start a handshake: it is paired, or a pairing code is open. */
  admits(deviceId: string, identityKey: string): boolean {
    return this.matches(deviceId, identityKey) || this.pairingOpen()
  }

  /** The check after the handshake: a paired device, or a new one that holds the open code. */
  authorize(deviceId: string, identityKey: string, hello: HandshakeHello): boolean {
    if (this.matches(deviceId, identityKey)) return true
    if (hello.pairingCode === undefined || !this.pairingOpen()) return false
    const pairing = this.pairing!
    if (!sameText(hello.pairingCode, pairing.code)) {
      pairing.misses += 1
      if (pairing.misses >= 5) this.pairing = undefined
      return false
    }
    this.pairing = undefined
    this.devices.set(deviceId, { deviceId, identityKey, name: hello.name ?? '', pairedAt: this.now() })
    this.onChange?.(this.list())
    return true
  }

  revoke(deviceId: string): boolean {
    const removed = this.devices.delete(deviceId)
    if (removed) this.onChange?.(this.list())
    return removed
  }

  private matches(deviceId: string, identityKey: string): boolean {
    const device = this.devices.get(deviceId)
    return device !== undefined && sameText(device.identityKey, identityKey)
  }
}

function sameText(a: string, b: string): boolean {
  const left = utf8Encode(a)
  const right = utf8Encode(b)
  let diff = left.length ^ right.length
  for (let index = 0; index < Math.max(left.length, right.length); index += 1) diff |= (left[index] ?? 0) ^ (right[index] ?? 0)
  return diff === 0
}

export { sha256 }
