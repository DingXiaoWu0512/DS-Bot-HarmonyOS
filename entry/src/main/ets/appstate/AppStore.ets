// App-wide state the UI observes: the theme (from prefs + team prefs), the
// saved computers, the active link, and the language. State Management V2 keeps
// every screen in sync the way the React contexts did.
import { palette, type Palette } from '../common/ui/tokens'
import { setLang, setSystemIsZh, type LangSetting } from '../common/ui/i18n'
import { readPrefs, loadIdentity, loadComputer, listComputers, setActiveComputer, removeComputer, writePrefs, onPrefsChange, type PhoneIdentity, type SavedComputer, type StoredComputer } from '../common/team/store-core'
import { TeamLink, bridgeTeamFeed } from '../common/team/team-link'
import { applySystemBar } from '../platform/Platform'
import { DemoLink } from '../common/demo/demo-link'
import type { TeamState } from '../common/team/types'

// The chat on screen: one Bot or one group chat (RN: TeamList's ChatTarget).
export interface ChatTarget {
  kind: 'bot' | 'room'
  id: string
}

@ObservedV2
export class ThemeState {
  @Trace dark: boolean = false
  @Trace teamTheme: string | undefined = undefined
  @Trace teamAccent: string | undefined = undefined
  // Bumped on a language switch: every screen reads theme.p while it builds,
  // so the tick re-renders their t() texts too.
  @Trace langTick: number = 0

  get p(): Palette {
    void this.langTick
    return palette(this.dark, this.teamTheme, this.teamAccent)
  }
}

@ObservedV2
export class LinkState {
  @Trace team: TeamState | null = null
  @Trace online: boolean = false
  @Trace linked: boolean = false
  @Trace demo: boolean = false
  @Trace error: string | null = null
  @Trace helloApi: number | null = null
  @Trace helloCapabilities: string[] = []
  controller: TeamLink | DemoLink | null = null
  private unsubscribe: (() => void) | null = null
  private offFeedDispatch: (() => void) | null = null
  private readonly feedHandlers = new Set<(event: string, data: object) => void>()

  attach(controller: TeamLink | DemoLink): void {
    this.detach()
    this.controller = controller
    this.demo = controller instanceof DemoLink
    this.pull(controller)
    this.unsubscribe = controller.onChange(() => this.pull(controller))
    // The controller's feed events reach every onFeed subscriber (the chat
    // screen and the notice banner); the demo link has no feed.
    if (controller instanceof TeamLink) {
      this.offFeedDispatch = bridgeTeamFeed(controller, (event: string, data: object): void => {
        const handlers: Array<(event: string, data: object) => void> = []
        this.feedHandlers.forEach((handler: (event: string, data: object) => void): void => {
          handlers.push(handler)
        })
        for (const handler of handlers) {
          handler(event, data)
        }
      })
    }
  }

  detach(): void {
    if (this.offFeedDispatch !== null) {
      this.offFeedDispatch()
      this.offFeedDispatch = null
    }
    this.unsubscribe?.()
    this.unsubscribe = null
    this.controller = null
    this.team = null
    this.online = false
    this.linked = false
    this.demo = false
    this.error = null
    this.helloApi = null
    this.helloCapabilities = []
  }

  private pull(controller: TeamLink | DemoLink): void {
    if (controller instanceof TeamLink) {
      const snapshot = controller.snapshot()
      this.team = snapshot.team
      this.online = snapshot.online
      this.linked = snapshot.linked
      this.error = snapshot.error
      this.helloApi = snapshot.hello?.api ?? null
      this.helloCapabilities = snapshot.hello?.capabilities ?? []
    } else {
      this.team = controller.team
      this.online = controller.online
      this.linked = true
      this.error = controller.error
      this.helloApi = 1
    }
  }

  onFeed(handler: (event: string, data: object) => void): () => void {
    this.feedHandlers.add(handler)
    return () => this.feedHandlers.delete(handler)
  }

  // The link's AppState listener: waking probes the socket and reads at once,
  // sleeping stops the poll timer (RN: link.ts's foreground subscription).
  onForeground(): void {
    if (this.controller instanceof TeamLink) this.controller.onForeground()
  }

  onBackground(): void {
    if (this.controller instanceof TeamLink) this.controller.onBackground()
  }

  get isDemo(): boolean {
    return this.controller instanceof DemoLink
  }
}

@ObservedV2
export class ComputersState {
  @Trace identity: PhoneIdentity | null = null
  @Trace computers: StoredComputer[] = []
  @Trace active: SavedComputer | null = null
  @Trace adding: boolean = false
  @Trace booted: boolean = false
  @Trace bootError: string | null = null

  async refresh(): Promise<void> {
    this.computers = (await listComputers()).computers
    this.active = await loadComputer() ?? null
  }

  async switchTo(hostDeviceId: string): Promise<void> {
    await setActiveComputer(hostDeviceId)
    await this.refresh()
  }

  async forget(hostDeviceId: string): Promise<void> {
    this.computers = await removeComputer(hostDeviceId)
    if (this.active?.hostDeviceId === hostDeviceId) this.active = await loadComputer() ?? null
  }
}

@ObservedV2
export class PrefsState {
  @Trace theme: string = 'system'
  @Trace banners: boolean = true
  @Trace lang: LangSetting = 'system'

  async load(): Promise<void> {
    const prefs = await readPrefs()
    this.theme = prefs.theme ?? 'system'
    this.banners = prefs.banners !== 'off'
    this.lang = (prefs.lang === 'zh' || prefs.lang === 'en') ? (prefs.lang as LangSetting) : 'system'
    setLang(this.lang)
  }

  async setTheme(value: string): Promise<void> {
    this.theme = value
    await writePrefs({ theme: value })
  }

  async setBanners(value: boolean): Promise<void> {
    this.banners = value
    await writePrefs({ banners: value ? 'on' : 'off' })
  }

  async setLang(value: LangSetting): Promise<void> {
    this.lang = value
    setLang(value)
    await writePrefs({ lang: value })
    // The palette getter reads langTick, so every open screen rebuilds with
    // the new dictionary.
    appStore.theme.langTick += 1
  }
}

// One instance lives for the whole app; Index passes it down.
@ObservedV2
export class AppStore {
  readonly theme: ThemeState = new ThemeState()
  // The window draws under the status bar and the gesture indicator; these are
  // the areas the content must keep clear of (in vp), set once at startup.
  @Trace safeTop: number = 0
  @Trace safeBottom: number = 0
  // Full-screen layout disables the system keyboard avoidance; the avoid-area
  // listener reports the keyboard height (vp) and the shell lifts by it.
  @Trace keyboard: number = 0
  readonly link: LinkState = new LinkState()
  readonly computers: ComputersState = new ComputersState()
  readonly prefs: PrefsState = new PrefsState()
  @Trace currentChat: ChatTarget | null = null
  @Trace systemDark: boolean = false
  private prefsUnsubscribe: (() => void) | null = null
  private activeLinkHost: string | null = null

  async boot(systemDark: boolean, systemIsZh: boolean): Promise<void> {
    this.systemDark = systemDark
    setSystemIsZh(systemIsZh)
    try {
      const identity = await loadIdentity()
      await this.prefs.load()
      this.computers.identity = identity
      await this.computers.refresh()
      this.prefsUnsubscribe = onPrefsChange(() => {
        void this.prefs.load().then((): void => {
          this.applyTheme()
        })
      })
    } catch (error) {
      this.computers.bootError = error instanceof Error ? error.message : String(error)
    }
    this.computers.booted = true
  }

  /** The link follows the active computer; a switch tears the old one down. */
  ensureLink(): void {
    const active = this.computers.active
    const adding = this.computers.adding
    if (active === null || adding) {
      void this.closeLink()
      return
    }
    if (this.activeLinkHost === active.hostDeviceId) return
    void this.closeLink()
    this.activeLinkHost = active.hostDeviceId
    if (this.computers.identity === null) return
    const controller = new TeamLink(active, this.computers.identity)
    this.link.attach(controller)
    // The team carries prefs the theme follows (theme/accent); a state change
    // re-applies it, the way the RN contexts recomputed on every team read.
    controller.onChange((): void => this.applyTheme())
    void controller.start()
  }

  attachDemo(): void {
    void this.closeLink()
    this.activeLinkHost = null
    const controller = new DemoLink()
    this.link.attach(controller)
    controller.onChange((): void => this.applyTheme())
  }

  async closeLink(): Promise<void> {
    const controller = this.link.controller
    if (controller instanceof TeamLink) await controller.stop()
    this.link.detach()
    this.activeLinkHost = null
  }

  /** Opens a chat as the shell's base chat and remembers it (RN: dsbot.lastChat). */
  openChat(target: ChatTarget): void {
    this.currentChat = target
    void writePrefs({ 'lastChat': JSON.stringify(target) })
  }

  /** The chat the last session ended on, if one was saved. */
  async restoreChat(): Promise<ChatTarget | null> {
    const prefs = await readPrefs()
    const raw: string | undefined = prefs['lastChat']
    if (raw === undefined || raw === '') return null
    try {
      const parsed = JSON.parse(raw) as ChatTarget
      if ((parsed.kind !== 'bot' && parsed.kind !== 'room') || typeof parsed.id !== 'string' || parsed.id === '') {
        return null
      }
      return parsed
    } catch {
      return null
    }
  }

  /** Drops the remembered chat — the team no longer has it. */
  forgetChat(): void {
    this.currentChat = null
    void writePrefs({ 'lastChat': '' })
  }

  async setComputerDark(dark: boolean): Promise<void> {
    this.systemDark = dark
  }

  applyTheme(): void {
    this.theme.dark = this.isDark()
    const teamPrefs = this.link.team?.prefs
    this.theme.teamTheme = teamPrefs?.theme
    this.theme.teamAccent = teamPrefs?.accent
    applySystemBar(this.isDark())
  }

  setSafeInsets(top: number, bottom: number): void {
    this.safeTop = top
    this.safeBottom = bottom
  }

  setKeyboard(height: number): void {
    this.keyboard = height
  }

  isDark(): boolean {
    const override = this.prefs.theme
    return override === 'dark' || (override !== 'light' && this.systemDark)
  }
}

export const appStore: AppStore = new AppStore()
