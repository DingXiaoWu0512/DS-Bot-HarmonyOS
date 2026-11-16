// Transport contracts shared by the relay and secure layers. The platform layer
// (an .ets file) installs the WebSocket factory; everything above stays pure.
import type { TransportStats } from './frames.ts'

export interface RelaySocket {
  /** 0 connecting, 1 open, 2 closing, 3 closed. */
  readonly readyState: number
  readonly bufferedAmount: number
  open(): void
  sendText(text: string): void
  close(): void
  onOpen(cb: () => void): () => void
  onMessage(cb: (data: string) => void): () => void
  onError(cb: () => void): () => void
  onClose(cb: () => void): () => void
}

export type SocketFactory = (url: string) => RelaySocket

let socketFactory: SocketFactory | null = null

export function installSocketFactory(factory: SocketFactory): void {
  socketFactory = factory
}

export function createSocket(url: string): RelaySocket {
  if (socketFactory === null) throw new Error('No socket factory was installed')
  return socketFactory(url)
}

export interface RemoteTransport {
  connect(): Promise<void>
  send(data: Uint8Array): Promise<void>
  onMessage(cb: (data: Uint8Array) => void): () => void
  onClose?(cb: () => void): () => void
  /** Ask the far end for a liveness reply now, when the transport supports it. */
  probe?(): void
  close(): Promise<void>
  getStats(): TransportStats
}

export interface SecureHandshakeTransport extends RemoteTransport {
  connectionInfo(): { connectionId: string; localDeviceId: string; remoteDeviceId: string }
  sendHandshake(step: number, data: Uint8Array): Promise<void>
  onHandshake(cb: (step: number, data: Uint8Array) => void): () => void
  readonly closeReason?: Error
}

type MessageHandler = (data: Uint8Array) => void

export abstract class BaseTransport implements RemoteTransport {
  protected handlers = new Set<MessageHandler>()
  protected closeHandlers = new Set<() => void>()

  onMessage(cb: MessageHandler): () => void {
    this.handlers.add(cb)
    return () => this.handlers.delete(cb)
  }

  onClose(cb: () => void): () => void {
    this.closeHandlers.add(cb)
    return () => this.closeHandlers.delete(cb)
  }

  protected emit(data: Uint8Array): void {
    for (const handler of [...this.handlers]) handler(data)
  }

  protected emitClose(): void {
    for (const handler of [...this.closeHandlers]) handler()
  }

  abstract connect(): Promise<void>
  abstract send(data: Uint8Array): Promise<void>
  abstract close(): Promise<void>
  abstract getStats(): TransportStats
}

/** Bounds Relay buffering without changing frame order. Call from serialized sends. */
export async function waitForRelayCapacity(socket: { readonly readyState: number; readonly bufferedAmount: number }): Promise<void> {
  const started = Date.now()
  while (socket.bufferedAmount > 512 * 1024) {
    if (socket.readyState !== 1 || Date.now() - started > 10_000) throw new Error('Relay consumer is too slow or disconnected')
    await new Promise<void>(resolve => setTimeout(resolve, 10))
  }
  if (socket.readyState !== 1) throw new Error('Relay transport closed')
}
