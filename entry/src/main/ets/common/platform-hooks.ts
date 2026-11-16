// Injection points the platform layer fills at startup: the system language
// flag and the dsbot://pair deep-link handlers. Pure, so the app state reads
// them without touching @ohos modules.
export type LangSetting = 'system' | 'zh' | 'en'

let systemIsZh = false

export function installSystemIsZh(value: boolean): void {
  systemIsZh = value
}

export function systemPrefersZh(): boolean {
  return systemIsZh
}

let deviceNameValue = 'HarmonyOS phone'

export function setDeviceName(name: string): void {
  deviceNameValue = name
}

export function deviceDisplayName(): string {
  return deviceNameValue
}

type LinkHandler = (url: string) => void
const linkHandlers = new Set<LinkHandler>()
let pendingLink: string | null = null

export function installDeepLinkHandler(): void {
  // The platform layer calls pushPairLink for cold and warm starts.
}

export function pushPairLink(url: string): void {
  // A warm start reaches the live handler at once; a cold start has no
  // subscriber yet, so the link parks until Index consumes it in aboutToAppear.
  if (linkHandlers.size > 0) {
    for (const handler of [...linkHandlers]) handler(url)
    return
  }
  pendingLink = url
}

export function consumePendingPairLink(): string | null {
  const link = pendingLink
  pendingLink = null
  return link
}

export function onPairLink(handler: LinkHandler): () => void {
  linkHandlers.add(handler)
  return () => linkHandlers.delete(handler)
}
