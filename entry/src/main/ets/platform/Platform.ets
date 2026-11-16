// Platform bindings, installed once at startup: secure storage over Asset kit,
// the WebSocket factory over @ohos.net.webSocket, clipboard, haptics, biometric
// unlock, the photo picker, the QR scanner, deep links and device facts.
// Everything above the platform stays pure.
import { asset } from '@kit.AssetStoreKit'
import { webSocket } from '@kit.NetworkKit'
import { pasteboard } from '@kit.BasicServicesKit'
import { vibrator } from '@kit.SensorServiceKit'
import { userAuth } from '@kit.UserAuthenticationKit'
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { image } from '@kit.ImageKit'
import { scanBarcode, scanCore } from '@kit.ScanKit'
import { common, Want } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { i18n } from '@kit.LocalizationKit'
import { util } from '@kit.ArkTS'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { backgroundTaskManager } from '@kit.BackgroundTasksKit'
import { window } from '@kit.ArkUI'
import wantAgent from '@ohos.app.ability.wantAgent'
import deviceInfo from '@ohos.deviceInfo'

import { installSecureStore, type SecureStoreLike } from '../common/team/store-core'
import { installSocketFactory, type RelaySocket } from '../common/link/transport'
import { installSeenStore } from '../common/team/state-utils'
import { installEnsureUnlock, installKeepAlive, GATED } from '../common/team/team-link'
import { installRandom } from '../common/chacha20poly1305'
import { installSystemIsZh, setDeviceName, pushPairLink } from '../common/platform-hooks'
import { t } from '../common/ui/i18n'

// ---- Random -------------------------------------------------------------

// createRandom/generateRandomSync need the CryptoFramework.Rand syscap; the
// canIUse guard matches it so the compiler knows the call is protected, and
// devices without it fall back to a weaker source (every standard-system
// device ships the framework).
let cryptoRandom: cryptoFramework.Random | null = null
installRandom({ fill: bytes => {
  if (canIUse('SystemCapability.Security.CryptoFramework.Rand')) {
    let rand = cryptoRandom
    if (rand === null) {
      rand = cryptoFramework.createRandom()
      cryptoRandom = rand
    }
    const blob = rand.generateRandomSync(bytes.byteLength)
    bytes.set(blob.data)
  } else {
    for (let i = 0; i < bytes.byteLength; i++) bytes[i] = Math.floor(Math.random() * 256)
  }
} })

// ---- Background keep-alive ------------------------------------------------
// While a link is active the app holds a continuous task (dataTransfer), so
// HarmonyOS does not freeze it in the background and the WebSocket to the
// computer stays connected. Needs the notification channel; a denial or a
// failed request just degrades to reconnect-on-foreground.

let taskContext: common.UIAbilityContext | null = null
let mainWindow: window.Window | null = null

/** The immersive window handle, set once the window stage is ready. */
export function setMainWindow(win: window.Window): void {
  mainWindow = win
  lastBarDark = null
}

/** Status bar icon color follows the theme; bar backgrounds stay transparent so
 * the full-bleed layout shows through (defaults are opaque system colors).
 * The IPC only fires when the theme actually flips — state revisions call this
 * constantly, and repeated property updates would force system-bar redraws. */
let lastBarDark: boolean | null = null

export function applySystemBar(dark: boolean): void {
  const win = mainWindow
  if (win === null) return
  if (lastBarDark === dark) return
  const content = dark ? '#ffffff' : '#000000'
  try {
    win.setWindowSystemBarProperties({
      statusBarColor: '#00000000',
      navigationBarColor: '#00000000',
      statusBarContentColor: content,
      navigationBarContentColor: content,
    })
    lastBarDark = dark
  } catch {
    // Best-effort theming; the flag stays unset so the next call retries.
  }
}
let linkTaskActive = false

async function setLinkTask(active: boolean): Promise<void> {
  const context = taskContext
  if (context === null) return
  if (active === linkTaskActive) return
  linkTaskActive = active
  try {
    if (active) {
      const agentWant: Want = { bundleName: context.abilityInfo.bundleName, abilityName: 'EntryAbility' }
      const info: wantAgent.WantAgentInfo = { wants: [agentWant], requestCode: 0 }
      const agent = await wantAgent.getWantAgent(info)
      await backgroundTaskManager.startBackgroundRunning(context, backgroundTaskManager.BackgroundMode.DATA_TRANSFER, agent)
    } else {
      await backgroundTaskManager.stopBackgroundRunning(context)
    }
  } catch (failure) {
    hilog.warn(0x0000, 'DSBot', 'link continuous task %{public}s failed: %{public}s', active ? 'start' : 'stop',
      failure instanceof Error ? failure.message : String(failure))
  }
}

function installKeepAliveBinding(): void {
  installKeepAlive({ set: (active: boolean): void => {
    void setLinkTask(active)
  } })
}

// ---- Byte helpers for Asset kit tags --------------------------------------

class PlatformBytes {
  static of(text: string): Uint8Array {
    const out = new Uint8Array(text.length)
    for (let i = 0; i < text.length; i++) out[i] = text.charCodeAt(i) & 0xff
    return out
  }

  static toText(bytes: Uint8Array): string {
    let out = ''
    for (let i = 0; i < bytes.byteLength; i++) out += String.fromCharCode(bytes[i]!)
    return out
  }
}

// ---- Secure storage over Asset kit ---------------------------------------
// Keys never leave this phone and are not included in backups, like the
// Keystore-backed store the RN build uses.

class AssetStore implements SecureStoreLike {
  private readonly cache = new Map<string, string>()

  async get(key: string): Promise<string | null> {
    const cached = this.cache.get(key)
    if (cached !== undefined) return cached
    try {
      const query: asset.AssetMap = new Map<asset.Tag, asset.Value>()
      query.set(asset.Tag.ALIAS, PlatformBytes.of(key))
      query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL)
      const rows: Array<asset.AssetMap> = await asset.query(query)
      const row = rows[0]
      if (row === undefined) return null
      const secret = row.get(asset.Tag.SECRET) as Uint8Array
      const text = PlatformBytes.toText(secret)
      this.cache.set(key, text)
      return text
    } catch {
      return null
    }
  }

  async set(key: string, value: string): Promise<void> {
    this.cache.set(key, value)
    await this.remove(key)
    const attributes: asset.AssetMap = new Map<asset.Tag, asset.Value>()
    attributes.set(asset.Tag.SECRET, PlatformBytes.of(value))
    attributes.set(asset.Tag.ALIAS, PlatformBytes.of(key))
    attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_POWERED_ON)
    attributes.set(asset.Tag.SYNC_TYPE, asset.SyncType.NEVER)
    try {
      await asset.add(attributes)
    } catch (failure) {
      hilog.error(0x0000, 'DSBot', 'asset add %{public}s failed: %{public}s', key,
        failure instanceof Error ? failure.message : String(failure))
    }
  }

  async delete(key: string): Promise<void> {
    this.cache.delete(key)
    await this.remove(key)
  }

  private async remove(key: string): Promise<void> {
    const query: asset.AssetMap = new Map<asset.Tag, asset.Value>()
    query.set(asset.Tag.ALIAS, PlatformBytes.of(key))
    try {
      await asset.remove(query)
    } catch {
      // No previous entry; the asset kit throws when the alias is absent.
    }
  }
}

// ---- WebSocket ------------------------------------------------------------

interface SocketHandlers {
  open: Set<() => void>
  message: Set<(data: string) => void>
  error: Set<() => void>
  close: Set<() => void>
}

class HarmonySocket implements RelaySocket {
  private readonly ws: webSocket.WebSocket = webSocket.createWebSocket()
  private readonly handlers: SocketHandlers = {
    open: new Set<() => void>(),
    message: new Set<(data: string) => void>(),
    error: new Set<() => void>(),
    close: new Set<() => void>(),
  }
  private closed = false
  bufferedAmount = 0
  readyState = 0

  constructor(url: string) {
    this.ws.on('open', () => {
      this.readyState = 1
      for (const cb of this.handlers.open) cb()
    })
    this.ws.on('message', (_err: Error | null, value: string | ArrayBuffer | ArrayBufferView) => {
      const text = typeof value === 'string' ? value : PlatformBytes.toText(new Uint8Array(value as ArrayBuffer))
      for (const cb of this.handlers.message) cb(text)
    })
    this.ws.on('error', () => {
      for (const cb of this.handlers.error) cb()
    })
    this.ws.on('close', () => {
      this.readyState = 3
      for (const cb of this.handlers.close) cb()
    })
    this.ws.connect(url, (err: Error | null) => {
      if (err && !this.closed) {
        this.readyState = 3
        for (const cb of this.handlers.error) cb()
        for (const cb of this.handlers.close) cb()
      }
    })
  }

  open(): void {}
  sendText(text: string): void {
    this.ws.send(text, (err: Error | null) => {
      if (err) for (const cb of this.handlers.error) cb()
    })
  }
  close(): void {
    if (this.closed) return
    this.closed = true
    this.readyState = 3
    this.ws.close(() => {})
  }
  onOpen(cb: () => void): () => void {
    this.handlers.open.add(cb)
    return () => this.handlers.open.delete(cb)
  }
  onMessage(cb: (data: string) => void): () => void {
    this.handlers.message.add(cb)
    return () => this.handlers.message.delete(cb)
  }
  onError(cb: () => void): () => void {
    this.handlers.error.add(cb)
    return () => this.handlers.error.delete(cb)
  }
  onClose(cb: () => void): () => void {
    this.handlers.close.add(cb)
    return () => this.handlers.close.delete(cb)
  }
}

// ---- Clipboard ------------------------------------------------------------

export async function copyToClipboard(text: string): Promise<void> {
  const board = pasteboard.getSystemPasteboard()
  const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)
  try {
    await board.setData(data)
  } catch {
    // Best-effort copy; a failed call leaves the previous clipboard intact.
  }
}

// ---- Haptics --------------------------------------------------------------

export async function hapticLight(): Promise<void> {
  try {
    await vibrator.startVibration({ type: 'time', duration: 10 }, { usage: 'touch' })
  } catch {
    // Haptics are a nicety; a missing vibrator service must not break a send.
  }
}

export async function hapticSuccess(): Promise<void> {
  try {
    await vibrator.startVibration({ type: 'time', duration: 25 }, { usage: 'touch' })
  } catch {
    // Ignore.
  }
}

// ---- Biometric unlock (gate.ts) -------------------------------------------

/** unlock/unavailable: no screen lock; unlock/canceled: the prompt failed or was dismissed. */
class UnlockError extends Error {
  readonly code: string

  constructor(code: string, message: string) {
    super(message)
    this.code = code
  }
}

/** The SDK takes its result callbacks as an interface, not a function. */
class AuthResultCallback implements userAuth.IAuthCallback {
  private readonly onDone: (result: userAuth.UserAuthResult) => void

  constructor(onDone: (result: userAuth.UserAuthResult) => void) {
    this.onDone = onDone
  }

  onResult(result: userAuth.UserAuthResult): void {
    this.onDone(result)
  }
}

async function ensureUnlock(endpoint: string): Promise<void> {
  if (!GATED.has(endpoint)) return
  // Without an enrolled biometric there is no prompt to show; the caller
  // surfaces the "set a screen lock" guidance instead of a failed prompt.
  const types: userAuth.UserAuthType[] = [userAuth.UserAuthType.FACE, userAuth.UserAuthType.FINGERPRINT]
  let enrolled = false
  for (const type of types) {
    try {
      userAuth.getAvailableStatus(type, userAuth.AuthTrustLevel.ATL1)
      enrolled = true
      break
    } catch {
      // This type is not enrolled.
    }
  }
  if (!enrolled) throw new UnlockError('unlock/unavailable', 'Set a screen lock on this phone to do this')
  try {
    await new Promise<void>((resolve, reject) => {
      const authParam: userAuth.AuthParam = {
        challenge: new Uint8Array(0),
        authType: types,
        authTrustLevel: userAuth.AuthTrustLevel.ATL1,
      }
      const widgetParam: userAuth.WidgetParam = { title: t('Unlock to continue') }
      const auth = userAuth.getUserAuthInstance(authParam, widgetParam)
      auth.on('result', new AuthResultCallback(result => {
        if (result.result === userAuth.UserAuthResultCode.SUCCESS) resolve()
        else reject(new UnlockError('unlock/canceled', result.result === userAuth.UserAuthResultCode.CANCELED ? 'Canceled' : 'Unlock failed'))
      }))
      auth.start()
    })
  } catch (error) {
    if (error instanceof UnlockError) throw error
    // The widget itself failed to come up (busy, locked out, canceled early).
    throw new UnlockError('unlock/canceled', 'Canceled')
  }
}

// ---- Photos ----------------------------------------------------------------

function base64Of(bytes: Uint8Array): string {
  return new util.Base64Helper().encodeToStringSync(bytes)
}

/** Picks an image and returns it as base64 JPEG, resized so the long side is at most 2048. */
export async function pickPhoto(context: common.UIAbilityContext): Promise<string | null> {
  try {
    const picker = new photoAccessHelper.PhotoViewPicker()
    const result = await picker.select({
      MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
      maxSelectNumber: 1,
    })
    if (result.photoUris.length === 0) return null
    return await compressImage(result.photoUris[0]!)
  } catch {
    return null
  }
}

// A picked avatar photo as a data URI (manage.tsx pickPhoto).
export async function pickAvatar(context: common.UIAbilityContext): Promise<string | null> {
  const data = await pickPhoto(context)
  return data === null ? null : `data:image/jpeg;base64,${data}`
}

/** Picks images (several at once); each arrives as base64 JPEG with its long side at most 2048. */
export async function pickPhotos(onReady: (data: string) => void): Promise<void> {
  const picker = new photoAccessHelper.PhotoViewPicker()
  try {
    const result = await picker.select({
      MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
      maxSelectNumber: 9,
    })
    for (const uri of result.photoUris) {
      const data = await compressImage(uri)
      if (data !== null && data !== '') {
        onReady(data)
      }
    }
  } catch {
    // The picker failed or was dismissed; nothing to attach.
  }
}

async function compressImage(uri: string): Promise<string | null> {
  try {
    const source = image.createImageSource(uri)
    if (source === undefined) return null
    const info = await source.getImageInfo()
    const long = Math.max(info.size.width, info.size.height)
    const options: image.DecodingOptions = long > 2048
      ? { desiredSize: { width: Math.round(info.size.width * 2048 / long), height: Math.round(info.size.height * 2048 / long) } }
      : {}
    const pixelMap = await source.createPixelMap(options)
    const packer = image.createImagePacker()
    const buffer: ArrayBuffer = await packer.packToData(pixelMap, { format: 'image/jpeg', quality: 82 })
    await packer.release()
    pixelMap.release()
    await source.release()
    return base64Of(new Uint8Array(buffer))
  } catch {
    return null
  }
}

// ---- QR scan (Pair screen) -------------------------------------------------

export async function launchScanner(context: common.UIAbilityContext): Promise<string | null> {
  try {
    const options: scanBarcode.ScanOptions = {
      scanTypes: [scanCore.ScanType.QR_CODE],
      enableMultiMode: true,
      enableAlbum: true,
    }
    const result: scanBarcode.ScanResult = await scanBarcode.startScanForResult(context, options)
    return result.originalValue ?? null
  } catch {
    return null
  }
}

// ---- Deep links ------------------------------------------------------------

export function handleWant(want: Want): void {
  const uri = want.uri
  if (uri !== undefined && uri.startsWith('dsbot://pair')) pushPairLink(uri)
}

// ---- Device facts -----------------------------------------------------------

export function isSystemZh(): boolean {
  try {
    return i18n.System.getSystemLanguage().toLowerCase().startsWith('zh')
  } catch {
    return false
  }
}

export function deviceName(): string {
  try {
    const name = `${deviceInfo.brand} ${deviceInfo.marketName}`.trim()
    return name === '' ? 'HarmonyOS phone' : name
  } catch {
    return 'HarmonyOS phone'
  }
}
/** Installs every binding; called once from EntryAbility before the UI loads. */
export function installPlatform(context: common.UIAbilityContext): void {
  taskContext = context
  const assetStore = new AssetStore()
  installSecureStore(assetStore)
  installSeenStore(async (value: string) => {
    await assetStore.set('dsbot.seenAt', value)
  })
  installSocketFactory(url => new HarmonySocket(url))
  installEnsureUnlock(ensureUnlock)
  installKeepAliveBinding()
  installSystemIsZh(isSystemZh())
  setDeviceName(deviceName())
}
