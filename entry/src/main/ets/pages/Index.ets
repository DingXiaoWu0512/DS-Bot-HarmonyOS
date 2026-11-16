// The app's single @Entry host (plan §Research 1): the unpaired boot gate and
// the paired main shell swap in place here, and a dsbot://pair deep link swaps
// the pairing flow in over whatever is showing (App.tsx's Boot: adding state).
//
// The main shell is Navigation(Stack) + NavPathStack + the system route table
// (resources/base/profile/router_map.json, referenced from module.json5). Its
// home content is the chat base: the header (ShellB's Header — menu with the
// pending dot, the title pill into details, the side-chat button, the
// reconnecting strip) over the chat screen (T025). The drawer is the desktop
// sidebar as a left drawer (ShellB + Drawer.tsx): an edge pan or the header
// button opens it, a pan on the panel or a tap on the scrim closes it, and the
// system back closes it first. The chat the last session ended on is restored
// (dsbot.lastChat semantics); a chat the team no longer has falls back to the
// Main Bot. Pair stays out of the stack: the host renders it conditionally, as
// the gate or as the deep-link flow.

import { mediaquery, curves } from '@kit.ArkUI'

import { appStore, type ChatTarget } from '../appstate/AppStore'
import { onPairLink, consumePendingPairLink } from '../common/platform-hooks'
import { isSystemZh } from '../platform/Platform'
import { t } from '../common/ui/i18n'
import { pendingCountOf } from '../common/team/state-utils'
import type { Bot, Room, TeamState } from '../common/team/types'
import type { SavedComputer } from '../common/team/store-core'
import { shadowOf, type } from '../components/Theme'
import { Icon } from '../components/Icon'
import { Avatar, RoomAvatar } from '../components/Marks'
import { Banner, BannerNotice } from '../components/Banner'
import { Pair } from '../screens/Pair'
import { TeamList } from '../screens/TeamList'
import { Chat, prefetchChat } from '../screens/Chat'

interface BotDetailsParam {
  botId: string
}

interface GroupDetailsParam {
  roomId: string
}

interface SideParam {
  botId: string
  sessionId: string
}

@Entry
@ComponentV2
struct Index {
  @Local navPathStack: NavPathStack = new NavPathStack()
  @Local drawerOpen: boolean = false
  @Local drawerDrag: number = 0
  @Local pairOverlay: boolean = false
  @Local pairOffer: string | null = null
  // The notice banner (ShellB's NoticeBanner): a question or approval that
  // lands while the app is open, with the chat it belongs to.
  @Local bannerNotice: BannerNotice | undefined = undefined
  private bannerTarget: ChatTarget | null = null
  private offPairLink: (() => void) | null = null
  private offFeed: (() => void) | null = null
  private darkListener: mediaquery.MediaQueryListener | null = null

  @Computed
  get watchedTeam(): TeamState | null {
    return appStore.link.team
  }

  @Computed
  get watchedChat(): ChatTarget | null {
    return appStore.currentChat
  }

  @Computed
  get watchedLinked(): boolean {
    return appStore.link.linked
  }

  @Monitor('watchedTeam', 'watchedChat', 'watchedLinked')
  onTeamOrChatChange(): void {
    this.validateCurrentChat()
    this.maybePrefetch()
  }

  aboutToAppear(): void {
    // System dark mode drives the theme the way useColorScheme did on RN.
    const listener = this.getUIContext().getMediaQuery().matchMediaSync('(prefers-color-scheme: dark)')
    this.darkListener = listener
    void appStore.boot(listener.matches, isSystemZh()).then(() => {
      appStore.ensureLink()
      appStore.applyTheme()
      void this.restoreLastChat()
    })
    listener.on('change', (result: mediaquery.MediaQueryResult) => {
      void appStore.setComputerDark(result.matches).then(() => {
        appStore.applyTheme()
      })
    })
    // A cold-start dsbot://pair link waited in the pending slot; consume it.
    const pending = consumePendingPairLink()
    if (pending !== null) {
      this.showPairFlow(pending)
    }
    // Warm links (onNewWant) swap the pairing flow in over whatever shows.
    this.offPairLink = onPairLink((url: string) => {
      this.showPairFlow(url)
    })
    // Notice feed events (a question or approval landing live) show the banner.
    this.offFeed = appStore.link.onFeed((event: string, data: object): void => {
      this.onFeedEvent(event, data)
    })
  }

  aboutToDisappear(): void {
    if (this.offPairLink !== null) {
      this.offPairLink()
      this.offPairLink = null
    }
    if (this.offFeed !== null) {
      this.offFeed()
      this.offFeed = null
    }
    if (this.darkListener !== null) {
      this.darkListener.off('change')
      this.darkListener = null
    }
  }

  onBackPress(): boolean {
    // The drawer closes first, the way the hardware back button did on RN.
    if (this.drawerOpen) {
      this.drawerOpen = false
      return true
    }
    return false
  }

  private async handlePaired(computer: SavedComputer): Promise<void> {
    await appStore.computers.refresh()
    appStore.computers.adding = false
    appStore.ensureLink()
    appStore.applyTheme()
    this.pairOverlay = false
    this.pairOffer = null
  }

  private cancelPairing(): void {
    appStore.computers.adding = false
    appStore.ensureLink()
    this.pairOverlay = false
    this.pairOffer = null
  }

  /** The pair flow swaps in over the shell and tears the link down for it. */
  private showPairFlow(offer: string): void {
    this.pairOffer = offer
    this.pairOverlay = true
    // Adding a computer closes the current link (RN: App.tsx's adding state),
    // so pairing starts from a clean slate and the old link comes back on cancel.
    appStore.computers.adding = true
    appStore.ensureLink()
  }

  private closeDrawer(): void {
    this.drawerOpen = false
    this.drawerDrag = 0
  }

  /** A drawer row opens a chat: the shell's base chat swaps in place. */
  private openChatTarget(target: ChatTarget): void {
    appStore.openChat(target)
  }

  /** The chat the last session ended on (dsbot.lastChat). */
  private async restoreLastChat(): Promise<void> {
    const saved: ChatTarget | null = await appStore.restoreChat()
    if (saved !== null) {
      appStore.currentChat = saved
      this.validateCurrentChat()
    }
  }

  /** The bot of the chat on screen, when it is a Bot chat. */
  private targetBot(): Bot | null {
    const team: TeamState | null = appStore.link.team
    const target: ChatTarget | null = appStore.currentChat
    if (team !== null && target !== null && target.kind === 'bot') {
      const bot: Bot | undefined = team.bots.find((item: Bot): boolean => item.id === target.id)
      if (bot !== undefined) return bot
    }
    return null
  }

  /** The group of the chat on screen, when it is a group chat. */
  private targetRoom(): Room | null {
    const team: TeamState | null = appStore.link.team
    const target: ChatTarget | null = appStore.currentChat
    if (team !== null && target !== null && target.kind === 'room') {
      const room: Room | undefined = (team.rooms ?? []).find((item: Room): boolean => item.id === target.id)
      if (room !== undefined) return room
    }
    return null
  }

  /** The Main Bot (or first Bot) a chatless shell falls back to. */
  private fallbackBot(): Bot | null {
    const team: TeamState | null = appStore.link.team
    if (team === null) return null
    const mainId: string | null | undefined = team.mainBotId
    if (mainId !== undefined && mainId !== null) {
      const main: Bot | undefined = team.bots.find((item: Bot): boolean => item.id === mainId)
      if (main !== undefined) return main
    }
    return team.bots.length > 0 ? team.bots[0] : null
  }

  /** The bot the header shows: the chat's Bot, or the fallback when chatless. */
  private effectiveBot(): Bot | null {
    return this.targetBot() ?? (this.targetRoom() === null ? this.fallbackBot() : null)
  }

  /** What the drawer marks as the open chat (the fallback counts, like RN). */
  private currentChatId(): string {
    const target: ChatTarget | null = appStore.currentChat
    if (target !== null) return target.id
    return this.fallbackBot()?.id ?? ''
  }

  private headerTitle(): string {
    return this.effectiveBot()?.name ?? this.targetRoom()?.name ?? ''
  }

  private hasPending(): boolean {
    return pendingCountOf(appStore.link.team) > 0
  }

  private sideSessionId(): string | null {
    const bot: Bot | null = this.effectiveBot()
    if (bot !== null && bot.sessionId !== undefined) return bot.sessionId
    return null
  }

  /** A chat the team no longer has is dropped; the Main Bot takes its place. */
  private validateCurrentChat(): void {
    const team: TeamState | null = appStore.link.team
    const target: ChatTarget | null = appStore.currentChat
    if (team === null || target === null) return
    if (target.kind === 'bot') {
      if (team.bots.some((item: Bot): boolean => item.id === target.id)) return
    } else {
      if ((team.rooms ?? []).some((item: Room): boolean => item.id === target.id)) return
    }
    appStore.forgetChat()
    const fallback: Bot | null = this.fallbackBot()
    if (fallback !== null) {
      appStore.openChat({ kind: 'bot', id: fallback.id })
    }
  }

  /** On launch the saved chat is read while the team state is still on its way. */
  private maybePrefetch(): void {
    if (!appStore.link.linked || appStore.link.team !== null) return
    const target: ChatTarget | null = appStore.currentChat
    const controller = appStore.link.controller
    if (target === null || controller === null) return
    prefetchChat(controller.call, appStore.computers.active?.hostDeviceId ?? '', target)
  }

  /** The chat visible on screen, when the chat home is what shows (open-chat.ts). */
  private activeChatTarget(): ChatTarget | null {
    if (this.navPathStack.size() > 0) return null
    const target: ChatTarget | null = appStore.currentChat
    if (target !== null) return target
    const fallback: Bot | null = this.fallbackBot()
    return fallback !== null ? { kind: 'bot', id: fallback.id } : null
  }

  /** A live question or approval shows the banner unless its chat is on screen. */
  private onFeedEvent(event: string, data: object): void {
    if (event !== 'notice' || !appStore.prefs.banners) return
    const record: Record<string, Object> = data as Record<string, Object>
    const kind: Object | undefined = record['kind']
    if (kind !== 'question' && kind !== 'approval') return
    const roomId: Object | undefined = record['roomId']
    const botId: Object | undefined = record['botId']
    let target: ChatTarget
    if (typeof roomId === 'string') {
      target = { kind: 'room', id: roomId }
    } else {
      target = { kind: 'bot', id: typeof botId === 'string' ? botId : '' }
    }
    // The chat on screen already shows its own card.
    const active: ChatTarget | null = this.activeChatTarget()
    if (active !== null && active.kind === target.kind && active.id === target.id) return
    const title: Object | undefined = record['title']
    const text: Object | undefined = record['text']
    const textPart: string = typeof text === 'string' ? text : ''
    const message: string = typeof title === 'string' ? `${title}：${textPart}` : textPart
    this.bannerTarget = target
    this.bannerNotice = new BannerNotice(message, typeof kind === 'string' ? kind : '', target.id)
  }

  /** A banner tap opens its chat, the way popTo('Chat') did. */
  private openBanner(): void {
    const target: ChatTarget | null = this.bannerTarget
    this.bannerNotice = undefined
    this.bannerTarget = null
    if (target !== null) {
      this.openChatTarget(target)
    }
    if (this.navPathStack.size() > 0) {
      this.navPathStack.clear()
    }
  }

  private dismissBanner(): void {
    this.bannerNotice = undefined
    this.bannerTarget = null
  }

  private openFromPill(): void {
    const bot: Bot | null = this.effectiveBot()
    if (bot !== null) {
      const param: BotDetailsParam = { botId: bot.id }
      this.navPathStack.pushPathByName('botDetails', param)
      return
    }
    const room: Room | null = this.targetRoom()
    if (room !== null) {
      const param: GroupDetailsParam = { roomId: room.id }
      this.navPathStack.pushPathByName('groupDetails', param)
    }
  }

  private openSide(): void {
    const bot: Bot | null = this.effectiveBot()
    if (bot === null || bot.sessionId === undefined) return
    const param: SideParam = { botId: bot.id, sessionId: bot.sessionId }
    this.navPathStack.pushPathByName('side', param)
  }

  private connectText(): string {
    const error: string | null = appStore.link.error
    return error !== null ? error : t('Connecting…')
  }

  build() {
    Stack() {
      if (this.pairOverlay) {
        this.pairFlow()
      } else if (appStore.link.demo || (appStore.computers.active !== null && !appStore.computers.adding)) {
        this.mainShell()
      } else {
        this.pairGate()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(appStore.theme.p.main)
  }

  /** Boot gate: boot error → message, identity loading → spinner, else Pair. */
  @Builder
  pairGate() {
    if (appStore.computers.bootError !== null) {
      Column() {
        Text(appStore.computers.bootError)
          .fontSize(type.settingsRow.fontSize)
          .lineHeight(type.settingsRow.lineHeight)
          .fontWeight(type.settingsRow.fontWeight)
          .fontColor(appStore.theme.p.danger)
          .textAlign(TextAlign.Center)
          .padding(24)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor(appStore.theme.p.main)
    } else if (appStore.computers.identity !== null) {
      Pair({
        identity: appStore.computers.identity,
        offer: null,
        cancellable: false,
        onPaired: (computer: SavedComputer) => {
          void this.handlePaired(computer)
        },
        onCancel: () => {},
      })
    } else {
      Column() {
        LoadingProgress()
          .width(28)
          .height(28)
          .color(appStore.theme.p.accent)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor(appStore.theme.p.main)
    }
  }

  /** The dsbot://pair flow: Pair with the offer, cancellable once paired. */
  @Builder
  pairFlow() {
    if (appStore.computers.identity !== null) {
      Pair({
        identity: appStore.computers.identity,
        offer: this.pairOffer,
        cancellable: appStore.computers.computers.length > 0,
        onPaired: (computer: SavedComputer) => {
          void this.handlePaired(computer)
        },
        onCancel: () => {
          this.cancelPairing()
        },
      })
    }
  }

  /** Paired main shell: Navigation home (chat base) + the drawer + the banner. */
  @Builder
  mainShell() {
    Stack() {
      Column() {
        Navigation(this.navPathStack) {
          this.chatBase()
        }
        .mode(NavigationMode.Stack)
      }
      .width('100%')
      .height('100%')
      // Immersive: the window runs under the system bars. The chat home runs
      // full-bleed edge to edge — every pushed NavDestination pads its own
      // safe area. The keyboard is not padded here — the page uses
      // KeyboardAvoidMode.RESIZE, which shrinks it above the keyboard (a
      // manual pad would squeeze twice). The drawer and scrim stay edge
      // to edge.
      if (!this.drawerOpen && this.navPathStack.size() === 0) {
        this.edgeStrip()
      }
      if (this.drawerOpen) {
        this.drawerMask()
        this.drawerPanel()
      }
      Banner({
        notice: this.bannerNotice,
        topInset: appStore.safeTop,
        onOpen: (notice: BannerNotice): void => {
          this.openBanner()
        },
        onDismiss: (): void => {
          this.dismissBanner()
        },
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(appStore.theme.p.main)
    // Left-aligned children: the drawer hugs the screen's left edge (RN's
    // drawer did) and the edge pan strip sits at the edge, not mid-screen.
    .alignContent(Alignment.Start)
  }

  /** Navigation home: the chat header floats over the full-bleed chat screen. */
  @Builder
  chatBase() {
    Stack() {
      Column() {
        if (appStore.link.team === null) {
          this.connectingView()
        } else {
          Column() {
            Chat({
              onNavigate: (route: string, param: Object | null): void => {
                this.navPathStack.pushPathByName(route, param)
              },
            })
          }
          .width('100%')
          .height('100%')
        }
      }
      .width('100%')
      .height('100%')
      this.chatHeader()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(appStore.theme.p.main)
    .alignContent(Alignment.Top)
  }

  /** The chat header: menu (pending dot), title pill, side button, strip. */
  @Builder
  chatHeader() {
    Column() {
      Row() {
        Stack({ alignContent: Alignment.TopEnd }) {
          Column() {
            Icon({ name: 'sidebar', iconSize: 20, color: appStore.theme.p.ink })
          }
          .width(40)
          .height(40)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .borderRadius(20)
          .backgroundColor(appStore.theme.p.card)
          .border({
            width: this.getUIContext().px2vp(1),
            color: appStore.theme.p.line2,
          })
          .shadow(shadowOf(1))
          .accessibilityText(t('Open team list'))
          .onClick(() => {
            this.drawerOpen = true
          })
          if (this.hasPending()) {
            Column() {
            }
            .width(8)
            .height(8)
            .borderRadius(4)
            .backgroundColor(appStore.theme.p.accent)
            .margin(6)
          }
        }
        .width(40)
        .height(40)
        Column() {
          if (this.headerTitle() !== '') {
            if (this.effectiveBot() === null && this.targetRoom() === null) {
              Text(this.headerTitle())
                .fontSize(type.headerTitle.fontSize)
                .lineHeight(type.headerTitle.lineHeight)
                .fontWeight(type.headerTitle.fontWeight)
                .fontColor(appStore.theme.p.ink)
                .maxLines(1)
            } else {
              this.headerPill()
            }
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
        if (this.sideSessionId() !== null) {
          Column() {
            Icon({ name: 'side', iconSize: 20, color: appStore.theme.p.ink })
          }
          .width(40)
          .height(40)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .borderRadius(20)
          .backgroundColor(appStore.theme.p.card)
          .border({
            width: this.getUIContext().px2vp(1),
            color: appStore.theme.p.line2,
          })
          .shadow(shadowOf(1))
          .accessibilityText(t('Side chat'))
          .onClick(() => {
            this.openSide()
          })
        } else {
          Column() {
          }
          .width(40)
        }
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 4, bottom: 8 })
      .alignItems(VerticalAlign.Center)
      if (appStore.link.team !== null && appStore.link.online !== true) {
        this.reconnectingStrip()
      }
    }
    .width('100%')
    // Floating header: transparent over the full-bleed chat, dropped below
    // the status bar only.
    .padding({ top: appStore.safeTop })
  }

  /** The title pill: the avatar and name; a tap opens the details screen. */
  @Builder
  headerPill() {
    Row({ space: 8 }) {
      if (this.effectiveBot() !== null) {
        Avatar({
          bot: this.effectiveBot() ?? undefined,
          dark: appStore.theme.dark,
          markSize: 24,
          ring: appStore.theme.p.card,
        })
      } else if (this.targetRoom() !== null) {
        RoomAvatar({
          room: this.targetRoom() ?? undefined,
          bots: appStore.link.team?.bots ?? [],
          dark: appStore.theme.dark,
          markSize: 24,
          ring: appStore.theme.p.card,
        })
      }
      Text(this.headerTitle())
        .fontSize(14)
        .lineHeight(20)
        .fontWeight('500')
        .fontColor(appStore.theme.p.ink)
        .maxLines(1)
    }
    .height(40)
    .borderRadius(20)
    .padding({ left: 14, right: 14 })
    .border({
      width: this.getUIContext().px2vp(1),
      color: appStore.theme.p.line2,
    })
    .backgroundColor(appStore.theme.p.card)
    .shadow(shadowOf(1))
    .constraintSize({ maxWidth: '100%' })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.openFromPill()
    })
  }

  /** The strip while the team shows but the link is down. */
  @Builder
  reconnectingStrip() {
    Row({ space: 6 }) {
      LoadingProgress()
        .width(14)
        .height(14)
        .color(appStore.theme.p.ink3)
      Text(t('Reconnecting…'))
        .fontSize(type.caption.fontSize)
        .lineHeight(type.caption.lineHeight)
        .fontWeight(type.caption.fontWeight)
        .fontColor(appStore.theme.p.ink3)
    }
    .width('100%')
    .padding({ top: 4, bottom: 6 })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
  }

  /** Connecting screen: spinner, the error if any, and the Computers jump. */
  @Builder
  connectingView() {
    Column({ space: 12 }) {
      LoadingProgress()
        .width(28)
        .height(28)
        .color(appStore.theme.p.accent)
      Text(this.connectText())
        .fontSize(type.caption.fontSize)
        .lineHeight(type.caption.lineHeight)
        .fontWeight(type.caption.fontWeight)
        .fontColor(appStore.theme.p.ink3)
        .textAlign(TextAlign.Center)
      Text(t('Computers'))
        .fontSize(type.caption.fontSize)
        .lineHeight(type.caption.lineHeight)
        .fontWeight(type.caption.fontWeight)
        .fontColor(appStore.theme.p.accent)
        .constraintSize({ minHeight: 44 })
        .onClick(() => {
          this.navPathStack.pushPathByName('settings', null)
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding(24)
  }

  /** Left edge pan opens the drawer, only while the chat home is on top. */
  @Builder
  edgeStrip() {
    Column() {
    }
    .width(24)
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
    .gesture(
      PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 8 })
        .onActionEnd((event: GestureEvent) => {
          if (event.offsetX > 30 || event.velocityX > 350) {
            this.drawerOpen = true
          }
        })
    )
  }

  /** Drawer scrim: tap anywhere to close. */
  @Builder
  drawerMask() {
    Column() {
    }
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(0,0,0,0.32)')
    .transition(TransitionEffect.OPACITY.animation({ curve: curves.springMotion() }))
    .onClick(() => {
      this.closeDrawer()
    })
  }

  /** The drawer panel: the team list, a third of the width, capped 264vp. */
  @Builder
  drawerPanel() {
    Column() {
      TeamList({
        current: this.currentChatId(),
        onOpen: (target: ChatTarget): void => {
          this.closeDrawer()
          this.openChatTarget(target)
        },
        onNeeds: (): void => {
          this.closeDrawer()
          this.navPathStack.pushPathByName('needs', null)
        },
        onSettings: (): void => {
          this.closeDrawer()
          this.navPathStack.pushPathByName('settings', null)
        },
        onCreateBot: (): void => {
          this.closeDrawer()
          this.navPathStack.pushPathByName('newBot', null)
        },
        onCreateGroup: (): void => {
          this.closeDrawer()
          this.navPathStack.pushPathByName('newGroup', null)
        },
      })
    }
    .width('33%')
    // Wide enough that the "DS Bot" header row (title + search + new) fits on
    // one line, capped on large screens.
    .constraintSize({ minWidth: '182vp', maxWidth: '264vp' })
    .height('100%')
    // Full-height panel: the sidebar color runs edge to edge; the content
    // itself clears the status bar and the gesture indicator.
    .padding({ top: appStore.safeTop, bottom: appStore.safeBottom })
    .backgroundColor(appStore.theme.p.sidebar)
    .shadow(shadowOf(2))
    .translate({ x: this.drawerDrag })
    .transition(TransitionEffect.translate({ x: '-100%' }).animation({ curve: curves.springMotion() }))
    .gesture(
      PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 8 })
        .onActionUpdate((event: GestureEvent) => {
          this.drawerDrag = Math.min(0, event.offsetX)
        })
        .onActionEnd((event: GestureEvent) => {
          if (event.velocityX < -350 || this.drawerDrag < -100) {
            this.drawerOpen = false
            this.drawerDrag = 0
          } else {
            this.getUIContext().animateTo({ curve: curves.springMotion() }, (): void => {
              this.drawerDrag = 0
            })
          }
        })
    )
  }
}
