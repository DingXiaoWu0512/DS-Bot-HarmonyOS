// The Needs-you panel: every pending thing grouped the way the desktop groups
// them (mobile/src/screens/NeedsYou.tsx) — questions, approvals, secret
// requests, browser handoffs and cards each get a section with its own badge.
// A row opens the chat it belongs to (a roomId rows to the group, everything
// else to the Bot); the shell's chat home swaps in place via appStore.openChat.

import { appStore, type, radius } from '../components/Theme'
import { t } from '../common/ui/i18n'
import type { Approval, Bot, Room, SecretRequest, ShownView, TeamState } from '../common/team/types'
import { Avatar } from '../components/Marks'
import type { ChatTarget } from '../appstate/AppStore'

// One pending row: what opens, and the one-line summary under the name.
interface PendingRow {
  key: string
  botId: string
  roomId: string
  summary: string
}

interface PendingSection {
  title: string
  mark: string
  rows: PendingRow[]
}

interface RowLook {
  name: string
  bot: Bot | null
  pressed: boolean
}

// The teams' Bot for a session id (its own chat) or an exact id.
function botOfSession(team: TeamState, sessionId: string): Bot | null {
  for (const bot of team.bots) {
    if (bot.sessionId === sessionId || bot.id === sessionId) return bot
  }
  return null
}

function botById(team: TeamState, id: string): Bot | null {
  for (const bot of team.bots) {
    if (bot.id === id) return bot
  }
  return null
}

function roomById(team: TeamState, id: string): Room | null {
  for (const room of team.rooms ?? []) {
    if (room.id === id) return room
  }
  return null
}

function pendingSections(team: TeamState): PendingSection[] {
  const questions: PendingRow[] = []
  const entries = Object.entries(team.questions ?? {})
  for (const pair of entries) {
    const sessionId = pair[0]
    const question = pair[1]
    const bot = botOfSession(team, sessionId)
    if (bot !== null) {
      questions.push({ key: `q-${question.id}`, botId: bot.id, roomId: '', summary: question.question })
    }
  }
  const approvals: PendingRow[] = []
  for (const approval of team.work?.approvals ?? []) {
    const item: Approval = approval
    const parts: string[] = []
    if (item.tool !== '') parts.push(item.tool)
    if (item.reason !== '') parts.push(item.reason)
    approvals.push({ key: `a-${item.id}`, botId: item.botId, roomId: item.roomId ?? '', summary: parts.join(' · ') })
  }
  const secrets: PendingRow[] = []
  const secretEntries = Object.entries(team.secretRequests ?? {})
  for (const pair of secretEntries) {
    const botId = pair[0]
    const list = pair[1]
    for (const request of list ?? []) {
      const item: SecretRequest = request
      if (item.status !== 'pending') continue
      const summary = item.name !== undefined && item.name !== ''
        ? t('Asks for the secret {name}', { 'name': item.name })
        : t('A secret is needed')
      secrets.push({ key: `s-${item.id}`, botId, roomId: '', summary })
    }
  }
  const handoffs: PendingRow[] = []
  const holdEntries = Object.entries(team.browserHolds ?? {})
  for (const pair of holdEntries) {
    const botId = pair[0]
    const hold = pair[1]
    if (hold.callId === undefined) continue
    const summary = hold.note ?? hold.reason ?? t('Browser handoff')
    handoffs.push({ key: `h-${hold.callId}`, botId, roomId: '', summary })
  }
  const views: PendingRow[] = []
  const viewEntries = Object.entries(team.views ?? {})
  for (const pair of viewEntries) {
    const sessionId = pair[0]
    const shown: ShownView = pair[1]
    const bot = botOfSession(team, sessionId)
    if (bot !== null) {
      const title = shown?.title !== undefined && shown.title !== '' ? shown.title : 'View'
      views.push({ key: `v-${shown?.id ?? sessionId}`, botId: bot.id, roomId: '', summary: title })
    }
  }
  const sections: PendingSection[] = [
    { title: t('Questions'), mark: '?', rows: questions },
    { title: t('Approvals'), mark: '!', rows: approvals },
    { title: t('Secret requests'), mark: '🔑', rows: secrets },
    { title: t('Browser handoffs'), mark: '🌐', rows: handoffs },
    { title: t('Cards'), mark: '▣', rows: views },
  ]
  const visible: PendingSection[] = []
  for (const section of sections) {
    if (section.rows.length > 0) visible.push(section)
  }
  return visible
}

function rowCount(sections: PendingSection[]): number {
  let total = 0
  for (const section of sections) {
    total += section.rows.length
  }
  return total
}

@ComponentV2
export struct NeedsYou {
  @Local pathStack: NavPathStack | null = null
  @Local pressedKey: string = ''
  @Local refreshTick: number = 0

  private team(): TeamState | null {
    void this.refreshTick
    return appStore.link.team
  }

  private sections(): PendingSection[] {
    const team = this.team()
    if (team === null) return []
    return pendingSections(team)
  }

  private empty(): boolean {
    return this.sections().length === 0
  }

  private lookOf(row: PendingRow): RowLook {
    const team = this.team()
    if (team === null) {
      return { name: '', bot: null, pressed: this.pressedKey === row.key }
    }
    const room = row.roomId !== '' ? roomById(team, row.roomId) : null
    const bot = botById(team, row.botId)
    const name = room !== null ? room.name : (bot !== null ? bot.name : '')
    return { name, bot, pressed: this.pressedKey === row.key }
  }

  private targetOf(row: PendingRow): ChatTarget {
    if (row.roomId !== '') {
      return { kind: 'room', id: row.roomId }
    }
    return { kind: 'bot', id: row.botId }
  }

  private openRow(row: PendingRow): void {
    this.pressedKey = ''
    appStore.openChat(this.targetOf(row))
    if (this.pathStack !== null) {
      this.pathStack.clear()
    }
  }

  @Builder
  sectionHeader(section: PendingSection) {
    Row({ space: 8 }) {
      Text(section.mark)
        .fontSize(11)
        .lineHeight(20)
        .textAlign(TextAlign.Center)
        .fontColor(appStore.theme.p.ink2)
        .width(20)
        .height(20)
        .borderRadius(radius.tag)
        .backgroundColor(appStore.theme.p.hover)
      Text(section.title)
        .fontSize(type.caption.fontSize)
        .lineHeight(type.caption.lineHeight)
        .fontWeight('600')
        .fontColor(appStore.theme.p.ink3)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 4 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  pendingRow(row: PendingRow) {
    Row({ space: 12 }) {
      if (this.lookOf(row).bot !== null) {
        Avatar({
          bot: this.lookOf(row).bot ?? undefined,
          dark: appStore.theme.dark,
          markSize: 44,
          ring: appStore.theme.p.main,
          waiting: true,
        })
      } else {
        Column()
          .width(44)
          .height(44)
      }
      Column({ space: 1 }) {
        Text(this.lookOf(row).name)
          .fontSize(type.rowName.fontSize)
          .lineHeight(type.rowName.lineHeight)
          .fontWeight(type.rowName.fontWeight)
          .fontColor(appStore.theme.p.ink)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(row.summary)
          .fontSize(type.rowPreview.fontSize)
          .lineHeight(type.rowPreview.lineHeight)
          .fontWeight(type.rowPreview.fontWeight)
          .fontColor(appStore.theme.p.ink2)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .constraintSize({ minHeight: 56 })
    .width('100%')
    .padding({ left: 16, right: 16, top: 7, bottom: 7 })
    .backgroundColor(this.lookOf(row).pressed ? appStore.theme.p.hover : Color.Transparent)
    .alignItems(VerticalAlign.Center)
    .onClick(() => this.openRow(row))
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.pressedKey = row.key
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressedKey = ''
      }
    })
  }

  build() {
    NavDestination() {
      Column() {
        List({ space: 0 }) {
          if (this.empty()) {
            ListItem() {
              Text(t('Nothing needs you'))
                .fontSize(type.small.fontSize)
                .lineHeight(type.small.lineHeight)
                .fontColor(appStore.theme.p.ink3)
                .textAlign(TextAlign.Center)
                .width('100%')
                .margin({ top: 60 })
            }
          }
          ForEach(this.sections(), (section: PendingSection) => {
            ListItem() {
              this.sectionHeader(section)
            }
            ForEach(section.rows, (row: PendingRow) => {
              ListItem() {
                this.pendingRow(row)
              }
            }, (row: PendingRow) => row.key)
          }, (section: PendingSection) => section.title)
          ListItem() {
            Column().height(appStore.safeBottom)
          }
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(appStore.theme.p.main)
    }
    .title(t('Needs you'))
    .padding({ top: appStore.safeTop })
    .backgroundColor(appStore.theme.p.main)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack
    })
    .onShown(() => {
      // Team reads land while the panel is open; recompute the sections.
      this.refreshTick += 1
    })
  }
}

@Builder
export function NeedsYouBuilder() {
  NeedsYou()
}
