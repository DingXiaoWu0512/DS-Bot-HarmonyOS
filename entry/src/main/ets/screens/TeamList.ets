// Drawer content (US2): the port of ShellB's DrawerContent plus TeamList.tsx —
// the desktop sidebar as a drawer. The DS Bot head carries Search and New, the
// Needs you row sits on top when anything is pending, the team list shows the
// Main Bots as tiles and every other Bot and group as rows (pinned first, then
// by latest message), the New menu offers creating a Bot or a group chat, and
// the settings gear closes the foot. The host (Index) owns the drawer chrome
// and swaps the chat on onOpen.

import { appStore, type, radius, shadowOf, Palette } from '../components/Theme'
import { Icon } from '../components/Icon'
import { Avatar, RoomAvatar } from '../components/Marks'
import { t } from '../common/ui/i18n'
import { workPhrase } from '../common/ui/phrases'
import { pendingCountOf, isUnread } from '../common/team/state-utils'
import { cleanPreview } from '../common/team/chat-state'
import type { Bot, Room, TeamState } from '../common/team/types'
import type { ChatTarget } from '../appstate/AppStore'

interface ListEntry {
  kind: 'bot' | 'room'
  bot: Bot | null
  room: Room | null
}

@ComponentV2
export struct TeamList {
  @Param current: string = ''
  @Event onOpen: (target: ChatTarget) => void = (_target: ChatTarget) => {}
  @Event onNeeds: () => void = () => {}
  @Event onSettings: () => void = () => {}
  @Event onCreateBot: () => void = () => {}
  @Event onCreateGroup: () => void = () => {}
  @Local searching: boolean = false
  @Local query: string = ''
  @Local newOpen: boolean = false
  @Local tilePressed: string = ''

  @Computed
  get error(): string | null {
    return appStore.link.error
  }

  @Computed
  get pending(): number {
    return pendingCountOf(appStore.link.team)
  }

  @Computed
  get mainTiles(): Bot[] {
    const team: TeamState | null = appStore.link.team
    const query: string = this.searchQuery().toLowerCase()
    const mains: Set<string> = new Set<string>(team?.mainBotIds ?? [])
    const list: Bot[] = []
    for (const bot of team?.bots ?? []) {
      if (!mains.has(bot.id) || bot.hidden === true) continue
      if (query !== '' && !bot.name.toLowerCase().includes(query)) continue
      list.push(bot)
    }
    return list
  }

  @Computed
  get entries(): ListEntry[] {
    const team: TeamState | null = appStore.link.team
    const query: string = this.searchQuery().toLowerCase()
    const mains: Set<string> = new Set<string>(team?.mainBotIds ?? [])
    const list: ListEntry[] = []
    for (const bot of team?.bots ?? []) {
      if (mains.has(bot.id) || bot.hidden === true) continue
      if (query !== '' && !bot.name.toLowerCase().includes(query)) continue
      list.push({ kind: 'bot', bot: bot, room: null })
    }
    for (const room of team?.rooms ?? []) {
      if (room.hidden === true) continue
      if (query !== '' && !room.name.toLowerCase().includes(query)) continue
      list.push({ kind: 'room', bot: null, room: room })
    }
    list.sort((a: ListEntry, b: ListEntry): number => {
      const aPinned: boolean = a.kind === 'bot' ? a.bot?.pinned === true : a.room?.pinned === true
      const bPinned: boolean = b.kind === 'bot' ? b.bot?.pinned === true : b.room?.pinned === true
      if (aPinned !== bPinned) {
        return aPinned ? -1 : 1
      }
      const aAt: number = a.kind === 'bot' ? (a.bot?.lastAt ?? a.bot?.createdAt ?? 0) : (a.room?.lastAt ?? a.room?.createdAt ?? 0)
      const bAt: number = b.kind === 'bot' ? (b.bot?.lastAt ?? b.bot?.createdAt ?? 0) : (b.room?.lastAt ?? b.room?.createdAt ?? 0)
      return bAt - aAt
    })
    return list
  }

  private searchQuery(): string {
    return this.searching ? this.query.trim() : ''
  }

  /** Waiting-for-answer / working / group-work states first, then the preview. */
  private botPreview(bot: Bot): string {
    const team: TeamState | null = appStore.link.team
    const sessionId: string = bot.sessionId ?? bot.id
    if (team?.questions?.[sessionId] !== undefined || team?.views?.[sessionId] !== undefined) {
      return t('Waiting for your answer')
    }
    for (const approval of team?.work?.approvals ?? []) {
      if (approval.botId === bot.id) return t('Waiting for your approval')
    }
    const doing = team?.work?.bots?.[bot.id] ?? team?.activity?.[bot.id]
    if (doing !== undefined) return `${workPhrase(doing)}…`
    const workRooms = team?.work?.rooms ?? {}
    for (const roomId of Object.keys(workRooms)) {
      for (const entry of workRooms[roomId] ?? []) {
        if (entry.botId === bot.id) {
          const room: Room | undefined = (team?.rooms ?? []).find((item: Room): boolean => item.id === roomId)
          return `${room?.name ?? t('a group chat')} · ${workPhrase(entry)}…`
        }
      }
    }
    const waits = team?.work?.waiting?.[bot.id]
    if (waits !== undefined && ((waits.bots?.length ?? 0) > 0 || (waits.rooms?.length ?? 0) > 0)) {
      return t('Waiting for your answer')
    }
    return cleanPreview(bot.preview) ?? bot.role ?? ''
  }

  private roomPreview(room: Room): string {
    const team: TeamState | null = appStore.link.team
    for (const approval of team?.work?.approvals ?? []) {
      if (approval.roomId === room.id) return t('Waiting for your approval')
    }
    const members = team?.work?.rooms?.[room.id] ?? []
    if (members.length > 0) {
      const name: string = (team?.bots ?? []).find((item: Bot): boolean => item.id === members[0].botId)?.name ?? ''
      const extra: string = members.length > 1 ? ` +${members.length - 1}` : ''
      return `${name} · ${workPhrase(members[0])}…${extra}`
    }
    return room.preview ?? ''
  }

  private botWaiting(bot: Bot): boolean {
    const team: TeamState | null = appStore.link.team
    const sessionId: string = bot.sessionId ?? bot.id
    if (team?.questions?.[sessionId] !== undefined) return true
    for (const approval of team?.work?.approvals ?? []) {
      if (approval.botId === bot.id) return true
    }
    return false
  }

  private botWorking(bot: Bot): boolean {
    return appStore.link.team?.work?.bots?.[bot.id] !== undefined
  }

  private roomWaiting(room: Room): boolean {
    for (const approval of appStore.link.team?.work?.approvals ?? []) {
      if (approval.roomId === room.id) return true
    }
    return false
  }

  private roomWorking(room: Room): boolean {
    return (appStore.link.team?.work?.rooms?.[room.id] ?? []).length > 0
  }

  build() {
    Stack() {
      Column() {
        Row({ space: 8 }) {
          Text('DS Bot')
            .fontSize(17)
            .fontWeight('600')
            .fontColor(appStore.theme.p.ink)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          this.roundButton('search', t('Search'), (): void => {
            this.searching = !this.searching
          })
          this.roundButton('plus', t('New'), (): void => {
            this.newOpen = true
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 6, bottom: 10 })
        if (this.searching) {
          Row({ space: 8 }) {
            Icon({ name: 'search', iconSize: 15, color: appStore.theme.p.ink3 })
            TextInput({ text: this.query, placeholder: t('Search the team') })
              .layoutWeight(1)
              .defaultFocus(true)
              .fontSize(15)
              .fontColor(appStore.theme.p.ink)
              .placeholderColor(appStore.theme.p.ink3)
              .backgroundColor('transparent')
              .padding({ left: 0, right: 0 })
              .onChange((value: string) => {
                this.query = value
              })
          }
          .width('calc(100% - 28vp)')
          .height(36)
          .padding({ left: 10, right: 10 })
          .margin({ left: 14, right: 14, bottom: 8 })
          .borderRadius(10)
          .backgroundColor(appStore.theme.p.hover)
          .alignItems(VerticalAlign.Center)
        }
        if (this.error !== null) {
          Text(this.error)
            .fontSize(type.small.fontSize)
            .lineHeight(type.small.lineHeight)
            .fontWeight(type.small.fontWeight)
            .fontColor(appStore.theme.p.danger)
            .padding({ left: 20, right: 20, bottom: 4 })
            .width('100%')
        }
        if (this.pending > 0) {
          Row() {
            Text(t('Needs you'))
              .fontSize(type.rowName.fontSize)
              .lineHeight(type.rowName.lineHeight)
              .fontWeight(type.rowName.fontWeight)
              .fontColor(appStore.theme.p.accent)
              .layoutWeight(1)
            Text(`${this.pending}`)
              .fontSize(12)
              .fontWeight('600')
              .fontColor(appStore.theme.p.accentInk)
              .textAlign(TextAlign.Center)
              .constraintSize({ minWidth: 22 })
              .height(22)
              .borderRadius(11)
              .padding({ left: 6, right: 6 })
              .backgroundColor(appStore.theme.p.accent)
          }
          .width('calc(100% - 24vp)')
          .height(44)
          .padding({ left: 12, right: 12 })
          .margin({ left: 12, right: 12, bottom: 4 })
          .borderRadius(10)
          .alignItems(VerticalAlign.Center)
          .onClick(() => this.onNeeds())
        }
        if (appStore.link.team === null) {
          Column() {
            Text(t('Connecting…'))
              .fontSize(type.small.fontSize)
              .lineHeight(type.small.lineHeight)
              .fontWeight(type.small.fontWeight)
              .fontColor(appStore.theme.p.ink3)
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List() {
            if (this.mainTiles.length > 0) {
              ListItem() {
                this.mainTilesView()
              }
            }
            ForEach(this.entries, (entry: ListEntry) => {
              ListItem() {
                if (entry.kind === 'bot' && entry.bot !== null) {
                  BotRowView({
                    bot: entry.bot,
                    preview: this.botPreview(entry.bot),
                    unread: isUnread(entry.bot.id, entry.bot.lastAt, false),
                    selected: this.current === entry.bot.id,
                    waiting: this.botWaiting(entry.bot),
                    working: this.botWorking(entry.bot),
                    onPress: (): void => {
                      this.onOpen({ kind: 'bot', id: entry.bot?.id ?? '' })
                    },
                  })
                } else if (entry.kind === 'room' && entry.room !== null) {
                  RoomRowView({
                    room: entry.room,
                    preview: this.roomPreview(entry.room),
                    unread: isUnread(entry.room.id, entry.room.lastAt, false),
                    selected: this.current === entry.room.id,
                    waiting: this.roomWaiting(entry.room),
                    working: this.roomWorking(entry.room),
                    onPress: (): void => {
                      this.onOpen({ kind: 'room', id: entry.room?.id ?? '' })
                    },
                  })
                }
              }
            }, (entry: ListEntry): string => `${entry.kind}-${entry.bot?.id ?? entry.room?.id ?? ''}`)
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
        }
        Row() {
          this.roundButton('gear', t('Settings'), (): void => {
            this.onSettings()
          })
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(appStore.theme.p.sidebar)
      if (this.newOpen) {
        Column() {
          Column() {
            this.newRow('plus', t('Create new Bot'), (): void => {
              this.newOpen = false
              this.onCreateBot()
            })
            Row() {
            }
            .width('100%')
            .height(this.getUIContext().px2vp(1))
            .backgroundColor(appStore.theme.p.line)
            .margin({ left: 64 })
            this.newRow('people', t('Create group chat'), (): void => {
              this.newOpen = false
              this.onCreateGroup()
            })
          }
          .width('calc(100% - 24vp)')
          // The card floats over the gesture zone; its bottom gap is half of
          // what the safe inset plus margin used to leave below it.
          .margin({ left: 12, right: 12, bottom: (appStore.safeBottom + 12) / 2 })
          .borderRadius(16)
          .border({
            width: this.getUIContext().px2vp(1),
            color: appStore.theme.p.line,
          })
          .backgroundColor(appStore.theme.p.card)
          .clip(true)
          .shadow(shadowOf(3))
        }
        .width('100%')
        // Extends past the drawer's safe-bottom padding so the card can sit
        // lower, right down toward the true screen edge.
        .height(`calc(100% + ${appStore.safeBottom}vp)`)
        .justifyContent(FlexAlign.End)
        .backgroundColor('rgba(0,0,0,0.25)')
        .onClick(() => {
          this.newOpen = false
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  /** The 36×36 round head buttons (Search / New / gear). */
  @Builder
  roundButton(name: string, label: string, action: () => void) {
    Column() {
      Icon({ name: name, iconSize: 16, color: appStore.theme.p.ink2 })
    }
    .width(36)
    .height(36)
    .borderRadius(18)
    .border({
      width: this.getUIContext().px2vp(1),
      color: appStore.theme.p.line,
    })
    .backgroundColor(appStore.theme.p.card)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .accessibilityText(label)
    .onClick(() => action())
  }

  /** Main Bot tiles on top of the list, like the desktop sidebar. */
  @Builder
  mainTilesView() {
    Flex({
      wrap: FlexWrap.Wrap,
      justifyContent: FlexAlign.Center,
    }) {
      ForEach(this.mainTiles, (main: Bot) => {
        Column() {
          Avatar({
            bot: main,
            dark: appStore.theme.dark,
            markSize: 52,
            ring: appStore.theme.p.hover,
            main: true,
            working: this.botWorking(main),
            waiting: appStore.link.team?.questions?.[main.sessionId ?? main.id] !== undefined,
          })
          Text(main.name)
            .fontSize(type.small.fontSize)
            .lineHeight(type.small.lineHeight)
            .fontWeight('600')
            .fontColor(appStore.theme.p.ink)
            .maxLines(1)
            .margin({ top: 6 })
          if (main.role !== undefined && main.role !== '') {
            Text(main.role)
              .fontSize(11)
              .lineHeight(15)
              .fontColor(appStore.theme.p.ink2)
              .maxLines(1)
              .margin({ top: 3 })
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(6)
              .backgroundColor(appStore.theme.p.active)
          }
        }
        .width(104)
        .alignItems(HorizontalAlign.Center)
        .borderRadius(radius.card)
        .padding({ left: 6, right: 6, top: 10, bottom: 8 })
        .backgroundColor(this.tilePressed === main.id || this.current === main.id ? appStore.theme.p.active : appStore.theme.p.hover)
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.tilePressed = main.id
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.tilePressed = ''
          }
        })
        .onClick(() => {
          this.onOpen({ kind: 'bot', id: main.id })
        })
      }, (main: Bot): string => main.id)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 4, bottom: 10 })
  }

  /** One row of the New menu. */
  @Builder
  newRow(icon: string, label: string, action: () => void) {
    Row({ space: 12 }) {
      Column() {
        Icon({ name: icon, iconSize: 18, color: appStore.theme.p.ink })
      }
      .width(36)
      .height(36)
      .borderRadius(18)
      .backgroundColor(appStore.theme.p.hover)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      Text(label)
        .fontSize(type.settingsRow.fontSize)
        .lineHeight(type.settingsRow.lineHeight)
        .fontWeight(type.settingsRow.fontWeight)
        .fontColor(appStore.theme.p.ink)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .constraintSize({ minHeight: 56 })
    .padding({ left: 14, right: 14 })
    .onClick(() => action())
  }
}

@ComponentV2
struct BotRowView {
  @Require @Param bot: Bot
  @Param preview: string = ''
  @Param unread: boolean = false
  @Param selected: boolean = false
  @Param waiting: boolean = false
  @Param working: boolean = false
  @Event onPress: () => void = () => {}
  @Local pressed: boolean = false

  build() {
    Row({ space: 10 }) {
      Avatar({
        bot: this.bot,
        dark: appStore.theme.dark,
        markSize: 36,
        ring: appStore.theme.p.sidebar,
        working: this.working,
        waiting: this.waiting,
      })
      Column() {
        Row({ space: 6 }) {
          Text(this.bot.name)
            .fontSize(type.rowName.fontSize)
            .lineHeight(type.rowName.lineHeight)
            .fontWeight(type.rowName.fontWeight)
            .fontColor(appStore.theme.p.ink)
            .maxLines(1)
          if (this.bot.pinned === true) {
            Icon({ name: 'pinMark', iconSize: 12 })
          }
          if (this.unread) {
            Blank()
            Row() {
            }
            .width(8)
            .height(8)
            .borderRadius(4)
            .backgroundColor(appStore.theme.p.accent)
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        if (this.preview !== '') {
          Text(this.preview)
            .fontSize(type.rowPreview.fontSize)
            .lineHeight(type.rowPreview.lineHeight)
            .fontWeight(type.rowPreview.fontWeight)
            .fontColor(appStore.theme.p.ink2)
            .maxLines(1)
            .margin({ top: 1 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('calc(100% - 16vp)')
    .alignItems(VerticalAlign.Center)
    .constraintSize({ minHeight: 52 })
    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
    .margin({ left: 8, right: 8 })
    .borderRadius(10)
    .backgroundColor(this.pressed || this.selected ? appStore.theme.p.hover : 'transparent')
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.pressed = true
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressed = false
      }
    })
    .onClick(() => this.onPress())
  }
}

@ComponentV2
struct RoomRowView {
  @Require @Param room: Room
  @Param preview: string = ''
  @Param unread: boolean = false
  @Param selected: boolean = false
  @Param waiting: boolean = false
  @Param working: boolean = false
  @Event onPress: () => void = () => {}
  @Local pressed: boolean = false

  build() {
    Row({ space: 10 }) {
      Stack({ alignContent: Alignment.BottomEnd }) {
        RoomAvatar({
          room: this.room,
          bots: appStore.link.team?.bots ?? [],
          dark: appStore.theme.dark,
          markSize: 36,
          ring: appStore.theme.p.sidebar,
        })
        if (this.waiting) {
          Column() {
            Text('?')
              .fontSize(9)
              .lineHeight(11)
              .fontWeight('600')
              .fontColor('#ffffff')
              .textAlign(TextAlign.Center)
          }
          .width(12)
          .height(12)
          .borderRadius(6)
          .border({ width: 3, color: appStore.theme.p.main })
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor(appStore.theme.p.accent)
          .offset({ x: 2, y: 2 })
        } else if (this.working) {
          Column() {
          }
          .width(8)
          .height(8)
          .borderRadius(4)
          .border({ width: 3, color: appStore.theme.p.main })
          .backgroundColor(appStore.theme.p.green)
          .offset({ x: 2, y: 2 })
        }
      }
      Column() {
        Row({ space: 6 }) {
          Text(this.room.name)
            .fontSize(type.rowName.fontSize)
            .lineHeight(type.rowName.lineHeight)
            .fontWeight(type.rowName.fontWeight)
            .fontColor(appStore.theme.p.ink)
            .maxLines(1)
          if (this.room.pinned === true) {
            Icon({ name: 'pinMark', iconSize: 12 })
          }
          if (this.unread) {
            Blank()
            Row() {
            }
            .width(8)
            .height(8)
            .borderRadius(4)
            .backgroundColor(appStore.theme.p.accent)
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        if (this.preview !== '') {
          Text(this.preview)
            .fontSize(type.rowPreview.fontSize)
            .lineHeight(type.rowPreview.lineHeight)
            .fontWeight(type.rowPreview.fontWeight)
            .fontColor(appStore.theme.p.ink2)
            .maxLines(1)
            .margin({ top: 1 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('calc(100% - 16vp)')
    .alignItems(VerticalAlign.Center)
    .constraintSize({ minHeight: 52 })
    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
    .margin({ left: 8, right: 8 })
    .borderRadius(10)
    .backgroundColor(this.pressed || this.selected ? appStore.theme.p.hover : 'transparent')
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.pressed = true
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressed = false
      }
    })
    .onClick(() => this.onPress())
  }
}
