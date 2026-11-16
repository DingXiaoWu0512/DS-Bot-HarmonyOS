// The desktop's model menu (mobile/src/screens/model-menu.tsx) as a bottom
// sheet: models grouped by provider, the default one marked, and the
// thinking-level slider of the picked model under them. ModelPicker is the
// same trigger and sheet for a Bot that does not exist yet — no thinking level.

import { appStore, type, radius } from '../components/Theme'
import { t } from '../common/ui/i18n'
import type { Bot, ModelInfo, Reasoning } from '../common/team/types'
import { Icon } from '../components/Icon'

export interface EffortOption {
  id: string
  name: string
}

// One provider group: its display title and every model under it.
export interface ModelGroup {
  provider: string
  list: ModelInfo[]
}

// What a Bot runs on, for display: the chosen model, else the one it last ran on.
export interface ModelRef {
  ref: string
  name: string
  provider: string
}

// One thinking level on the slider; the Default stop carries no effort id.
export interface EffortStop {
  effort?: string
  label: string
}

interface EffortsPayload {
  ref: string
}

interface EffortsReply {
  efforts?: EffortOption[]
  defaultEffort?: string
}

interface UpdateBotPayload {
  id: string
  model?: string
  effort?: string | null
}

const KNOB = 18
const INSET = 11

// Models grouped by provider; two providers sharing a display name get the
// raw provider id appended, the way the REF disambiguates them.
export function groupModels(models: ModelInfo[]): ModelGroup[] {
  const groups = new Map<string, ModelInfo[]>()
  for (const model of models) {
    const provider = model.provider ?? model.providerName ?? model.ref.split('/')[0]
    const list = groups.get(provider)
    if (list === undefined) {
      groups.set(provider, [model])
    } else {
      list.push(model)
    }
  }
  const names = new Map<string, number>()
  groups.forEach((list: ModelInfo[]): void => {
    const name = list[0].providerName ?? list[0].ref.split('/')[0]
    const count = names.get(name) ?? 0
    names.set(name, count + 1)
  })
  const out: ModelGroup[] = []
  groups.forEach((list: ModelInfo[], provider: string): void => {
    const name = list[0].providerName ?? provider
    const title = (names.get(name) ?? 0) > 1 ? `${name} (${provider})` : name
    out.push({ provider: title, list })
  })
  return out
}

function servedModel(models: ModelInfo[], ref: string): ModelInfo | null {
  for (const model of models) {
    if (model.ref === ref) return model
  }
  return null
}

export function modelOf(bot: Bot, models: ModelInfo[]): ModelRef | null {
  const ref = bot.model ?? bot.appliedModel
  if (ref === undefined || ref === '') return null
  const served = servedModel(models, ref)
  const split = ref.split('/')
  const provider = split.length > 0 ? split[0] : ref
  const rest = split.slice(1).join('/')
  return {
    ref,
    name: served !== null ? served.name : rest,
    provider: served?.providerName ?? provider,
  }
}

// The thinking levels of one model. The catalog carries them for models Bots
// use; any other ref asks the computer once, and the answer is cached.
const effortCache = new Map<string, Reasoning | null>()

export function effortLabel(reasoning: Reasoning | null | undefined, effort: string | undefined): string | undefined {
  const efforts: EffortOption[] = reasoning?.efforts ?? []
  if (efforts.length === 0) return undefined
  let picked: string | undefined = undefined
  for (const item of efforts) {
    if (item.id === effort) picked = effort
  }
  const current = picked ?? reasoning?.defaultEffort
  if (current === undefined) return t('Default')
  for (const item of efforts) {
    if (item.id === current) return item.name
  }
  return current
}

// When the model names its default level the stops are the levels and a reset
// clears back to Default; otherwise Default sits at the first stop.
function effortStops(reasoning: Reasoning | null | undefined): EffortStop[] {
  const efforts: EffortOption[] = reasoning?.efforts ?? []
  if (efforts.length === 0) return []
  const defaultEffort = reasoning?.defaultEffort
  let hasDefault = false
  for (const item of efforts) {
    if (item.id === defaultEffort) hasDefault = true
  }
  const levels: EffortStop[] = []
  for (const item of efforts) {
    levels.push({ effort: item.id, label: item.name })
  }
  if (hasDefault) return levels
  const stops: EffortStop[] = [{ label: t('Default') }]
  return stops.concat(levels)
}

function sameEffort(a: string | undefined, b: string | undefined): boolean {
  if (a === undefined && b === undefined) return true
  if (a === undefined || b === undefined) return false
  return a === b
}

// The thinking-level slider: a stop rail with a knob, tap or drag to a stop,
// release commits. While dragging the outside `current` is ignored.
@ComponentV2
export struct EffortBar {
  @Param reasoning: Reasoning | null = null
  @Param current: string | undefined = undefined
  @Event onPick: (effort: string | undefined) => void = (effort: string | undefined): void => {}
  @Local picked: string | undefined = undefined
  @Local trackWidth: number = 0
  private dragging: boolean = false

  aboutToAppear(): void {
    this.picked = this.current
  }

  @Monitor('current')
  onCurrentChange(): void {
    if (!this.dragging) {
      this.picked = this.current
    }
  }

  private stops(): EffortStop[] {
    return effortStops(this.reasoning)
  }

  private hasDefault(): boolean {
    const defaultEffort = this.reasoning?.defaultEffort
    for (const item of this.reasoning?.efforts ?? []) {
      if (item.id === defaultEffort) return true
    }
    return false
  }

  private activeIndex(): number {
    const stops = this.stops()
    if (stops.length === 0) return 0
    const activeEffort = this.picked ?? (this.hasDefault() ? this.reasoning?.defaultEffort : undefined)
    let index = -1
    let at = 0
    for (const stop of stops) {
      if (sameEffort(stop.effort, activeEffort)) {
        index = at
        break
      }
      at += 1
    }
    if (index < 0) index = 0
    return index
  }

  private ratio(): number {
    const stops = this.stops()
    if (stops.length <= 1) return 1
    return this.activeIndex() / (stops.length - 1)
  }

  private span(): number {
    return Math.max(1, this.trackWidth - INSET * 2)
  }

  private fillWidth(): number {
    return INSET * 2 + this.span() * this.ratio()
  }

  private knobLeft(): number {
    return INSET + this.span() * this.ratio() - KNOB / 2
  }

  private stopLeft(at: number): number {
    return INSET + this.span() * at - 2
  }

  private stopFromX(x: number): EffortStop | null {
    const stops = this.stops()
    if (stops.length === 0 || this.trackWidth <= 0) return null
    const raw = (x - INSET) / this.span()
    const r = Math.max(0, Math.min(1, raw))
    const index = Math.round(r * (stops.length - 1))
    return stops[index] ?? stops[0]
  }

  private commit(effort: string | undefined): void {
    this.picked = effort
    if (!sameEffort(effort, this.current)) {
      this.onPick(effort)
    }
  }

  private touch(event: TouchEvent): void {
    const x = event.touches.length > 0 ? event.touches[0].x : 0
    if (event.type === TouchType.Down || event.type === TouchType.Move) {
      const stop = this.stopFromX(x)
      if (stop !== null) {
        this.dragging = true
        this.picked = stop.effort
      }
    } else if (event.type === TouchType.Up) {
      const stop = this.stopFromX(x)
      this.dragging = false
      if (stop !== null) this.commit(stop.effort)
    } else if (event.type === TouchType.Cancel) {
      this.dragging = false
      this.picked = this.current
    }
  }

  private dotColor(at: number): string {
    if (at <= this.ratio() + 0.001) {
      return 'rgba(255,255,255,0.65)'
    }
    return appStore.theme.p.ink3
  }

  private dotOpacity(at: number): number {
    return at <= this.ratio() + 0.001 ? 1 : 0.45
  }

  private activeLabel(): string {
    const stops = this.stops()
    if (stops.length === 0) return ''
    return stops[this.activeIndex()]?.label ?? ''
  }

  private resetOpacity(): number {
    return this.picked === undefined ? 0.35 : 1
  }

  private resetDisabled(): boolean {
    return this.picked === undefined
  }

  @Builder
  stopDots() {
    ForEach(this.stops(), (stop: EffortStop, index: number) => {
      Column()
        .width(4)
        .height(4)
        .borderRadius(2)
        .backgroundColor(this.dotColor(index))
        .opacity(this.dotOpacity(index))
        .position({ x: this.stopLeft(index), y: 14 })
    }, (stop: EffortStop) => stop.effort ?? 'default')
  }

  build() {
    if (this.stops().length === 0) {
      Column()
    } else {
      Column({ space: 6 }) {
        Row({ space: 8 }) {
          Text(t('Thinking level'))
            .fontSize(type.caption.fontSize)
            .lineHeight(type.caption.lineHeight)
            .fontWeight('500')
            .fontColor(appStore.theme.p.ink3)
          Column() {
            Row({ space: 6 }) {
              if (this.picked === undefined && this.hasDefault()) {
                Text(t('Default'))
                  .fontSize(type.caption.fontSize)
                  .lineHeight(type.caption.lineHeight)
                  .fontColor(appStore.theme.p.ink3)
              }
              Text(this.activeLabel())
                .fontSize(13)
                .lineHeight(18)
                .fontWeight('600')
                .fontColor(appStore.theme.p.accent)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (this.picked !== undefined || !this.hasDefault()) {
                Column() {
                  Text('↺')
                    .fontSize(13)
                    .fontColor(appStore.theme.p.ink2)
                }
                .width(28)
                .height(28)
                .borderRadius(14)
                .alignItems(HorizontalAlign.Center)
                .justifyContent(FlexAlign.Center)
                .backgroundColor(appStore.theme.p.hover)
                .opacity(this.resetOpacity())
                .onClick(() => {
                  if (!this.resetDisabled()) this.commit(undefined)
                })
              }
            }
            .alignItems(VerticalAlign.Center)
            .justifyContent(FlexAlign.End)
          }
          .constraintSize({ minWidth: 0 })
          .alignItems(HorizontalAlign.End)
        }
        .width('100%')
        .constraintSize({ minHeight: 28 })
        .alignItems(VerticalAlign.Center)
        Column() {
          Stack({ alignContent: Alignment.Start }) {
            Column()
              .width('100%')
              .height(20)
              .borderRadius(999)
              .backgroundColor(appStore.theme.p.hover)
              .border({ width: this.hairline(), color: appStore.theme.p.line })
              .position({ x: 0, y: 6 })
            Column()
              .width(this.fillWidth())
              .height(20)
              .borderRadius(999)
              .backgroundColor(appStore.theme.p.accent)
              .position({ x: 0, y: 6 })
            this.stopDots()
            Column()
              .width(KNOB)
              .height(KNOB)
              .borderRadius(KNOB / 2)
              .backgroundColor('#ffffff')
              .shadow({ radius: 3, color: 'rgba(0,0,0,0.2)', offsetX: 0, offsetY: 1 })
              .position({ x: this.knobLeft(), y: 7 })
          }
          .width('100%')
          .height(32)
          .alignContent(Alignment.Start)
          .onAreaChange((_old: Area, area: Area): void => {
            this.trackWidth = Number(area.width)
          })
          .onTouch((event: TouchEvent) => this.touch(event))
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
      .accessibilityText(t('Thinking level'))
    }
  }

  private hairline(): number {
    return this.getUIContext().px2vp(1)
  }
}

// Every model under its provider, the default one marked.
@ComponentV2
export struct ModelGroups {
  @Param models: ModelInfo[] = []
  @Param current: string | undefined = undefined
  @Param fallback: string | undefined = undefined
  @Event onPick: (ref: string) => void = (ref: string): void => {}
  @Local pressedRef: string = ''

  private groups(): ModelGroup[] {
    return groupModels(this.models)
  }

  private rowBg(ref: string): ResourceColor {
    if (this.pressedRef === ref) {
      return appStore.theme.p.hover
    }
    return Color.Transparent
  }

  @Builder
  modelRow(item: ModelInfo) {
    Row({ space: 10 }) {
      Text(item.name)
        .fontSize(type.settingsRow.fontSize)
        .lineHeight(type.settingsRow.lineHeight)
        .fontColor(appStore.theme.p.ink)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      if (this.fallback !== undefined && item.ref === this.fallback) {
        Text(t('Default'))
          .fontSize(type.caption.fontSize)
          .lineHeight(type.caption.lineHeight)
          .fontColor(appStore.theme.p.ink3)
      }
      if (this.current !== undefined && item.ref === this.current) {
        Icon({ name: 'check', iconSize: 20 })
      }
    }
    .constraintSize({ minHeight: 48 })
    .width('100%')
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.rowBg(item.ref))
    .onClick(() => this.onPick(item.ref))
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.pressedRef = item.ref
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressedRef = ''
      }
    })
  }

  build() {
    Scroll() {
      Column() {
        ForEach(this.groups(), (group: ModelGroup) => {
          Column() {
            Text(group.provider)
              .fontSize(type.caption.fontSize)
              .lineHeight(type.caption.lineHeight)
              .fontColor(appStore.theme.p.ink3)
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 4 })
            ForEach(group.list, (item: ModelInfo) => {
              this.modelRow(item)
            }, (item: ModelInfo) => item.ref)
          }
          .width('100%')
        }, (group: ModelGroup) => group.provider)
      }
      .width('100%')
    }
    .constraintSize({ maxHeight: 420 })
    .width('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }
}

// A model picker for a Bot that does not exist yet (Create new Bot): the same
// trigger and sheet as a Bot's model menu, without the thinking level.
@ComponentV2
export struct ModelPicker {
  @Param current: string | undefined = undefined
  @Event onPick: (ref: string) => void = (ref: string): void => {}
  @Local open: boolean = false

  private models(): ModelInfo[] {
    return appStore.link.team?.models ?? []
  }

  private model(): ModelInfo | null {
    if (this.current === undefined) return null
    return servedModel(this.models(), this.current)
  }

  private nameText(): string {
    const model = this.model()
    if (model !== null) return model.name
    return t('Choose a model')
  }

  private providerText(): string {
    const model = this.model()
    if (model === null) return ''
    return model.providerName ?? model.ref.split('/')[0]
  }

  private fallbackRef(): string | undefined {
    return appStore.link.team?.defaultModel
  }

  private pick(ref: string): void {
    this.onPick(ref)
    this.open = false
  }

  private hairline(): number {
    return this.getUIContext().px2vp(1)
  }

  private sheetOptions(): SheetOptions {
    return {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: false,
      backgroundColor: appStore.theme.p.card,
      onDisappear: (): void => {
        this.open = false
      },
    }
  }

  @Builder
  pickerSheet() {
    Column() {
      ModelGroups({
        models: this.models(),
        current: this.current,
        fallback: this.fallbackRef(),
        onPick: (ref: string): void => this.pick(ref),
      })
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
  }

  build() {
    Row({ space: 8 }) {
      Column() {
        Text(this.nameText())
          .fontSize(type.settingsRow.fontSize)
          .lineHeight(type.settingsRow.lineHeight)
          .fontWeight('500')
          .fontColor(appStore.theme.p.ink)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.model() !== null) {
          Text(this.providerText())
            .fontSize(type.caption.fontSize)
            .lineHeight(type.caption.lineHeight)
            .fontColor(appStore.theme.p.ink3)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text('⌄')
        .fontSize(12)
        .fontColor(appStore.theme.p.ink3)
    }
    .constraintSize({ minHeight: 52 })
    .width('100%')
    .borderRadius(radius.card)
    .border({ width: this.hairline(), color: appStore.theme.p.line })
    .backgroundColor(appStore.theme.p.card)
    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
    .accessibilityText(t('Model'))
    .onClick(() => {
      this.open = true
    })
    .bindSheet($$this.open, this.pickerSheet(), this.sheetOptions())
  }
}

// The trigger shows the model name over its provider and thinking level, as on
// the desktop; the sheet edits model and thinking level in place.
@ComponentV2
export struct ModelMenu {
  @Require @Param bot: Bot
  @Event onManage: () => void = (): void => {}
  @Local open: boolean = false
  @Local error: string = ''
  @Local fetchedFor: string = ''
  @Local fetched: Reasoning | null | undefined = undefined
  @Local pressedManage: boolean = false

  private models(): ModelInfo[] {
    return appStore.link.team?.models ?? []
  }

  private model(): ModelRef | null {
    return modelOf(this.bot, this.models())
  }

  private fallbackRef(): string | undefined {
    return appStore.link.team?.defaultModel
  }

  // The served catalog entry carries the levels for models Bots use; any other
  // ref asks the computer once (answer cached).
  private servedReasoning(): Reasoning | undefined {
    const ref = this.model()?.ref
    if (ref === undefined) return undefined
    return servedModel(this.models(), ref)?.reasoning
  }

  private reasoning(): Reasoning | null | undefined {
    const served = this.servedReasoning()
    if (served !== undefined) return served
    const ref = this.model()?.ref
    if (ref === undefined) return undefined
    if (this.fetchedFor === ref) return this.fetched
    return undefined
  }

  private level(): string | undefined {
    return effortLabel(this.reasoning(), this.bot.effort)
  }

  private subtitle(): string {
    const model = this.model()
    if (model === null) return ''
    const parts: string[] = []
    if (model.provider !== '') parts.push(model.provider)
    const level = this.level()
    if (level !== undefined) parts.push(level)
    return parts.join(' · ')
  }

  aboutToAppear(): void {
    this.refreshReasoning()
  }

  @Monitor('bot')
  onBotChange(): void {
    this.refreshReasoning()
  }

  private refreshReasoning(): void {
    const ref = this.model()?.ref
    if (ref === undefined) return
    if (this.servedReasoning() !== undefined) return
    if (effortCache.has(ref)) {
      this.fetchedFor = ref
      this.fetched = effortCache.get(ref) ?? null
      return
    }
    this.fetchedFor = ''
    this.fetched = undefined
    void this.fetchReasoning(ref)
  }

  private async fetchReasoning(ref: string): Promise<void> {
    const controller = appStore.link.controller
    if (controller === null) return
    const payload: EffortsPayload = { ref }
    try {
      const raw = (await controller.call('efforts', payload)) as EffortsReply | null
      const reasoning: Reasoning | null =
        raw !== null && raw !== undefined && raw.efforts !== undefined && raw.efforts.length > 0
          ? raw as Reasoning
          : null
      effortCache.set(ref, reasoning)
      if (this.model()?.ref === ref) {
        this.fetchedFor = ref
        this.fetched = reasoning
      }
    } catch {
      // No thinking levels for this ref; the bar just stays hidden.
    }
  }

  private save(patch: UpdateBotPatch): void {
    const payload: UpdateBotPayload = { id: this.bot.id }
    if (patch.model !== undefined) payload.model = patch.model
    if (patch.effortSet) payload.effort = patch.effort ?? null
    const controller = appStore.link.controller
    if (controller === null) return
    void controller.call('update-bot', payload).then((): void => {
      this.error = ''
    }).catch((failure: Error): void => {
      this.error = failure instanceof Error ? failure.message : String(failure)
    })
  }

  private pickModel(ref: string): void {
    if (ref !== this.bot.model) {
      this.save({ model: ref })
    }
  }

  private effortValid(): string | undefined {
    const effort = this.bot.effort
    for (const item of this.reasoning()?.efforts ?? []) {
      if (item.id === effort) return effort
    }
    return undefined
  }

  private showEffort(): boolean {
    return this.model() !== null && (this.reasoning()?.efforts?.length ?? 0) > 0
  }

  private manageBg(): ResourceColor {
    if (this.pressedManage) {
      return appStore.theme.p.hover
    }
    return Color.Transparent
  }

  private hairline(): number {
    return this.getUIContext().px2vp(1)
  }

  private sheetOptions(): SheetOptions {
    return {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: false,
      backgroundColor: appStore.theme.p.card,
      onDisappear: (): void => {
        this.open = false
      },
    }
  }

  @Builder
  menuSheet() {
    Column() {
      ModelGroups({
        models: this.models(),
        current: this.model()?.ref,
        fallback: this.fallbackRef(),
        onPick: (ref: string): void => this.pickModel(ref),
      })
      if (this.showEffort()) {
        Column() {
          EffortBar({
            reasoning: this.reasoning() ?? null,
            current: this.effortValid(),
            onPick: (effort: string | undefined): void => this.save({ effort, effortSet: true }),
          })
        }
        .width('100%')
        .margin({ top: 6 })
        .border({ width: { top: this.hairline() }, color: appStore.theme.p.line })
      }
      Row({ space: 10 }) {
        Text(t('Models and providers…'))
          .fontSize(type.settingsRow.fontSize)
          .lineHeight(type.settingsRow.lineHeight)
          .fontColor(appStore.theme.p.ink)
          .layoutWeight(1)
        Icon({ name: 'chevronRight', iconSize: 20, color: appStore.theme.p.ink3 })
      }
      .constraintSize({ minHeight: 48 })
      .width('100%')
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)
      .border({ width: { top: this.hairline() }, color: appStore.theme.p.line })
      .backgroundColor(this.manageBg())
      .onClick(() => {
        this.open = false
        this.onManage()
      })
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.pressedManage = true
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.pressedManage = false
        }
      })
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
  }

  build() {
    Column({ space: 0 }) {
      Row({ space: 8 }) {
        Column() {
          Text(this.model()?.name ?? t('Choose a model'))
            .fontSize(type.settingsRow.fontSize)
            .lineHeight(type.settingsRow.lineHeight)
            .fontWeight('500')
            .fontColor(appStore.theme.p.ink)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.model() !== null) {
            Text(this.subtitle())
              .fontSize(type.caption.fontSize)
              .lineHeight(type.caption.lineHeight)
              .fontColor(appStore.theme.p.ink3)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Text('⌄')
          .fontSize(12)
          .fontColor(appStore.theme.p.ink3)
      }
      .constraintSize({ minHeight: 52 })
      .width('100%')
      .borderRadius(radius.card)
      .border({ width: this.hairline(), color: appStore.theme.p.line })
      .backgroundColor(appStore.theme.p.card)
      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .alignItems(VerticalAlign.Center)
      .accessibilityText(t('Model'))
      .onClick(() => {
        this.open = true
      })
      .bindSheet($$this.open, this.menuSheet(), this.sheetOptions())
      if (this.model() === null) {
        Text(t('Pick a model and {name} can start.', { 'name': this.bot.name }))
          .fontSize(type.small.fontSize)
          .lineHeight(type.small.lineHeight)
          .fontColor(appStore.theme.p.ink3)
          .width('100%')
          .margin({ top: 6 })
      }
      if (this.error !== '') {
        Text(this.error)
          .fontSize(type.small.fontSize)
          .lineHeight(type.small.lineHeight)
          .fontColor(appStore.theme.p.danger)
          .width('100%')
          .margin({ top: 6 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

// The update-bot patch shape: model rename, or a thinking level where
// effortSet marks "clear back to Default" (the wire value is null).
export interface UpdateBotPatch {
  model?: string
  effort?: string
  effortSet?: boolean
}
