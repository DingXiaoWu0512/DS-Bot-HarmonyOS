// The phone's saved identity, computers and preferences. Port of store.ts with
// the secure storage behind an injectable interface (the platform layer binds it
// to Asset kit, which keeps keys device-local like the Keystore-backed store).
import { deviceIdFor, generateKeyPair, randomToken } from '../link/keys.ts'

export interface PhoneIdentity {
  deviceId: string
  publicKey: string
  privateKey: string
  accessToken: string
}

export interface SavedComputer {
  server: string
  hostDeviceId: string
  hostKey: string
  name: string
}

export interface StoredComputer extends SavedComputer {
  addedAt: number
}

interface ComputerList {
  activeId: string | null
  computers: StoredComputer[]
}

export interface PairingOfferForStore {
  server: string
  hostDeviceId: string
  hostKey: string
  name: string
}

// The platform layer binds these to Asset kit / preferences at startup.
export interface SecureStoreLike {
  get(key: string): Promise<string | null>
  set(key: string, value: string): Promise<void>
  delete(key: string): Promise<void>
}

let store: SecureStoreLike | null = null

export function installSecureStore(next: SecureStoreLike): void {
  store = next
}

function requireStore(): SecureStoreLike {
  if (store === null) throw new Error('No secure store was installed')
  return store
}

const IDENTITY = 'dsbot.identity'
const COMPUTERS = 'dsbot.computers'
const PREFS = 'dsbot.prefs'
const LEGACY_COMPUTER = 'dsbot.computer'

function validIdentity(value: unknown): value is PhoneIdentity {
  const identity = value as Partial<PhoneIdentity> | null
  if (identity === null || identity === undefined) return false
  if (typeof identity.publicKey !== 'string' || typeof identity.privateKey !== 'string' || typeof identity.accessToken !== 'string') return false
  try {
    return deviceIdFor(identity.publicKey) === identity.deviceId
  } catch {
    return false
  }
}

async function readJson(key: string): Promise<unknown> {
  const text = await requireStore().get(key)
  if (text === null) return undefined
  try {
    return JSON.parse(text)
  } catch {
    return undefined
  }
}

export async function loadIdentity(): Promise<PhoneIdentity> {
  const saved = await readJson(IDENTITY)
  if (validIdentity(saved)) return saved
  const keys = generateKeyPair()
  const identity: PhoneIdentity = {
    deviceId: deviceIdFor(keys.publicKey),
    publicKey: keys.publicKey,
    privateKey: keys.privateKey,
    accessToken: randomToken(),
  }
  await requireStore().set(IDENTITY, JSON.stringify(identity))
  return identity
}

// The computer list is the one record of paired computers; the active one is
// the one the app links to.
export async function loadComputer(): Promise<SavedComputer | undefined> {
  const { activeId, computers } = await listComputers()
  return computers.find(item => item.hostDeviceId === activeId) ?? computers[0]
}

async function readLegacy(): Promise<SavedComputer | undefined> {
  const single = await readJson(LEGACY_COMPUTER) as Partial<SavedComputer> | undefined
  if (single === undefined || typeof single.server !== 'string' || typeof single.hostDeviceId !== 'string' || typeof single.hostKey !== 'string') return undefined
  return { server: single.server, hostDeviceId: single.hostDeviceId, hostKey: single.hostKey, name: single.name ?? '' }
}

// The older single-computer key migrates into the list on first read.
export async function listComputers(): Promise<ComputerList> {
  const saved = await readJson(COMPUTERS) as ComputerList | undefined
  if (saved !== undefined && Array.isArray(saved.computers)) return saved
  const single = await readLegacy()
  const list: ComputerList = single === undefined
    ? { activeId: null, computers: [] }
    : { activeId: single.hostDeviceId, computers: [{ ...single, addedAt: Date.now() }] }
  await requireStore().set(COMPUTERS, JSON.stringify(list))
  await requireStore().delete(LEGACY_COMPUTER)
  return list
}

export async function addComputer(offer: PairingOfferForStore): Promise<SavedComputer> {
  const list = await listComputers()
  // Pairing again with a known computer (new Server address, new key) replaces its entry in place.
  const known = list.computers.find(item => item.hostDeviceId === offer.hostDeviceId)
  const computer: StoredComputer = {
    server: offer.server,
    hostDeviceId: offer.hostDeviceId,
    hostKey: offer.hostKey,
    name: offer.name,
    addedAt: known?.addedAt ?? Date.now(),
  }
  list.computers = known === undefined ? [...list.computers, computer] : list.computers.map(item => (item.hostDeviceId === known.hostDeviceId ? computer : item))
  list.activeId = computer.hostDeviceId
  await requireStore().set(COMPUTERS, JSON.stringify(list))
  return computer
}

export async function setActiveComputer(hostDeviceId: string): Promise<void> {
  const list = await listComputers()
  list.activeId = hostDeviceId
  await requireStore().set(COMPUTERS, JSON.stringify(list))
}

export async function removeComputer(hostDeviceId: string): Promise<StoredComputer[]> {
  const list = await listComputers()
  list.computers = list.computers.filter(item => item.hostDeviceId !== hostDeviceId)
  if (list.activeId === hostDeviceId) list.activeId = list.computers[0]?.hostDeviceId ?? null
  await requireStore().set(COMPUTERS, JSON.stringify(list))
  return list.computers
}

export async function removeComputerReturnList(hostDeviceId: string): Promise<ComputerList> {
  const list = await listComputers()
  list.computers = list.computers.filter(item => item.hostDeviceId !== hostDeviceId)
  if (list.activeId === hostDeviceId) list.activeId = list.computers[0]?.hostDeviceId ?? null
  await requireStore().set(COMPUTERS, JSON.stringify(list))
  return list
}

export async function seedComputers(raw: ComputerList): Promise<void> {
  await requireStore().set(COMPUTERS, JSON.stringify(raw))
}

let prefsCache: Record<string, string> | null = null
const prefListeners = new Set<() => void>()

export async function readPrefs(): Promise<Record<string, string>> {
  if (prefsCache !== null) return prefsCache
  const text = await requireStore().get(PREFS)
  prefsCache = (text === null ? {} : (JSON.parse(text) as Record<string, string>)) ?? {}
  return prefsCache
}

export function onPrefsChange(listener: () => void): () => void {
  prefListeners.add(listener)
  return () => prefListeners.delete(listener)
}

export async function writePrefs(patch: Record<string, string>): Promise<void> {
  prefsCache = { ...(await readPrefs()), ...patch }
  await requireStore().set(PREFS, JSON.stringify(prefsCache))
  for (const listener of [...prefListeners]) listener()
}
