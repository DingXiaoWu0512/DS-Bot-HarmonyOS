// The pending dock above the composer: the port of
// mobile/src/screens/chat/dock.tsx. Accordion cards stack — approvals, the
// question card, secret requests, the browser handoff, the chat's shown view
// and the asides — with one expanded at a time; the header dots mark the cards
// still waiting. Taller than roughly half the screen, the dock scrolls inside.
// Every card answers in place through the link (TeamLink.call gates the secret
// endpoints behind the phone's unlock), so nothing here needs a call prop.

import { display } from '@kit.ArkUI'
import { BusinessError } from '@kit.BasicServicesKit'

import { appStore, type, radius, Palette, MONO, shadowOf } from '../../components/Theme'
import { t } from '../../common/ui/i18n'
import type { Approval, Bot, ConnectorRequest, Question, SecretRequest, ShownView } from '../../common/team/types'
import { connectorCanConnectOnMobile } from '../../common/team/connectors'
import { shownViewNode } from '../../common/team/chat-state'
import { agentEditRows, lineDiff } from '../../common/team/learning'
import type { DiffRow, LearningProposal } from '../../common/team/learning'
import type { ViewNode } from '../../common/deepview/views-core'
import { hapticLight, hapticSuccess } from '../../platform/Platform'
import { DeepView } from './DeepView'
import { Icon } from '../../components/Icon'
import { Avatar } from '../../components/Marks'

// Placeholder values for the guarded accordion branches below.
const EMPTY_VIEW_NODE: ViewNode = {}
const EMPTY_APPROVAL: Approval = { id: '', sessionId: '', botId: '', tool: '', reason: '' }
const EMPTY_SECRET: SecretRequest = { id: '' }
const EMPTY_CONNECTOR: ConnectorRequest = { id: '', connectorId: '' }
const EMPTY_BTW: BtwCardData = { id: '' }
const EMPTY_LEARNING: LearningProposal = { id: '', botId: '' }

// Learning rows are folded past this count until expanded (dock.tsx).
const LEARNING_COLLAPSE_ROWS: number = 8

// An aside the Bot parked beside the chat (team.btwCards entry).
export interface BtwCardData {
  id: string
  partId?: string
  question?: string
  answer?: string
  failure?: string
  status?: string
}

// A browser handoff the Bot handed to this phone (team.browserHolds entry).
export interface HandoffData {
  callId: string
  reason?: string
  note?: string
}

// One accordion entry in the dock, in display order.
interface DockCardMeta {
  key: string
  title: string
  needs: boolean
}

interface QuestionOption {
  label: string
}

// The pending dock: approvals first, then the question, secrets, handoff, view
// and asides. `expanded` names the card the user opened (null = the first one
// that needs an answer).
@ComponentV2
export struct Dock {
  @Param question: Question | undefined = undefined
  @Require @Param sessionId: string
  @Param approvals: Approval[] = []
  @Param learning: LearningProposal[] = []
  @Param secrets: SecretRequest[] = []
  @Param connectorRequests: ConnectorRequest[] = []
  @Param botName: string = ''
  @Event onOpenConnector: (connectorId: string) => void = (_connectorId: string): void => {}
  @Param btw: BtwCardData[] = []
  @Param handoff: HandoffData | undefined = undefined
  @Param view: ShownView | undefined = undefined
  @Param canViewBrowser: boolean = false
  @Event onViewBrowser: () => void = (): void => {}
  @Param maxHeight: number = 0
  @Param expanded: string | null = null
  @Event onExpand: (key: string | null) => void = (_key: string | null): void => {}

  private p(): Palette {
    return appStore.theme.p
  }

  private hairline(): number {
    return this.getUIContext().px2vp(1)
  }

  // The dock's height cap: the caller's, or a bit over half the screen.
  private cap(): number {
    if (this.maxHeight > 0) return this.maxHeight
    try {
      return Math.round(this.getUIContext().px2vp(display.getDefaultDisplaySync().height) * 0.52)
    } catch {
      return 420
    }
  }

  private metas(): DockCardMeta[] {
    const out: DockCardMeta[] = []
    for (const proposal of this.learning) {
      const title = proposal.kind === 'agents'
        ? t('AGENTS.md update')
        : `${t(proposal.action === 'update' ? 'Skill update' : 'New skill')} · ${proposal.name ?? ''}`
      out.push({ key: `learning-${proposal.id}`, title, needs: true })
    }
    for (const approval of this.approvals) {
      out.push({
        key: `approval-${approval.id}`,
        title: approval.tool !== '' ? approval.tool : t('Approval'),
        needs: true,
      })
    }
    if (this.question !== undefined) {
      out.push({
        key: 'question',
        title: this.question.question !== '' ? this.question.question : t('Question'),
        needs: true,
      })
    }
    for (const secret of this.secrets) {
      const name = secret.name ?? ''
      const title = secret.kind === 'allow'
        ? t('Allow a secret')
        : (name !== '' ? t('{name} needs a key', { 'name': name }) : t('A secret is needed'))
      out.push({ key: `secret-${secret.id}`, title, needs: true })
    }
    for (const request of this.connectorRequests) {
      const name = request.name ?? ''
      const title = t('{bot} needs {name}', {
        'bot': this.botName !== '' ? this.botName : t('the Bot'),
        'name': name !== '' ? name : request.connectorId,
      })
      out.push({ key: `connector-${request.id}`, title, needs: true })
    }
    if (this.handoff !== undefined) {
      out.push({ key: 'handoff', title: t('Browser handoff'), needs: true })
    }
    if (this.view !== undefined) {
      const title = this.view.title ?? ''
      out.push({ key: `view-${this.view.id ?? 'view'}`, title: title !== '' ? title : t('Card'), needs: true })
    }
    for (const card of this.btw) {
      const question = card.question ?? ''
      out.push({ key: `btw-${card.id}`, title: question !== '' ? question : t('Aside'), needs: false })
    }
    return out
  }

  // The card shown open: the one the user chose, else the first that needs an
  // answer, else the first.
  private activeKey(): string {
    const metas = this.metas()
    if (this.expanded !== null) {
      for (const meta of metas) {
        if (meta.key === this.expanded) return meta.key
      }
    }
    for (const meta of metas) {
      if (meta.needs) return meta.key
    }
    const first = metas[0]
    return first !== undefined ? first.key : ''
  }

  private toggle(meta: DockCardMeta): void {
    void hapticLight()
    if (meta.key === this.activeKey() && this.expanded !== null) {
      this.onExpand(null)
    } else {
      this.onExpand(meta.key)
    }
  }

  private entryApproval(key: string): Approval | undefined {
    const id = key.slice('approval-'.length)
    for (const approval of this.approvals) {
      if (approval.id === id) return approval
    }
    return undefined
  }

  private entryLearning(key: string): LearningProposal | undefined {
    const id = key.slice('learning-'.length)
    for (const proposal of this.learning) {
      if (proposal.id === id) return proposal
    }
    return undefined
  }

  private entrySecret(key: string): SecretRequest | undefined {
    const id = key.slice('secret-'.length)
    for (const secret of this.secrets) {
      if (secret.id === id) return secret
    }
    return undefined
  }

  private entryConnector(key: string): ConnectorRequest | undefined {
    const id = key.slice('connector-'.length)
    for (const request of this.connectorRequests) {
      if (request.id === id) return request
    }
    return undefined
  }

  private entryBtw(key: string): BtwCardData | undefined {
    const id = key.slice('btw-'.length)
    for (const card of this.btw) {
      if (card.id === id) return card
    }
    return undefined
  }

  private botIdOf(): string {
    return this.sessionId.split(':')[0] ?? ''
  }

  private dockViewRoot(): ViewNode {
    return shownViewNode(this.view) ?? EMPTY_VIEW_NODE
  }

  build() {
    Column() {
      if (this.metas().length > 0) {
        Scroll() {
          Column() {
            ForEach(this.metas(), (meta: DockCardMeta) => {
              this.accordion(meta)
            }, (meta: DockCardMeta): string => meta.key)
          }
          .width('100%')
          .padding({ bottom: 4 })
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .constraintSize({ maxHeight: this.cap() })
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .margin({ bottom: 6 })
      }
    }
    .width('100%')
  }

  @Builder
  accordion(meta: DockCardMeta) {
    Column() {
      Row({ space: 8 }) {
        Text(meta.title)
          .fontSize(type.settingsRow.fontSize)
          .lineHeight(type.settingsRow.lineHeight)
          .fontWeight('600')
          .fontColor(this.p().ink)
          .layoutWeight(1)
          .maxLines(meta.key === this.activeKey() ? 4 : 1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (meta.needs && meta.key !== this.activeKey() && this.expanded === null) {
          Column()
            .width(7)
            .height(7)
            .borderRadius(4)
            .backgroundColor(this.p().accent)
        }
        Icon({ name: 'chevronRight', iconSize: 16, color: this.p().ink3 })
          .rotate({ x: 0, y: 0, z: 1, angle: meta.key === this.activeKey() ? 90 : 0, centerX: 8, centerY: 8 })
          .animation({ duration: 180, curve: Curve.EaseOut })
      }
      .constraintSize({ minHeight: 46 })
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
      .alignItems(VerticalAlign.Center)
      .onClick((): void => this.toggle(meta))

      if (meta.key === this.activeKey()) {
        Column() {
          this.cardBody(meta.key)
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 14 })
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('calc(100% - 24vp)')
    .margin({ left: 12, right: 12, top: 5, bottom: 5 })
    .borderRadius(radius.card)
    .border({ width: this.hairline(), color: this.p().line })
    .backgroundColor(this.p().card)
    .clip(true)
    .shadow(shadowOf(1))
  }

  @Builder
  cardBody(key: string) {
    if (key.startsWith('learning-')) {
      if (this.entryLearning(key) !== undefined) {
        LearningCard({ proposal: this.entryLearning(key) ?? EMPTY_LEARNING })
      }
    } else if (key.startsWith('approval-')) {
      if (this.entryApproval(key) !== undefined) {
        ApprovalCard({ approval: this.entryApproval(key) ?? EMPTY_APPROVAL, bare: true })
      }
    } else if (key === 'question') {
      if (this.question !== undefined) {
        QuestionCard({ question: this.question, sessionId: this.sessionId, bare: true })
      }
    } else if (key.startsWith('secret-')) {
      if (this.entrySecret(key) !== undefined) {
        SecretCard({ secret: this.entrySecret(key) ?? EMPTY_SECRET, bare: true })
      }
    } else if (key.startsWith('connector-')) {
      if (this.entryConnector(key) !== undefined) {
        ConnectorRequestCard({
          request: this.entryConnector(key) ?? EMPTY_CONNECTOR,
          onConnect: (connectorId: string): void => this.onOpenConnector(connectorId),
          bare: true,
        })
      }
    } else if (key === 'handoff') {
      if (this.handoff !== undefined) {
        HandoffCard({
          handoff: this.handoff,
          botId: this.botIdOf(),
          canView: this.canViewBrowser,
          onView: (): void => this.onViewBrowser(),
          bare: true,
        })
      }
    } else if (key.startsWith('view-')) {
      DeepView({
        sessionId: this.sessionId,
        viewId: this.view?.id ?? '',
        title: this.view?.title ?? '',
        root: this.dockViewRoot(),
        bare: true,
      })
    } else if (key.startsWith('btw-')) {
      if (this.entryBtw(key) !== undefined) {
        BtwCard({ card: this.entryBtw(key) ?? EMPTY_BTW, sessionId: this.sessionId, bare: true })
      }
    }
  }
}

// A learning proposal awaiting approval (chat/learning.ts): the file it
// touches as a diff — an AGENTS.md proposal's edits as removals and
// additions, a skill's content against its previous text — folded past 8
// rows and answered Approve / Decline through learning-answer, which the
// link gates behind the phone's unlock.
@ComponentV2
export struct LearningCard {
  @Require @Param proposal: LearningProposal
  @Local busy: boolean = false
  @Local error: string = ''
  @Local showAll: boolean = false

  private p(): Palette {
    return appStore.theme.p
  }

  @Computed
  get rows(): DiffRow[] {
    if (this.proposal.kind === 'agents') {
      const out: DiffRow[] = []
      for (const edit of this.proposal.edits ?? []) {
        for (const row of agentEditRows(edit)) out.push(row)
      }
      return out
    }
    const previous: string = this.proposal.action === 'update' ? (this.proposal.previous?.content ?? '') : ''
    return lineDiff(previous, this.proposal.content ?? '')
  }

  private folds(): boolean {
    return this.rows.length > LEARNING_COLLAPSE_ROWS
  }

  private visibleRows(): DiffRow[] {
    if (this.folds() && !this.showAll) {
      return this.rows.slice(0, LEARNING_COLLAPSE_ROWS)
    }
    return this.rows
  }

  private filePath(): string {
    return this.proposal.kind === 'agents'
      ? (this.proposal.folder ?? '')
      : `skills/${this.proposal.name ?? ''}/SKILL.md`
  }

  private whys(): string[] {
    const out: string[] = []
    if (this.proposal.kind === 'agents') {
      for (const edit of this.proposal.edits ?? []) {
        const why = edit.why ?? ''
        if (why !== '') out.push(why)
      }
    } else {
      const why = this.proposal.why ?? ''
      if (why !== '') out.push(why)
    }
    return out
  }

  private answer(approve: boolean): void {
    if (this.busy) return
    this.busy = true
    this.error = ''
    const controller = appStore.link.controller
    if (controller === null) {
      this.error = t('Not connected')
      this.busy = false
      return
    }
    const payload: Record<string, Object> = { 'id': this.proposal.id, 'approve': approve }
    void controller.call('learning-answer', payload).then((): void => {
      this.busy = false
    }).catch((failure: BusinessError): void => {
      const code = `${failure.code ?? ''}`
      if (code !== 'unlock/canceled') {
        this.error = `${failure.message ?? code}`
      }
      this.busy = false
    })
  }

  build() {
    Column() {
      Text(t('Awaiting approval'))
        .fontSize(type.caption.fontSize)
        .lineHeight(type.caption.lineHeight)
        .fontColor(this.p().ink2)
      Text(this.filePath())
        .fontSize(type.small.fontSize)
        .lineHeight(type.small.lineHeight)
        .fontColor(this.p().ink)
        .margin({ top: 8 })
      if ((this.proposal.description ?? '') !== '') {
        Text(this.proposal.description ?? '')
          .fontSize(type.small.fontSize)
          .lineHeight(type.small.lineHeight)
          .fontColor(this.p().ink2)
          .margin({ top: 6 })
      }
      Column() {
        ForEach(this.visibleRows(), (row: DiffRow) => {
          Text(`${row.kind === 'added' ? '+ ' : row.kind === 'removed' ? '\u2212 ' : '  '}${row.line}`)
            .fontFamily(MONO)
            .fontSize(12)
            .lineHeight(19)
            .fontColor(row.kind === 'removed' ? this.p().danger : this.p().ink)
            .backgroundColor(row.kind === 'added' ? this.p().hover : Color.Transparent)
        }, (row: DiffRow, index: number): string => `${index}`)
        if (this.folds()) {
          Text(this.showAll ? t('Show less') : t('Show all {count} lines', { 'count': this.rows.length }))
            .fontSize(type.caption.fontSize)
            .lineHeight(type.caption.lineHeight)
            .fontColor(this.p().accent)
            .margin({ top: 6 })
            .padding({ top: 4, bottom: 4 })
            .onClick((): void => {
              this.showAll = !this.showAll
            })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ top: 8 })
      ForEach(this.whys(), (why: string) => {
        Text(why)
          .fontSize(type.small.fontSize)
          .lineHeight(type.small.lineHeight)
          .fontColor(this.p().ink2)
          .margin({ top: 8 })
      }, (why: string): string => why)
      if (this.error !== '') {
        Text(this.error)
          .fontSize(type.small.fontSize)
          .lineHeight(type.small.lineHeight)
          .fontColor(this.p().danger)
          .margin({ top: 8 })
      }
      Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
        Text(t('Decline'))
          .fontSize(14)
          .fontColor(this.p().ink)
          .backgroundColor(this.p().hover)
          .borderRadius(radius.pill)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .constraintSize({ minHeight: 44, minWidth: 104 })
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .opacity(this.busy ? 0.35 : 1)
          .margin({ right: 8 })
          .onClick((): void => this.answer(false))
        Text(t('Approve'))
          .fontSize(14)
          .fontWeight('600')
          .fontColor(this.p().accentInk)
          .backgroundColor(this.p().accent)
          .borderRadius(radius.pill)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .constraintSize({ minHeight: 44, minWidth: 104 })
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .opacity(this.busy ? 0.35 : 1)
          .onClick((): void => this.answer(true))
      }
      .margin({ top: 12 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

// The question card (ui-standard 10.8): options in a framed list — a single
// pick answers at once, a multi-select toggles and submits — with a custom
// answer row when several can be picked or there are no options.
@ComponentV2
export struct QuestionCard {
  @Require @Param question: Question
  @Require @Param sessionId: string
  @Param bare: boolean = false
  @Local picked: Set<string> = new Set<string>()
  @Local custom: string = ''
  @Local busy: boolean = false
  @Local failed: boolean = false

  private p(): Palette {
    return appStore.theme.p
  }

  private hairline(): number {
    return this.getUIContext().px2vp(1)
  }

  private submitDisabled(): boolean {
    return this.busy || (this.picked.size === 0 && this.custom.trim() === '')
  }

  private send(selected: string[]): void {
    if (this.busy) return
    if (selected.length === 0 && this.custom.trim() === '') return
    this.busy = true
    this.failed = false
    const controller = appStore.link.controller
    if (controller === null) {
      this.failed = true
      this.busy = false
      return
    }
    const answer: Record<string, Object> = { 'selected': selected, 'custom': this.custom.trim() }
    const payload: Record<string, Object> = {
      'sessionId': this.sessionId,
      'questionId': this.question.id,
      'answer': answer,
    }
    void controller.call('answer-question', payload).then((): void => {
      this.busy = false
      void hapticSuccess()
    }).catch((): void => {
      this.failed = true
      this.busy = false
    })
  }

  private toggle(label: string): void {
    if (this.question.multiSelect !== true) {
      this.send([label])
      return
    }
    const next: Set<string> = new Set<string>(this.picked)
    if (next.has(label)) next.delete(label)
    else next.add(label)
    this.picked = next
  }

  build() {
    if (this.bare) {
      Column() {
        this.cardBody()
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    } else {
      Column() {
        Text(this.question.question)
          .fontSize(type.settingsRow.fontSize)
          .lineHeight(type.settingsRow.lineHeight)
          .fontWeight('600')
          .fontColor(this.p().ink)
        this.cardBody()
      }
      .width('calc(100% - 24vp)')
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(radius.card)
      .border({ width: this.hairline(), color: this.p().line })
      .backgroundColor(this.p().card)
      .padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .shadow(shadowOf(1))
    }
  }

  @Builder
  cardBody() {
    if ((this.question.detail ?? '') !== '') {
      Text(this.question.detail ?? '')
        .fontSize(type.small.fontSize)
        .lineHeight(type.small.lineHeight)
        .fontColor(this.p().ink2)
        .margin({ top: 4 })
    }
    Column() {
      ForEach(this.question.options ?? [], (option: QuestionOption, index: number) => {
        Text(option.label)
          .fontSize(type.settingsRow.fontSize)
          .lineHeight(type.settingsRow.lineHeight)
          .fontColor(this.picked.has(option.label) ? this.p().accent : this.p().ink)
          .width('100%')
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .constraintSize({ minHeight: 44 })
          .onClick((): void => this.toggle(option.label))
        if (index < (this.question.options ?? []).length - 1) {
          Divider()
            .strokeWidth(this.hairline())
            .color(this.p().line)
        }
      }, (option: QuestionOption): string => option.label)
    }
    .width('100%')
    .borderRadius(radius.option)
    .border({ width: 1, color: this.p().line })
    .clip(true)
    .margin({ top: 12 })

    if (this.question.multiSelect === true || (this.question.options ?? []).length === 0) {
      Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
        TextInput({ text: this.custom, placeholder: t('Your answer') })
          .onChange((value: string): void => {
            this.custom = value
          })
          .placeholderColor(this.p().ink3)
          .fontSize(15)
          .fontColor(this.p().ink)
          .backgroundColor(this.p().hover)
          .borderRadius(radius.input)
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .constraintSize({ minHeight: 40, minWidth: 160 })
          .layoutWeight(1)
        Text(t('Submit'))
          .fontSize(13)
          .fontWeight('600')
          .fontColor(this.p().accentInk)
          .backgroundColor(this.p().accent)
          .borderRadius(radius.pill)
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .constraintSize({ minHeight: 40 })
          .margin({ left: 8 })
          .opacity(this.submitDisabled() ? 0.35 : 1)
          .onClick((): void => {
            const selected: string[] = []
            for (const label of this.picked) selected.push(label)
            this.send(selected)
          })
      }
      .margin({ top: 12 })
    }

    if (this.failed) {
      Text(t('This question is no longer open.'))
        .fontSize(type.small.fontSize)
        .lineHeight(type.small.lineHeight)
        .fontColor(this.p().danger)
        .margin({ top: 8 })
    }
  }
}

// An approval the Bot paused for: what it wants to run and why, with Allow
// once / Reject when the phone can answer it.
@ComponentV2
export struct ApprovalCard {
  @Require @Param approval: Approval
  @Param bare: boolean = false
  @Local busy: boolean = false
  @Local failed: boolean = false

  private p(): Palette {
    return appStore.theme.p
  }

  private hairline(): number {
    return this.getUIContext().px2vp(1)
  }

  // [taskTitle, tool or 'Approval'] — what the approval is for, joined.
  private titleText(): string {
    const parts: string[] = []
    if ((this.approval.taskTitle ?? '') !== '') parts.push(this.approval.taskTitle ?? '')
    parts.push(this.approval.tool !== '' ? this.approval.tool : 'Approval')
    return parts.join(' · ')
  }

  private answer(choice: string): void {
    if (this.busy) return
    this.busy = true
    this.failed = false
    const controller = appStore.link.controller
    if (controller === null) {
      this.failed = true
      this.busy = false
      return
    }
    const payload: Record<string, Object> = { 'id': this.approval.id, 'choice': choice }
    void controller.call('approval-answer', payload).then((): void => {
      this.busy = false
      if (choice === 'allow') void hapticSuccess()
      else void hapticLight()
    }).catch((): void => {
      this.failed = true
      this.busy = false
    })
  }

  build() {
    if (this.bare) {
      Column() {
        this.cardBody()
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    } else {
      Column() {
        Text(this.titleText())
          .fontSize(type.settingsRow.fontSize)
          .lineHeight(type.settingsRow.lineHeight)
          .fontWeight('600')
          .fontColor(this.p().ink)
          .maxLines(2)
        this.cardBody()
      }
      .width('calc(100% - 24vp)')
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(radius.card)
      .border({ width: this.hairline(), color: this.p().line })
      .backgroundColor(this.p().card)
      .padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .shadow(shadowOf(1))
    }
  }

  @Builder
  cardBody() {
    if (this.bare && (this.approval.taskTitle ?? '') !== '') {
      Text(this.approval.taskTitle ?? '')
        .fontSize(type.caption.fontSize)
        .lineHeight(type.caption.lineHeight)
        .fontColor(this.p().ink2)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ bottom: 2 })
    }
    if ((this.approval.detail?.text ?? '') !== '') {
      Text(this.approval.detail?.text ?? '')
        .fontSize(type.small.fontSize)
        .lineHeight(type.small.lineHeight)
        .fontColor(this.p().ink)
        .margin({ top: 4 })
        .copyOption(CopyOptions.LocalDevice)
    }
    if (this.approval.reason !== '') {
      Text(this.approval.reason)
        .fontSize(type.small.fontSize)
        .lineHeight(type.small.lineHeight)
        .fontColor(this.p().ink2)
        .margin({ top: 4 })
        .maxLines(4)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .copyOption(CopyOptions.LocalDevice)
    }
    if ((this.approval.detail?.code ?? '') !== '') {
      Text(this.approval.detail?.code ?? '')
        .fontSize(type.small.fontSize)
        .lineHeight(type.small.lineHeight)
        .fontColor(this.p().ink3)
        .margin({ top: 6 })
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .fontFamily(MONO)
        .copyOption(CopyOptions.LocalDevice)
    }
    if (this.approval.answerable === true) {
      Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
        Text(t('Reject'))
          .fontSize(14)
          .fontColor(this.p().ink)
          .backgroundColor(this.p().hover)
          .borderRadius(radius.pill)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .constraintSize({ minHeight: 44, minWidth: 104 })
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .opacity(this.busy ? 0.35 : 1)
          .margin({ right: 8 })
          .onClick((): void => this.answer('reject'))
        Text(t('Allow once'))
          .fontSize(14)
          .fontWeight('600')
          .fontColor(this.p().accentInk)
          .backgroundColor(this.p().accent)
          .borderRadius(radius.pill)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .constraintSize({ minHeight: 44, minWidth: 104 })
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .opacity(this.busy ? 0.35 : 1)
          .onClick((): void => this.answer('allow'))
      }
      .margin({ top: 12 })
    } else {
      Text(t('Answer on the computer.'))
        .fontSize(type.small.fontSize)
        .lineHeight(type.small.lineHeight)
        .fontColor(this.p().ink2)
        .margin({ top: 8 })
    }
    if (this.failed) {
      Text(t('This approval is no longer open.'))
        .fontSize(type.small.fontSize)
        .lineHeight(type.small.lineHeight)
        .fontColor(this.p().danger)
        .margin({ top: 8 })
    }
  }
}

// A secret request: allow a stored key, or type one — the value never echoes
// back, the input is a secure field and clears the moment it is saved. The
// secret endpoints unlock behind the phone's biometrics; a dismissed prompt
// leaves the card open.
@ComponentV2
export struct SecretCard {
  @Require @Param secret: SecretRequest
  @Param bare: boolean = false
  @Local value: string = ''
  @Local busy: boolean = false
  @Local failed: boolean = false

  private p(): Palette {
    return appStore.theme.p
  }

  private hairline(): number {
    return this.getUIContext().px2vp(1)
  }

  private allow(): boolean {
    return this.secret.kind === 'allow'
  }

  private send(endpoint: string, payload: Record<string, Object>): void {
    if (this.busy) return
    this.busy = true
    const controller = appStore.link.controller
    if (controller === null) {
      this.failed = true
      this.busy = false
      return
    }
    const full: Record<string, Object> = { 'requestId': this.secret.id }
    for (const key of Object.keys(payload)) {
      full[key] = payload[key]
    }
    void controller.call(endpoint, full).then((): void => {
      this.busy = false
    }).catch((failure: BusinessError): void => {
      const code = `${failure.code ?? ''}`
      if (code === 'unlock/canceled') {
        // The unlock prompt was dismissed; the card stays open.
      } else {
        this.failed = true
      }
      this.busy = false
    })
  }

  build() {
    if (this.bare) {
      Column() {
        this.cardBody()
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    } else {
      Column() {
        if (!this.allow()) {
          Text(t('{name} needs a key', { 'name': this.secret.name ?? '' }))
            .fontSize(type.settingsRow.fontSize)
            .lineHeight(type.settingsRow.lineHeight)
            .fontWeight('600')
            .fontColor(this.p().ink)
        } else {
          Text(t('Let {bot} use {name}?', { 'bot': t('the Bot'), 'name': this.secret.name ?? '' }))
            .fontSize(type.settingsRow.fontSize)
            .lineHeight(type.settingsRow.lineHeight)
            .fontWeight('600')
            .fontColor(this.p().ink)
        }
        this.cardBody()
      }
      .width('calc(100% - 24vp)')
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(radius.card)
      .border({ width: this.hairline(), color: this.p().line })
      .backgroundColor(this.p().card)
      .padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .shadow(shadowOf(1))
    }
  }

  @Builder
  cardBody() {
    if (this.allow() && this.secret.scope !== undefined) {
      Text(this.scopeLine())
        .fontSize(type.small.fontSize)
        .lineHeight(type.small.lineHeight)
        .fontColor(this.p().ink2)
        .margin({ top: 6 })
    }
    if (!this.allow()) {
      TextInput({ text: this.value, placeholder: t('Value of {name}', { 'name': this.secret.name ?? '' }) })
        .onChange((value: string): void => {
          this.value = value
        })
        .placeholderColor(this.p().ink3)
        .fontSize(14)
        .fontColor(this.p().ink)
        .type(InputType.Password)
        .border({ width: 1, color: this.p().line })
        .borderRadius(10)
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .constraintSize({ minHeight: 40 })
        .margin({ top: 10 })
        .backgroundColor(Color.Transparent.toString())
    }
    Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
      Text(t('Cancel'))
        .fontSize(14)
        .fontColor(this.p().ink)
        .backgroundColor(this.p().hover)
        .borderRadius(radius.pill)
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .constraintSize({ minHeight: 44, minWidth: 104 })
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .opacity(this.busy ? 0.35 : 1)
        .margin({ right: 8 })
        .onClick((): void => {
          this.send('secret-cancel', {})
        })
      if (this.allow()) {
        Text(this.busy ? t('Allowing…') : t('Allow'))
          .fontSize(14)
          .fontWeight('600')
          .fontColor(this.p().accentInk)
          .backgroundColor(this.p().accent)
          .borderRadius(radius.pill)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .constraintSize({ minHeight: 44, minWidth: 104 })
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .opacity(this.busy ? 0.35 : 1)
          .onClick((): void => {
            this.send('secret-allow', {})
          })
      } else {
        Text(this.busy ? t('Saving…') : t('Save'))
          .fontSize(14)
          .fontWeight('600')
          .fontColor(this.p().accentInk)
          .backgroundColor(this.p().accent)
          .borderRadius(radius.pill)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .constraintSize({ minHeight: 44, minWidth: 104 })
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .opacity(this.busy || this.value.trim() === '' ? 0.35 : 1)
          .onClick((): void => {
            if (this.value.trim() === '') return
            const next = this.value
            this.value = ''
            this.send('secret-set', { 'value': next })
          })
      }
    }
    .margin({ top: 12 })

    if (this.failed) {
      Text(t('This approval is no longer open.'))
        .fontSize(type.small.fontSize)
        .lineHeight(type.small.lineHeight)
        .fontColor(this.p().danger)
        .margin({ top: 8 })
    }
  }

  private scopeLine(): string {
    const scope = this.secret.scope
    if (Array.isArray(scope)) return scope.join(', ')
    return scope ?? ''
  }
}

// The Bot asked to use a connector (mail and friends): dismiss it here, or
// open the connector's setup screen when the phone can connect it.
@ComponentV2
export struct ConnectorRequestCard {
  @Require @Param request: ConnectorRequest
  @Event onConnect: (connectorId: string) => void = (_connectorId: string): void => {}
  @Param bare: boolean = false
  @Local busy: boolean = false
  @Local failed: boolean = false

  private p(): Palette {
    return appStore.theme.p
  }

  private hairline(): number {
    return this.getUIContext().px2vp(1)
  }

  private mobileSupported(): boolean {
    return connectorCanConnectOnMobile(this.request.connectorId)
  }

  private dismiss(): void {
    if (this.busy) return
    this.busy = true
    this.failed = false
    const controller = appStore.link.controller
    if (controller === null) {
      this.failed = true
      this.busy = false
      return
    }
    const payload: Record<string, Object> = { 'requestId': this.request.id }
    void controller.call('connector-request-cancel', payload).then((): void => {
      this.busy = false
    }).catch((failure: BusinessError): void => {
      this.failed = true
      this.busy = false
    })
  }

  build() {
    if (this.bare) {
      Column() {
        this.cardBody()
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    } else {
      Column() {
        Text(t('{bot} needs {name}', {
          'bot': t('the Bot'),
          'name': this.request.name ?? this.request.connectorId,
        }))
          .fontSize(type.settingsRow.fontSize)
          .lineHeight(type.settingsRow.lineHeight)
          .fontWeight('600')
          .fontColor(this.p().ink)
        this.cardBody()
      }
      .width('calc(100% - 24vp)')
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(radius.card)
      .border({ width: this.hairline(), color: this.p().line })
      .backgroundColor(this.p().card)
      .padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .shadow(shadowOf(1))
    }
  }

  @Builder
  cardBody() {
    if (this.request.purpose !== undefined && this.request.purpose !== '') {
      Text(this.request.purpose)
        .fontSize(type.small.fontSize)
        .lineHeight(type.small.lineHeight)
        .fontColor(this.p().ink2)
        .margin({ top: this.bare ? 0 : 4 })
    }
    if (!this.mobileSupported()) {
      Text(t('Set up your mailbox on the computer.'))
        .fontSize(type.small.fontSize)
        .lineHeight(type.small.lineHeight)
        .fontColor(this.p().ink2)
        .margin({ top: 8 })
    }
    Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
      Text(t('Dismiss'))
        .fontSize(14)
        .fontColor(this.p().ink)
        .backgroundColor(this.p().hover)
        .borderRadius(radius.pill)
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .constraintSize({ minHeight: 44, minWidth: 104 })
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .opacity(this.busy ? 0.35 : 1)
        .margin({ right: 8 })
        .onClick((): void => {
          this.dismiss()
        })
      if (this.mobileSupported()) {
        Text(t('Connect'))
          .fontSize(14)
          .fontWeight('600')
          .fontColor(this.p().accentInk)
          .backgroundColor(this.p().accent)
          .borderRadius(radius.pill)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .constraintSize({ minHeight: 44, minWidth: 104 })
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .opacity(this.busy ? 0.35 : 1)
          .onClick((): void => {
            this.onConnect(this.request.connectorId)
          })
      }
    }
    .margin({ top: 12 })

    if (this.failed) {
      Text(t('This approval is no longer open.'))
        .fontSize(type.small.fontSize)
        .lineHeight(type.small.lineHeight)
        .fontColor(this.p().danger)
        .margin({ top: 8 })
    }
  }
}

// An aside the Bot parked beside the chat; dismissed with one tap.
@ComponentV2
export struct BtwCard {
  @Require @Param card: BtwCardData
  @Require @Param sessionId: string
  @Param bare: boolean = false
  @Local busy: boolean = false

  private p(): Palette {
    return appStore.theme.p
  }

  private hairline(): number {
    return this.getUIContext().px2vp(1)
  }

  private drop(): void {
    if (this.busy) return
    this.busy = true
    const controller = appStore.link.controller
    if (controller === null) {
      this.busy = false
      return
    }
    const payload: Record<string, Object> = { 'sessionId': this.sessionId, 'cardId': this.card.id }
    void controller.call('btw-delete', payload).catch((): void => {}).then((): void => {
      this.busy = false
    })
  }

  build() {
    if (this.bare) {
      Column() {
        this.texts(0)
        Text(t('Dismiss'))
          .fontSize(type.caption.fontSize)
          .lineHeight(type.caption.lineHeight)
          .fontColor(this.p().ink2)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .borderRadius(radius.pill)
          .backgroundColor(this.p().hover)
          .margin({ top: 8 })
          .opacity(this.busy ? 0.35 : 1)
          .onClick((): void => this.drop())
          .alignSelf(ItemAlign.End)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    } else {
      Column() {
        Row({ space: 8 }) {
          Column({ space: 2 }) {
            Text(t('Aside'))
              .fontSize(type.small.fontSize)
              .lineHeight(type.small.lineHeight)
              .fontColor(this.p().ink3)
            if ((this.card.question ?? '') !== '') {
              Text(this.card.question ?? '')
                .fontSize(type.settingsRow.fontSize)
                .lineHeight(type.settingsRow.lineHeight)
                .fontWeight('600')
                .fontColor(this.p().ink)
            }
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          Text('×')
            .fontSize(18)
            .fontColor(this.p().ink3)
            .width(36)
            .height(36)
            .textAlign(TextAlign.Center)
            .onClick((): void => this.drop())
            .opacity(this.busy ? 0.35 : 1)
        }
        .alignItems(VerticalAlign.Top)
        this.texts(6)
      }
      .width('calc(100% - 24vp)')
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(radius.card)
      .border({ width: this.hairline(), color: this.p().line })
      .backgroundColor(this.p().card)
      .padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .shadow(shadowOf(1))
    }
  }

  @Builder
  texts(top: number) {
    if ((this.card.failure ?? '') !== '') {
      Text(this.card.failure ?? '')
        .fontSize(type.small.fontSize)
        .lineHeight(type.small.lineHeight)
        .fontColor(this.p().danger)
        .margin({ top: top })
    }
    if ((this.card.answer ?? '') !== '') {
      Text(this.card.answer ?? '')
        .fontSize(type.settingsRow.fontSize)
        .lineHeight(type.settingsRow.lineHeight)
        .fontColor(this.p().ink2)
        .margin({ top: top })
    }
  }
}

// The browser handoff: the Bot gave this phone the page. Skip hands it back
// untouched, Done confirms the work, Card opens the browser view.
@ComponentV2
export struct HandoffCard {
  @Require @Param handoff: HandoffData
  @Require @Param botId: string
  @Param canView: boolean = false
  @Event onView: () => void = (): void => {}
  @Param bare: boolean = false
  @Local busy: boolean = false

  private p(): Palette {
    return appStore.theme.p
  }

  private hairline(): number {
    return this.getUIContext().px2vp(1)
  }

  private answer(outcome: string): void {
    if (this.busy) return
    this.busy = true
    const controller = appStore.link.controller
    if (controller === null) {
      this.busy = false
      return
    }
    const payload: Record<string, Object> = {
      'botId': this.botId,
      'outcome': outcome,
      'callId': this.handoff.callId,
    }
    void controller.call('browser-give-back', payload).catch((): void => {}).then((): void => {
      this.busy = false
    })
  }

  build() {
    if (this.bare) {
      Column() {
        this.cardBody()
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    } else {
      Column() {
        Text(t('Browser handoff'))
          .fontSize(type.settingsRow.fontSize)
          .lineHeight(type.settingsRow.lineHeight)
          .fontWeight('600')
          .fontColor(this.p().ink)
        this.cardBody()
      }
      .width('calc(100% - 24vp)')
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(radius.card)
      .border({ width: this.hairline(), color: this.p().line })
      .backgroundColor(this.p().card)
      .padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .shadow(shadowOf(1))
    }
  }

  @Builder
  cardBody() {
    if ((this.handoff.note ?? this.handoff.reason ?? '') !== '') {
      Text(this.handoff.note ?? this.handoff.reason ?? '')
        .fontSize(type.small.fontSize)
        .lineHeight(type.small.lineHeight)
        .fontColor(this.p().ink2)
        .margin({ top: 4 })
    }
    Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
      if (this.canView) {
        Text(t('Card'))
          .fontSize(14)
          .fontColor(this.p().ink)
          .backgroundColor(this.p().hover)
          .borderRadius(radius.pill)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .constraintSize({ minHeight: 44, minWidth: 104 })
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .margin({ right: 8 })
          .onClick((): void => this.onView())
      }
      Text(t('Skip'))
        .fontSize(14)
        .fontColor(this.p().ink)
        .backgroundColor(this.p().hover)
        .borderRadius(radius.pill)
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .constraintSize({ minHeight: 44, minWidth: 104 })
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .opacity(this.busy ? 0.35 : 1)
        .margin({ right: 8 })
        .onClick((): void => this.answer('skip'))
      Text(t('Done'))
        .fontSize(14)
        .fontWeight('600')
        .fontColor(this.p().accentInk)
        .backgroundColor(this.p().accent)
        .borderRadius(radius.pill)
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .constraintSize({ minHeight: 44, minWidth: 104 })
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .opacity(this.busy ? 0.35 : 1)
        .onClick((): void => this.answer('done'))
    }
    .margin({ top: 12 })
  }
}

// "X is doing…" while a Bot works: a small working avatar and a text that
// breathes between two opacities.
@ComponentV2
export struct ActionRow {
  @Require @Param bot: Bot
  @Require @Param doing: string
  @Local shine: boolean = false

  private p(): Palette {
    return appStore.theme.p
  }

  aboutToAppear(): void {
    this.getUIContext().animateTo(
      { duration: 900, iterations: -1, curve: Curve.EaseInOut, playMode: PlayMode.Alternate },
      (): void => {
        this.shine = true
      },
    )
  }

  build() {
    Row({ space: 8 }) {
      Avatar({ bot: this.bot, dark: appStore.theme.dark, markSize: 28, ring: this.p().main, working: true })
      Text(`${this.doing}…`)
        .fontSize(type.rowPreview.fontSize)
        .lineHeight(type.rowPreview.lineHeight)
        .fontColor(this.p().ink2)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .opacity(this.shine ? 1 : 0.35)
    }
    .height(36)
    .margin({ left: 12, right: 12 })
    .alignItems(VerticalAlign.Center)
  }
}
