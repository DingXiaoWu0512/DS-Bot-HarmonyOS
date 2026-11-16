// The chat screen: the port of mobile/src/screens/Chat.tsx's ChatView. An
// inverted list (MessageList), the pending dock, the composer, the pending-send
// outbox that survives chat switches, the page cache shared with prefetchChat,
// and the poll/feed/refresh loop. The shell (Index) owns the header; this
// screen covers the rest of the chat base and is mounted whenever a team shows.
//
// Recovered from the ArkTS compiler cache (fields, methods and the original
// line numbers) after an accidental overwrite, with the UI trees rebuilt.

import { display } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'

import { appStore, type, radius, shadowOf, MONO, Palette, rgba } from '../components/Theme'
import type { ChatTarget } from '../appstate/AppStore'
import { t } from '../common/ui/i18n'
import type { Approval, Bot, ChatItem, ComputerAsk, ComputerControl, ComputerLive, FileRef, ModelInfo, Question, Room, RoomGoal, RoomGoalStage, RoomGoalTask, SecretRequest, ShownView, TeamState } from '../common/team/types'
import {
  keepSame, keysOf, stampOf,
  markOutgoing, queueOutgoing, dropOutgoing, findOutgoing, dropShownOutbox,
  outboxOf, subscribeOutbox, fileTextOf, stageImageId,
} from '../common/team/chat-state'
import type { Outgoing } from '../common/team/chat-state'
import { createChatCache, markSeen } from '../common/team/state-utils'
import type { CachedChatEntry } from '../common/team/state-utils'
import { offline } from '../common/team/team-link'
import type { CallFn } from '../common/team/team-link'
import { workPhrase } from '../common/ui/phrases'
import type { DoingState } from '../common/ui/phrases'
import { hapticLight } from '../platform/Platform'
import { Avatar, RoomAvatar } from '../components/Marks'
import { MessageList } from './chat/MessageList'
import type { MessageRow } from './chat/MessageList'
import { Composer } from './chat/ChatInput'
import type { ComposerPhoto } from './chat/ChatInput'
import { Dock, ActionRow } from './chat/ChatCards'
import type { BtwCardData, HandoffData } from './chat/ChatCards'
import { Actions, PhotoViewer } from './chat/ChatRows'
import type { PhotoOpenData } from './chat/ChatRows'
import { openExternalUrl } from './chat/MarkdownText'

// Feed events refresh the chat as things happen; the poll only catches what a
// dropped event missed, so it runs rarely.
const POLL_MS: number = 15_000

// The immersive top (沉浸光感渐变模糊): the list content frosts progressively
// under the floating header. The gradient blur runs on the unrotated list
// container — full blur at the top edge easing to clear below the header.
const TOP_FROST_STOPS: FractionStop[] = [[1, 0], [0.55, 0.05], [0, 0.115]]
const TOP_FROST_RADIUS: number = 30
// The last page of each chat opened in this run, kept in memory only.
const PAGES_KEPT: number = 16

// One page of a chat, as the 'chat'/'room-chat' calls answer it.
interface ChatPage {
  sessionId?: string
  items: ChatItem[]
  cursor: Object | null
}

const pages = createChatCache<ChatPage, ChatItem>(PAGES_KEPT)

// A chat read started before the chat is on screen: on launch the last chat is
// asked for while the team state is still on its way, and the chat takes that
// answer.
const reads = new Map<string, Promise<ChatPage>>()

function readChat(call: CallFn, room: boolean, id: string): Promise<ChatPage> {
  const payload: Record<string, Object> = room ? { 'roomId': id, 'steps': true } : { 'botId': id, 'steps': true }
  return call(room ? 'room-chat' : 'chat', payload) as Promise<ChatPage>
}

/** Asks for a chat before it is on screen, so opening it shows at once. */
export function prefetchChat(call: CallFn, computerId: string, target: ChatTarget): void {
  const key: string = `${computerId}:${target.kind}:${target.id}`
  if (pages.has(key) || reads.has(key)) return
  const read = readChat(call, target.kind === 'room', target.id)
  reads.set(key, read)
  read.catch((): void => {}).finally((): void => {
    if (reads.get(key) === read) {
      setTimeout((): void => {
        reads.delete(key)
      }, 5000)
    }
  })
}

// Host failures carry a DSH failure code next to the message.
interface CodedError {
  code?: string
}

// The desktop's repair card (turn-error.js) for a failure only the user can fix.
function failureText(code: string, name: string, provider: string, status?: number): string {
  switch (code) {
    case 'MISSING_CREDENTIAL': return t("{name}'s model has no API key yet.", { 'name': name })
    case 'INVALID_CREDENTIAL': return t('This API key is not in the right format.')
    case 'AUTH': return status === undefined
      ? t('{provider} did not accept the current API key.', { 'provider': provider })
      : t('{provider} did not accept the current API key ({status}).', { 'provider': provider, 'status': status })
    case 'QUOTA': return status === undefined
      ? t('{provider} is out of balance or quota.', { 'provider': provider })
      : t('{provider} is out of balance or quota ({status}).', { 'provider': provider, 'status': status })
    case 'ACCOUNT_QUOTA': return t('The DeepSeek account balance is too low.')
    case 'ACCOUNT_SIGN_IN_REQUIRED':
    case 'ACCOUNT_SIGNED_OUT':
    case 'ACCOUNT_TOKEN_INVALID': return t('The DeepSeek account sign-in has expired.')
    default: return t('This turn failed.')
  }
}

// A group's work entry (team.work.rooms value), named so the chat can hold it
// without reaching through the wire type.
interface RoomWorkEntry {
  botId: string
  tool?: string
  said?: string
  note?: string
  target?: string
}

// One computer-use answer button (ComputerCards below).
interface AskButtonOptions {
  ask: ComputerAsk
  answer: string
  label: string
  accent: boolean
}

const REPORTED: Set<string> = new Set<string>(['reported', 'done'])
const RUNNING: Set<string> = new Set<string>(['active', 'paused'])

// A group's goal, as the desktop's goal island shows it: the goal and the stage
// it is at, the stage bar, and on a tap every stage with its state.
@ComponentV2
struct GoalBar {
  @Require @Param goal: RoomGoal
  @Local open: boolean = false

  private p(): Palette {
    return appStore.theme.p
  }

  private hairline(): number {
    return this.getUIContext().px2vp(1)
  }

  private stages(): RoomGoalStage[] {
    return this.goal.stages ?? []
  }

  private at(): number {
    return this.goal.current ?? 0
  }

  private currentStage(): RoomGoalStage | undefined {
    if (!RUNNING.has(this.goal.status ?? '')) return undefined
    return this.stages()[this.at()]
  }

  private checking(): boolean {
    const current: RoomGoalStage | undefined = this.currentStage()
    if (current === undefined) return false
    return (current.tasks ?? []).every((task: RoomGoalTask): boolean => REPORTED.has(task.status ?? ''))
  }

  private stageNumber(): number | undefined {
    const status: string | undefined = this.goal.status
    if (status === 'drafting') return undefined
    if (status === 'stopped') {
      return this.stages().filter((stage: RoomGoalStage): boolean => stage.status === 'passed').length
    }
    const current: RoomGoalStage | undefined = this.currentStage()
    if (current !== undefined) return this.at() + 1
    return this.stages().length
  }

  private label(): string {
    const status: string | undefined = this.goal.status
    const current: RoomGoalStage | undefined = this.currentStage()
    if (status === 'drafting') return t('Aligning the goal with you')
    if (status === 'stopped') return t('Stopped')
    if (status === 'complete') return t('Goal reached')
    if (status === 'paused') {
      return current !== undefined ? t('Paused · {title}', { 'title': current.title ?? '' }) : t('Paused')
    }
    if (this.goal.idle === true) {
      return current !== undefined ? t('Waiting for you · {title}', { 'title': current.title ?? '' }) : t('Waiting for you')
    }
    if (current === undefined) return t('Final check')
    return this.checking() ? t('Checking · {title}', { 'title': current.title ?? '' }) : current.title ?? ''
  }

  private segmentColor(index: number): string {
    const stage: RoomGoalStage | undefined = this.stages()[index]
    if (stage !== undefined && stage.status === 'passed') return this.p().green
    if (index === this.at() && RUNNING.has(this.goal.status ?? '')) return this.p().accent
    return this.p().line
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Text(this.goal.title ?? '')
          .fontSize(type.settingsRow.fontSize)
          .lineHeight(type.settingsRow.lineHeight)
          .fontWeight('600')
          .fontColor(this.p().ink)
          .layoutWeight(1)
          .maxLines(1)
        if (this.stageNumber() !== undefined) {
          Text(`${this.stageNumber()}/${this.stages().length}`)
            .fontSize(type.caption.fontSize)
            .lineHeight(type.caption.lineHeight)
            .fontColor(this.p().ink3)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      Text(this.label())
        .fontSize(type.small.fontSize)
        .lineHeight(type.small.lineHeight)
        .fontColor(this.p().ink2)
        .margin({ top: 2 })
        .maxLines(this.open ? 9999 : 1)
      if (this.stages().length > 0) {
        Row({ space: 3 }) {
          ForEach(this.stages(), (stage: RoomGoalStage, index: number) => {
            Row({ space: 8 }) {
              Text(`${index + 1}`)
                .fontSize(type.small.fontSize)
                .lineHeight(type.small.lineHeight)
                .fontColor(this.p().ink3)
                .constraintSize({ minWidth: 18 })
              Text(stage.title ?? '')
                .fontSize(type.small.fontSize)
                .lineHeight(type.small.lineHeight)
                .fontColor(stage.status === 'passed' ? this.p().ink3 : this.p().ink)
                .layoutWeight(1)
              if (stage.status === 'passed') {
                Text('✓')
                  .fontSize(13)
                  .fontColor(this.p().green)
              }
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
            .margin({ top: 10 })
          }, (stage: RoomGoalStage, index: number): string => `stage-${index}`)
        }
        .width('100%')
        .margin({ top: 8 })
      }
    }
    .width('calc(100% - 24vp)')
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .borderRadius(radius.dialog)
    .border({ width: this.hairline(), color: this.p().line })
    .backgroundColor(this.p().card)
    .margin({ left: 12, right: 12, bottom: 6 })
    .onClick((): void => {
      this.open = !this.open
    })
  }
}

// The desktop's turn-error card (turn-error.js): what failed and the one fix
// for it — enter the key, top up, or pick another model.
@ComponentV2
struct BlockedCard {
  @Require @Param bot: Bot
  @Event onNavigate: (route: string, param: Object | null) => void

  private p(): Palette {
    return appStore.theme.p
  }

  private hairline(): number {
    return this.getUIContext().px2vp(1)
  }

  private providerName(): string {
    const blocked = this.bot.blocked
    if (blocked === undefined) return ''
    const models: ModelInfo[] = appStore.link.team?.models ?? []
    const provider: string = blocked.provider ?? ''
    const found: ModelInfo | undefined = models.find((model: ModelInfo): boolean => model.ref.split('/')[0] === provider)
    return found?.providerName ?? provider
  }

  private isKeyIssue(): boolean {
    const code: string = this.bot.blocked?.code ?? ''
    return code === 'MISSING_CREDENTIAL' || code === 'INVALID_CREDENTIAL' || code === 'AUTH'
  }

  private isTopUp(): boolean {
    const blocked = this.bot.blocked
    if (blocked === undefined) return false
    return (blocked.code === 'QUOTA' && blocked.provider === 'deepseek-official') || blocked.code === 'ACCOUNT_QUOTA'
  }

  build() {
    Column() {
      Text(failureText(this.bot.blocked?.code ?? '', this.bot.name, this.providerName(), this.bot.blocked?.status))
        .fontSize(type.settingsRow.fontSize)
        .lineHeight(type.settingsRow.lineHeight)
        .fontColor(this.p().ink)
      Flex({ wrap: FlexWrap.Wrap }) {
        if (this.isKeyIssue()) {
          Column() {
            Text(this.bot.blocked?.code === 'MISSING_CREDENTIAL' ? t('Enter API key') : t('Enter the key again'))
              .fontSize(type.rowPreview.fontSize)
              .lineHeight(type.rowPreview.lineHeight)
              .fontWeight('600')
              .fontColor(this.p().accentInk)
          }
          .constraintSize({ minHeight: 40 })
          .borderRadius(20)
          .padding({ left: 16, right: 16 })
          .margin({ right: 8, bottom: 8 })
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.p().accent)
          .onClick((): void => {
            this.onNavigate('settings', null)
          })
        }
        if (this.isTopUp()) {
          Column() {
            Text(t('Top up ↗'))
              .fontSize(type.rowPreview.fontSize)
              .lineHeight(type.rowPreview.lineHeight)
              .fontWeight('600')
              .fontColor(this.p().accentInk)
          }
          .constraintSize({ minHeight: 40 })
          .borderRadius(20)
          .padding({ left: 16, right: 16 })
          .margin({ right: 8, bottom: 8 })
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.p().accent)
          .onClick((): void => {
            openExternalUrl(this.getUIContext().getHostContext() as common.UIAbilityContext, 'https://platform.deepseek.com/top_up')
          })
        }
        Column() {
          Text(t('Pick another model'))
            .fontSize(type.rowPreview.fontSize)
            .lineHeight(type.rowPreview.lineHeight)
            .fontColor(this.p().ink)
        }
        .constraintSize({ minHeight: 40 })
        .borderRadius(20)
        .padding({ left: 16, right: 16 })
        .margin({ bottom: 8 })
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.p().hover)
        .onClick((): void => {
          const param: Record<string, Object> = { 'botId': this.bot.id }
          this.onNavigate('botDetails', param)
        })
      }
      .margin({ top: 10 })
    }
    .width('calc(100% - 24vp)')
    .padding(14)
    .borderRadius(radius.dialog)
    .border({ width: this.hairline(), color: this.p().line })
    .backgroundColor(this.p().card)
    .margin({ left: 12, right: 12, bottom: 8 })
  }
}

// Computer use (computer.js): a Bot's ask to use an app, answered Deny / This
// time / Always, and the running row with its Stop button.
@ComponentV2
struct ComputerCards {
  @Require @Param bot: Bot
  @Local error: string = ''

  private p(): Palette {
    return appStore.theme.p
  }

  private hairline(): number {
    return this.getUIContext().px2vp(1)
  }

  private live(): ComputerLive | undefined {
    return appStore.link.team?.computerLive
  }

  private asks(): ComputerAsk[] {
    const out: ComputerAsk[] = []
    const askMap = this.live()?.asks
    if (askMap === undefined) return out
    for (const id of Object.keys(askMap)) {
      const ask: ComputerAsk | undefined = askMap[id]
      if (ask !== undefined && ask.botId === this.bot.id) out.push(ask)
    }
    return out
  }

  private control(): ComputerControl | undefined {
    const botMap = this.live()?.bots
    return botMap !== undefined ? botMap[this.bot.id] : undefined
  }

  private acting(): boolean {
    const control: ComputerControl | undefined = this.control()
    return control !== undefined && control.state !== undefined && control.state !== 'idle'
  }

  private act(endpoint: string, body: Record<string, Object>): void {
    const controller = appStore.link.controller
    if (controller === null) return
    void controller.call(endpoint, body).then((): void => {
      this.error = ''
    }).catch((failure: Error): void => {
      this.error = failure?.message ?? ''
    })
  }

  @Builder
  askButton($$: AskButtonOptions) {
    Column() {
      Text($$.label)
        .fontSize(type.rowPreview.fontSize)
        .lineHeight(type.rowPreview.lineHeight)
        .fontWeight($$.accent ? '600' : '400')
        .fontColor($$.accent ? this.p().accentInk : this.p().ink)
    }
    .constraintSize({ minHeight: 40 })
    .borderRadius(20)
    .padding({ left: 16, right: 16 })
    .margin({ right: 8, bottom: 8 })
    .justifyContent(FlexAlign.Center)
    .backgroundColor($$.accent ? this.p().accent : this.p().hover)
    .onClick((): void => {
      const body: Record<string, Object> = { 'id': $$.ask.id, 'answer': $$.answer }
      this.act('computer-app-answer', body)
    })
  }

  build() {
    if (this.asks().length > 0 || this.acting()) {
      Column() {
        ForEach(this.asks(), (ask: ComputerAsk) => {
          Column() {
            Text(t('Allow {name} to use {app}?', { 'name': this.bot.name, 'app': ask.appName ?? '' }))
              .fontSize(type.settingsRow.fontSize)
              .lineHeight(type.settingsRow.lineHeight)
              .fontColor(this.p().ink)
            Flex({ wrap: FlexWrap.Wrap }) {
              this.askButton({ ask: ask, answer: 'deny', label: t('Deny'), accent: false })
              this.askButton({ ask: ask, answer: 'once', label: t('This time'), accent: false })
              this.askButton({ ask: ask, answer: 'always', label: t('Always'), accent: true })
            }
            .margin({ top: 10 })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding(14)
          .borderRadius(radius.dialog)
          .border({ width: this.hairline(), color: this.p().line })
          .backgroundColor(this.p().card)
          .margin({ bottom: 8 })
        }, (ask: ComputerAsk): string => ask.id)
        if (this.acting()) {
          Row({ space: 8 }) {
            Text(this.control()?.app !== undefined && this.control()?.app !== ''
              ? `${t('Computer use')} · ${this.control()?.app}` : t('Computer use'))
              .fontSize(type.small.fontSize)
              .lineHeight(type.small.lineHeight)
              .fontColor(this.p().ink)
              .layoutWeight(1)
              .maxLines(1)
            Column() {
              Text(t('Stop'))
                .fontSize(type.rowPreview.fontSize)
                .lineHeight(type.rowPreview.lineHeight)
                .fontColor(this.p().danger)
            }
            .constraintSize({ minHeight: 36 })
            .borderRadius(20)
            .padding({ left: 16, right: 16 })
            .justifyContent(FlexAlign.Center)
            .backgroundColor(this.p().hover)
            .onClick((): void => {
              const body: Record<string, Object> = { 'botId': this.bot.id }
              this.act('computer-stop', body)
            })
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .borderRadius(radius.dialog)
          .border({ width: this.hairline(), color: this.p().line })
          .backgroundColor(this.p().card)
          .alignItems(VerticalAlign.Center)
        }
        if (this.error !== '') {
          Text(this.error)
            .fontSize(type.small.fontSize)
            .lineHeight(type.small.lineHeight)
            .fontColor(this.p().danger)
            .margin({ left: 16, right: 16, bottom: 6 })
        }
      }
      .width('100%')
    }
  }
}

@ComponentV2
export struct Chat {
  @Event onNavigate: (route: string, param: Object | null) => void
  @Local page: ChatPage | null = null
  @Local older: ChatItem[] = []
  @Local gone: boolean = false
  @Local loadError: string | null = null
  @Local loadingOlder: boolean = false
  @Local openSteps: Record<string, boolean> = {}
  @Local expandedKey: string | null = null
  @Local menuText: string | null = null
  @Local readerText: string | null = null
  @Local readerTitle: string | null = null
  @Local fileError: string | null = null
  @Local photosOpen: PhotoOpenData | null = null
  @Local chatWidth: number = 0
  @Local pending: Outgoing[] = []
  @Local streamText: string = ''
  // undefined = no page boundary known yet (the first read fills it); null =
  // the chat has no older pages (the REF ref's unknown cursor semantics).
  private cursor: Object | null | undefined = undefined
  private generation: number = 0
  private reading: boolean = false
  private again: boolean = false
  private loading: boolean = false
  private pollTimer: number = -1
  private wasOnline: boolean = false
  private attempts: Map<string, string> = new Map()
  private offFeed: (() => void) | null = null
  private offOutbox: (() => void) | null = null

  // ---- which chat is on screen ----------------------------------------------
  private fallbackBot(): Bot | null {
    const team: TeamState | null = appStore.link.team
    if (team === null) return null
    const mainId: string | null | undefined = team.mainBotId
    if (mainId !== undefined && mainId !== null) {
      const main: Bot | undefined = team.bots.find((entry: Bot): boolean => entry.id === mainId)
      if (main !== undefined) return main
    }
    return team.bots.length > 0 ? team.bots[0] : null
  }

  private roomOf(): Room | null {
    const team: TeamState | null = appStore.link.team
    const target: ChatTarget | null = appStore.currentChat
    if (team !== null && target !== null && target.kind === 'room') {
      const found: Room | undefined = (team.rooms ?? []).find((entry: Room): boolean => entry.id === target.id)
      if (found !== undefined) return found
    }
    return null
  }

  private botOf(): Bot | null {
    const team: TeamState | null = appStore.link.team
    const target: ChatTarget | null = appStore.currentChat
    if (team !== null && target !== null && target.kind === 'bot') {
      const found: Bot | undefined = team.bots.find((entry: Bot): boolean => entry.id === target.id)
      if (found !== undefined) return found
    }
    if (this.roomOf() === null) return this.fallbackBot()
    return null
  }

  private targetIdOf(): string {
    const bot: Bot | null = this.botOf()
    if (bot !== null) return bot.id
    const room: Room | null = this.roomOf()
    return room !== null ? room.id : ''
  }

  private sessionIdOf(): string {
    const page: ChatPage | null = this.page
    if (page !== null && page.sessionId !== undefined) return page.sessionId
    const bot: Bot | null = this.botOf()
    if (bot !== null && bot.sessionId !== undefined) return bot.sessionId
    const room: Room | null = this.roomOf()
    if (room !== null) return room.id
    return this.targetIdOf()
  }

  @Computed
  get watchedKey(): string {
    const room: Room | null = this.roomOf()
    const computerId: string = appStore.computers.active?.hostDeviceId ?? ''
    return `${computerId}:${room !== null ? 'room' : 'bot'}:${this.targetIdOf()}`
  }

  @Computed
  get watchedOnline(): boolean {
    return appStore.link.online
  }

  // ---- the read loop ---------------------------------------------------------
  private clearPoll(): void {
    if (this.pollTimer >= 0) {
      clearTimeout(this.pollTimer)
      this.pollTimer = -1
    }
  }

  /** A chat switch starts over: the cached page, a fresh loop, cleared state. */
  private startChat(): void {
    this.generation += 1
    const key: string = this.watchedKey
    const kept: CachedChatEntry<ChatPage, ChatItem> | undefined = pages.get(key)
    this.page = kept !== undefined ? kept.page : null
    this.older = kept !== undefined ? kept.older : []
    this.cursor = kept !== undefined ? (kept.cursor as Object | null | undefined) : undefined
    this.gone = false
    this.loadError = null
    this.loadingOlder = false
    this.openSteps = {}
    this.expandedKey = null
    this.menuText = null
    this.fileError = null
    this.readerText = null
    this.readerTitle = null
    this.photosOpen = null
    this.attempts.clear()
    this.streamText = ''
    this.pending = outboxOf(key)
    markSeen(this.targetIdOf())
    this.clearPoll()
    void this.loop(this.generation)
  }

  @Monitor('watchedKey')
  onChatSwitch(): void {
    this.startChat()
  }

  private async loop(gen: number): Promise<void> {
    await this.refresh(gen)
    if (this.generation === gen) {
      this.pollTimer = setTimeout((): void => {
        this.pollTimer = -1
        if (this.generation === gen) {
          void this.loop(gen)
        }
      }, POLL_MS)
    }
  }

  private keepPage(): void {
    const page: ChatPage | null = this.page
    if (page === null) return
    const entry: CachedChatEntry<ChatPage, ChatItem> = { page: page, older: this.older, cursor: this.cursor }
    pages.keep(this.watchedKey, this.watchedKey, entry)
  }

  // One chat read at a time, like the team state: a burst of messages becomes
  // one read now and at most one more after it.
  private async refresh(gen: number): Promise<void> {
    const key: string = this.watchedKey
    const id: string = this.targetIdOf()
    const isRoom: boolean = this.roomOf() !== null
    if (id === '' || this.generation !== gen) return
    if (this.reading) {
      this.again = true
      return
    }
    this.reading = true
    try {
      const early: Promise<ChatPage> | undefined = reads.get(key)
      reads.delete(key)
      const next: ChatPage = await (early !== undefined ? early : this.readNow(isRoom, id))
      if (this.generation === gen) {
        const prev: ChatPage | null = this.page
        if (prev !== null && prev.sessionId === next.sessionId) {
          this.page = { sessionId: next.sessionId, items: keepSame(prev.items, next.items), cursor: next.cursor }
        } else {
          this.page = next
        }
        if (this.cursor === undefined) this.cursor = next.cursor
        this.loadError = null
        this.keepPage()
      }
    } catch (failure) {
      if (this.generation !== gen) return
      const code: string = (failure as CodedError)?.code ?? ''
      if (code === 'bot/not-found') {
        this.gone = true
        this.handleMissing()
      } else if (code !== 'link/offline') {
        // Offline is the link's state, not this chat's; the reconnect refreshes.
        this.loadError = failure instanceof Error ? failure.message : String(failure)
      }
    } finally {
      this.reading = false
      if (this.again) {
        this.again = false
        void this.refresh(this.generation)
      }
    }
  }

  private async readNow(isRoom: boolean, id: string): Promise<ChatPage> {
    const controller = appStore.link.controller
    if (controller === null) throw offline()
    return readChat(controller.call, isRoom, id)
  }

  /** The saved chat is gone: forget it and fall back to the Main Bot. */
  private handleMissing(): void {
    appStore.forgetChat()
    const team: TeamState | null = appStore.link.team
    if (team === null) return
    const fallback: Bot | null = this.fallbackBot()
    if (fallback !== null) {
      appStore.openChat({ kind: 'bot', id: fallback.id })
    }
  }

  // The page before the oldest one shown. The cursor lives outside the page
  // state: the list can ask again before the previous load commits.
  private async loadMore(): Promise<void> {
    const id: string = this.targetIdOf()
    const isRoom: boolean = this.roomOf() !== null
    if (this.cursor === null || this.cursor === undefined || id === '' || this.loading) return
    const gen: number = this.generation
    this.loading = true
    this.loadingOlder = true
    try {
      const controller = appStore.link.controller
      if (controller === null) throw offline()
      const payload: Record<string, Object> = isRoom
        ? { 'roomId': id, 'cursor': this.cursor, 'steps': true }
        : { 'botId': id, 'cursor': this.cursor, 'steps': true }
      const next: ChatPage = (await controller.call(isRoom ? 'room-chat' : 'chat', payload)) as ChatPage
      if (this.generation !== gen) return
      this.cursor = next.cursor
      this.older = next.items.concat(this.older)
      this.keepPage()
    } catch (error) {
      // keep the page we have
    } finally {
      this.loading = false
      this.loadingOlder = false
    }
  }

  // Back online after a drop: read what was missed. Not on mount, which reads already.
  @Monitor('watchedOnline')
  onOnlineChange(): void {
    if (appStore.link.online && !this.wasOnline) {
      void this.refresh(this.generation)
    }
    this.wasOnline = appStore.link.online
  }

  // ---- feed events -------------------------------------------------------------
  private appendFeedItem(item: ChatItem): void {
    const page: ChatPage | null = this.page
    if (page === null) return
    if (item.seq !== undefined) {
      for (const existing of page.items) {
        if (existing.seq !== undefined && existing.seq === item.seq) return
      }
    }
    this.page = { sessionId: page.sessionId, items: page.items.concat([item]), cursor: page.cursor }
    this.keepPage()
  }

  private onStreamEvent(record: Record<string, Object>): void {
    const attemptId: Object | undefined = record['attemptId']
    if (typeof attemptId !== 'string') return
    const phase: Object | undefined = record['phase']
    const text: Object | undefined = record['text']
    if (phase === 'start') {
      this.attempts.set(attemptId, '')
    } else if (typeof text === 'string') {
      this.attempts.set(attemptId, (this.attempts.get(attemptId) ?? '') + text)
    } else if (phase === 'end') {
      this.attempts.delete(attemptId)
    }
    // Each attempt is its own reply part; the saved message shows them as
    // separate bubbles.
    const parts: string[] = []
    this.attempts.forEach((part: string): void => {
      if (part !== '') parts.push(part)
    })
    this.streamText = parts.join('\n\n')
  }

  private onFeedEvent(event: string, data: object): void {
    const record: Record<string, Object> = data as Record<string, Object>
    if (event === 'room') {
      const room: Room | null = this.roomOf()
      const roomId: Object | undefined = record['roomId']
      if (room !== null && typeof roomId === 'string' && roomId === room.id) {
        void this.refresh(this.generation)
      }
      return
    }
    if (event === 'message') {
      const sessionId: Object | undefined = record['sessionId']
      if (typeof sessionId === 'string' && sessionId === this.sessionIdOf()) {
        const item: Object | undefined = record['item']
        if (item !== undefined && item !== null && typeof item === 'object') {
          this.appendFeedItem(item as ChatItem)
        }
        markSeen(this.targetIdOf())
        void this.refresh(this.generation)
      }
      return
    }
    if (event === 'stream') {
      const sessionId: Object | undefined = record['sessionId']
      if (typeof sessionId === 'string' && sessionId === this.sessionIdOf()) {
        this.onStreamEvent(record)
      }
    }
  }

  // ---- sending -----------------------------------------------------------------
  // Sending: the message shows at once and the composer clears; photos travel
  // one by one, then the message names them. It stays until the chat shows it
  // back.
  private send(text: string, photos: ComposerPhoto[]): void {
    const key: string = this.watchedKey
    const localId: string = `${Date.now()}-${Math.random().toString(36).slice(2)}`
    const item: ChatItem = {
      kind: 'user',
      text: text,
      local: 'sending',
      localId: localId,
      time: Date.now(),
    }
    if (photos.length > 0) {
      const uris: string[] = []
      for (const photo of photos) uris.push(photo.uri)
      item.localImages = uris
    }
    const entry: Outgoing = { item: item, photos: photos, sessionId: this.sessionIdOf() }
    queueOutgoing(key, entry)
    void this.deliver(key, entry)
  }

  private async deliver(key: string, entry: Outgoing): Promise<void> {
    const localId: string = entry.item.localId ?? ''
    markOutgoing(key, localId, 'sending')
    const controller = appStore.link.controller
    if (controller === null) {
      markOutgoing(key, localId, 'failed')
      if (key === this.watchedKey) this.loadError = offline().message
      return
    }
    try {
      const images: string[] = []
      for (const photo of entry.photos) {
        const payload: Record<string, Object> = { 'mediaType': photo.mediaType, 'data': photo.data }
        const id: string = await stageImageId(controller.call('stage-image', payload))
        images.push(id)
      }
      const sendPayload: Record<string, Object> = { 'sessionId': entry.sessionId, 'text': entry.item.text ?? '' }
      if (images.length > 0) {
        sendPayload['images'] = images
      }
      await controller.call('send', sendPayload)
      // What the chat already holds, so only a new row of the same text counts
      // as this one.
      const kept: CachedChatEntry<ChatPage, ChatItem> | undefined = pages.get(key)
      const all: ChatItem[] = (kept !== undefined ? kept.older : []).concat(kept !== undefined ? kept.page.items : [])
      const keys: string[] = keysOf(all)
      const known: Set<string> = new Set<string>()
      for (let i = 0; i < all.length; i++) {
        known.add(keys[i] ?? '')
      }
      markOutgoing(key, localId, 'sending', known)
      void hapticLight()
      if (key === this.watchedKey) void this.refresh(this.generation)
    } catch (failure) {
      markOutgoing(key, localId, 'failed')
      if (key === this.watchedKey) {
        this.loadError = failure instanceof Error ? failure.message : String(failure)
      }
    }
  }

  private retry(localId: string, discard: boolean): void {
    const key: string = this.watchedKey
    const entry: Outgoing | undefined = findOutgoing(key, localId)
    if (entry === undefined) return
    if (discard) {
      dropOutgoing(key, localId)
      return
    }
    this.loadError = null
    void this.deliver(key, entry)
  }

  private stop(): void {
    const room: Room | null = this.roomOf()
    const bot: Bot | null = this.botOf()
    const controller = appStore.link.controller
    if (controller === null) return
    if (room !== null) {
      const payload: Record<string, Object> = { 'roomId': room.id }
      void controller.call('stop-room-work', payload).catch((): void => {})
    } else if (bot !== null) {
      const payload: Record<string, Object> = { 'botId': bot.id }
      void controller.call('stop-chat', payload).catch((): void => {})
    }
  }

  // ---- derived chat state ---------------------------------------------------
  private questionOf(): Question | undefined {
    const team: TeamState | null = appStore.link.team
    if (team === null) return undefined
    const questions = team.questions
    if (questions === undefined) return undefined
    return questions[this.sessionIdOf()]
  }

  private approvalsOf(): Approval[] {
    const team: TeamState | null = appStore.link.team
    const sessionId: string = this.sessionIdOf()
    const room: Room | null = this.roomOf()
    const all: Approval[] = team?.work?.approvals ?? []
    return all.filter((entry: Approval): boolean => entry.sessionId === sessionId
      || (entry.roomId !== undefined && room !== null && entry.roomId === room.id))
  }

  private secretsOf(): SecretRequest[] {
    const team: TeamState | null = appStore.link.team
    const bot: Bot | null = this.botOf()
    const all: SecretRequest[] = []
    if (team !== null && bot !== null) {
      const requests = team.secretRequests
      if (requests !== undefined) {
        const mine = requests[bot.id]
        if (mine !== undefined) {
          for (const entry of mine) all.push(entry)
        }
      }
    }
    return all.filter((entry: SecretRequest): boolean => entry.status === 'pending')
  }

  private browserHoldOf(): HandoffData | undefined {
    const team: TeamState | null = appStore.link.team
    const bot: Bot | null = this.botOf()
    if (team === null || bot === null) return undefined
    const holds = team.browserHolds
    if (holds === undefined) return undefined
    const hold = holds[bot.id]
    if (hold === undefined || hold.callId === undefined) return undefined
    const handoff: HandoffData = { callId: hold.callId, reason: hold.reason, note: hold.note }
    return handoff
  }

  private btwOf(): BtwCardData[] {
    const team: TeamState | null = appStore.link.team
    const bot: Bot | null = this.botOf()
    const out: BtwCardData[] = []
    if (team === null || bot === null) return out
    const cards = team.btwCards
    if (cards === undefined) return out
    const mine = cards[bot.id]
    if (mine === undefined) return out
    const sessionId: string = this.sessionIdOf()
    for (const card of mine) {
      if (card.partId === undefined || card.partId === sessionId) {
        out.push({
          id: card.id,
          partId: card.partId,
          question: card.question,
          answer: card.answer,
          failure: card.failure,
          status: card.status,
        })
      }
    }
    return out
  }

  private viewOf(): ShownView | undefined {
    const team: TeamState | null = appStore.link.team
    if (team === null) return undefined
    const views = team.views
    if (views === undefined) return undefined
    return views[this.sessionIdOf()]
  }

  private doingOf(): DoingState | undefined {
    const team: TeamState | null = appStore.link.team
    const bot: Bot | null = this.botOf()
    if (team === null || bot === null) return undefined
    const work = team.work
    if (work !== undefined) {
      const bots = work.bots
      if (bots !== undefined) {
        const mine = bots[bot.id]
        if (mine !== undefined) return mine
      }
    }
    const activity = team.activity
    if (activity !== undefined) {
      return activity[bot.id]
    }
    return undefined
  }

  private roomWorkOf(): RoomWorkEntry[] {
    const team: TeamState | null = appStore.link.team
    const room: Room | null = this.roomOf()
    if (team === null || room === null) return []
    const work = team.work
    if (work === undefined) return []
    const rooms = work.rooms
    if (rooms === undefined) return []
    const mine = rooms[room.id]
    return mine !== undefined ? mine : []
  }

  private doingBotOf(): Bot | null {
    const bot: Bot | null = this.botOf()
    if (bot !== null) return bot
    const team: TeamState | null = appStore.link.team
    if (team === null) return null
    const roomWork: RoomWorkEntry[] = this.roomWorkOf()
    const first: RoomWorkEntry | undefined = roomWork[0]
    if (first === undefined) return null
    const found: Bot | undefined = team.bots.find((entry: Bot): boolean => entry.id === first.botId)
    return found !== undefined ? found : null
  }

  private doingTextOf(): string {
    const doing: DoingState | undefined = this.doingOf()
    if (doing !== undefined) return workPhrase(doing)
    const roomWork: RoomWorkEntry[] = this.roomWorkOf()
    const first: RoomWorkEntry | undefined = roomWork[0]
    if (first === undefined) return ''
    const name: string = this.doingBotOf()?.name ?? ''
    return `${name} · ${workPhrase(first)}`
  }

  private runningOf(): boolean {
    return this.doingOf() !== undefined || this.roomWorkOf().length > 0
  }

  private canStopOf(): boolean {
    if (this.roomOf() !== null) return this.roomWorkOf().length > 0
    return this.runningOf()
  }

  private flatOf(): boolean {
    const team: TeamState | null = appStore.link.team
    return team?.prefs?.layout === 'flat'
  }

  private chatName(): string {
    const bot: Bot | null = this.botOf()
    if (bot !== null) return bot.name
    const room: Room | null = this.roomOf()
    return room !== null ? room.name : ''
  }

  private toggleSteps(rowKey: string): void {
    const next: Record<string, boolean> = {}
    for (const key of Object.keys(this.openSteps)) {
      next[key] = this.openSteps[key]
    }
    next[rowKey] = this.openSteps[rowKey] !== true
    this.openSteps = next
  }

  private openFile(file: FileRef): void {
    const controller = appStore.link.controller
    if (controller === null) {
      this.fileError = t('This file cannot be read here')
      return
    }
    const payload: Record<string, Object> = { 'file': file }
    void fileTextOf(controller.call('file-text', payload)).then((text: string): void => {
      this.readerTitle = file.name
      this.readerText = text
    }).catch((failure: Error): void => {
      this.fileError = failure?.message ?? t('This file cannot be read here')
    })
  }

  private readerIsMono(): boolean {
    const title: string | null = this.readerTitle
    if (title === null) return false
    return !/\.(md|markdown|txt)$/i.test(title)
  }

  // Chronological rows (oldest first) with stable keys and the desktop's time
  // stamps, newest first (index 0 renders at the visual bottom).
  @Computed
  get rows(): MessageRow[] {
    const team: TeamState | null = appStore.link.team
    const room: Room | null = this.roomOf()
    const inRoom: boolean = room !== null
    const admin: string | undefined = room?.admin
    const flat: boolean = team?.prefs?.layout === 'flat'
    const width: number = Math.min(100, Math.max(50, team?.prefs?.width ?? 80))
    // Bubble caps in px — narrow phone screens ignore the desktop's wide-window
    // column slider so bubbles do not waste a third of the screen; group rows
    // reserve 30px (22px avatar + 8px gap) on the left.
    const narrow: boolean = this.chatWidth < 520
    const roomOffset: number = inRoom && !flat ? 30 : 0
    const botSpan: number = Math.max(0, this.chatWidth - roomOffset)
    const botMax: number = this.chatWidth === 0 ? 0
      : Math.round(Math.min(botSpan * (narrow ? 0.93 : width / 100), botSpan - (narrow ? 8 : 40)))
    const userMax: number = Math.round(this.chatWidth * (narrow ? 0.86 : width / 100))
    const items: ChatItem[] = this.older.concat(this.page !== null ? this.page.items : [])
    const pendingItems: ChatItem[] = this.pending.map((entry: Outgoing): ChatItem => entry.item)
    const all: ChatItem[] = items.concat(pendingItems)
    const keys: string[] = keysOf(all)
    const botsById: Map<string, Bot> = new Map<string, Bot>()
    if (team !== null) {
      for (const bot of team.bots) botsById.set(bot.id, bot)
    }
    const out: MessageRow[] = []
    for (let i = all.length - 1; i >= 0; i--) {
      const item: ChatItem = all[i]
      const key: string = keys[i] ?? ''
      const row: MessageRow = {
        item: item,
        key: key,
        stamp: inRoom || item.local !== undefined ? '' : (stampOf(all, i) ?? ''),
        stepsOpen: this.openSteps[key] === true,
        maxWidth: item.kind === 'bot' || item.kind === 'post' ? botMax : userMax,
        author: inRoom && item.botId !== undefined ? botsById.get(item.botId) : undefined,
        admin: inRoom && item.botId !== undefined && item.botId === admin,
      }
      out.push(row)
    }
    // The turn being streamed shows below the newest row; the real item lands
    // with the 'message' event when the turn's text is saved.
    if (this.streamText !== '') {
      const streamItem: ChatItem = { kind: 'bot', text: this.streamText }
      const streamRow: MessageRow = {
        item: streamItem,
        key: 'streaming',
        stamp: '',
        stepsOpen: false,
        maxWidth: botMax,
        author: undefined,
        admin: false,
      }
      out.unshift(streamRow)
    }
    return out
  }

  // A sent message leaves the outbox once the chat shows a new row with its text.
  @Monitor('rows')
  onRowsChange(): void {
    if (this.pending.length === 0) return
    const items: ChatItem[] = this.older.concat(this.page !== null ? this.page.items : [])
    dropShownOutbox(this.watchedKey, items)
  }

  // ---- lifecycle ------------------------------------------------------------
  aboutToAppear(): void {
    this.wasOnline = appStore.link.online
    try {
      const screen: display.Display = display.getDefaultDisplaySync()
      this.chatWidth = Math.max(0, this.getUIContext().px2vp(screen.width) - 24)
    } catch (error) {
      this.chatWidth = 0
    }
    this.offFeed = appStore.link.onFeed((event: string, data: object): void => {
      this.onFeedEvent(event, data)
    })
    this.offOutbox = subscribeOutbox((): void => {
      this.pending = outboxOf(this.watchedKey)
    })
    this.startChat()
  }

  aboutToDisappear(): void {
    this.generation += 1
    this.clearPoll()
    if (this.offFeed !== null) {
      this.offFeed()
      this.offFeed = null
    }
    if (this.offOutbox !== null) {
      this.offOutbox()
      this.offOutbox = null
    }
  }

  // ---- view -----------------------------------------------------------------
  // A chat with nothing in it yet: who it is with, large, where the messages
  // will be.
  @Builder
  emptyChat() {
    Column() {
      if (this.botOf() !== null) {
        Avatar({
          bot: this.botOf() ?? undefined,
          dark: appStore.theme.dark,
          markSize: 64,
          ring: appStore.theme.p.main,
        })
      } else if (this.roomOf() !== null) {
        RoomAvatar({
          room: this.roomOf() ?? undefined,
          bots: appStore.link.team?.bots ?? [],
          dark: appStore.theme.dark,
          markSize: 64,
          ring: appStore.theme.p.main,
        })
      }
      Text(this.chatName())
        .fontSize(type.settingsRow.fontSize)
        .lineHeight(type.settingsRow.lineHeight)
        .fontWeight('600')
        .fontColor(appStore.theme.p.ink)
        .maxLines(1)
        .margin({ top: 12 })
      if (this.botOf()?.role !== undefined && this.botOf()?.role !== '') {
        Text(this.botOf()?.role ?? '')
          .fontSize(type.small.fontSize)
          .lineHeight(type.small.lineHeight)
          .fontColor(appStore.theme.p.ink3)
          .maxLines(1)
          .margin({ top: 2 })
      }
      Text(t('No messages yet'))
        .fontSize(type.caption.fontSize)
        .lineHeight(type.caption.lineHeight)
        .fontColor(appStore.theme.p.ink3)
        .margin({ top: 10 })
    }
    .alignItems(HorizontalAlign.Center)
    .width('100%')
    .padding({ left: 24, right: 24 })
    .position({ x: 0, y: '28%' })
  }

  // The file reader over the chat: the file text with a Done button.
  @Builder
  readerOverlay() {
    Column() {
      Scroll() {
        Column() {
          if (this.readerTitle !== null) {
            Text(this.readerTitle ?? '')
              .fontSize(type.caption.fontSize)
              .lineHeight(type.caption.lineHeight)
              .fontColor(appStore.theme.p.ink3)
              .margin({ bottom: 10 })
          }
          Text(this.readerText ?? '')
            .fontSize(type.bubble.fontSize)
            .lineHeight(type.bubble.lineHeight)
            .fontColor(appStore.theme.p.ink)
            .fontFamily(this.readerIsMono() ? MONO : 'HarmonyOS Sans')
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding({ left: 20, right: 20, top: appStore.safeTop + 24, bottom: 100 })
      }
      .scrollBar(BarState.Off)
      .layoutWeight(1)
      Column() {
        Text(t('Done'))
          .fontSize(type.settingsRow.fontSize)
          .lineHeight(type.settingsRow.lineHeight)
          .fontColor(appStore.theme.p.accent)
      }
      .padding({ left: 24, right: 24, top: 10, bottom: 10 })
      .borderRadius(20)
      .border({ width: 1, color: appStore.theme.p.line })
      .backgroundColor(appStore.theme.p.card)
      .margin({ bottom: appStore.safeBottom + 30 })
      .shadow(shadowOf(1))
      .onClick((): void => {
        this.readerText = null
        this.readerTitle = null
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(appStore.theme.p.main)
  }

  // The messages run edge to edge; the avatar pill and the composer float over
  // them with transparent chrome — no solid bands anywhere.
  build() {
    // Bottom-aligned: the floating bottom chrome (dock cards + composer) pins
    // to the screen bottom; the top chrome overrides with an explicit position.
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        if (this.gone) {
          Text(t('No messages yet'))
            .fontSize(type.caption.fontSize)
            .lineHeight(type.caption.lineHeight)
            .fontColor(appStore.theme.p.ink3)
            .textAlign(TextAlign.Center)
            .margin({ top: appStore.safeTop + 24 })
        } else if (this.page === null && this.loadError !== null) {
          Column() {
            Text(this.loadError ?? '')
              .fontSize(type.caption.fontSize)
              .lineHeight(type.caption.lineHeight)
              .fontColor(appStore.theme.p.ink3)
              .textAlign(TextAlign.Center)
            Text(t('Retry'))
              .fontSize(type.caption.fontSize)
              .lineHeight(type.caption.lineHeight)
              .fontColor(appStore.theme.p.accent)
              .margin({ top: 8 })
              .onClick((): void => {
                this.loadError = null
                void this.refresh(this.generation)
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .margin({ top: appStore.safeTop + 24 })
        } else if (this.page === null || this.chatWidth <= 0) {
          Column() {
            LoadingProgress()
              .width(28)
              .height(28)
              .color(appStore.theme.p.accent)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          MessageList({
            rows: this.rows,
            sessionId: this.sessionIdOf(),
            flat: this.flatOf(),
            inRoom: this.roomOf() !== null,
            loadingOlder: this.loadingOlder,
            onLoadOlder: (): void => {
              void this.loadMore()
            },
            onLongPress: (text: string): void => {
              this.menuText = text
            },
            onOpenPhoto: (open: PhotoOpenData): void => {
              this.photosOpen = open
            },
            onOpenFile: (file: FileRef): void => {
              this.openFile(file)
            },
            onRetry: (localId: string, discard: boolean): void => {
              this.retry(localId, discard)
            },
            onToggleSteps: (rowKey: string): void => {
              this.toggleSteps(rowKey)
            },
          })
        }
        if (!this.gone && this.page !== null && this.rows.length === 0) {
          this.emptyChat()
        }
      }
      .width('100%')
      .height('100%')
      // Progressive frost: the list content blurs toward the top edge and
      // clears below the floating header — no hard edge anywhere.
      .linearGradientBlur(TOP_FROST_RADIUS, {
        fractionStops: TOP_FROST_STOPS,
        direction: GradientDirection.Bottom,
      })
      .onAreaChange((_oldValue: Area, newValue: Area): void => {
        const measured: Length = newValue.width
        if (typeof measured === 'number') {
          this.chatWidth = Math.max(0, measured - 24)
        }
      })

      // The luminous veil (光感): a bg-colored gradient over the frosted list
      // top that dissolves it into the page — the header floats on this.
      Column() {
      }
      .width('100%')
      .height(appStore.safeTop + 64)
      .linearGradient({
        direction: GradientDirection.Bottom,
        colors: [
          [rgba(appStore.theme.p.main, 0.55), 0],
          [rgba(appStore.theme.p.main, 0.28), 0.45],
          [rgba(appStore.theme.p.main, 0), 1],
        ],
      })
      .hitTestBehavior(HitTestMode.None)
      .position({ x: 0, y: 0 })

      // Floating top chrome: the room goal bar on a clear background —
      // messages scroll behind it and behind the shell's header pill above.
      Column() {
        if (this.roomOf() !== null && this.roomOf()?.goal !== undefined) {
          GoalBar({ goal: (this.roomOf() as Room).goal })
        }
      }
      .width('100%')
      .padding({ top: appStore.safeTop + 60 })
      // Pin to the top: the Stack aligns children bottom for the composer.
      .position({ x: 0, y: 0 })

      // Floating bottom chrome: the dock cards and the composer over the
      // messages.
      Column() {
        if (this.botOf()?.blocked !== undefined) {
          BlockedCard({
            bot: this.botOf() as Bot,
            onNavigate: (route: string, param: Object | null): void => {
              this.onNavigate(route, param)
            },
          })
        }
        if (this.botOf() !== null) {
          ComputerCards({ bot: this.botOf() as Bot })
        }
        if (this.runningOf() && this.doingBotOf() !== null) {
          ActionRow({ bot: this.doingBotOf() as Bot, doing: this.doingTextOf() })
        }
        Dock({
          question: this.questionOf(),
          sessionId: this.sessionIdOf(),
          approvals: this.approvalsOf(),
          secrets: this.secretsOf(),
          btw: this.btwOf(),
          handoff: this.browserHoldOf(),
          view: this.viewOf(),
          expanded: this.expandedKey,
          onExpand: (key: string | null): void => {
            this.expandedKey = key
          },
        })
        if (this.fileError !== null) {
          Text(this.fileError ?? '')
            .fontSize(type.small.fontSize)
            .lineHeight(type.small.lineHeight)
            .fontColor(appStore.theme.p.danger)
            .textAlign(TextAlign.Center)
            .margin({ bottom: 4 })
        }
        if (this.page !== null && this.loadError !== null) {
          Text(this.loadError ?? '')
            .fontSize(type.small.fontSize)
            .lineHeight(type.small.lineHeight)
            .fontColor(appStore.theme.p.danger)
            .textAlign(TextAlign.Center)
            .margin({ bottom: 4, left: 16, right: 16 })
        }
        Composer({
          name: this.chatName(),
          running: this.runningOf(),
          canStop: this.canStopOf(),
          canAttach: appStore.link.helloCapabilities.includes('send-images'),
          bottomInset: Math.max(appStore.safeBottom, 10),
          onSend: (text: string, picked: ComposerPhoto[]): void => {
            this.send(text, picked)
          },
          onStop: (): void => {
            this.stop()
          },
        })
      }
      .width('100%')

      if (this.readerText !== null) {
        this.readerOverlay()
      }
      if (this.photosOpen !== null) {
        PhotoViewer({
          open: this.photosOpen,
          onClose: (): void => {
            this.photosOpen = null
          },
        })
      }
      Actions({
        visible: this.menuText !== null,
        text: this.menuText ?? '',
        onClose: (): void => {
          this.menuText = null
        },
        onSelect: (): void => {
          this.readerTitle = null
          this.readerText = this.menuText
          this.menuText = null
        },
      })
    }
    .width('100%')
    .height('100%')
  }
}
