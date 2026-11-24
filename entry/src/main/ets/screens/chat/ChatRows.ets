// Message rows: the port of mobile/src/screens/chat/items.tsx. Every ChatItem
// kind renders here — Bot bubbles with markdown, the user's bubbles with photos
// and failed-send retries, group event rows, folded tool steps, turn dividers,
// settled question/handoff/view cards, photo grids and the full-screen viewer.
//
// Photos are fetched once per attachment into a session-wide preview cache (and
// a small originals cache for the viewer); a long-press opens the copy/select
// sheet with the row's source text. Dynamic deep-view values and image call
// answers reach this file only through common/team/chat-state's typed helpers,
// never as raw unknowns.

import { appStore, inkColor, type, radius, Palette, MONO } from '../../components/Theme'
import { t, clockLabel, messageClock } from '../../common/ui/i18n'
import type { Bot, ChatItem, FileRef, ImageRef } from '../../common/team/types'
import {
  handoffTitleOf, imageUriOf, imPlatformName, itemViewNode, relayReplyText, roundEventText,
  settledLinesOf, stripLongNote, viewRepliesOf,
} from '../../common/team/chat-state'
import type { SettledLine, SettledPick, ViewReplyDetail } from '../../common/team/chat-state'
import { copyToClipboard, hapticLight } from '../../platform/Platform'
import type { ViewNode } from '../../common/deepview/views-core'
import { MarkdownText, hasBlockContent } from './MarkdownText'
import { DeepView } from './DeepView'
import { Icon } from '../../components/Icon'
import { Avatar } from '../../components/Marks'

// One photo shows large; several sit two to a row (items.tsx gridOf).
const GRID_GAP: number = 6

function gridTileOf(count: number): number {
  return count === 1 ? 200 : 120
}

// Session data URIs, kept only in memory so nothing touches disk. The chat
// shows previews; an original is fetched when its photo is opened, and only the
// last few stay.
const imageCache: Map<string, string> = new Map<string, string>()
const originals: Map<string, string> = new Map<string, string>()
const ORIGINALS_KEPT: number = 6

// A deep-view root that never renders anything, for the type-safe branch below.
const EMPTY_NODE: ViewNode = {}

// One image the computer holds: fetched as a preview, tapped to open the viewer.
@ComponentV2
struct ImageTile {
  @Require @Param imageRef: ImageRef
  @Require @Param sessionId: string
  @Param tile: number = 120
  @Event onOpen: () => void = (): void => {}
  @Local uri: string = ''
  @Local failed: boolean = false

  private p(): Palette {
    return appStore.theme.p
  }

  aboutToAppear(): void {
    const key = `${this.sessionId}:${this.imageRef.attachmentId}`
    const hit = imageCache.get(key)
    if (hit !== undefined) {
      this.uri = hit
      return
    }
    const controller = appStore.link.controller
    if (controller === null) {
      this.failed = true
      return
    }
    const payload: Record<string, Object> = {
      'sessionId': this.sessionId,
      'attachmentId': this.imageRef.attachmentId,
      'preview': true,
    }
    void imageUriOf(controller.call('image', payload)).then((uri: string): void => {
      imageCache.set(key, uri)
      this.uri = uri
    }).catch((): void => {
      this.failed = true
    })
  }

  build() {
    if (this.uri !== '') {
      Image(this.uri)
        .width(this.tile)
        .height(this.tile)
        .objectFit(ImageFit.Cover)
        .borderRadius(radius.bubble)
        .onClick((): void => this.onOpen())
    } else if (this.failed) {
      Column() {
        Text(t('View it on the computer'))
          .fontSize(type.caption.fontSize)
          .lineHeight(type.caption.lineHeight)
          .fontColor(this.p().ink3)
          .textAlign(TextAlign.Center)
      }
      .justifyContent(FlexAlign.Center)
      .padding(8)
      .width(this.tile)
      .height(this.tile)
    } else {
      Column() {
        LoadingProgress()
          .width(22)
          .height(22)
          .color(this.p().ink3)
      }
      .justifyContent(FlexAlign.Center)
      .width(this.tile)
      .height(this.tile)
    }
  }
}

// The photo grid inside a bubble: two columns of squares fetched once per
// attachment. A failed tile says why and points at the computer.
@ComponentV2
struct ImageGrid {
  @Require @Param refs: ImageRef[]
  @Require @Param sessionId: string
  @Event onOpen: (index: number) => void = (_index: number): void => {}

  private p(): Palette {
    return appStore.theme.p
  }

  private hairline(): number {
    return this.getUIContext().px2vp(1)
  }

  private tile(): number {
    return gridTileOf(this.refs.length)
  }

  private columns(): number {
    return Math.min(this.refs.length, 2)
  }

  private gridWidth(): number {
    const columns = this.columns()
    return this.tile() * columns + GRID_GAP * (columns - 1)
  }

  private rowEndGap(index: number): number {
    if ((index + 1) % this.columns() === 0 || index === this.refs.length - 1) return 0
    return GRID_GAP
  }

  private rowBelowGap(index: number): number {
    return index + this.columns() < this.refs.length ? GRID_GAP : 0
  }

  build() {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(this.refs, (ref: ImageRef, index: number) => {
        Column() {
          ImageTile({
            imageRef: ref,
            sessionId: this.sessionId,
            tile: this.tile(),
            onOpen: (): void => this.onOpen(index),
          })
        }
        .margin({ right: this.rowEndGap(index), bottom: this.rowBelowGap(index) })
      }, (ref: ImageRef): string => ref.attachmentId)
    }
    .width(this.gridWidth())
    .margin({ top: 6 })
  }
}

// Photos the phone is sending, shown from the phone itself until the computer
// has them.
@ComponentV2
struct LocalImages {
  @Require @Param uris: string[]

  private tile(): number {
    return gridTileOf(this.uris.length)
  }

  private columns(): number {
    return Math.min(this.uris.length, 2)
  }

  private gridWidth(): number {
    const columns = this.columns()
    return this.tile() * columns + GRID_GAP * (columns - 1)
  }

  private rowEndGap(index: number): number {
    if ((index + 1) % this.columns() === 0 || index === this.uris.length - 1) return 0
    return GRID_GAP
  }

  private rowBelowGap(index: number): number {
    return index + this.columns() < this.uris.length ? GRID_GAP : 0
  }

  build() {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(this.uris, (uri: string, index: number) => {
        Column() {
          Image(uri)
            .width(this.tile())
            .height(this.tile())
            .objectFit(ImageFit.Cover)
            .borderRadius(radius.bubble)
        }
        .margin({ right: this.rowEndGap(index), bottom: this.rowBelowGap(index) })
      }, (uri: string, index: number): string => `${index}-${uri}`)
    }
    .width(this.gridWidth())
    .margin({ top: 6 })
  }
}

// One full-screen page: the preview at once, the original once it arrives.
@ComponentV2
struct PhotoPage {
  @Require @Param imageRef: ImageRef
  @Require @Param sessionId: string
  @Param active: boolean = false
  @Event onClose: () => void = (): void => {}
  @Local preview: string = ''
  @Local whole: string = ''

  aboutToAppear(): void {
    const key = `${this.sessionId}:${this.imageRef.attachmentId}`
    const hit = imageCache.get(key)
    if (hit !== undefined) {
      this.preview = hit
    } else {
      const controller = appStore.link.controller
      if (controller !== null) {
        const payload: Record<string, Object> = {
          'sessionId': this.sessionId,
          'attachmentId': this.imageRef.attachmentId,
          'preview': true,
        }
        void imageUriOf(controller.call('image', payload)).then((uri: string): void => {
          imageCache.set(key, uri)
          this.preview = uri
        }).catch((): void => {})
      }
    }
    if (this.active) this.loadWhole()
  }

  @Monitor('active')
  onActiveChange(): void {
    if (this.active) this.loadWhole()
  }

  private loadWhole(): void {
    if (this.whole !== '') return
    const key = `${this.sessionId}:${this.imageRef.attachmentId}`
    const kept = originals.get(key)
    if (kept !== undefined) {
      this.whole = kept
      return
    }
    const controller = appStore.link.controller
    if (controller === null) return
    const payload: Record<string, Object> = {
      'sessionId': this.sessionId,
      'attachmentId': this.imageRef.attachmentId,
    }
    void imageUriOf(controller.call('image', payload)).then((uri: string): void => {
      originals.set(key, uri)
      while (originals.size > ORIGINALS_KEPT) {
        for (const oldest of originals.keys()) {
          originals.delete(oldest)
          break
        }
      }
      this.whole = uri
    }).catch((): void => {})
  }

  private shown(): string {
    return this.whole !== '' ? this.whole : this.preview
  }

  build() {
    if (this.shown() !== '') {
      Image(this.shown())
        .objectFit(ImageFit.Contain)
        .width('100%')
        .layoutWeight(1)
        .onClick((): void => this.onClose())
    } else {
      Column() {
        LoadingProgress()
          .width(28)
          .height(28)
          .color('#ffffff')
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')
      .layoutWeight(1)
      .onClick((): void => this.onClose())
    }
  }
}

// What the viewer was asked to open: one conversation photo set and position.
export interface PhotoOpenData {
  sessionId: string
  refs: ImageRef[]
  index: number
}

// Full-screen photos, swiped side to side: the preview at once, the original
// once it arrives. The host renders this inside its safe area.
@ComponentV2
export struct PhotoViewer {
  @Require @Param open: PhotoOpenData
  @Event onClose: () => void = (): void => {}
  @Local at: number = 0

  aboutToAppear(): void {
    this.at = this.open.index
  }

  build() {
    Stack() {
      Swiper() {
        ForEach(this.open.refs, (ref: ImageRef, index: number) => {
          PhotoPage({
            imageRef: ref,
            sessionId: this.open.sessionId,
            active: this.at === index,
            onClose: (): void => this.onClose(),
          })
        }, (ref: ImageRef): string => ref.attachmentId)
      }
      .index(this.open.index)
      .loop(false)
      .indicator(false)
      .onChange((index: number) => {
        // Swiping must drive the page counter and the active page's
        // full-size load; .index() only sets the initial value.
        this.at = index
      })
      .width('100%')
      .height('100%')

      Row() {
        if (this.open.refs.length > 1) {
          Text(`${this.at + 1} / ${this.open.refs.length}`)
            .fontSize(type.small.fontSize)
            .lineHeight(type.small.lineHeight)
            .fontColor('rgba(255,255,255,0.8)')
        }
        Blank()
        Text(t('Done'))
          .fontSize(type.settingsRow.fontSize)
          .lineHeight(type.settingsRow.lineHeight)
          .fontColor('#ffffff')
          .padding(10)
          .onClick((): void => this.onClose())
      }
      .width('100%')
      .padding({ left: 16, right: 8, top: appStore.safeTop + 6 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
  }
}

// The bottom sheet a long-press opens: copy the source text or read it in a
// selectable page. The chat mounts one for the whole conversation.
@ComponentV2
export struct Actions {
  @Param visible: boolean = false
  @Param text: string = ''
  @Event onClose: () => void = (): void => {}
  @Event onSelect: () => void = (): void => {}

  private p(): Palette {
    return appStore.theme.p
  }

  private copySource(): void {
    void copyToClipboard(this.text).then((): void => this.onClose())
  }

  build() {
    if (this.visible) {
      Stack({ alignContent: Alignment.Bottom }) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0,0,0,0.35)')
          .onClick((): void => this.onClose())
        Column() {
          Column() {
            Text(t('Copy'))
              .fontSize(type.settingsRow.fontSize)
              .lineHeight(type.settingsRow.lineHeight)
              .fontColor(this.p().ink)
              .width('100%')
              .textAlign(TextAlign.Start)
              .padding({ top: 14, bottom: 14, left: 18, right: 18 })
              .onClick((): void => this.copySource())
            Text(t('Select text'))
              .fontSize(type.settingsRow.fontSize)
              .lineHeight(type.settingsRow.lineHeight)
              .fontColor(this.p().ink)
              .width('100%')
              .textAlign(TextAlign.Start)
              .padding({ top: 14, bottom: 14, left: 18, right: 18 })
              .onClick((): void => {
                this.onClose()
                this.onSelect()
              })
            Text(t('Cancel'))
              .fontSize(type.settingsRow.fontSize)
              .lineHeight(type.settingsRow.lineHeight)
              .fontColor(this.p().ink3)
              .width('100%')
              .textAlign(TextAlign.Start)
              .padding({ top: 14, bottom: 14, left: 18, right: 18 })
              .onClick((): void => this.onClose())
          }
          .width('100%')
          .borderRadius(14)
          .border({ width: 1, color: this.p().line })
          .backgroundColor(this.p().card)
          .clip(true)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding({ left: 12, right: 12, bottom: appStore.safeBottom + 16 })
      }
      .width('100%')
      .height('100%')
    }
  }
}

// A group round's tool list entry (ChatItem.tools).
interface ToolEntry {
  name: string
  label?: string | null
  ok?: boolean
  detail?: string | null
}

// An answer card's browser-handoff outcome (ChatItem.handoff / parsed JSON).
interface HandoffData {
  reason?: string
  note?: string
  outcome?: string
}

interface HandoffRaw {
  kind?: string
  reason?: string
  note?: string
  outcome?: string
}

// One displayItems row (items.tsx Item). Bubbles: radius 18, padding 9×14, Bot
// on the theme's bubble color, the user on user/userInk; maxWidth caps both in
// vp so the parent can size the chat column. The steps rows keep their open
// state in the parent; every row long-presses to its source text.
@ComponentV2
export struct Item {
  @Require @Param item: ChatItem
  @Require @Param maxWidth: number
  @Param flat: boolean = false
  @Param inRoom: boolean = false
  @Param sessionId: string = ''
  @Param stepsOpen: boolean = false
  // The steps row's expanded tool index: -1 means every tool is collapsed.
  @Param expandedTool: number = -1
  @Param stamp: string = ''
  @Param author: Bot | undefined = undefined
  @Param admin: boolean = false
  @Event onLongPress: (text: string) => void = (_text: string): void => {}
  @Event onToggleSteps: () => void = (): void => {}
  @Event onToggleTool: (index: number) => void = (_index: number): void => {}
  @Event onOpenFile: (file: FileRef) => void = (_file: FileRef): void => {}
  @Event onSaveFile: (file: FileRef) => void = (_file: FileRef): void => {}
  @Event onOpenPhoto: (index: number) => void = (_index: number): void => {}
  @Event onRetry: (localId: string, discard: boolean) => void = (_localId: string, _discard: boolean): void => {}
  // The steps row whose Copy action just ran, so the label can say "Copied".
  @Local copiedTool: number = -1

  private p(): Palette {
    return appStore.theme.p
  }

  private hairline(): number {
    return this.getUIContext().px2vp(1)
  }

  // ---- shared values -------------------------------------------------------

  // Markdown image fetches go through the row's own session (a group reply may
  // come from another session than the room being viewed).
  private rowSessionId(): string {
    return this.item.sessionId ?? this.sessionId
  }

  private authorBotId(): string {
    return this.item.botId ?? this.author?.id ?? ''
  }

  private wholeFile(): FileRef | undefined {
    const file = this.item.file
    if (file !== undefined && file.attachmentId !== undefined) return file
    const wholeRef = this.item.whole?.file
    if (wholeRef !== undefined && wholeRef.attachmentId !== undefined) return wholeRef
    return undefined
  }

  private bodyTexts(): string[] {
    const texts = this.item.texts
    if (texts !== undefined && texts.length > 0) {
      return texts.filter((entry: string): boolean => entry.trim() !== '')
    }
    const text = this.item.text ?? ''
    // Whitespace-only text renders an empty Markdown — a blank bubble; skip it.
    if (text.trim() !== '') {
      return [this.wholeFile() !== undefined ? stripLongNote(text) : text]
    }
    return []
  }

  private bodyJoined(): string {
    return this.bodyTexts().join('\n\n')
  }

  private source(): string {
    const answers = this.item.answers
    if (answers !== undefined) {
      const lines: string[] = []
      for (const answer of answers) {
        const parts: string[] = []
        const selected = answer.selected ?? []
        for (const entry of selected) parts.push(entry)
        if (answer.custom !== undefined && answer.custom !== '') parts.push(answer.custom)
        lines.push(parts.join(', '))
      }
      return lines.join('\n')
    }
    return this.bodyJoined()
  }

  private longPress(): void {
    void hapticLight()
    this.onLongPress(this.source())
  }

  private photosOnly(): boolean {
    return (this.item.text ?? '').trim() === ''
      && (this.item.files ?? []).length === 0
      && ((this.item.imageRefs ?? []).length > 0 || (this.item.localImages ?? []).length > 0)
  }

  // A bubble with block content (code, table…) cannot hold it while wrapped to
  // the text; the wide rules come from the RN build (items.tsx): a user bubble
  // widens on its own text, a Bot row on any body part or its images.
  private userWide(): boolean {
    return hasBlockContent(this.item.text ?? '')
  }

  private roomHasImages(): boolean {
    return (this.item.imageRefs ?? []).length > 0 && this.sessionId !== ''
  }

  private botWide(): boolean {
    return this.bodyTexts().some((entry: string): boolean => hasBlockContent(entry)) || this.roomHasImages()
  }

  private bubblePadding(): Padding {
    if (this.photosOnly()) {
      return { left: 0, right: 0, top: 0, bottom: 0 }
    }
    return { left: 14, right: 14, top: 9, bottom: 9 }
  }

  private userTap(): void {
    if (this.item.local !== 'failed' || this.item.localId === undefined) return
    this.onRetry(this.item.localId, false)
  }

  private retryTap(discard: boolean): void {
    const localId = this.item.localId
    if (localId === undefined) return
    this.onRetry(localId, discard)
  }

  private viaLabel(): string {
    return t('via {platform}', { 'platform': imPlatformName(this.item.via ?? '') })
  }

  // ---- answer folding ------------------------------------------------------

  private handoffOf(): HandoffData | undefined {
    const direct = this.item.handoff
    if (direct !== undefined) return direct
    const questions = this.item.questions ?? []
    const views = this.item.views ?? []
    const text = this.item.text
    if (questions.length === 0 && views.length === 0 && typeof text === 'string') {
      try {
        const parsed = JSON.parse(text) as HandoffRaw
        if (parsed !== null && parsed.kind === 'answer_to_pending_handoff' && typeof parsed.reason === 'string') {
          const handoff: HandoffData = { 'reason': parsed.reason, 'note': parsed.note, 'outcome': parsed.outcome }
          return handoff
        }
      } catch {
        // A plain text answer stays a bubble below.
      }
    }
    return undefined
  }

  private handoffSkipped(): boolean {
    return this.handoffOf()?.outcome === 'skipped'
  }

  private handoffReturned(): boolean {
    return this.handoffOf()?.outcome === 'returned'
  }

  private viewRoot(): ViewNode {
    const node = itemViewNode(this.item)
    return node ?? EMPTY_NODE
  }

  // ---- steps ---------------------------------------------------------------

  // The caption over a turn's tools: a single tool shows its phrase (not "Used
  // 1 tool"), several show the count, and steps without tools fall back to the
  // thinking time alone.
  private stepsSummary(): string {
    const tools = this.item.tools ?? []
    const ms = this.item.ms
    const seconds = typeof ms === 'number' ? Math.round(ms / 1000) : 0
    const thought = seconds > 0 ? t(' · thought for {seconds}s', { 'seconds': seconds }) : ''
    if (tools.length === 1) {
      return `${this.toolLine(tools[0])}${thought}`
    }
    if (tools.length === 0 && seconds > 0) {
      return t('Thought for {seconds}s', { 'seconds': seconds })
    }
    return `${t('Used {count} tools', { 'count': tools.length })}${thought}`
  }

  private toolLine(tool: ToolEntry): string {
    const label = tool.label !== null && tool.label !== undefined && tool.label !== '' ? t(tool.label) : tool.name
    if (tool.ok === false) {
      return `${label}${t(' — failed')}`
    }
    return label
  }

  // What the call actually did — the command, the file, the query — as one
  // collapsed line from the computer; empty when the call said nothing useful.
  private toolDetailOf(tool: ToolEntry): string {
    const detail = tool.detail
    if (detail === null || detail === undefined) return ''
    return detail.trim()
  }

  // Whether a tool carries a detail worth opening: no detail, no accordion.
  private toolHasDetail(tool: ToolEntry): boolean {
    return this.toolDetailOf(tool) !== ''
  }

  private copyToolDetail(tool: ToolEntry, index: number): void {
    const detail = this.toolDetailOf(tool)
    if (detail === '') return
    void copyToClipboard(detail).then((): void => {
      this.copiedTool = index
      setTimeout((): void => {
        if (this.copiedTool === index) this.copiedTool = -1
      }, 1500)
    })
  }

  // ---- group events --------------------------------------------------------

  private eventLabel(): string {
    switch (this.item.role ?? '') {
      case 'request': return t('asked for work')
      case 'reply': return t('replied')
      case 'report': return t('reported back')
      case 'stopped': return t('stopped')
      default: return this.item.role ?? ''
    }
  }

  private eventLine(): string {
    if (this.item.role === 'paused') {
      return t('Paused after {count} Bot relays. Waiting: {names}', {
        'count': this.item.ms ?? 0,
        'names': this.item.text ?? '',
      })
    }
    if (this.item.role === 'schedule') {
      const text = this.item.text ?? ''
      return text !== ''
        ? t('Scheduled task: {text}', { 'text': text })
        : t('Routine started')
    }
    const round = roundEventText(this.item.name ?? t('a Bot'), this.item.event, this.item.text, this.item.code)
    if (round !== undefined) return round
    return t('{name} {event}', { 'name': this.item.name ?? t('a Bot'), 'event': this.eventLabel() })
  }

  private relayLine(): string {
    return relayReplyText(this.item.reply) ?? ''
  }

  private closedBadge(): string {
    return t(this.item.closed === 'replied' ? 'Answered by message' : 'Dismissed')
  }

  private fileSub(file: FileRef): string {
    const ext = (file.name.split('.').pop() ?? '').toUpperCase()
    const kb = file.bytes !== undefined ? `${Math.max(1, Math.round(file.bytes / 1024))} KB` : ''
    if (ext !== '' && kb !== '') return `${ext} · ${kb}`
    return ext !== '' ? ext : kb
  }

  private botHasContent(): boolean {
    const hasImages = (this.item.imageRefs ?? []).length > 0 && this.sessionId !== ''
    return this.bodyTexts().length > 0
      || hasImages
      || (this.item.files ?? []).length > 0
      || this.wholeFile() !== undefined
  }

  build() {
    if (this.item.kind === 'steps') {
      this.stepsRow()
    } else if (this.item.kind === 'divider') {
      this.dividerRow()
    } else if (this.item.kind === 'relay') {
      this.relayRow()
    } else if (this.item.kind === 'event') {
      this.eventRow()
    } else if (this.item.kind === 'closed') {
      this.closedRow()
    } else if (this.item.kind === 'view') {
      this.viewRow()
    } else if (this.item.kind === 'answer') {
      this.answerRow()
    } else if (this.item.kind === 'user') {
      this.userRow()
    } else if (this.botHasContent()) {
      if (this.inRoom && !this.flat) {
        this.roomRow()
      } else if (this.flat) {
        this.flatRow()
      } else {
        this.botBubbleRow()
      }
    }
  }

  // One folded caption row per turn: a tap lists what the tools did, and each
  // listed tool opens its full detail in its own accordion row.
  @Builder
  stepsRow() {
    Column({ space: 2 }) {
      Text(this.stepsSummary())
        .fontSize(type.caption.fontSize)
        .lineHeight(type.caption.lineHeight)
        .fontColor(this.p().ink3)
        .textAlign(TextAlign.Center)
        .onClick((): void => this.onToggleSteps())
      if (this.stepsOpen) {
        Column({ space: 3 }) {
          ForEach(this.item.tools ?? [], (tool: ToolEntry, index: number) => {
            this.toolBlock(tool, index)
          }, (tool: ToolEntry, index: number): string => `${tool.name}-${index}`)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
    }
    .constraintSize({ maxWidth: '92%' })
    .alignSelf(ItemAlign.Center)
    .margin({ top: 4, bottom: 4 })
  }

  // One tool row of the expanded steps: the label (failed tools in the theme's
  // danger color) with a one-line detail preview; a tap opens the tool's full
  // detail — monospace, fully wrapped, with a copy action in the corner — and
  // a tap on the label closes it again. A tool without detail stays a single
  // line that does not expand.
  @Builder
  toolBlock(tool: ToolEntry, index: number) {
    Column({ space: 2 }) {
      Text(this.toolLine(tool))
        .fontSize(type.caption.fontSize)
        .lineHeight(type.caption.lineHeight)
        .fontColor(tool.ok === false ? this.p().danger : this.p().ink2)
        .textAlign(TextAlign.Start)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .onClick((): void => {
          if (this.toolHasDetail(tool)) this.onToggleTool(index)
        })
      if (this.expandedTool === index) {
        Column({ space: 4 }) {
          Text(this.toolDetailOf(tool))
            .fontSize(type.small.fontSize)
            .lineHeight(type.small.lineHeight)
            .fontColor(tool.ok === false ? this.p().danger : this.p().ink2)
            .fontFamily(MONO)
            .textAlign(TextAlign.Start)
            .width('100%')
            .copyOption(CopyOptions.LocalDevice)
          Text(this.copiedTool === index ? t('Copied') : t('Copy'))
            .fontSize(type.caption.fontSize)
            .lineHeight(type.caption.lineHeight)
            .fontColor(this.p().ink3)
            .alignSelf(ItemAlign.End)
            .onClick((): void => this.copyToolDetail(tool, index))
        }
        .width('100%')
        .padding({ left: 8, right: 8, top: 6, bottom: 6 })
        .borderRadius(radius.input)
        .backgroundColor(this.p().hover)
        .alignItems(HorizontalAlign.Start)
      } else if (this.toolHasDetail(tool)) {
        Text(this.toolDetailOf(tool))
          .fontSize(type.small.fontSize)
          .lineHeight(type.small.lineHeight)
          .fontColor(this.p().ink3)
          .textAlign(TextAlign.Start)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .onClick((): void => this.onToggleTool(index))
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  dividerRow() {
    Row({ space: 10 }) {
      Divider()
        .strokeWidth(this.hairline())
        .color(this.p().line)
        .layoutWeight(1)
      if (typeof this.item.time === 'number') {
        Text(clockLabel(this.item.time))
          .fontSize(type.caption.fontSize)
          .lineHeight(type.caption.lineHeight)
          .fontColor(this.p().ink3)
      }
      Divider()
        .strokeWidth(this.hairline())
        .color(this.p().line)
        .layoutWeight(1)
    }
    .width('100%')
    .margin({ top: 12, bottom: 12 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  relayRow() {
    if (this.relayLine() !== '') {
      Text(this.relayLine())
        .fontSize(type.caption.fontSize)
        .lineHeight(type.caption.lineHeight)
        .fontColor(this.p().ink3)
        .textAlign(TextAlign.Center)
        .padding({ left: 12, right: 12 })
        .margin({ top: 4, bottom: 4 })
        .alignSelf(ItemAlign.Center)
    }
  }

  @Builder
  eventRow() {
    Text(this.eventLine())
      .fontSize(type.caption.fontSize)
      .lineHeight(type.caption.lineHeight)
      .fontColor(this.p().ink3)
      .textAlign(TextAlign.Center)
      .padding({ left: 12, right: 12 })
      .margin({ top: 4, bottom: 4 })
      .alignSelf(ItemAlign.Center)
  }

  @Builder
  closedRow() {
    Row({ space: 10 }) {
      Text(this.item.question?.question ?? this.item.title ?? '')
        .fontSize(type.small.fontSize)
        .lineHeight(type.small.lineHeight)
        .fontWeight('500')
        .fontColor(this.p().ink2)
        .layoutWeight(1)
      Text(this.closedBadge())
        .fontSize(type.caption.fontSize)
        .lineHeight(type.caption.lineHeight)
        .fontColor(this.p().ink2)
        .padding({ left: 8, right: 8, top: 2, bottom: 2 })
        .borderRadius(radius.pill)
        .border({ width: 1, color: this.p().line2, style: BorderStyle.Dashed })
    }
    .alignItems(VerticalAlign.Top)
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .margin({ top: 6, bottom: 6 })
    .borderRadius(radius.dialog)
    .border({ width: this.hairline(), color: this.p().line })
    .backgroundColor(this.p().card)
  }

  @Builder
  viewRow() {
    if (itemViewNode(this.item) !== null) {
      DeepView({
        sessionId: this.sessionId,
        title: this.item.title ?? '',
        root: this.viewRoot(),
        readOnly: true,
      })
    } else {
      Column() {
        Text(this.item.title ?? 'View')
          .fontSize(type.settingsRow.fontSize)
          .lineHeight(type.settingsRow.lineHeight)
          .fontWeight('600')
          .fontColor(this.p().ink)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .margin({ top: 6, bottom: 6 })
      .borderRadius(radius.dialog)
      .border({ width: this.hairline(), color: this.p().line })
      .backgroundColor(this.p().card)
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  answerRow() {
    if (this.handoffOf() !== undefined) {
      this.handoffCard()
    } else if (viewRepliesOf(this.item).length > 0) {
      this.viewRepliesCard()
    } else if ((this.item.questions ?? []).length > 0) {
      this.settledQuestionsCard()
    } else {
      this.answerBubble()
    }
  }

  @Builder
  handoffCard() {
    Row({ space: 10 }) {
      Text(handoffTitleOf(this.handoffOf()?.reason))
        .fontSize(type.small.fontSize)
        .lineHeight(type.small.lineHeight)
        .fontWeight('500')
        .fontColor(this.p().ink2)
        .layoutWeight(1)
      if (this.handoffSkipped() || this.handoffReturned()) {
        Text(t(this.handoffSkipped() ? 'Skipped' : 'Returned'))
          .fontSize(type.caption.fontSize)
          .lineHeight(type.caption.lineHeight)
          .fontColor(this.p().ink2)
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .borderRadius(radius.pill)
          .border({ width: 1, color: this.p().line2, style: BorderStyle.Dashed })
      } else {
        Icon({ name: 'check', iconSize: 16, color: this.p().ink2 })
      }
    }
    .alignItems(VerticalAlign.Top)
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .margin({ top: 6, bottom: 6 })
    .borderRadius(radius.dialog)
    .border({ width: this.hairline(), color: this.p().line })
    .backgroundColor(this.p().card)
  }

  @Builder
  viewRepliesCard() {
    Column({ space: 8 }) {
      ForEach(viewRepliesOf(this.item), (reply: ViewReplyDetail, index: number) => {
        Column({ space: 4 }) {
          if (reply.title !== '') {
            Text(reply.title)
              .fontSize(type.small.fontSize)
              .lineHeight(type.small.lineHeight)
              .fontWeight('500')
              .fontColor(this.p().ink2)
          }
          Text(reply.detail !== '' ? reply.detail : this.source())
            .fontSize(type.small.fontSize)
            .lineHeight(type.small.lineHeight)
            .fontColor(this.p().ink)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
      }, (reply: ViewReplyDetail, index: number): string => `${index}-${reply.title}`)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .margin({ top: 6, bottom: 6 })
    .borderRadius(radius.dialog)
    .border({ width: this.hairline(), color: this.p().line })
    .backgroundColor(this.p().card)
    .gesture(LongPressGesture().onAction((): void => this.longPress()))
  }

  // An answered ask_user card folds to its result across the chat column, so
  // multi-line picks never collapse or clip.
  @Builder
  settledQuestionsCard() {
    Column({ space: 8 }) {
      ForEach(settledLinesOf(this.item), (line: SettledLine, index: number) => {
        Column({ space: 6 }) {
          Text(line.question)
            .fontSize(type.small.fontSize)
            .lineHeight(type.small.lineHeight)
            .fontWeight('500')
            .fontColor(this.p().ink2)
          ForEach(line.picks, (pick: SettledPick, pickIndex: number) => {
            Row({ space: 10 }) {
              Column() {
                Text(pick.letter)
                  .fontSize(12)
                  .fontWeight('600')
                  .fontColor(this.p().accentInk)
              }
              .width(22)
              .height(22)
              .borderRadius(7)
              .backgroundColor(this.p().accent)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              .margin({ top: 1 })
              Text(pick.label)
                .fontSize(type.small.fontSize)
                .lineHeight(20)
                .fontColor(this.p().ink)
                .layoutWeight(1)
            }
            .alignItems(VerticalAlign.Top)
            .padding({ top: 2, bottom: 2 })
          }, (pick: SettledPick, pickIndex: number): string => `${index}-${pickIndex}-${pick.label}`)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
      }, (line: SettledLine, index: number): string => `${index}-${line.question}`)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .margin({ top: 6, bottom: 6 })
    .borderRadius(radius.dialog)
    .border({ width: this.hairline(), color: this.p().line })
    .backgroundColor(this.p().card)
    .gesture(LongPressGesture().onAction((): void => this.longPress()))
  }

  @Builder
  answerBubble() {
    Column() {
      Text(this.source())
        .fontSize(type.bubble.fontSize)
        .lineHeight(type.bubble.lineHeight)
        .fontColor(this.p().userInk)
    }
    .padding({ left: 14, right: 14, top: 9, bottom: 9 })
    .margin({ top: 2, bottom: 2 })
    .borderRadius(radius.bubble)
    .backgroundColor(this.p().user)
    .constraintSize({ maxWidth: this.maxWidth })
    .alignSelf(ItemAlign.End)
    .gesture(LongPressGesture().onAction((): void => this.longPress()))
  }

  @Builder
  userRow() {
    if (this.item.local === 'failed') {
      Column({ space: 4 }) {
        this.userBubble()
        Row({ space: 12 }) {
          Text(t('Not sent. Tap to retry'))
            .fontSize(type.caption.fontSize)
            .lineHeight(type.caption.lineHeight)
            .fontColor(this.p().danger)
            .onClick((): void => this.retryTap(false))
          Text(t('Delete'))
            .fontSize(type.caption.fontSize)
            .lineHeight(type.caption.lineHeight)
            .fontColor(this.p().ink3)
            .onClick((): void => this.retryTap(true))
        }
        .margin({ right: 2 })
      }
      .alignItems(HorizontalAlign.End)
      .constraintSize({ maxWidth: this.maxWidth })
      .alignSelf(ItemAlign.End)
    } else if (this.stamp !== '' || this.item.via !== undefined) {
      Column({ space: 2 }) {
        this.userBubble()
        Row({ space: 6 }) {
          if (this.item.via !== undefined) {
            Text(this.viaLabel())
              .fontSize(11)
              .lineHeight(16)
              .fontColor(this.p().ink3)
              .padding({ left: 6, right: 6 })
              .borderRadius(6)
              .backgroundColor(this.p().hover)
          }
          if (this.stamp !== '') {
            Text(this.stamp)
              .fontSize(type.caption.fontSize)
              .lineHeight(type.caption.lineHeight)
              .fontColor(this.p().ink3)
          }
        }
        .margin({ right: 2 })
      }
      .alignItems(HorizontalAlign.End)
      .constraintSize({ maxWidth: this.maxWidth })
      .alignSelf(ItemAlign.End)
    } else {
      this.userBubble()
    }
  }

  @Builder
  userBubble() {
    // A user message with a code block or table takes the full width, as a
    // Bot's does: a bubble sized to its content cannot hold a block that
    // scrolls sideways. The two branches share the content builder; only the
    // width attribute differs (RN: width: wide ? maxWidth : undefined).
    if (this.userWide()) {
      Column() {
        this.userBubbleContent()
      }
      .padding(this.bubblePadding())
      .margin({ top: 2, bottom: 2 })
      .borderRadius(radius.bubble)
      .backgroundColor(this.photosOnly() ? 'transparent' : this.p().user)
      .width(this.maxWidth)
      .constraintSize({ maxWidth: this.maxWidth })
      .alignSelf(ItemAlign.End)
      .opacity(this.item.local === 'sending' ? 0.7 : 1)
      .onClick((): void => this.userTap())
      .gesture(LongPressGesture().onAction((): void => this.longPress()))
    } else {
      Column() {
        this.userBubbleContent()
      }
      .padding(this.bubblePadding())
      .margin({ top: 2, bottom: 2 })
      .borderRadius(radius.bubble)
      .backgroundColor(this.photosOnly() ? 'transparent' : this.p().user)
      .constraintSize({ maxWidth: this.maxWidth })
      .alignSelf(ItemAlign.End)
      .opacity(this.item.local === 'sending' ? 0.7 : 1)
      .onClick((): void => this.userTap())
      .gesture(LongPressGesture().onAction((): void => this.longPress()))
    }
  }

  @Builder
  userBubbleContent() {
    if ((this.item.text ?? '').trim() !== '') {
      MarkdownText({ text: this.item.text ?? '', textColor: this.p().userInk, bg: this.p().user,
        sessionId: this.rowSessionId(), botId: this.authorBotId() })
    }
    ForEach(this.item.files ?? [], (file: FileRef) => {
      this.fileChip(file)
    }, (file: FileRef): string => file.attachmentId ?? file.name)
    if ((this.item.localImages ?? []).length > 0) {
      LocalImages({ uris: this.item.localImages ?? [] })
    } else if ((this.item.imageRefs ?? []).length > 0 && this.sessionId !== '') {
      ImageGrid({
        refs: this.item.imageRefs ?? [],
        sessionId: this.sessionId,
        onOpen: (index: number): void => this.onOpenPhoto(index),
      })
    } else if (this.item.images !== undefined && this.item.images > 0) {
      Text(t('{count} images', { 'count': this.item.images }))
        .fontSize(type.caption.fontSize)
        .lineHeight(type.caption.lineHeight)
        .fontColor(this.p().userInk)
        .opacity(0.8)
        .margin({ top: 4 })
    }
  }

  @Builder
  fileChip(file: FileRef) {
    Row() {
      Column({ space: 1 }) {
        Text(file.name)
          .fontSize(type.small.fontSize)
          .lineHeight(type.small.lineHeight)
          .fontWeight('500')
          .fontColor(this.p().ink)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.fileSub(file))
          .fontSize(type.caption.fontSize)
          .lineHeight(type.caption.lineHeight)
          .fontColor(this.p().ink3)
      }
      .constraintSize({ minHeight: 44 })
      .justifyContent(FlexAlign.Center)
      .padding({ left: 10, right: 10, top: 8, bottom: 8 })
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .onClick((): void => this.onOpenFile(file))
      Column() {
        Text(t('Save'))
          .fontSize(type.small.fontSize)
          .lineHeight(type.small.lineHeight)
          .fontWeight('600')
          .fontColor(this.p().accent)
          .padding({ left: 12, right: 12 })
      }
      .constraintSize({ minHeight: 44 })
      .justifyContent(FlexAlign.Center)
      .onClick((): void => this.onSaveFile(file))
    }
    .alignItems(VerticalAlign.Center)
    .borderRadius(12)
    .border({ width: this.hairline(), color: this.p().line2 })
    .backgroundColor(this.p().card)
    .margin({ top: 6 })
  }

  // The images, file chips and full-message link that trail a Bot reply.
  @Builder
  trailingBotContent() {
    if ((this.item.imageRefs ?? []).length > 0 && this.sessionId !== '') {
      ImageGrid({
        refs: this.item.imageRefs ?? [],
        sessionId: this.sessionId,
        onOpen: (index: number): void => this.onOpenPhoto(index),
      })
    }
    ForEach(this.item.files ?? [], (file: FileRef) => {
      this.fileChip(file)
    }, (file: FileRef): string => file.attachmentId ?? file.name)
    if (this.wholeFile() !== undefined) {
      Text(t('Read full message'))
        .fontSize(type.small.fontSize)
        .lineHeight(type.small.lineHeight)
        .fontWeight('500')
        .fontColor(this.p().accent)
        .padding({ top: 2, bottom: 2 })
        .margin({ top: 6 })
        .onClick((): void => {
          const whole = this.wholeFile()
          if (whole !== undefined) this.onOpenFile(whole)
        })
    }
  }

  // In a group each reply carries its member: avatar, name in the member's
  // color, the admin tag and the time, as the desktop's group rows do.
  @Builder
  roomRow() {
    Row({ space: 8 }) {
      Column() {
        if (this.author !== undefined) {
          Avatar({ bot: this.author, dark: appStore.theme.dark, markSize: 22, ring: this.p().main })
        }
      }
      .width(22)
      .padding({ top: 22 })
      .alignItems(HorizontalAlign.Start)

      Column() {
        Row({ space: 6 }) {
          Text(this.item.name ?? this.author?.name ?? '')
            .fontSize(type.caption.fontSize)
            .lineHeight(type.caption.lineHeight)
            .fontWeight('500')
            .fontColor(this.author !== undefined ? inkColor(this.author.color, appStore.theme.dark) : this.p().ink2)
            .maxLines(1)
            .layoutWeight(1)
          if (this.admin) {
            Text(t('Admin'))
              .fontSize(11)
              .lineHeight(16)
              .fontColor(this.p().ink3)
              .padding({ left: 6, right: 6 })
              .borderRadius(6)
              .backgroundColor(this.p().hover)
          }
          if (typeof this.item.time === 'number') {
            Text(messageClock(this.item.time))
              .fontSize(type.caption.fontSize)
              .lineHeight(type.caption.lineHeight)
              .fontColor(this.p().ink3)
          }
        }
        .margin({ left: 2, bottom: 3 })
        .alignItems(VerticalAlign.Center)

        ForEach(this.bodyTexts(), (partText: string, partIndex: number) => {
          Column() {
            MarkdownText({ text: partText, textColor: this.p().ink, bg: this.p().bubble,
              sessionId: this.rowSessionId(), botId: this.authorBotId() })
            if (partIndex === this.bodyTexts().length - 1) {
              this.trailingBotContent()
            }
          }
          .padding({ left: 14, right: 14, top: 9, bottom: 9 })
          .margin({ top: 2, bottom: 2 })
          .borderRadius(radius.bubble)
          .backgroundColor(this.p().bubble)
          .constraintSize({ maxWidth: '100%' })
          .alignSelf(hasBlockContent(partText) || (partIndex === this.bodyTexts().length - 1 && this.roomHasImages())
            ? ItemAlign.Stretch : ItemAlign.Start)
          .alignItems(HorizontalAlign.Start)
        }, (partText: string, partIndex: number): string => `${partIndex}-${partText}`)

        if (this.bodyTexts().length === 0) {
          Column() {
            this.trailingBotContent()
          }
          .padding({ left: 14, right: 14, top: 9, bottom: 9 })
          .margin({ top: 2, bottom: 2 })
          .borderRadius(radius.bubble)
          .backgroundColor(this.p().bubble)
          .constraintSize({ maxWidth: '100%' })
          .alignItems(HorizontalAlign.Start)
        }
      }
      .layoutWeight(1)
      .constraintSize({ maxWidth: this.maxWidth })
      .alignItems(HorizontalAlign.Start)
    }
    .alignItems(VerticalAlign.Top)
    .margin({ top: 6 })
    .gesture(LongPressGesture().onAction((): void => this.longPress()))
  }

  @Builder
  flatRow() {
    Column() {
      if (this.inRoom && (this.item.name ?? '') !== '') {
        Text(this.item.name)
          .fontSize(type.caption.fontSize)
          .lineHeight(type.caption.lineHeight)
          .fontColor(this.p().ink3)
          .margin({ bottom: 2, left: 2 })
      }
      if (this.bodyJoined() !== '') {
        MarkdownText({ text: this.bodyJoined(), textColor: this.p().ink, bg: this.p().main,
          sessionId: this.rowSessionId(), botId: this.authorBotId() })
      }
      this.trailingBotContent()
      if (this.stamp !== '') {
        Text(this.stamp)
          .fontSize(type.caption.fontSize)
          .lineHeight(type.caption.lineHeight)
          .fontColor(this.p().ink3)
          .margin({ top: 4 })
      }
    }
    .width('100%')
    .margin({ top: 4, bottom: 4 })
    .alignItems(HorizontalAlign.Start)
    .gesture(LongPressGesture().onAction((): void => this.longPress()))
  }

  @Builder
  botBubbleRow() {
    // A Bot row with block content in any body part, or with images, takes
    // the full width (RN items.tsx): width: wide ? maxWidth : undefined.
    // The two branches share the content builder; only the width differs.
    if (this.botWide()) {
      Column() {
        this.botBubbleContent()
      }
      .width(this.maxWidth)
      .constraintSize({ maxWidth: this.maxWidth })
      .alignSelf(ItemAlign.Start)
      .alignItems(HorizontalAlign.Start)
      .gesture(LongPressGesture().onAction((): void => this.longPress()))
    } else {
      Column() {
        this.botBubbleContent()
      }
      .constraintSize({ maxWidth: this.maxWidth })
      .alignSelf(ItemAlign.Start)
      .alignItems(HorizontalAlign.Start)
      .gesture(LongPressGesture().onAction((): void => this.longPress()))
    }
  }

  @Builder
  botBubbleContent() {
    if (this.inRoom && (this.item.name ?? '') !== '') {
      Text(this.item.name)
        .fontSize(type.caption.fontSize)
        .lineHeight(type.caption.lineHeight)
        .fontColor(this.p().ink3)
        .margin({ bottom: 2, left: 2 })
    }
    Column() {
      if (this.bodyJoined() !== '') {
        MarkdownText({ text: this.bodyJoined(), textColor: this.p().ink, bg: this.p().bubble,
          sessionId: this.rowSessionId(), botId: this.authorBotId() })
      }
      this.trailingBotContent()
    }
    .padding({ left: 14, right: 14, top: 9, bottom: 9 })
    .margin({ top: 2, bottom: 2 })
    .borderRadius(radius.bubble)
    .backgroundColor(this.p().bubble)
    .constraintSize({ maxWidth: '100%' })
    .alignItems(HorizontalAlign.Start)
    if (this.stamp !== '') {
      Text(this.stamp)
        .fontSize(type.caption.fontSize)
        .lineHeight(type.caption.lineHeight)
        .fontColor(this.p().ink3)
        .margin({ top: 2, left: 4 })
    }
  }
}
