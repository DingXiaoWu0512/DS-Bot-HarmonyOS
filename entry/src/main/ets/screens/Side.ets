// The side chat (mobile/src/screens/side.tsx): quick questions about the work
// so far, answered from progress without running anything. History side chats
// open as cards; an open chat streams answers with a poll to shorten the gap.

import { appStore, type, radius, shadowOf } from '../components/Theme'
import { t } from '../common/ui/i18n'
import type { Bot, TeamState } from '../common/team/types'
import { Avatar } from '../components/Marks'
import { Icon } from '../components/Icon'
import { MarkdownText } from './chat/MarkdownText'
import { readStringParam } from './routes'

interface SideEntry {
  id: string
  question?: string
  answer?: string
  status?: string
  failure?: string
}

interface SideChat {
  chatId: string
  entries?: SideEntry[]
}

interface SideNewReply {
  chatId?: string
}

interface SideChatPayload {
  sessionId?: string
  chatId?: string
  recent?: boolean
  text?: string
  entryId?: string
}

interface SideSessionPayload {
  sessionId: string
}

interface StatePayload {
  since: number
}

interface SideClosePayload {
  chatId: string
}

interface CodedError {
  code?: string
}

const POLL_MS = 1500

function botOf(team: TeamState | null, id: string): Bot | null {
  for (const bot of team?.bots ?? []) {
    if (bot.id === id) return bot
  }
  return null
}

@ComponentV2
export struct Side {
  @Local pathStack: NavPathStack | null = null
  @Local botId: string = ''
  @Local sessionId: string = ''
  @Local openId: string = ''
  @Local draft: string = ''
  @Local busy: boolean = false
  @Local error: string = ''
  @Local refreshTick: number = 0
  private pollTimer: number = -1

  private team(): TeamState | null {
    void this.refreshTick
    return appStore.link.team
  }

  private bot(): Bot | null {
    return botOf(this.team(), this.botId)
  }

  private chats(): SideChat[] {
    return this.team()?.sideChats?.[this.botId] ?? []
  }

  private openChat(): SideChat | null {
    for (const chat of this.chats()) {
      if (chat.chatId === this.openId) return chat
    }
    return null
  }

  private entries(): SideEntry[] {
    return this.openChat()?.entries ?? []
  }

  private running(): boolean {
    for (const entry of this.entries()) {
      if (entry.status === 'answering') return true
    }
    return false
  }

  private hairline(): number {
    return this.getUIContext().px2vp(1)
  }

  private goBack(): void {
    if (this.pathStack !== null) this.pathStack.pop()
  }

  private setPolling(active: boolean): void {
    if (active && this.pollTimer < 0) {
      // While an answer streams, keep asking for fresh state; the link's own
      // poll refreshes team on revision, this just shortens the gap.
      this.pollTimer = setInterval((): void => {
        const controller = appStore.link.controller
        if (controller === null) return
        const payload: StatePayload = { since: -1 }
        void controller.call('state', payload).catch((): void => {})
      }, POLL_MS)
    } else if (!active && this.pollTimer >= 0) {
      clearInterval(this.pollTimer)
      this.pollTimer = -1
    }
  }

  aboutToDisappear(): void {
    this.setPolling(false)
  }

  private async send(): Promise<void> {
    const text = this.draft.trim()
    if (text === '' || this.busy) return
    this.busy = true
    const controller = appStore.link.controller
    if (controller === null) {
      this.busy = false
      return
    }
    try {
      const chat = this.openChat()
      if (chat === null) {
        const sessionPayload: SideSessionPayload = { sessionId: this.sessionId }
        const created = (await controller.call('side-new', sessionPayload)) as SideNewReply | null
        if (created?.chatId !== undefined) this.openId = created.chatId
        const payload: SideChatPayload = { sessionId: this.sessionId, chatId: created?.chatId, recent: true, text: text }
        await controller.call('side-ask', payload)
      } else {
        const payload: SideChatPayload = { sessionId: this.sessionId, chatId: chat.chatId, recent: true, text: text }
        await controller.call('side-ask', payload)
      }
      this.draft = ''
      this.error = ''
    } catch (failure) {
      this.error = failure instanceof Error ? failure.message : String(failure)
    } finally {
      this.busy = false
    }
  }

  private closeChat(): void {
    const chat = this.openChat()
    if (chat === null) return
    const controller = appStore.link.controller
    if (controller === null) return
    const payload: SideClosePayload = { chatId: chat.chatId }
    void controller.call('side-close', payload).then((): void => {
      this.openId = ''
    }).catch((): void => {})
  }

  private cancelEntry(entry: SideEntry): void {
    const chat = this.openChat()
    if (chat === null) return
    const controller = appStore.link.controller
    if (controller === null) return
    const payload: SideChatPayload = { chatId: chat.chatId, entryId: entry.id }
    void controller.call('side-cancel', payload).catch((): void => {})
  }

  private lastQuestion(item: SideChat): string {
    const entries = item.entries ?? []
    const last = entries.length > 0 ? entries[entries.length - 1] : undefined
    if (last !== undefined && (last.question ?? '') !== '') return last.question ?? ''
    return t('New side chat')
  }

  private sendOpacity(): number {
    if (this.draft.trim() === '' || this.busy) return 0.4
    return 1
  }

  build() {
    NavDestination() {
      Column() {
        // The head: back, the Bot over its "Side chat" label, close.
        Row({ space: 10 }) {
          Column() {
            Icon({ name: 'chevronLeft', iconSize: 20, color: appStore.theme.p.ink2 })
          }
          .width(40)
          .height(40)
          .alignItems(HorizontalAlign.Center)
          .justifyContent(FlexAlign.Center)
          .onClick(() => this.goBack())
          if (this.bot() !== null) {
            Avatar({
              bot: this.bot() ?? undefined,
              dark: appStore.theme.dark,
              markSize: 28,
              ring: appStore.theme.p.main,
            })
          }
          Column({ space: 1 }) {
            Text(this.bot()?.name ?? '')
              .fontSize(type.rowName.fontSize)
              .lineHeight(type.rowName.lineHeight)
              .fontWeight(type.rowName.fontWeight)
              .fontColor(appStore.theme.p.ink)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(t('Side chat'))
              .fontSize(type.caption.fontSize)
              .lineHeight(type.caption.lineHeight)
              .fontColor(appStore.theme.p.ink3)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .constraintSize({ minWidth: 0 })
          .alignItems(HorizontalAlign.Start)
          if (this.openChat() !== null) {
            Column() {
              Icon({ name: 'close', iconSize: 18, color: appStore.theme.p.ink2 })
            }
            .width(40)
            .height(40)
            .alignItems(HorizontalAlign.Center)
            .justifyContent(FlexAlign.Center)
            .accessibilityText(t('Close'))
            .onClick(() => this.closeChat())
          } else {
            Column()
              .width(40)
              .height(40)
          }
        }
        .width('100%')
        .padding({ left: 10, right: 10, top: 8, bottom: 8 })
        .alignItems(VerticalAlign.Center)
        Scroll() {
          Column() {
            if (this.openChat() === null) {
              // History: one card per side chat, the last question as title.
              ForEach(this.chats(), (item: SideChat) => {
                Column({ space: 3 }) {
                  Text(this.lastQuestion(item))
                    .fontSize(type.settingsRow.fontSize)
                    .lineHeight(type.settingsRow.lineHeight)
                    .fontColor(appStore.theme.p.ink)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(t('{count} questions', { 'count': (item.entries ?? []).length }))
                    .fontSize(type.small.fontSize)
                    .lineHeight(type.small.lineHeight)
                    .fontColor(appStore.theme.p.ink3)
                }
                .width('100%')
                .padding(14)
                .margin({ bottom: 10 })
                .borderRadius(radius.card)
                .border({ width: 1, color: appStore.theme.p.line })
                .backgroundColor(appStore.theme.p.card)
                .shadow(shadowOf(1))
                .alignItems(HorizontalAlign.Start)
                .onClick(() => {
                  this.openId = item.chatId
                })
              }, (item: SideChat) => item.chatId)
              if (this.chats().length === 0) {
                Text(t('Ask about the work so far'))
                  .fontSize(type.small.fontSize)
                  .lineHeight(type.small.lineHeight)
                  .fontColor(appStore.theme.p.ink3)
                  .width('100%')
                  .textAlign(TextAlign.Center)
                  .margin({ top: 30 })
              }
            } else {
              ForEach(this.entries(), (entry: SideEntry) => {
                Column() {
                  Column() {
                    Text(entry.question ?? '')
                      .fontSize(type.settingsRow.fontSize)
                      .lineHeight(type.settingsRow.lineHeight)
                      .fontColor(appStore.theme.p.ink)
                  }
                  .constraintSize({ maxWidth: '85%' })
                  .borderRadius(radius.card)
                  .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                  .backgroundColor(appStore.theme.p.hover)
                  if (entry.status === 'answering') {
                    Row({ space: 10 }) {
                      Text(t('Answering…'))
                        .fontSize(type.small.fontSize)
                        .lineHeight(type.small.lineHeight)
                        .fontColor(appStore.theme.p.ink3)
                      Text(t('Cancel this side question'))
                        .fontSize(13)
                        .lineHeight(18)
                        .fontColor(appStore.theme.p.ink2)
                        .onClick(() => this.cancelEntry(entry))
                    }
                    .margin({ top: 6 })
                    .alignItems(VerticalAlign.Center)
                  } else {
                    Column() {
                      if (entry.status === 'cancelled') {
                        Text(t('Cancelled'))
                          .fontSize(type.small.fontSize)
                          .lineHeight(type.small.lineHeight)
                          .fontColor(appStore.theme.p.ink3)
                      }
                      if (entry.status === 'failed') {
                        Text(entry.failure ?? t('The side answer failed.'))
                          .fontSize(type.small.fontSize)
                          .lineHeight(type.small.lineHeight)
                          .fontColor(appStore.theme.p.danger)
                      }
                      if ((entry.answer ?? '') !== '') {
                        MarkdownText({
                          text: entry.answer ?? '',
                          textColor: appStore.theme.p.ink,
                          fontSize: 15,
                          lineHeight: 22,
                        })
                      }
                    }
                    .margin({ top: 6 })
                    .width('100%')
                    .alignItems(HorizontalAlign.Start)
                  }
                }
                .width('100%')
                .margin({ bottom: 12 })
                .alignItems(HorizontalAlign.End)
              }, (entry: SideEntry) => entry.id)
              Text(t('Answered from progress so far; nothing was run'))
                .fontSize(type.caption.fontSize)
                .lineHeight(type.caption.lineHeight)
                .fontColor(appStore.theme.p.ink3)
                .width('100%')
                .margin({ top: 4 })
            }
            if (this.error !== '') {
              Text(this.error)
                .fontSize(type.small.fontSize)
                .lineHeight(type.small.lineHeight)
                .fontColor(appStore.theme.p.danger)
                .width('100%')
                .margin({ top: 8 })
            }
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 14, bottom: 10 })
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
        // The composer: multiline input and the send pill.
        Row({ space: 8 }) {
          TextArea({ text: this.draft, placeholder: t('Ask about the work so far') })
            .fontSize(15)
            .fontColor(appStore.theme.p.ink)
            .placeholderColor(appStore.theme.p.ink3)
            .backgroundColor(Color.Transparent)
            .border({ width: 1, color: appStore.theme.p.line })
            .borderRadius(20)
            .padding({ left: 14, right: 14, top: 10, bottom: 10 })
            .constraintSize({ maxHeight: 120 })
            .layoutWeight(1)
            .onChange((value: string): void => {
              this.draft = value
            })
          Column() {
            Icon({ name: 'arrowUp', iconSize: 18, color: appStore.theme.p.accentInk })
          }
          .width(40)
          .height(40)
          .borderRadius(20)
          .backgroundColor(appStore.theme.p.accent)
          .opacity(this.sendOpacity())
          .alignItems(HorizontalAlign.Center)
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            void this.send()
          })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .border({ width: { top: this.hairline() }, color: appStore.theme.p.line })
        .alignItems(VerticalAlign.Bottom)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(appStore.theme.p.main)
    }
    .hideTitleBar(true)
    .padding({ top: appStore.safeTop, bottom: appStore.safeBottom })
    .backgroundColor(appStore.theme.p.main)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack
      this.botId = readStringParam(ctx.pathInfo.param, 'botId')
      this.sessionId = readStringParam(ctx.pathInfo.param, 'sessionId')
    })
    .onShown(() => {
      this.refreshTick += 1
    })
    .onHidden(() => {
      this.setPolling(false)
    })
  }
}

@Builder
export function SideBuilder() {
  Side()
}
