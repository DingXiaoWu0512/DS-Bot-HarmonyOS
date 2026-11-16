// Form control set ported from mobile/src/screens/Settings.tsx (Row/Choice/
// Section/Switch patterns) plus the destructive back/field/pick rows the screens
// need. RN names Row/Section/Field become FormRow/FormSection/FormField to avoid
// colliding with the ArkUI system Row component and to read clearly at call
// sites. Section children place SectionDivider between items (the RN Section
// auto-inserted dividers; an ArkTS @BuilderParam slot cannot introspect them).

import { appStore, type, radius, shadowOf, luminance } from './Theme'
import { Icon } from './Icon'
import { ConfirmDanger } from './Sheet'

@Builder
function emptyBuilder() {
}

// The row chrome every settings row shares: min height 50, 16/10 padding,
// gap 10, label grows (min 96), value fades right (max 52%).
@ComponentV2
export struct FormRow {
  @Param label: string = ''
  @Param hint: string = ''
  @Param value: string | undefined = undefined
  @Param hasAction: boolean = false
  @Event onPress: () => void = () => {}
  @BuilderParam end: () => void = emptyBuilder
  @Local pressed: boolean = false

  private bg(): ResourceColor {
    if (this.pressed && this.hasAction) {
      return appStore.theme.p.hover
    }
    return Color.Transparent
  }

  private tap(): void {
    if (this.hasAction) {
      this.onPress()
    }
  }

  private handleTouch(e: TouchEvent): void {
    if (!this.hasAction) {
      return
    }
    if (e.type === TouchType.Down) {
      this.pressed = true
    } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
      this.pressed = false
    }
  }

  build() {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text(this.label)
          .fontSize(type.settingsRow.fontSize)
          .lineHeight(type.settingsRow.lineHeight)
          .fontWeight(type.settingsRow.fontWeight)
          .fontColor(appStore.theme.p.ink)
        if (this.hint !== '') {
          Text(this.hint)
            .fontSize(type.small.fontSize)
            .lineHeight(type.small.lineHeight)
            .fontColor(appStore.theme.p.ink3)
        }
      }
      .layoutWeight(1)
      .constraintSize({ minWidth: 96 })
      .alignItems(HorizontalAlign.Start)
      if (this.value !== undefined) {
        Text(this.value)
          .fontSize(type.settingsRow.fontSize)
          .lineHeight(type.settingsRow.lineHeight)
          .fontWeight(type.settingsRow.fontWeight)
          .fontColor(appStore.theme.p.ink2)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.End)
          .constraintSize({ maxWidth: '52%' })
      }
      this.end()
      if (this.hasAction) {
        Icon({ name: 'chevronRight', iconSize: 16, color: appStore.theme.p.ink3 })
      }
    }
    .constraintSize({ minHeight: 50 })
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
    .width('100%')
    .backgroundColor(this.bg())
    .onClick(() => this.tap())
    .onTouch((e: TouchEvent) => this.handleTouch(e))
  }
}

// A labeled inline text input on the shared row chrome.
@ComponentV2
export struct FormField {
  @Param label: string = ''
  @Param text: string = ''
  @Param placeholder: string = ''
  @Event onTextChange: (v: string) => void = (v: string) => {}

  build() {
    Row({ space: 10 }) {
      Text(this.label)
        .fontSize(type.settingsRow.fontSize)
        .lineHeight(type.settingsRow.lineHeight)
        .fontWeight(type.settingsRow.fontWeight)
        .fontColor(appStore.theme.p.ink)
        .layoutWeight(1)
        .constraintSize({ minWidth: 96 })
      TextInput({ text: this.text, placeholder: this.placeholder })
        .fontSize(type.settingsRow.fontSize)
        .fontColor(appStore.theme.p.ink)
        .placeholderColor(appStore.theme.p.ink3)
        .backgroundColor(Color.Transparent)
        .padding(0)
        .textAlign(TextAlign.End)
        .constraintSize({ maxWidth: '52%' })
        .onChange((v: string) => this.onTextChange(v))
    }
    .constraintSize({ minHeight: 50 })
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
    .width('100%')
  }
}

// The manage screen's Field: the label stacked over the input, saved when the
// field loses focus. The multiline variant is a TextArea (ArkUI's TextInput is
// single-line only).
@ComponentV2
export struct FormFieldBlock {
  @Param label: string = ''
  @Param text: string = ''
  @Param placeholder: string = ''
  @Param multiline: boolean = false
  @Event onSave: (next: string) => void = (next: string) => {}
  @Local draft: string | null = null

  @Monitor('text')
  onTextReset(): void {
    // The saved value caught up; drop any stale draft.
    this.draft = null
  }

  private display(): string {
    if (this.draft !== null) return this.draft
    return this.text
  }

  private change(value: string): void {
    this.draft = value
  }

  private commit(): void {
    const next = (this.draft ?? '').trim()
    this.draft = null
    if (next !== this.text.trim()) {
      this.onSave(next)
    }
  }

  build() {
    Row() {
      Column({ space: 4 }) {
        if (this.label !== '') {
          Text(this.label)
            .fontSize(type.settingsRow.fontSize)
            .lineHeight(type.settingsRow.lineHeight)
            .fontWeight(type.settingsRow.fontWeight)
            .fontColor(appStore.theme.p.ink3)
        }
        if (this.multiline) {
          TextArea({ text: this.display(), placeholder: this.placeholder })
            .fontSize(type.settingsRow.fontSize)
            .fontColor(appStore.theme.p.ink)
            .placeholderColor(appStore.theme.p.ink3)
            .backgroundColor(Color.Transparent)
            .padding({ top: 4, bottom: 4 })
            .constraintSize({ minHeight: 90, maxWidth: '100%' })
            .onChange((value: string) => this.change(value))
            .onBlur(() => this.commit())
        } else {
          TextInput({ text: this.display(), placeholder: this.placeholder })
            .fontSize(type.settingsRow.fontSize)
            .fontColor(appStore.theme.p.ink)
            .placeholderColor(appStore.theme.p.ink3)
            .backgroundColor(Color.Transparent)
            .padding({ top: 4, bottom: 4 })
            .width('100%')
            .onChange((value: string) => this.change(value))
            .onBlur(() => this.commit())
            .onSubmit(() => this.commit())
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .constraintSize({ minHeight: 50 })
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
    .width('100%')
  }
}

// A choice of a few values, all in view: the segmented control's shape.
// Segments sit on p.hover, the selected one lifts to p.card with shadow(1).
export interface SegmentOption {
  id: string
  label: string
}

@ComponentV2
export struct Segmented {
  @Param label: string = ''
  @Param options: SegmentOption[] = []
  @Param value: string = ''
  @Event onPick: (id: string) => void = (id: string) => {}

  private isCurrent(opt: SegmentOption): boolean {
    return opt.id === this.value
  }

  private segColor(opt: SegmentOption): string {
    if (this.isCurrent(opt)) {
      return appStore.theme.p.ink
    }
    return appStore.theme.p.ink2
  }

  private segWeight(opt: SegmentOption): string {
    if (this.isCurrent(opt)) {
      return '600'
    }
    return '400'
  }

  private segBg(opt: SegmentOption): ResourceColor {
    if (this.isCurrent(opt)) {
      return appStore.theme.p.card
    }
    return Color.Transparent
  }

  private segShadow(opt: SegmentOption): ShadowOptions {
    if (this.isCurrent(opt)) {
      return shadowOf(1)
    }
    return { radius: 0, color: Color.Transparent, offsetX: 0, offsetY: 0 }
  }

  @Builder
  segment(opt: SegmentOption) {
    Column() {
      Text(opt.label)
        .fontSize(type.small.fontSize)
        .lineHeight(type.small.lineHeight)
        .fontWeight(this.segWeight(opt))
        .fontColor(this.segColor(opt))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
    }
    .layoutWeight(1)
    .constraintSize({ minHeight: 34 })
    .padding({ left: 6, right: 6, top: 5, bottom: 5 })
    .borderRadius(7)
    .backgroundColor(this.segBg(opt))
    .shadow(this.segShadow(opt))
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => this.onPick(opt.id))
  }

  build() {
    Column({ space: 8 }) {
      Text(this.label)
        .fontSize(type.settingsRow.fontSize)
        .lineHeight(type.settingsRow.lineHeight)
        .fontWeight(type.settingsRow.fontWeight)
        .fontColor(appStore.theme.p.ink)
      Row() {
        ForEach(this.options, (opt: SegmentOption) => {
          this.segment(opt)
        }, (opt: SegmentOption) => opt.id)
      }
      .width('100%')
      .borderRadius(9)
      .backgroundColor(appStore.theme.p.hover)
      .padding(2)
    }
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

// The grouped card: caption label above, rounded card with hairline border and
// shadow(1); rows go in the content slot with SectionDivider between them.
@ComponentV2
export struct FormSection {
  @Param label: string = ''
  @BuilderParam content: () => void = emptyBuilder

  private hairline(): number {
    return this.getUIContext().px2vp(1)
  }

  build() {
    Column() {
      Text(this.label)
        .fontSize(11)
        .lineHeight(type.caption.lineHeight)
        .fontWeight(type.caption.fontWeight)
        .fontColor(appStore.theme.p.ink3)
        .letterSpacing(0.6)
        .textCase(TextCase.UpperCase)
        .padding({ left: 18, right: 18 })
        .margin({ bottom: 6 })
      Column() {
        this.content()
      }
      // calc keeps the card inside its margins: a plain 100% width plus
      // horizontal margins overflows the right screen edge.
      .width('calc(100% - 28vp)')
      .backgroundColor(appStore.theme.p.card)
      .borderRadius(radius.card)
      .border({ width: this.hairline(), color: appStore.theme.p.line })
      .margin({ left: 14, right: 14 })
      .clip(true)
      .shadow(shadowOf(1))
    }
    .margin({ top: 16 })
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

// The hairline between rows inside a FormSection.
@ComponentV2
export struct SectionDivider {
  private hairline(): number {
    return this.getUIContext().px2vp(1)
  }

  build() {
    Divider()
      .strokeWidth(this.hairline())
      .color(appStore.theme.p.line)
      .margin({ left: 16 })
  }
}

// A row ending in a switch: track p.line2 off / p.accent on, thumb p.knob.
@ComponentV2
export struct SwitchRow {
  @Param label: string = ''
  @Param hint: string = ''
  @Param on: boolean = false
  @Event onChange: (v: boolean) => void = (v: boolean) => {}

  build() {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text(this.label)
          .fontSize(type.settingsRow.fontSize)
          .lineHeight(type.settingsRow.lineHeight)
          .fontWeight(type.settingsRow.fontWeight)
          .fontColor(appStore.theme.p.ink)
        if (this.hint !== '') {
          Text(this.hint)
            .fontSize(type.small.fontSize)
            .lineHeight(type.small.lineHeight)
            .fontColor(appStore.theme.p.ink3)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Toggle({ type: ToggleType.Switch, isOn: this.on })
        .selectedColor(appStore.theme.p.accent)
        .switchPointColor(appStore.theme.p.knob)
        .switchStyle({ unselectedColor: appStore.theme.p.line2, pointColor: appStore.theme.p.knob })
        .onChange((v: boolean) => this.onChange(v))
    }
    .constraintSize({ minHeight: 50 })
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
    .width('100%')
  }
}

// A back entry with the left chevron, for screens that lead deeper.
@ComponentV2
export struct BackRow {
  @Param label: string = ''
  @Event onBack: () => void = () => {}

  build() {
    Row({ space: 2 }) {
      Icon({ name: 'chevronLeft', iconSize: 20, color: appStore.theme.p.ink2 })
      if (this.label !== '') {
        Text(this.label)
          .fontSize(type.headerTitle.fontSize)
          .lineHeight(type.headerTitle.lineHeight)
          .fontWeight(type.headerTitle.fontWeight)
          .fontColor(appStore.theme.p.ink)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .constraintSize({ minHeight: 44 })
    .padding({ left: 10, right: 16 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => this.onBack())
  }
}

// A destructive row: the label arms into its "tap again" phrase, then confirms.
@ComponentV2
export struct DangerRow {
  @Param label: string = ''
  @Param confirmLabel: string = ''
  @Event onConfirm: () => void = () => {}

  build() {
    Column() {
      ConfirmDanger({ label: this.label, confirmLabel: this.confirmLabel, onConfirm: () => this.onConfirm() })
    }
    .constraintSize({ minHeight: 50 })
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Center)
  }
}

// A wrapping grid of pickable swatches (colors, themes): colored dot with a
// check when current, caption label below.
export interface PickItem {
  id: string
  label: string
  swatch: string
}

@ComponentV2
export struct PickGrid {
  @Param items: PickItem[] = []
  @Param value: string = ''
  @Param columns: number = 4
  @Event onPick: (id: string) => void = (id: string) => {}

  private isCurrent(item: PickItem): boolean {
    return item.id === this.value
  }

  private checkColor(item: PickItem): string {
    if (luminance(item.swatch) > 0.55) {
      return '#000000'
    }
    return '#ffffff'
  }

  private hairline(): number {
    return this.getUIContext().px2vp(1)
  }

  private cellWidth(): string {
    return `${Math.floor(100 / this.columns)}%`
  }

  @Builder
  pickItem(item: PickItem) {
    Column({ space: 4 }) {
      if (item.swatch !== '') {
        Stack() {
          Column()
            .width(36)
            .height(36)
            .borderRadius(18)
            .backgroundColor(item.swatch)
            .border({ width: this.hairline(), color: appStore.theme.p.line2 })
          if (this.isCurrent(item)) {
            Icon({ name: 'check', iconSize: 15, color: this.checkColor(item) })
          }
        }
      }
      Text(item.label)
        .fontSize(type.caption.fontSize)
        .lineHeight(type.caption.lineHeight)
        .fontWeight(type.caption.fontWeight)
        .fontColor(appStore.theme.p.ink2)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width(this.cellWidth())
    .padding({ top: 6, bottom: 6 })
    .alignItems(HorizontalAlign.Center)
    .onClick(() => this.onPick(item.id))
  }

  build() {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(this.items, (item: PickItem) => {
        this.pickItem(item)
      }, (item: PickItem) => item.id)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
  }
}
