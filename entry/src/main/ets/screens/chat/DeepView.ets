// A deep view card: the blueprint the computer sent, rendered in the fixed
// format (common/deepview/views-core parses and validates; formula.ts works out
// `{ "=": "…" }` values). No script runs and nothing loads from the network —
// html and sources nodes only ever show text. Rendering is capped: layouts
// nest at most MAX_DEPTH deep, a node holds at most MAX_CHILDREN children, and
// one text node renders at most MAX_TEXT_CHARS of markdown.
//
// A node's value is either a literal or a formula resolved against the view's
// inputs and `let`s; a formula that fails under the current values shows the
// ellipsis placeholder only where it sits. The answer names the component that
// sent it (checkAnswer → validateViewAnswer); the card's inputs ride along so
// the Bot sees what the slider or choice was set to. All dynamic values reach
// this file through common/deepview/view-bridge as `Object` (never `unknown`).

import { common } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'

import type { ViewNode } from '../../common/deepview/views-core'
import type { AnswerCheck } from '../../common/deepview/view-bridge'
import {
  initialInputs, checkAnswer, hasField, fieldOf, nodeString, nodeNumber, nodeIsTrue, nodeList,
  nodeNumberList, asNode, asObjectArray, choiceOf, resolveObj, resolveString, resolveShow,
  resolveNumber, resolveArray, resolveNodes,
} from '../../common/deepview/view-bridge'
import { show } from '../../common/deepview/formula'
import { t } from '../../common/ui/i18n'
import { appStore, INKS, radius, type } from '../../components/Theme'
import { copyToClipboard, hapticSuccess } from '../../platform/Platform'
import { MarkdownText, openExternalUrl } from './MarkdownText'

// Caps: layout nesting, children per layout node, one text node's markdown.
const MAX_DEPTH: number = 8
const MAX_CHILDREN: number = 100
const MAX_TEXT_CHARS: number = 4000

const EMPTY_VALUES: Record<string, Object> = {}

function capText(text: string): string {
  return text.length > MAX_TEXT_CHARS ? `${text.slice(0, MAX_TEXT_CHARS)}…` : text
}

@ComponentV2
export struct DeepView {
  @Require @Param sessionId: string
  @Param viewId: string = ''
  @Param title: string = ''
  @Require @Param root: ViewNode
  @Param readOnly: boolean = false
  @Param bare: boolean = false

  @Local inputs: Map<string, Object> = new Map<string, Object>()
  @Local done: string | null = null
  @Local failed: string | null = null

  aboutToAppear(): void {
    this.inputs = initialInputs(this.root)
  }

  setInput(id: string, value: Object): void {
    const next: Map<string, Object> = new Map<string, Object>(this.inputs)
    next.set(id, value)
    this.inputs = next
  }

  answer(component: string, values: Record<string, Object>): void {
    if (this.readOnly || this.done !== null) return
    const controller = appStore.link.controller
    if (controller === null) {
      this.failed = t('Not connected to the computer yet.')
      return
    }
    const checked: AnswerCheck = checkAnswer(this.root, component, values)
    const problem: string | undefined = checked.error
    if (problem !== undefined) {
      this.failed = problem
      return
    }
    // The checked answer plus the card's inputs, so the Bot sees what the
    // slider or choice was set to (validateViewAnswer reads `inputs` back).
    const sent: Record<string, Object> = {}
    const answer: Record<string, Object> = checked.answer ?? EMPTY_VALUES
    for (const key of Object.keys(answer)) sent[key] = answer[key]
    if (this.inputs.size > 0) {
      const inputs: Record<string, Object> = {}
      this.inputs.forEach((value: Object, key: string): void => {
        inputs[key] = value
      })
      sent['inputs'] = inputs
    }
    const payload: Record<string, Object> = {
      'sessionId': this.sessionId,
      'viewId': this.viewId,
      'action': component,
      'values': sent,
    }
    this.failed = null
    void controller.call('view-reply', payload).then((): void => {
      void hapticSuccess()
      this.done = component
    }).catch((failure: BusinessError): void => {
      this.failed = failure.message ?? String(failure)
    })
  }

  dismissView(): void {
    const controller = appStore.link.controller
    if (controller === null) return
    const payload: Record<string, Object> = { 'sessionId': this.sessionId }
    void controller.call('dismiss-view', payload).catch((): void => {})
  }

  @Builder
  content() {
    if (this.title !== '' && !this.bare) {
      Text(this.title)
        .fontSize(type.settingsRow.fontSize)
        .lineHeight(type.settingsRow.lineHeight)
        .fontWeight('600')
        .fontColor(appStore.theme.p.ink)
    }
    NodeView({
      node: this.root,
      root: this.root,
      inputs: this.inputs,
      depth: 0,
      readOnly: this.readOnly || this.done !== null,
      onInput: (id: string, value: Object): void => {
        this.setInput(id, value)
      },
      onAnswer: (component: string, values: Record<string, Object>): void => {
        this.answer(component, values)
      },
    })
    if (this.done === null && !this.readOnly) {
      Text(t('Dismiss'))
        .fontSize(type.caption.fontSize)
        .lineHeight(type.caption.lineHeight)
        .fontColor(appStore.theme.p.ink3)
        .padding({ top: 4, bottom: 4 })
        .onClick(() => {
          this.dismissView()
        })
    }
    if (this.failed !== null) {
      Text(this.failed)
        .fontSize(type.caption.fontSize)
        .lineHeight(type.caption.lineHeight)
        .fontColor(appStore.theme.p.danger)
        .margin({ top: 4 })
    }
    if (this.done !== null) {
      Text(t('Done'))
        .fontSize(type.caption.fontSize)
        .lineHeight(type.caption.lineHeight)
        .fontColor(appStore.theme.p.green)
        .margin({ top: 4 })
    }
  }

  build() {
    if (this.bare) {
      Column({ space: 10 }) {
        this.content()
      }
      .alignItems(HorizontalAlign.Start)
    } else {
      Column({ space: 10 }) {
        this.content()
      }
      .backgroundColor(appStore.theme.p.card)
      .borderRadius(radius.card)
      .border({ width: 1, color: appStore.theme.p.line })
      .padding(14)
      .margin({ top: 4, bottom: 4 })
      .alignItems(HorizontalAlign.Start)
    }
  }
}

@ComponentV2
struct NodeView {
  @Require @Param node: ViewNode
  @Require @Param root: ViewNode
  @Require @Param inputs: Map<string, Object>
  @Param depth: number = 0
  @Param readOnly: boolean = false
  @Event onInput: (id: string, value: Object) => void = (_id: string, _value: Object): void => {}
  @Event onAnswer: (component: string, values: Record<string, Object>) => void =
    (_component: string, _values: Record<string, Object>): void => {}

  typeOf(): string {
    if (this.depth >= MAX_DEPTH) return ''
    return nodeString(this.node, 'type') ?? ''
  }

  children(): ViewNode[] {
    return nodeList(this.node, 'children').slice(0, MAX_CHILDREN)
  }

  optionList(): ViewNode[] {
    return nodeList(this.node, 'options')
  }

  inputId(): string {
    return nodeString(this.node, 'id') ?? ''
  }

  textOf(): string | null {
    const text: string | null = resolveString(this.root, this.inputs, fieldOf(this.node, 'text'))
    return text === null ? null : capText(text)
  }

  metricValue(): Object | null {
    return resolveObj(this.root, this.inputs, fieldOf(this.node, 'value'))
  }

  metricLabel(): string {
    return resolveString(this.root, this.inputs, fieldOf(this.node, 'label')) ?? ''
  }

  hasCaption(): boolean {
    return hasField(this.node, 'caption')
  }

  metricCaption(): string {
    return resolveString(this.root, this.inputs, fieldOf(this.node, 'caption')) ?? ''
  }

  hasTable(): boolean {
    const columns: Object[] | null = resolveArray(this.root, this.inputs, fieldOf(this.node, 'columns'))
    const rows: Object[] | null = resolveArray(this.root, this.inputs, fieldOf(this.node, 'rows'))
    return columns !== null && rows !== null
  }

  tableColumns(): string[] {
    const raw: Object[] | null = resolveArray(this.root, this.inputs, fieldOf(this.node, 'columns'))
    if (raw === null) return []
    const out: string[] = []
    for (const entry of raw) {
      const column: ViewNode | null = asNode(entry)
      if (column !== null) {
        const label: string | null = resolveString(this.root, this.inputs, fieldOf(column, 'label'))
        const key: string | null = nodeString(column, 'key')
        if (label !== null) out.push(label)
        else if (key !== null) out.push(key)
        else out.push('')
      } else {
        out.push(String(entry))
      }
    }
    return out
  }

  tableRows(): string[][] {
    const raw: Object[] | null = resolveArray(this.root, this.inputs, fieldOf(this.node, 'rows'))
    if (raw === null) return []
    const out: string[][] = []
    for (const rowEntry of raw) {
      const row: Object[] | null = asObjectArray(rowEntry)
      if (row === null) {
        out.push([])
        continue
      }
      const cells: string[] = []
      for (const cell of row) {
        cells.push(resolveShow(this.root, this.inputs, cell) ?? '…')
      }
      out.push(cells)
    }
    return out
  }

  hasChart(): boolean {
    const categories: Object[] | null = resolveArray(this.root, this.inputs, fieldOf(this.node, 'categories'))
    const series: Object[] | null = resolveArray(this.root, this.inputs, fieldOf(this.node, 'series'))
    return categories !== null && series !== null
  }

  progressLabel(): string {
    return resolveString(this.root, this.inputs, fieldOf(this.node, 'label')) ?? ''
  }

  pct(): number {
    const percent: number = resolveNumber(this.root, this.inputs, fieldOf(this.node, 'percent'), Number.NaN)
    if (Number.isFinite(percent)) return percent
    const value: number = resolveNumber(this.root, this.inputs, fieldOf(this.node, 'value'), 0)
    const max: number = resolveNumber(this.root, this.inputs, fieldOf(this.node, 'max'), 1)
    const m: number = max > 0 ? max : 1
    return value / m * 100
  }

  valueLabelText(): string {
    const label: string | null = resolveString(this.root, this.inputs, fieldOf(this.node, 'valueLabel'))
    if (label !== null) return label
    return `${Math.round(this.pct())}%`
  }

  calloutTone(): string {
    const p = appStore.theme.p
    const key: string = nodeString(this.node, 'tone') ?? 'info'
    if (key === 'good') return p.green
    if (key === 'warn') return p.star
    if (key === 'bad') return p.danger
    return p.accent
  }

  calloutText(): string {
    return capText(resolveString(this.root, this.inputs, fieldOf(this.node, 'text')) ?? '')
  }

  sourcesItems(): ViewNode[] {
    return resolveNodes(this.root, this.inputs, fieldOf(this.node, 'items'))
  }

  sourceHref(item: ViewNode): string {
    return nodeString(item, 'url') ?? ''
  }

  sourceLabel(item: ViewNode): string {
    const label: string | null = nodeString(item, 'label')
    if (label !== null) return label
    const title: string | null = nodeString(item, 'title')
    if (title !== null) return title
    return this.sourceHref(item)
  }

  openSource(item: ViewNode): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    openExternalUrl(context, this.sourceHref(item))
  }

  htmlSummary(): string | null {
    if (!hasField(this.node, 'summary')) return null
    const summary: string | null = resolveString(this.root, this.inputs, fieldOf(this.node, 'summary'))
    return summary === null ? null : capText(summary)
  }

  sliderLabel(): string {
    return resolveString(this.root, this.inputs, fieldOf(this.node, 'label')) ?? ''
  }

  sliderMin(): number {
    return nodeNumber(this.node, 'min', 0)
  }

  sliderMax(): number {
    return nodeNumber(this.node, 'max', 100)
  }

  sliderStep(): number {
    const value: number = nodeNumber(this.node, 'step', 1)
    return value > 0 ? value : 1
  }

  sliderValue(): number {
    const current: Object | undefined = this.inputs.get(this.inputId())
    if (current !== undefined && Number.isFinite(Number(current))) {
      return Math.min(this.sliderMax(), Math.max(this.sliderMin(), Number(current)))
    }
    const raw: number = nodeNumber(this.node, 'value', Number.NaN)
    if (Number.isFinite(raw)) {
      return Math.min(this.sliderMax(), Math.max(this.sliderMin(), raw))
    }
    return this.sliderMin()
  }

  sliderUnit(): string {
    const unit: string | null = resolveString(this.root, this.inputs, fieldOf(this.node, 'unit'))
    return unit === null ? '' : ` ${unit}`
  }

  numberLabel(): string {
    return resolveString(this.root, this.inputs, fieldOf(this.node, 'label')) ?? ''
  }

  numberMin(): number {
    return nodeNumber(this.node, 'min', -Infinity)
  }

  numberMax(): number {
    return nodeNumber(this.node, 'max', Infinity)
  }

  numberStep(): number {
    const value: number = nodeNumber(this.node, 'step', 1)
    return value > 0 ? value : 1
  }

  numberValue(): number {
    const current: Object | undefined = this.inputs.get(this.inputId())
    if (current !== undefined && Number.isFinite(Number(current))) return Number(current)
    return nodeNumber(this.node, 'value', 0)
  }

  numberUnit(): string {
    const unit: string | null = resolveString(this.root, this.inputs, fieldOf(this.node, 'unit'))
    return unit === null ? '' : ` ${unit}`
  }

  bumpNumber(direction: number): void {
    if (this.readOnly) return
    const next: number = Math.min(this.numberMax(), Math.max(this.numberMin(),
      this.numberValue() + direction * this.numberStep()))
    this.onInput(this.inputId(), next)
  }

  choiceLabel(): string {
    return resolveString(this.root, this.inputs, fieldOf(this.node, 'label')) ?? ''
  }

  choiceCurrent(): Object | null {
    const current: Object | undefined = this.inputs.get(this.inputId())
    if (current !== undefined) return current
    return fieldOf(this.node, 'value')
  }

  optionText(option: ViewNode): string {
    return String(choiceOf(option))
  }

  choiceOn(option: ViewNode): boolean {
    return this.optionText(option) === String(this.choiceCurrent())
  }

  choiceShort(): boolean {
    return this.optionList().every((option: ViewNode): boolean => this.optionText(option).length <= 12)
  }

  toggleLabel(): string {
    return resolveString(this.root, this.inputs, fieldOf(this.node, 'label')) ?? ''
  }

  toggleOn(): boolean {
    const current: Object | undefined = this.inputs.get(this.inputId())
    if (current !== undefined) return Boolean(current)
    return nodeIsTrue(this.node, 'value')
  }

  confirmCancelLabel(): string {
    if (!hasField(this.node, 'cancelLabel')) return t('Cancel')
    return resolveString(this.root, this.inputs, fieldOf(this.node, 'cancelLabel')) ?? t('Cancel')
  }

  confirmConfirmLabel(): string {
    if (!hasField(this.node, 'confirmLabel')) return t('Confirm')
    return resolveString(this.root, this.inputs, fieldOf(this.node, 'confirmLabel')) ?? t('Confirm')
  }

  submitLabel(): string {
    if (!hasField(this.node, 'label')) return t('Submit')
    return resolveString(this.root, this.inputs, fieldOf(this.node, 'label')) ?? t('Submit')
  }

  @Builder
  placeholder() {
    Text('…')
      .fontSize(type.caption.fontSize)
      .lineHeight(type.caption.lineHeight)
      .fontColor(appStore.theme.p.ink3)
      .fontStyle(FontStyle.Italic)
  }

  build() {
    if (this.typeOf() === 'stack') {
      Column({ space: 10 }) {
        ForEach(this.children(), (child: ViewNode, index: number) => {
          NodeView({
            node: child,
            root: this.root,
            inputs: this.inputs,
            depth: this.depth + 1,
            readOnly: this.readOnly,
            onInput: this.onInput,
            onAnswer: this.onAnswer,
          })
        }, (child: ViewNode, index: number): string => `s${this.depth}-${index}`)
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    } else if (this.typeOf() === 'row') {
      Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
        ForEach(this.children(), (child: ViewNode, index: number) => {
          Column() {
            NodeView({
              node: child,
              root: this.root,
              inputs: this.inputs,
              depth: this.depth + 1,
              readOnly: this.readOnly,
              onInput: this.onInput,
              onAnswer: this.onAnswer,
            })
          }
          .constraintSize({ minWidth: 0 })
          .flexBasis(220)
          .flexGrow(1)
          .margin({ right: 10, bottom: 10 })
          .alignItems(HorizontalAlign.Start)
        }, (child: ViewNode, index: number): string => `w${this.depth}-${index}`)
      }
      .width('100%')
    } else if (this.typeOf() === 'text') {
      if (this.textOf() === null) {
        this.placeholder()
      } else {
        MarkdownText({
          text: this.textOf() ?? '',
          textColor: nodeString(this.node, 'tone') === 'muted' ? appStore.theme.p.ink2 : appStore.theme.p.ink,
        })
      }
    } else if (this.typeOf() === 'metric') {
      if (this.metricValue() === null) {
        this.placeholder()
      } else {
        Column() {
          Text(this.metricLabel())
            .fontSize(type.caption.fontSize)
            .lineHeight(type.caption.lineHeight)
            .fontColor(appStore.theme.p.ink3)
          Text(show(this.metricValue() ?? ''))
            .fontSize(type.largeTitle.fontSize)
            .lineHeight(type.largeTitle.lineHeight)
            .fontWeight(type.largeTitle.fontWeight)
            .fontColor(appStore.theme.p.ink)
          if (this.hasCaption()) {
            Text(this.metricCaption())
              .fontSize(type.caption.fontSize)
              .lineHeight(type.caption.lineHeight)
              .fontColor(appStore.theme.p.ink2)
          }
        }
        .alignItems(HorizontalAlign.Start)
      }
    } else if (this.typeOf() === 'table') {
      if (this.hasTable()) {
        DataTableView({ columns: this.tableColumns(), rows: this.tableRows() })
      } else {
        this.placeholder()
      }
    } else if (this.typeOf() === 'chart') {
      if (this.hasChart()) {
        ChartView({ node: this.node, root: this.root, inputs: this.inputs })
      } else {
        this.placeholder()
      }
    } else if (this.typeOf() === 'progress') {
      Column({ space: 4 }) {
        Row({ space: 8 }) {
          Text(this.progressLabel())
            .fontSize(type.caption.fontSize)
            .lineHeight(type.caption.lineHeight)
            .fontColor(appStore.theme.p.ink2)
            .layoutWeight(1)
          Text(this.valueLabelText())
            .fontSize(type.caption.fontSize)
            .lineHeight(type.caption.lineHeight)
            .fontColor(appStore.theme.p.ink3)
        }
        .alignItems(VerticalAlign.Top)
        .width('100%')
        Column() {
          Column() {
          }
          .width(`${Math.min(100, Math.max(0, this.pct()))}%`)
          .height('100%')
          .borderRadius(3)
          .backgroundColor(appStore.theme.p.accent)
        }
        .width('100%')
        .height(6)
        .borderRadius(3)
        .backgroundColor(appStore.theme.p.hover)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    } else if (this.typeOf() === 'callout') {
      Column() {
        MarkdownText({
          text: this.calloutText(),
          textColor: appStore.theme.p.ink,
        })
      }
      .backgroundColor(appStore.theme.p.hover)
      .borderRadius(radius.item)
      .padding(8)
      .border({ width: { left: 3 }, color: this.calloutTone() })
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    } else if (this.typeOf() === 'sources') {
      Column({ space: 4 }) {
        ForEach(this.sourcesItems(), (item: ViewNode, index: number) => {
          if (/^https?:/i.test(this.sourceHref(item))) {
            Text(this.sourceLabel(item))
              .fontSize(type.caption.fontSize)
              .lineHeight(type.caption.lineHeight)
              .fontColor(appStore.theme.p.accent)
              .onClick(() => {
                this.openSource(item)
              })
          }
        }, (item: ViewNode, index: number): string => `src-${index}`)
      }
      .alignItems(HorizontalAlign.Start)
    } else if (this.typeOf() === 'html') {
      Column({ space: 4 }) {
        if (this.htmlSummary() !== null) {
          MarkdownText({
            text: this.htmlSummary() ?? '',
            textColor: appStore.theme.p.ink2,
          })
        }
        Text(t('Open it on the computer'))
          .fontSize(type.caption.fontSize)
          .lineHeight(type.caption.lineHeight)
          .fontColor(appStore.theme.p.ink3)
      }
      .alignItems(HorizontalAlign.Start)
    } else if (this.typeOf() === 'slider') {
      Column({ space: 2 }) {
        Row({ space: 8 }) {
          Text(this.sliderLabel())
            .fontSize(type.caption.fontSize)
            .lineHeight(type.caption.lineHeight)
            .fontColor(appStore.theme.p.ink2)
            .layoutWeight(1)
          Text(`${this.sliderValue()}${this.sliderUnit()}`)
            .fontSize(type.caption.fontSize)
            .lineHeight(type.caption.lineHeight)
            .fontColor(appStore.theme.p.ink)
        }
        .alignItems(VerticalAlign.Top)
        .width('100%')
        Slider({
          value: this.sliderValue(),
          min: this.sliderMin(),
          max: this.sliderMax(),
          step: this.sliderStep(),
        })
          .selectedColor(appStore.theme.p.accent)
          .trackColor(appStore.theme.p.hover)
          .blockColor(appStore.theme.p.accent)
          .enabled(!this.readOnly)
          .onChange((value: number, mode: SliderChangeMode) => {
            if (this.readOnly) return
            const snapped: number = Math.min(this.sliderMax(), Math.max(this.sliderMin(),
              Math.round(value / this.sliderStep()) * this.sliderStep()))
            this.onInput(this.inputId(), snapped)
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    } else if (this.typeOf() === 'number') {
      Row({ space: 10 }) {
        Text(this.numberLabel())
          .fontSize(type.caption.fontSize)
          .lineHeight(type.caption.lineHeight)
          .fontColor(appStore.theme.p.ink2)
          .layoutWeight(1)
        Row({ space: 10 }) {
          Column() {
            Text('−')
              .fontSize(16)
              .fontColor(appStore.theme.p.ink)
          }
          .width(32)
          .height(32)
          .borderRadius(16)
          .border({ width: 1, color: appStore.theme.p.line })
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .onClick(() => {
            this.bumpNumber(-1)
          })
          Text(`${this.numberValue()}${this.numberUnit()}`)
            .fontSize(type.settingsRow.fontSize)
            .lineHeight(type.settingsRow.lineHeight)
            .fontColor(appStore.theme.p.ink)
            .constraintSize({ minWidth: 36 })
            .textAlign(TextAlign.Center)
          Column() {
            Text('+')
              .fontSize(16)
              .fontColor(appStore.theme.p.ink)
          }
          .width(32)
          .height(32)
          .borderRadius(16)
          .border({ width: 1, color: appStore.theme.p.line })
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .onClick(() => {
            this.bumpNumber(1)
          })
        }
        .alignItems(VerticalAlign.Center)
      }
      .alignItems(VerticalAlign.Center)
      .width('100%')
    } else if (this.typeOf() === 'choice') {
      Column({ space: 4 }) {
        if (this.choiceLabel() !== '') {
          Text(this.choiceLabel())
            .fontSize(type.caption.fontSize)
            .lineHeight(type.caption.lineHeight)
            .fontColor(appStore.theme.p.ink2)
        }
        if (this.choiceShort() && this.optionList().length <= 4) {
          Row({ space: 4 }) {
            ForEach(this.optionList(), (option: ViewNode, index: number) => {
              Row() {
                Text(this.optionText(option))
                  .fontSize(type.caption.fontSize)
                  .lineHeight(type.caption.lineHeight)
                  .fontColor(this.choiceOn(option) ? appStore.theme.p.accent : appStore.theme.p.ink2)
                  .textAlign(TextAlign.Center)
                  .layoutWeight(1)
              }
              .layoutWeight(1)
              .borderRadius(radius.input)
              .padding({ left: 10, right: 10, top: 7, bottom: 7 })
              .border({ width: 1, color: this.choiceOn(option) ? appStore.theme.p.accent : appStore.theme.p.line })
              .backgroundColor(this.choiceOn(option) ? appStore.theme.p.hover : Color.Transparent)
              .onClick(() => {
                if (this.readOnly) return
                const picked: Object | null = choiceOf(option)
                if (picked !== null) this.onInput(this.inputId(), picked)
              })
            }, (option: ViewNode, index: number): string => `ch-${index}`)
          }
          .width('100%')
        } else {
          Column({ space: 4 }) {
            ForEach(this.optionList(), (option: ViewNode, index: number) => {
              Row() {
                Text(this.optionText(option))
                  .fontSize(type.caption.fontSize)
                  .lineHeight(type.caption.lineHeight)
                  .fontColor(this.choiceOn(option) ? appStore.theme.p.accent : appStore.theme.p.ink2)
                  .textAlign(TextAlign.Center)
                  .layoutWeight(1)
              }
              .width('100%')
              .borderRadius(radius.input)
              .padding({ left: 10, right: 10, top: 7, bottom: 7 })
              .border({ width: 1, color: this.choiceOn(option) ? appStore.theme.p.accent : appStore.theme.p.line })
              .backgroundColor(this.choiceOn(option) ? appStore.theme.p.hover : Color.Transparent)
              .onClick(() => {
                if (this.readOnly) return
                const picked: Object | null = choiceOf(option)
                if (picked !== null) this.onInput(this.inputId(), picked)
              })
            }, (option: ViewNode, index: number): string => `cv-${index}`)
          }
          .width('100%')
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    } else if (this.typeOf() === 'toggle') {
      Row({ space: 10 }) {
        Text(this.toggleLabel())
          .fontSize(type.caption.fontSize)
          .lineHeight(type.caption.lineHeight)
          .fontColor(appStore.theme.p.ink2)
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.toggleOn() })
          .selectedColor(appStore.theme.p.accent)
          .switchPointColor(appStore.theme.p.knob)
          .switchStyle({ unselectedColor: appStore.theme.p.line2, pointColor: appStore.theme.p.knob })
          .enabled(!this.readOnly)
          .onChange((isOn: boolean) => {
            if (!this.readOnly) this.onInput(this.inputId(), isOn)
          })
      }
      .alignItems(VerticalAlign.Center)
      .width('100%')
    } else if (this.typeOf() === 'options') {
      OptionsView({
        options: this.optionList(),
        componentId: this.inputId(),
        multi: nodeIsTrue(this.node, 'multi'),
        readOnly: this.readOnly,
        onAnswer: this.onAnswer,
      })
    } else if (this.typeOf() === 'confirm') {
      Row({ space: 8 }) {
        Row() {
          Text(this.confirmCancelLabel())
            .fontSize(type.settingsRow.fontSize)
            .lineHeight(type.settingsRow.lineHeight)
            .fontColor(appStore.theme.p.ink2)
        }
        .layoutWeight(1)
        .constraintSize({ minWidth: 110 })
        .height(42)
        .borderRadius(radius.pill)
        .backgroundColor(appStore.theme.p.hover)
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          if (!this.readOnly) this.onAnswer(this.inputId(), { 'confirmed': false })
        })
        Row() {
          Text(this.confirmConfirmLabel())
            .fontSize(type.settingsRow.fontSize)
            .lineHeight(type.settingsRow.lineHeight)
            .fontWeight('600')
            .fontColor(appStore.theme.p.accentInk)
        }
        .layoutWeight(1)
        .constraintSize({ minWidth: 110 })
        .height(42)
        .borderRadius(radius.pill)
        .backgroundColor(appStore.theme.p.accent)
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          if (!this.readOnly) this.onAnswer(this.inputId(), { 'confirmed': true })
        })
      }
      .margin({ top: 4 })
      .width('100%')
    } else if (this.typeOf() === 'form') {
      FormView({
        node: this.node,
        root: this.root,
        inputs: this.inputs,
        componentId: this.inputId(),
        readOnly: this.readOnly,
        onAnswer: this.onAnswer,
      })
    } else if (this.typeOf() === 'submit') {
      Row() {
        Text(this.submitLabel())
          .fontSize(type.settingsRow.fontSize)
          .lineHeight(type.settingsRow.lineHeight)
          .fontColor(appStore.theme.p.accentInk)
      }
      .width('100%')
      .height(42)
      .borderRadius(radius.pill)
      .backgroundColor(appStore.theme.p.accent)
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
      .margin({ top: 4 })
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        if (!this.readOnly) this.onAnswer(this.inputId(), EMPTY_VALUES)
      })
    }
  }
}

@ComponentV2
struct OptionsView {
  @Require @Param options: ViewNode[]
  @Require @Param componentId: string
  @Param multi: boolean = false
  @Param readOnly: boolean = false
  @Event onAnswer: (component: string, values: Record<string, Object>) => void =
    (_component: string, _values: Record<string, Object>): void => {}

  @Local picked: Set<string> = new Set<string>()

  optionLabel(option: ViewNode): string {
    return String(choiceOf(option))
  }

  toggle(value: string): void {
    const next: Set<string> = new Set<string>(this.picked)
    if (this.multi) {
      if (next.has(value)) next.delete(value)
      else next.add(value)
    } else {
      next.clear()
      next.add(value)
    }
    this.picked = next
  }

  submit(): void {
    const selected: string[] = []
    this.picked.forEach((value: string): void => {
      selected.push(value)
    })
    this.onAnswer(this.componentId, { 'selected': selected })
  }

  build() {
    Column({ space: 6 }) {
      ForEach(this.options, (option: ViewNode, index: number) => {
        Row() {
          Text(this.optionLabel(option))
            .fontSize(type.settingsRow.fontSize)
            .lineHeight(type.settingsRow.lineHeight)
            .fontColor(appStore.theme.p.ink)
        }
        .width('100%')
        .borderRadius(radius.option)
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .border({
          width: 1,
          color: this.picked.has(this.optionLabel(option)) ? appStore.theme.p.accent : appStore.theme.p.line,
        })
        .backgroundColor(this.picked.has(this.optionLabel(option)) ? appStore.theme.p.hover : Color.Transparent)
        .onClick(() => {
          if (this.readOnly) return
          if (this.multi) this.toggle(this.optionLabel(option))
          else this.onAnswer(this.componentId, { 'selected': [this.optionLabel(option)] })
        })
      }, (option: ViewNode, index: number): string => `o-${index}`)
      if (this.multi) {
        Row() {
          Text(t('Submit'))
            .fontSize(type.settingsRow.fontSize)
            .lineHeight(type.settingsRow.lineHeight)
            .fontColor(this.picked.size === 0 ? appStore.theme.p.ink3 : appStore.theme.p.accentInk)
        }
        .width('100%')
        .height(42)
        .borderRadius(radius.pill)
        .backgroundColor(this.picked.size === 0 ? appStore.theme.p.hover : appStore.theme.p.accent)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          if (this.readOnly || this.picked.size === 0) return
          this.submit()
        })
      }
    }
    .margin({ top: 4 })
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }
}

@ComponentV2
struct FormView {
  @Require @Param node: ViewNode
  @Require @Param root: ViewNode
  @Require @Param inputs: Map<string, Object>
  @Require @Param componentId: string
  @Param readOnly: boolean = false
  @Event onAnswer: (component: string, values: Record<string, Object>) => void =
    (_component: string, _values: Record<string, Object>): void => {}

  @Local values: Record<string, string> = {}

  fieldList(): ViewNode[] {
    return nodeList(this.node, 'fields')
  }

  fieldId(field: ViewNode, index: number): string {
    return nodeString(field, 'id') ?? `${index}`
  }

  fieldLabel(field: ViewNode): string {
    return resolveString(this.root, this.inputs, fieldOf(field, 'label')) ?? ''
  }

  fieldPlaceholder(field: ViewNode): string {
    return resolveString(this.root, this.inputs, fieldOf(field, 'placeholder')) ?? ''
  }

  submitLabel(): string {
    if (!hasField(this.node, 'submitLabel')) return t('Submit')
    return resolveString(this.root, this.inputs, fieldOf(this.node, 'submitLabel')) ?? t('Submit')
  }

  setValue(key: string, value: string): void {
    const next: Record<string, string> = {}
    for (const k of Object.keys(this.values)) {
      next[k] = this.values[k]
    }
    next[key] = value
    this.values = next
  }

  build() {
    Column({ space: 8 }) {
      ForEach(this.fieldList(), (field: ViewNode, index: number) => {
        Column({ space: 4 }) {
          if (this.fieldLabel(field) !== '') {
            Text(this.fieldLabel(field))
              .fontSize(type.caption.fontSize)
              .lineHeight(type.caption.lineHeight)
              .fontColor(appStore.theme.p.ink2)
          }
          if (nodeString(field, 'kind') === 'multiline') {
            TextArea({ text: this.values[this.fieldId(field, index)] ?? '', placeholder: this.fieldPlaceholder(field) })
              .fontSize(15)
              .fontColor(appStore.theme.p.ink)
              .constraintSize({ minHeight: 72 })
              .backgroundColor(appStore.theme.p.hover)
              .borderRadius(radius.input)
              .padding({ left: 10, right: 10, top: 8, bottom: 8 })
              .placeholderColor(appStore.theme.p.ink3)
              .enabled(!this.readOnly)
              .onChange((value: string) => {
                this.setValue(this.fieldId(field, index), value)
              })
          } else {
            TextInput({ text: this.values[this.fieldId(field, index)] ?? '', placeholder: this.fieldPlaceholder(field) })
              .fontSize(15)
              .fontColor(appStore.theme.p.ink)
              .height(40)
              .backgroundColor(appStore.theme.p.hover)
              .borderRadius(radius.input)
              .padding({ left: 10, right: 10 })
              .placeholderColor(appStore.theme.p.ink3)
              .enabled(!this.readOnly)
              .onChange((value: string) => {
                this.setValue(this.fieldId(field, index), value)
              })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
      }, (field: ViewNode, index: number): string => `f-${index}`)
      Row() {
        Text(this.submitLabel())
          .fontSize(type.settingsRow.fontSize)
          .lineHeight(type.settingsRow.lineHeight)
          .fontColor(appStore.theme.p.accentInk)
      }
      .width('100%')
      .height(42)
      .borderRadius(radius.pill)
      .backgroundColor(appStore.theme.p.accent)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        if (!this.readOnly) {
          this.onAnswer(this.componentId, { 'fields': this.values })
        }
      })
    }
    .margin({ top: 4 })
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }
}

interface ChartRow {
  name: string
  values: number[]
  color: string
}

// The series colors cycle through these keys; the ink ones resolve by theme.
const CHART_SERIES: string[] = ['accent', 'green', 'magenta', 'violet', 'cyan', 'star']

@ComponentV2
struct ChartView {
  @Require @Param node: ViewNode
  @Require @Param root: ViewNode
  @Require @Param inputs: Map<string, Object>

  @Local pinned: number = -1
  @Local hidden: Set<number> = new Set<number>()
  @Local menu: boolean = false
  @Local asTable: boolean = false

  private settings: RenderingContextSettings = new RenderingContextSettings(true)
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings)

  kindOf(): string {
    return resolveString(this.root, this.inputs, fieldOf(this.node, 'kind')) ?? 'bar'
  }

  unitOf(): string {
    return resolveString(this.root, this.inputs, fieldOf(this.node, 'unit')) ?? ''
  }

  captionOf(): string {
    return resolveString(this.root, this.inputs, fieldOf(this.node, 'caption')) ?? ''
  }

  categories(): string[] {
    const raw: Object[] | null = resolveArray(this.root, this.inputs, fieldOf(this.node, 'categories'))
    if (raw === null) return []
    const out: string[] = []
    for (const entry of raw) {
      out.push(String(entry))
    }
    return out
  }

  seriesEntries(): ViewNode[] {
    return resolveNodes(this.root, this.inputs, fieldOf(this.node, 'series'))
  }

  valuesOf(entry: ViewNode): number[] {
    return nodeNumberList(entry, 'values', 'data')
  }

  colorAt(index: number): string {
    const p = appStore.theme.p
    const key: string = CHART_SERIES[index % CHART_SERIES.length]
    if (key === 'accent') return p.accent
    if (key === 'green') return p.green
    if (key === 'star') return p.star
    const ink: string[] | undefined = INKS[key]
    if (ink !== undefined) return ink[appStore.theme.dark ? 1 : 0]
    return p.accent
  }

  rows(): ChartRow[] {
    const cats: string[] = this.categories()
    const series: ViewNode[] = this.seriesEntries()
    if (this.kindOf() === 'donut') {
      const first: number[] = series.length > 0 ? this.valuesOf(series[0]) : []
      const out: ChartRow[] = []
      for (let i = 0; i < cats.length; i++) {
        const row: ChartRow = { name: cats[i] ?? '', values: [first[i] ?? 0], color: this.colorAt(i) }
        out.push(row)
      }
      return out
    }
    const out: ChartRow[] = []
    for (let si = 0; si < series.length; si++) {
      const entry: ViewNode = series[si]
      const row: ChartRow = {
        name: nodeString(entry, 'name') ?? `${si + 1}`,
        values: this.valuesOf(entry),
        color: this.colorAt(si),
      }
      out.push(row)
    }
    return out
  }

  visible(): ChartRow[] {
    const all: ChartRow[] = this.rows()
    const out: ChartRow[] = []
    for (let i = 0; i < all.length; i++) {
      if (!this.hidden.has(i)) out.push(all[i])
    }
    return out
  }

  maxOf(): number {
    let max: number = 1
    for (const row of this.visible()) {
      for (const value of row.values) {
        if (value > max) max = value
      }
    }
    return max
  }

  tableColumns(): string[] {
    if (this.kindOf() === 'donut') {
      const series: ViewNode[] = this.seriesEntries()
      const name: string = series.length > 0 ? nodeString(series[0], 'name') ?? '' : ''
      return ['', name]
    }
    const columns: string[] = ['']
    for (const row of this.rows()) columns.push(row.name)
    return columns
  }

  tableRows(): string[][] {
    const cats: string[] = this.categories()
    const rows: ChartRow[] = this.rows()
    const unit: string = this.unitOf()
    const out: string[][] = []
    if (this.kindOf() === 'donut') {
      for (let i = 0; i < cats.length; i++) {
        const row: ChartRow | undefined = rows[i]
        const value: number | undefined = row?.values[0]
        out.push([cats[i] ?? '', value !== undefined ? `${value}${unit}` : '—'])
      }
      return out
    }
    for (let i = 0; i < cats.length; i++) {
      const cells: string[] = [cats[i] ?? '']
      for (const row of rows) {
        const value: number | undefined = row.values[i]
        cells.push(value !== undefined ? `${value}${unit}` : '—')
      }
      out.push(cells)
    }
    return out
  }

  pinnedText(): string {
    const cats: string[] = this.categories()
    const unit: string = this.unitOf()
    const cat: string = cats[this.pinned] ?? ''
    if (this.kindOf() === 'donut') {
      const row: ChartRow | undefined = this.rows()[this.pinned]
      const value: number | undefined = row?.values[0]
      return `${cat} ${value ?? '—'}${unit}`
    }
    const parts: string[] = []
    for (const row of this.visible()) {
      const value: number | undefined = row.values[this.pinned]
      parts.push(`${row.name} ${value ?? '—'}${unit}`)
    }
    return `${cat}: ${parts.join(' · ')}`
  }

  copyCsv(): void {
    const lines: string[] = [this.tableColumns().join(',')]
    for (const row of this.tableRows()) {
      lines.push(row.join(','))
    }
    void copyToClipboard(lines.join('\n'))
    this.menu = false
  }

  drawDonut(): void {
    const ctx: CanvasRenderingContext2D = this.context
    const rows: ChartRow[] = this.rows()
    let total: number = 0
    for (let i = 0; i < rows.length; i++) {
      if (!this.hidden.has(i)) total += rows[i].values[0] ?? 0
    }
    total = Math.max(1e-9, total)
    const cx: number = ctx.width / 2
    const cy: number = ctx.height / 2
    let at: number = -Math.PI / 2
    for (let i = 0; i < rows.length; i++) {
      if (this.hidden.has(i)) continue
      const frac: number = (rows[i].values[0] ?? 0) / total
      ctx.globalAlpha = this.pinned === -1 || this.pinned === i ? 1 : 0.25
      ctx.fillStyle = rows[i].color
      ctx.beginPath()
      ctx.moveTo(cx, cy)
      ctx.arc(cx, cy, 60, at, at + frac * Math.PI * 2)
      ctx.closePath()
      ctx.fill()
      at += frac * Math.PI * 2
    }
    ctx.globalAlpha = 1
    ctx.fillStyle = appStore.theme.p.card
    ctx.beginPath()
    ctx.arc(cx, cy, 32, 0, Math.PI * 2)
    ctx.fill()
  }

  drawChart(): void {
    const ctx: CanvasRenderingContext2D = this.context
    ctx.clearRect(0, 0, ctx.width, ctx.height)
    const kind: string = this.kindOf()
    if (kind === 'donut') {
      this.drawDonut()
      return
    }
    const rows: ChartRow[] = this.visible()
    const cats: string[] = this.categories()
    const max: number = this.maxOf()
    const W: number = ctx.width
    const H: number = ctx.height
    const pad: number = 6
    if (kind === 'line' || kind === 'area') {
      for (const row of rows) {
        const xs: number[] = []
        const ys: number[] = []
        for (let i = 0; i < row.values.length; i++) {
          xs.push(pad + (i + 0.5) * (W - 2 * pad) / Math.max(1, cats.length))
          ys.push(H - pad - (row.values[i] / max) * (H - 2 * pad))
        }
        if (kind === 'area' && xs.length > 0) {
          ctx.globalAlpha = 0.25
          ctx.fillStyle = row.color
          ctx.beginPath()
          ctx.moveTo(xs[0], H - pad)
          for (let i = 0; i < xs.length; i++) ctx.lineTo(xs[i], ys[i])
          ctx.lineTo(xs[xs.length - 1], H - pad)
          ctx.closePath()
          ctx.fill()
          ctx.globalAlpha = 1
        }
        ctx.strokeStyle = row.color
        ctx.lineWidth = 2
        ctx.lineJoin = 'round'
        ctx.lineCap = 'round'
        ctx.beginPath()
        for (let i = 0; i < xs.length; i++) {
          if (i === 0) ctx.moveTo(xs[0], ys[0])
          else ctx.lineTo(xs[i], ys[i])
        }
        ctx.stroke()
      }
      return
    }
    // bar / hbar
    const bw: number = Math.max(6, (W - pad * 2) / Math.max(1, cats.length) - 6)
    for (let si = 0; si < rows.length; si++) {
      const row: ChartRow = rows[si]
      for (let i = 0; i < row.values.length; i++) {
        const value: number = row.values[i]
        ctx.globalAlpha = this.pinned === -1 || this.pinned === i ? 1 : 0.25
        ctx.fillStyle = row.color
        if (kind === 'hbar') {
          const y: number = pad + i * ((H - 2 * pad) / Math.max(1, cats.length)) + si * (bw / Math.max(1, rows.length))
          ctx.fillRect(pad, y, (value / max) * (W - 2 * pad), Math.max(2, bw / rows.length - 2))
        } else {
          const h: number = (value / max) * (H - 2 * pad)
          const x: number = pad + i * ((W - 2 * pad) / Math.max(1, cats.length)) + si * (bw / Math.max(1, rows.length))
          ctx.fillRect(x, H - pad - h, Math.max(2, bw / rows.length - 2), h)
        }
      }
    }
    ctx.globalAlpha = 1
  }

  build() {
    if (this.asTable) {
      Column({ space: 4 }) {
        DataTableView({ columns: this.tableColumns(), rows: this.tableRows() })
        Text(t('View as chart'))
          .fontSize(type.caption.fontSize)
          .lineHeight(type.caption.lineHeight)
          .fontColor(appStore.theme.p.accent)
          .onClick(() => {
            this.asTable = false
          })
      }
      .alignItems(HorizontalAlign.Start)
    } else {
      Column({ space: 4 }) {
        Stack() {
          Canvas(this.context)
            .width('100%')
            .height(160)
            .onReady(() => {
              this.drawChart()
            })
          Row() {
            ForEach(this.categories(), (cat: string, index: number) => {
              Column() {
              }
              .layoutWeight(1)
              .height('100%')
              .onClick(() => {
                this.pinned = this.pinned === index ? -1 : index
                this.drawChart()
              })
            }, (cat: string, index: number): string => `p-${index}`)
          }
          .width('100%')
          .height('100%')
        }
        .width('100%')
        if (this.kindOf() !== 'donut' && this.kindOf() !== 'hbar') {
          Row() {
            ForEach(this.categories(), (cat: string, index: number) => {
              Text(cat)
                .fontSize(type.caption.fontSize)
                .lineHeight(type.caption.lineHeight)
                .fontColor(this.pinned === index ? appStore.theme.p.ink : appStore.theme.p.ink3)
                .maxLines(1)
                .layoutWeight(1)
                .textAlign(TextAlign.Center)
            }, (cat: string, index: number): string => `cl-${index}`)
          }
          .width('100%')
        }
        if (this.pinned >= 0) {
          Text(this.pinnedText())
            .fontSize(type.caption.fontSize)
            .lineHeight(type.caption.lineHeight)
            .fontColor(appStore.theme.p.ink)
        }
        Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
          ForEach(this.rows(), (row: ChartRow, index: number) => {
            Row({ space: 4 }) {
              Column() {
              }
              .width(8)
              .height(8)
              .borderRadius(2)
              .backgroundColor(row.color)
              Text(row.name)
                .fontSize(type.caption.fontSize)
                .lineHeight(type.caption.lineHeight)
                .fontColor(appStore.theme.p.ink2)
            }
            .alignItems(VerticalAlign.Center)
            .opacity(this.hidden.has(index) ? 0.35 : 1)
            .margin({ right: 10, bottom: 4 })
            .onClick(() => {
              const next: Set<number> = new Set<number>(this.hidden)
              if (next.has(index)) next.delete(index)
              else next.add(index)
              this.hidden = next
              this.drawChart()
            })
          }, (row: ChartRow, index: number): string => `lg-${index}`)
          Text('…')
            .fontSize(18)
            .fontColor(appStore.theme.p.ink3)
            .margin({ right: 10, bottom: 4 })
            .onClick(() => {
              this.menu = !this.menu
            })
        }
        .margin({ top: 4 })
        if (this.menu) {
          Row({ space: 16 }) {
            Text(t('View as table'))
              .fontSize(type.small.fontSize)
              .lineHeight(type.small.lineHeight)
              .fontColor(appStore.theme.p.accent)
              .onClick(() => {
                this.asTable = true
                this.menu = false
              })
            Text(t('Copy data (CSV)'))
              .fontSize(type.small.fontSize)
              .lineHeight(type.small.lineHeight)
              .fontColor(appStore.theme.p.accent)
              .onClick(() => {
                this.copyCsv()
              })
          }
          .margin({ top: 6 })
        }
        if (this.captionOf() !== '') {
          Text(this.captionOf())
            .fontSize(type.caption.fontSize)
            .lineHeight(type.caption.lineHeight)
            .fontColor(appStore.theme.p.ink3)
            .margin({ top: 2 })
        }
      }
      .alignItems(HorizontalAlign.Start)
    }
  }
}

@ComponentV2
struct DataTableView {
  @Require @Param columns: string[]
  @Require @Param rows: string[][]
  @Local tableWidth: number = 0

  cellWidth(): number {
    if (this.columns.length === 0) return 88
    return Math.max(88, Math.floor((this.tableWidth - 2) / this.columns.length))
  }

  build() {
    Column() {
      Scroll() {
        Column() {
          Row() {
            ForEach(this.columns, (column: string, index: number) => {
              Text(column)
                .fontSize(type.caption.fontSize)
                .lineHeight(type.caption.lineHeight)
                .fontWeight('500')
                .fontColor(appStore.theme.p.ink2)
                .width(this.cellWidth())
                .padding({ left: 8, right: 8, top: 7, bottom: 7 })
            }, (column: string, index: number): string => `c-${index}`)
          }
          .backgroundColor(appStore.theme.p.hover)
          ForEach(this.rows, (row: string[], index: number) => {
            Row() {
              ForEach(row, (cell: string, ci: number) => {
                Text(cell)
                  .fontSize(type.small.fontSize)
                  .lineHeight(type.small.lineHeight)
                  .fontColor(appStore.theme.p.ink)
                  .width(this.cellWidth())
                  .padding({ left: 8, right: 8, top: 7, bottom: 7 })
              }, (cell: string, ci: number): string => `b-${ci}`)
            }
            .border({ width: { top: 1 }, color: appStore.theme.p.line })
          }, (row: string[], index: number): string => `r-${index}`)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
    }
    .border({ width: 1, color: appStore.theme.p.line })
    .borderRadius(radius.item)
    .clip(true)
    .onAreaChange((oldArea: Area, newArea: Area) => {
      const w: number = Number(newArea.width)
      if (Number.isFinite(w)) this.tableWidth = w
    })
  }
}
