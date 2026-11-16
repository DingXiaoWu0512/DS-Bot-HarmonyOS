// The link to one computer: connect, poll, feed events, calls with optimistic
// updates. Port of team/link.ts's useTeamLink and connection.ts as a controller
// class the ArkUI layer observes.
import { RpcClient } from '../link/rpc-client.ts'
import { RelayTransport } from '../link/relay-transport.ts'
import { SecureTransport } from '../link/secure-transport.ts'
import { encodeHandshakeHello, decodeHandshakeHello, type HandshakeHello } from '../link/pairing.ts'
import type { Hello, TeamState, Bot } from './types.ts'
import { withWrites, optimistic, OPTIMISTIC, type Write } from './optimistic.ts'
import { t } from '../ui/i18n.ts'
import type { PhoneIdentity, SavedComputer } from './store-core.ts'

// Feed events keep the app live; the poll only stays as a foreground fallback.
const POLL_MS = 15_000
const RETRY_MS = 2_000

// Profile photos travel by reference and are fetched once per content hash.
const photoCache = new Map<string, string>()
const photoFetching = new Set<string>()

export type FeedHandler = (event: string, data: unknown) => void
export type CallFn = (endpoint: string, payload?: unknown) => Promise<unknown>

// The AppStore bridge: a TeamLink's feed events reach the .ets subscribers
// with the payload narrowed to an object, so .ets never annotates `unknown`.
export function bridgeTeamFeed(
  controller: TeamLink,
  dispatch: (event: string, data: object) => void
): () => void {
  return controller.onFeed((event: string, data: unknown): void => {
    if (typeof data !== 'object' || data === null) return
    dispatch(event, data)
  })
}

export function rejected(error: unknown): boolean {
  const code = (error as { code?: unknown })?.code
  return code === 'NOT_PAIRED' || code === 'PAIRING_REJECTED'
}

export function errorText(error: unknown): string {
  const code = (error as { code?: unknown })?.code
  if (rejected(error)) return t('The computer did not accept this phone. Show a new QR code on the computer and scan it again.')
  if (code === 'HOST_OFFLINE') return t('The computer is not connected to the Server. Check that DS Bot is open and phone access is on.')
  if (code === 'SERVER_UNREACHABLE') return t("Could not reach the Server. Check the network. If the computer's Server address changed, pair again under Computers.")
  return t(error instanceof Error ? error.message : String(error))
}

export const offline = (): Error => {
  const error = new Error(t('Not connected to the computer yet.'))
  ;(error as Error & { code?: string }).code = 'link/offline'
  return error
}

// Host errors arrive in the plugin's English; screens show error.message as is.
function localized(failure: unknown): unknown {
  // The link dropping mid-call is the same state as being offline.
  if ((failure as { code?: unknown })?.code === 'TRANSPORT_CLOSED') return offline()
  if (failure instanceof Error) failure.message = t(failure.message)
  return failure
}

// Endpoints that can hand out or change secrets/capabilities need a device
// unlock, every time. The platform layer binds the biometric prompt.
export const GATED = new Set<string>([
  'provider-key', 'provider-add', 'provider-remove',
  'secret-set', 'secret-update', 'secret-delete', 'secret-allow',
  'connector-connect', 'connector-disconnect', 'connector-retry',
  'capability-save', 'capability-delete', 'capability-approve', 'bot-capability',
  'update-install', 'dsh-update-install',
])

// The link outlives the screen: the platform layer installs a background
// keep-alive (a continuous task) while the hook is active, so the system does
// not freeze the app and drop the WebSocket to the computer.
export interface LinkKeepAlive {
  set(active: boolean): void
}

let keepAlive: LinkKeepAlive | null = null

export function installKeepAlive(next: LinkKeepAlive): void {
  keepAlive = next
}

function setKeepAlive(active: boolean): void {
  if (keepAlive === null) return
  try {
    keepAlive.set(active)
  } catch {
    // A denied continuous task just degrades to reconnect-on-foreground.
  }
}

export type EnsureUnlock = (endpoint: string) => Promise<void>

let ensureUnlockImpl: EnsureUnlock = async () => {}

export function installEnsureUnlock(impl: EnsureUnlock): void {
  ensureUnlockImpl = impl
}

export async function ensureUnlock(endpoint: string): Promise<void> {
  await ensureUnlockImpl(endpoint)
}

/** Opens the encrypted link to the computer. The pairing code goes only with the first connection. */
export async function openLink(computer: SavedComputer, identity: PhoneIdentity, pairingCode?: string): Promise<RpcClient> {
  const relay = new RelayTransport(computer.server, {
    deviceId: identity.deviceId,
    identityKey: identity.publicKey,
    accessToken: identity.accessToken,
    targetDeviceId: computer.hostDeviceId,
  })
  const hello: HandshakeHello = pairingCode === undefined
    ? { name: deviceName() }
    : { name: deviceName(), pairingCode }
  const secure = new SecureTransport(relay, identity, { deviceId: computer.hostDeviceId, identityKey: computer.hostKey }, {
    hello,
  })
  const client = new RpcClient(secure)
  await client.connect()
  return client
}

// Handshake hello codec re-exports so callers above don't touch the wire format.
export { encodeHandshakeHello, decodeHandshakeHello }

// The phone's name on the computer; the platform layer sets the device model.
let deviceNameValue = 'HarmonyOS phone'

export function setDeviceName(name: string): void {
  deviceNameValue = name
}

function deviceName(): string {
  return deviceNameValue
}

/** Calls one DS Bot endpoint on the computer, the same one its window calls. */
export async function callBot<T>(client: RpcClient, endpoint: string, payload: unknown = {}): Promise<T> {
  const result = await client.rpc<{ ok: true; value: T } | { ok: false; error: { code: string; message: string } }>('bot', { endpoint, payload })
  if (!('ok' in result) || result.ok !== true) {
    const failure = new Error((result as { error?: { message?: string } }).error?.message ?? 'The call failed')
    ;(failure as Error & { code?: string }).code = (result as { error?: { code?: string } }).error?.code
    throw failure
  }
  return (result as { value: T }).value
}

/**
 * Same call, but the request carries `state` (the payload the `state` endpoint
 * would take). A write that moved the team answers with the new state in the
 * same reply, so the phone needs no second round trip.
 */
export async function callBotState<T>(client: RpcClient, endpoint: string, payload: unknown, state: unknown): Promise<{ value: T; state?: TeamState }> {
  const result = await client.rpc<{ ok: true; value: T; state?: TeamState } | { ok: false; error: { code: string; message: string } }>('bot', { endpoint, payload, state })
  if (!('ok' in result) || result.ok !== true) {
    const failure = new Error((result as { error?: { message?: string } }).error?.message ?? 'The call failed')
    ;(failure as Error & { code?: string }).code = (result as { error?: { code?: string } }).error?.code
    throw failure
  }
  return { value: (result as { value: T; state?: TeamState }).value, state: (result as { value: T; state?: TeamState }).state }
}

export interface TeamLinkSnapshot {
  team: TeamState | null
  online: boolean
  linked: boolean
  error: string | null
  hello: Hello | null
}

interface PhotoAnswer {
  ref?: string | null
  image?: string | null
}

/**
 * Keeps the link up and the team state fresh. One instance per active computer;
 * the UI observes the snapshot and `call` runs one /api/bot endpoint.
 */
export class TeamLink {
  private client?: RpcClient
  private team: TeamState | null = null
  private online = false
  private linked = false
  private error: string | null = null
  private hello: Hello | null = null
  private revision = -1
  private writes: Write[] = []
  private liveKey: string | undefined = undefined
  private stopped = false
  private pollTimer?: ReturnType<typeof setTimeout>
  private retryTimer?: ReturnType<typeof setTimeout>
  private pollRef: (() => void) | null = null
  private readonly feedHandlers = new Set<FeedHandler>()
  private readonly listeners = new Set<() => void>()
  private readonly hostId: string
  private readonly computer: SavedComputer
  private readonly identity: PhoneIdentity

  constructor(computer: SavedComputer, identity: PhoneIdentity) {
    this.computer = computer
    this.identity = identity
    this.hostId = computer.hostDeviceId
  }

  onChange(listener: () => void): () => void {
    this.listeners.add(listener)
    return () => this.listeners.delete(listener)
  }

  private notify(): void {
    for (const listener of [...this.listeners]) listener()
  }

  snapshot(): TeamLinkSnapshot {
    return { team: this.team, online: this.online, linked: this.linked, error: this.error, hello: this.hello }
  }

  get hostDeviceId(): string {
    return this.hostId
  }

  onFeed(handler: FeedHandler): () => void {
    this.feedHandlers.add(handler)
    return () => this.feedHandlers.delete(handler)
  }

  // Every bot whose photo came as a ref gets the cached image, or keeps the
  // previous team's photo while the fetch runs — never a blank avatar.
  private fillPhotos(team: TeamState, prev: TeamState | null): TeamState {
    if (!Array.isArray(team.bots)) return team
    const bots = team.bots.map((bot, index): Bot => {
      const ref = bot.avatar?.imageRef
      if (ref === undefined) return bot
      const cached = photoCache.get(ref)
      if (cached !== undefined) {
        return bot.avatar?.image === cached ? bot : { ...bot, avatar: { ...bot.avatar, image: cached } }
      }
      this.fetchPhoto(bot.id, ref)
      const kept = prev?.bots.find(entry => entry.id === bot.id)?.avatar?.image
      return kept !== undefined && kept !== bot.avatar?.image ? { ...bot, avatar: { ...bot.avatar, image: kept } } : bot
    })
    return bots.every((bot, index) => bot === team.bots[index]) ? team : { ...team, bots }
  }

  private fetchPhoto(botId: string, ref: string): void {
    if (photoFetching.has(ref)) return
    const client = this.client
    if (client === undefined) return
    photoFetching.add(ref)
    void callBot<PhotoAnswer>(client, 'avatar', { botId })
      .then(answer => {
        if (typeof answer.image === 'string') photoCache.set(typeof answer.ref === 'string' ? answer.ref : ref, answer.image)
        // Re-fill the current team now that this photo is cached.
        if (this.team !== null) {
          this.team = this.fillPhotos(this.team, this.team)
          this.notify()
        }
      })
      .catch(() => {})
      .finally(() => photoFetching.delete(ref))
  }

  // One place every state answer goes through. An older in-flight poll must
  // not overwrite a newer write reply.
  private apply(next: TeamState): void {
    if (next.revision < this.revision) return
    this.revision = next.revision
    if (typeof next.liveKey === 'string') this.liveKey = next.liveKey
    const prev = this.team
    const merged = next.unchanged === true && prev !== null ? { ...prev, ...next } : next
    this.team = this.fillPhotos(withWrites(merged, this.writes), prev)
    this.notify()
  }

  // An arrow property, not a method: the screens hand `controller.call` around
  // as a bare function (readChat/prefetchChat), and a bare method reference
  // loses `this`.
  call = async (endpoint: string, payload: unknown = {}): Promise<unknown> => {
    const client = this.client
    if (client === undefined) throw offline()
    await ensureUnlock(endpoint)
    if (this.client !== client) throw offline()
    try {
      if (endpoint === 'state' || endpoint === 'hello' || endpoint === 'notices') {
        return await callBot(client, endpoint, payload)
      }
      // Show the write's effect at once; the reply's state (or a full reload
      // on failure) puts the computer's truth back over it.
      const write: Write = { endpoint, payload: (payload ?? {}) as Record<string, unknown> }
      if (OPTIMISTIC.has(endpoint)) this.writes.push(write)
      this.team = optimistic(this.team, endpoint, write.payload)
      this.notify()
      try {
        const answer = await callBotState<unknown>(client, endpoint, payload, { since: this.revision, avatars: 'ref', live: this.liveKey })
        this.writes = this.writes.filter(entry => entry !== write)
        if (answer.state !== undefined && this.client === client) this.apply(answer.state)
        return answer.value
      } finally {
        this.writes = this.writes.filter(entry => entry !== write)
      }
    } catch (failure) {
      // Snap back to the computer's truth: forget the revision and re-read all.
      if (OPTIMISTIC.has(endpoint) && this.client === client) {
        this.revision = -1
        this.pollRef?.()
      }
      throw localized(failure)
    }
  }

  private later(run: () => void, ms: number): void {
    if (this.pollTimer !== undefined) clearTimeout(this.pollTimer)
    if (this.retryTimer !== undefined) clearTimeout(this.retryTimer)
    if (!this.stopped) this.pollTimer = setTimeout(run, ms)
  }

  async start(): Promise<void> {
    this.stopped = false
    setKeepAlive(true)
    this.resetState()
    void this.connectLoop()
  }

  private resetState(): void {
    this.revision = -1
    this.writes = []
    this.liveKey = undefined
    this.team = null
    this.online = false
    this.linked = false
    this.error = null
    this.hello = null
    this.notify()
  }

  private schedulePoll(): void {
    this.pollRef = () => void this.poll()
    void this.poll()
  }

  private async poll(): Promise<void> {
    const client = this.client
    if (this.stopped || client === undefined) return
    if (this.reading) {
      this.again = true
      return
    }
    this.reading = true
    try {
      const next = await callBot<TeamState>(client, 'state', { since: this.revision, avatars: 'ref', live: this.liveKey })
      if (this.stopped || this.client !== client) return
      this.apply(next)
      this.error = null
      this.notify()
      this.later(() => void this.poll(), POLL_MS)
    } catch (failure) {
      if (!this.stopped && this.client === client) {
        this.error = errorText(failure)
        this.notify()
      }
    } finally {
      this.reading = false
      if (this.again && !this.stopped) {
        this.again = false
        void this.poll()
      }
    }
  }

  private reading = false
  private again = false

  private async connectLoop(): Promise<void> {
    if (this.stopped) return
    try {
      const client = await openLink(this.computer, this.identity)
      if (this.stopped) {
        void client.close()
        return
      }
      this.client = client
      this.linked = true
      this.notify()
      // The handshake: its api is null when the computer's DS Bot is too old.
      this.schedulePoll()
      const helloResult = await callBot<Hello>(client, 'hello', {}).catch(() => null)
      if (this.stopped) {
        void client.close()
        return
      }
      if (helloResult === null || helloResult.api === null) {
        this.error = t('Update DS Bot on the computer to use this phone.')
        this.linked = false
        this.notify()
        void client.close()
        this.retryTimer = setTimeout(() => void this.connectLoop(), RETRY_MS)
        return
      }
      this.hello = helloResult
      this.online = true
      this.error = null
      this.notify()
      client.onEvent(event => {
        if (this.stopped || this.client !== client) return
        if (event.event === 'revision' || event.event === 'live') void this.poll()
        for (const handler of [...this.feedHandlers]) handler(event.event, event.data)
      })
      void callBot<{ reset?: boolean }>(client, 'notices', { boot: helloResult.boot, since: 0 }).then(answer => {
        if (this.stopped || this.client !== client) return
        if (answer.reset === true) void this.poll()
      }).catch(() => {})
      client.onClose(() => {
        if (this.stopped || this.client !== client) return
        this.client = undefined
        this.online = false
        this.linked = false
        this.notify()
        if (this.pollTimer !== undefined) clearTimeout(this.pollTimer)
        this.retryTimer = setTimeout(() => void this.connectLoop(), RETRY_MS)
      })
    } catch (failure) {
      if (this.stopped) return
      this.error = errorText(failure)
      if (rejected(failure)) this.team = null
      else this.retryTimer = setTimeout(() => void this.connectLoop(), RETRY_MS)
      this.notify()
    }
  }

  /** Waking is the common half-open case: probe first so a dead socket declares itself. */
  onForeground(): void {
    this.client?.probe()
    // A frozen background can leave the link dead with a retry still queued;
    // on return, skip the wait and reconnect at once.
    if (this.client === undefined && !this.stopped && this.retryTimer !== undefined) {
      clearTimeout(this.retryTimer)
      this.retryTimer = undefined
      void this.connectLoop()
    }
    void this.poll()
  }

  onBackground(): void {
    if (this.pollTimer !== undefined) clearTimeout(this.pollTimer)
  }

  async stop(): Promise<void> {
    this.stopped = true
    setKeepAlive(false)
    if (this.pollTimer !== undefined) clearTimeout(this.pollTimer)
    if (this.retryTimer !== undefined) clearTimeout(this.retryTimer)
    await this.client?.close()
    if (this.client !== undefined) this.client = undefined
  }
}
