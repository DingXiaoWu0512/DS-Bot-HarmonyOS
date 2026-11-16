// Client side of the Server's Relay over WebSocket. Port of relay-transport.ts,
// with the WebSocket created through the installed socket factory.
import {
  PROTOCOL_VERSION,
  acceptNegotiatedCapabilities,
  createControlFrame,
  decodeControlFrame,
  encodeControlFrame,
  type ConnectAcceptedPayload,
  type ConnectRequestPayload,
  type ControlFrameByteLimits,
  type ControlFrameType,
  type HelloAckPayload,
  type HelloPayload,
  type RelayPayload,
  type SecureHandshakePayload,
  type TransportStats,
} from './frames.ts'
import { toBase64Url, fromBase64Url } from '../bytes.ts'
import { BaseTransport, createSocket, type SecureHandshakeTransport, type RelaySocket, waitForRelayCapacity } from './transport.ts'

export interface RelayTransportOptions {
  deviceId: string
  identityKey: string
  accessToken: string
  targetDeviceId: string
  capabilities?: string[]
  handshakeTimeoutMs?: number
  /** How often a ready socket's silence is checked; default 5 s. */
  watchdogIntervalMs?: number
  /** Silence after which a ready socket is probed; default 15 s. */
  watchdogSilenceMs?: number
  /** Silence after a probe that declares the link dead; default 10 s. */
  probeTimeoutMs?: number
}

const RELAY_CAPABILITY = 'transport.relay'

export class RelayTransport extends BaseTransport implements SecureHandshakeTransport {
  private readonly handshakeHandlers = new Set<(step: number, data: Uint8Array) => void>()
  private socket?: RelaySocket
  private socketUnsubscribes: (() => void)[] = []
  private bytesSent = 0
  private bytesReceived = 0
  private connectionId?: string
  private relayCounter = 0
  /** Why the Host or Server dropped a connection that was already set up. */
  closeReason?: Error
  private readyResolve?: () => void
  private readyReject?: (error: Error) => void
  private handshakeTimer?: ReturnType<typeof setTimeout>
  private controlFrameLimits: ControlFrameByteLimits = {}
  private lastHeard = 0
  private probeAt = 0
  private endCurrent?: (reason?: Error, emit?: boolean) => void
  private readonly url: string
  private readonly options: RelayTransportOptions

  constructor(url: string, options: RelayTransportOptions) {
    super()
    this.url = url
    this.options = options
  }

  async connect(): Promise<void> {
    if (this.socket !== undefined) return
    this.controlFrameLimits = {}
    this.relayCounter = 0
    this.closeReason = undefined
    const socket = createSocket(this.url)
    this.socket = socket
    await new Promise<void>((resolve, reject) => {
      this.readyResolve = resolve
      this.readyReject = reject
      this.handshakeTimer = setTimeout(
        () => this.failConnection(errorOf('Relay control handshake timed out', 'SERVER_UNREACHABLE')),
        this.options.handshakeTimeoutMs ?? 10_000,
      )
      const current = socket
      // Every event from this socket counts only while it is still the current one.
      const stale = (): boolean => this.socket !== current
      let ended = false
      let watchdog: ReturnType<typeof setInterval> | undefined
      const endSocket = (reason?: Error, emit = true): void => {
        if (ended) return
        ended = true
        if (reason !== undefined) this.closeReason = reason
        current.close()
        if (this.socket === current) {
          this.socket = undefined
          this.connectionId = undefined
          this.endCurrent = undefined
          this.clearSocketHandlers()
        }
        if (watchdog !== undefined) clearInterval(watchdog)
        if (emit) this.emitClose()
      }
      this.endCurrent = endSocket
      this.lastHeard = Date.now()
      this.probeAt = 0
      this.socketUnsubscribes = [
        socket.onMessage(data => {
          if (stale()) return
          this.lastHeard = Date.now()
          this.handleSocketMessage(data)
        }),
        socket.onOpen(() => {
          if (stale()) return
          this.sendControl('hello', {
            role: 'client',
            deviceId: this.options.deviceId,
            identityKey: this.options.identityKey,
            accessToken: this.options.accessToken,
            protocols: [PROTOCOL_VERSION],
            capabilities: this.offeredCapabilities(),
          } satisfies HelloPayload)
        }),
        socket.onError(() => {
          if (stale()) return
          this.failConnection(errorOf(`RelayTransport failed to connect to ${this.url}`, 'SERVER_UNREACHABLE'))
        }),
        socket.onClose(() => {
          if (ended) return
          if (this.socket !== undefined && stale()) return
          ended = true
          if (watchdog !== undefined) clearInterval(watchdog)
          if (this.readyReject !== undefined) this.failConnection(errorOf('Relay control channel closed before it was ready', 'SERVER_UNREACHABLE'))
          this.socket = undefined
          this.connectionId = undefined
          this.clearSocketHandlers()
          this.emitClose()
        }),
      ]
      watchdog = setInterval(() => {
        if (ended || this.socket !== current || this.connectionId === undefined) return
        const now = Date.now()
        if (this.probeAt > 0) {
          if (now - Math.max(this.lastHeard, this.probeAt) >= (this.options.probeTimeoutMs ?? 10_000)) {
            endSocket(errorOf('The Server stopped answering', 'SERVER_UNREACHABLE'))
          }
          return
        }
        if (now - this.lastHeard >= (this.options.watchdogSilenceMs ?? 15_000)) this.probeNow()
      }, this.options.watchdogIntervalMs ?? 5_000)
    })
  }

  async send(data: Uint8Array): Promise<void> {
    if (this.socket === undefined || this.socket.readyState !== 1) throw new Error('relay transport is not connected')
    if (this.connectionId === undefined) throw new Error('relay connection has not been authorized')
    await waitForRelayCapacity(this.socket)
    this.sendControl('relay', {
      connectionId: this.connectionId,
      targetDeviceId: this.options.targetDeviceId,
      counter: this.relayCounter,
      ciphertext: toBase64Url(data),
    } satisfies RelayPayload)
    this.bytesSent += data.byteLength
    this.relayCounter += 1
  }

  connectionInfo(): { connectionId: string; localDeviceId: string; remoteDeviceId: string } {
    if (this.connectionId === undefined) throw new Error('relay connection has not been authorized')
    return {
      connectionId: this.connectionId,
      localDeviceId: this.options.deviceId,
      remoteDeviceId: this.options.targetDeviceId,
    }
  }

  async sendHandshake(step: number, data: Uint8Array): Promise<void> {
    if (this.socket === undefined || this.socket.readyState !== 1 || this.connectionId === undefined) {
      throw new Error('relay connection has not been authorized')
    }
    this.sendControl('secure.handshake', {
      connectionId: this.connectionId,
      targetDeviceId: this.options.targetDeviceId,
      step,
      data: toBase64Url(data),
    } satisfies SecureHandshakePayload)
  }

  onHandshake(cb: (step: number, data: Uint8Array) => void): () => void {
    this.handshakeHandlers.add(cb)
    return () => this.handshakeHandlers.delete(cb)
  }

  /** Ask the Server for a liveness reply now; a dead socket ends itself via the watchdog. */
  probe(): void {
    if (this.socket === undefined || this.socket.readyState !== 1 || this.connectionId === undefined || this.probeAt > 0) return
    this.probeNow()
  }

  private probeNow(): void {
    if (this.socket === undefined) return
    this.probeAt = Date.now()
    try {
      this.sendControl('ping', { nonce: this.probeAt })
    } catch {
      this.endCurrent?.(errorOf('The Server stopped answering', 'SERVER_UNREACHABLE'))
    }
  }

  async close(): Promise<void> {
    this.clearHandshake()
    const end = this.endCurrent
    if (end !== undefined) {
      end()
      return
    }
    this.socket?.close()
    this.socket = undefined
    this.connectionId = undefined
    this.clearSocketHandlers()
  }

  getStats(): TransportStats {
    const connected = this.socket !== undefined && this.socket.readyState === 1
    return { mode: connected ? 'Relay' : 'Disconnected', connected, bytesSent: this.bytesSent, bytesReceived: this.bytesReceived }
  }

  private clearSocketHandlers(): void {
    for (const unsubscribe of this.socketUnsubscribes) unsubscribe()
    this.socketUnsubscribes = []
  }

  private offeredCapabilities(): string[] {
    return this.options.capabilities ?? [RELAY_CAPABILITY]
  }

  private handleSocketMessage(raw: string): void {
    try {
      const frame = decodeControlFrame(raw, this.controlFrameLimits)
      if (frame.type === 'hello.ack') {
        const payload = frame.payload as Partial<HelloAckPayload>
        if (payload.protocol !== PROTOCOL_VERSION) throw new Error('Server selected an unsupported protocol version')
        const negotiated = acceptNegotiatedCapabilities(this.offeredCapabilities(), payload.capabilities)
        this.controlFrameLimits = {
          maxControlFrameBytes: payload.maxControlFrameBytes,
          maxRelayFrameBytes: payload.maxRelayFrameBytes,
        }
        if (!negotiated.includes(RELAY_CAPABILITY)) throw new Error('Server did not negotiate the required Relay capability')
        this.sendControl('connect.request', { hostDeviceId: this.options.targetDeviceId } satisfies ConnectRequestPayload)
        return
      }
      if (frame.type === 'connect.accepted') {
        const payload = frame.payload as Partial<ConnectAcceptedPayload>
        if (typeof payload.connectionId !== 'string' || payload.connectionId.length === 0) {
          throw new Error('connect.accepted did not include a connectionId')
        }
        this.connectionId = payload.connectionId
        this.finishConnection()
        return
      }
      if (frame.type === 'connect.rejected' || frame.type === 'error') {
        const payload = frame.payload as { message?: unknown; code?: unknown }
        const message = typeof payload.message === 'string' ? payload.message : 'Server rejected the relay connection'
        throw errorOf(message, typeof payload.code === 'string' ? payload.code : undefined)
      }
      if (frame.type === 'relay') {
        const payload = frame.payload as Partial<RelayPayload>
        if (payload.connectionId !== this.connectionId
          || payload.targetDeviceId !== this.options.deviceId
          || !Number.isSafeInteger(payload.counter)
          || typeof payload.ciphertext !== 'string') {
          throw new Error('Received a relay frame for an unknown connection')
        }
        const data = fromBase64Url(payload.ciphertext)
        this.bytesReceived += data.byteLength
        this.emit(data)
        return
      }
      if (frame.type === 'secure.handshake') {
        const payload = frame.payload as Partial<SecureHandshakePayload>
        if (payload.connectionId !== this.connectionId
          || payload.targetDeviceId !== this.options.deviceId
          || !Number.isSafeInteger(payload.step)
          || typeof payload.data !== 'string') {
          throw new Error('Received a secure handshake frame for an unknown connection')
        }
        const data = fromBase64Url(payload.data)
        for (const handler of [...this.handshakeHandlers]) handler(payload.step!, data)
        return
      }
      if (frame.type === 'ping') this.sendControl('pong', frame.payload)
    } catch (error) {
      this.failConnection(error instanceof Error ? error : new Error('Invalid relay control frame'))
    }
  }

  private sendControl(type: ControlFrameType, payload: unknown): void {
    if (this.socket === undefined || this.socket.readyState !== 1) throw new Error('relay control socket is not open')
    this.socket.sendText(encodeControlFrame(createControlFrame(type, payload), this.controlFrameLimits))
  }

  private finishConnection(): void {
    this.clearHandshake()
    this.readyResolve?.()
    this.readyResolve = undefined
    this.readyReject = undefined
  }

  private failConnection(error: Error): void {
    this.clearHandshake()
    const reject = this.readyReject
    this.readyResolve = undefined
    this.readyReject = undefined
    if (reject === undefined) {
      // Already ready: giving up on the socket is a close, reported at once.
      const end = this.endCurrent
      if (end !== undefined) {
        end(error)
        return
      }
      this.closeReason = error
      this.socket?.close()
      this.socket = undefined
      this.connectionId = undefined
      this.clearSocketHandlers()
      return
    }
    reject(error)
    // A socket that never became ready is ended quietly.
    const end = this.endCurrent
    if (end !== undefined) {
      end(undefined, false)
      return
    }
    this.socket?.close()
    this.socket = undefined
    this.connectionId = undefined
    this.clearSocketHandlers()
  }

  private clearHandshake(): void {
    if (this.handshakeTimer !== undefined) clearTimeout(this.handshakeTimer)
    this.handshakeTimer = undefined
  }
}

function errorOf(message: string, code?: string): Error {
  const error = new Error(message)
  if (code !== undefined) (error as Error & { code?: string }).code = code
  return error
}
