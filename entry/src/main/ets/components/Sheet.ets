// Sheet chrome ported from mobile/src/nav/sheet.tsx.
// Sheet: pushed-screen wrapper (p.main background, full size — the NavDestination
// host already keeps content inside the safe area).
// SheetHeader: what it is in the middle (headerTitle), the way out on one side
// and the form's finishing action on the other (settingsRow text, sides min
// 72 / max 34%, row min 52, hairline bottom border).
// ConfirmDanger: the port of the desktop's destructive confirm — first tap arms
// the label into its "tap again" phrase, the second tap within 3s confirms.

import { appStore, type, Palette } from './Theme'

@Builder
function emptyBuilder() {
}

// SheetView (RN: Sheet) — renamed because ArkUI now ships a built-in Sheet
// component and struct names cannot collide with built-ins.
@ComponentV2
export struct SheetView {
  @BuilderParam content: () => void = emptyBuilder

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(appStore.theme.p.main)
  }
}

@ComponentV2
export struct SheetHeader {
  @Param title: string = ''
  @Param leftLabel: string = ''
  @Param leftDisabled: boolean = false
  @Param leftStrong: boolean = false
  @Event onLeft: () => void = () => {}
  @Param rightLabel: string = ''
  @Param rightDisabled: boolean = false
  @Param rightStrong: boolean = false
  @Event onRight: () => void = () => {}

  private hairline(): number {
    return this.getUIContext().px2vp(1)
  }

  private sideWidth(): string {
    return '34%'
  }

  private leftColor(): string {
    const p: Palette = appStore.theme.p
    if (this.leftDisabled) {
      return p.ink3
    }
    if (this.leftStrong) {
      return p.accent
    }
    return p.ink2
  }

  private rightColor(): string {
    const p: Palette = appStore.theme.p
    if (this.rightDisabled) {
      return p.ink3
    }
    if (this.rightStrong) {
      return p.accent
    }
    return p.ink2
  }

  private leftWeight(): string {
    if (this.leftStrong) {
      return '600'
    }
    return type.settingsRow.fontWeight
  }

  private rightWeight(): string {
    if (this.rightStrong) {
      return '600'
    }
    return type.settingsRow.fontWeight
  }

  @Builder
  leftSide() {
    Column({ space: 8 }) {
      if (this.leftLabel !== '') {
        Text(this.leftLabel)
          .fontSize(type.settingsRow.fontSize)
          .lineHeight(type.settingsRow.lineHeight)
          .fontWeight(this.leftWeight())
          .fontColor(this.leftColor())
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ minHeight: 44 })
          .onClick(() => this.tapLeft())
      }
    }
    .constraintSize({ minWidth: 72, maxWidth: this.sideWidth() })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  rightSide() {
    Column({ space: 8 }) {
      if (this.rightLabel !== '') {
        Text(this.rightLabel)
          .fontSize(type.settingsRow.fontSize)
          .lineHeight(type.settingsRow.lineHeight)
          .fontWeight(this.rightWeight())
          .fontColor(this.rightColor())
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ minHeight: 44 })
          .onClick(() => this.tapRight())
      }
    }
    .constraintSize({ minWidth: 72, maxWidth: this.sideWidth() })
    .alignItems(HorizontalAlign.End)
  }

  private tapLeft(): void {
    if (!this.leftDisabled) {
      this.onLeft()
    }
  }

  private tapRight(): void {
    if (!this.rightDisabled) {
      this.onRight()
    }
  }

  build() {
    Row({ space: 8 }) {
      this.leftSide()
      Text(this.title)
        .fontSize(type.headerTitle.fontSize)
        .lineHeight(type.headerTitle.lineHeight)
        .fontWeight(type.headerTitle.fontWeight)
        .fontColor(appStore.theme.p.ink)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .layoutWeight(1)
      this.rightSide()
    }
    .constraintSize({ minHeight: 52 })
    .padding({ left: 16, right: 16 })
    .width('100%')
    .border({ width: { bottom: this.hairline() }, color: appStore.theme.p.line })
  }
}

@ComponentV2
export struct ConfirmDanger {
  @Param label: string = ''
  @Param confirmLabel: string = ''
  @Event onConfirm: () => void = () => {}
  @Local armed: boolean = false
  private timerId: number = -1

  private armedText(): string {
    if (this.confirmLabel !== '') {
      return this.confirmLabel
    }
    return this.label
  }

  private tap(): void {
    if (this.armed) {
      this.clearTimer()
      this.armed = false
      this.onConfirm()
      return
    }
    this.armed = true
    this.clearTimer()
    this.timerId = setTimeout(() => {
      this.armed = false
      this.timerId = -1
    }, 3000)
  }

  private clearTimer(): void {
    if (this.timerId >= 0) {
      clearTimeout(this.timerId)
      this.timerId = -1
    }
  }

  aboutToDisappear(): void {
    this.clearTimer()
  }

  private displayText(): string {
    if (this.armed) {
      return this.armedText()
    }
    return this.label
  }

  private textColor(): ResourceColor {
    if (this.armed) {
      return '#ffffff'
    }
    return appStore.theme.p.danger
  }

  private bg(): ResourceColor {
    if (this.armed) {
      return appStore.theme.p.danger
    }
    return Color.Transparent
  }

  build() {
    Text(this.displayText())
      .fontSize(type.settingsRow.fontSize)
      .lineHeight(type.settingsRow.lineHeight)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.textColor())
      .backgroundColor(this.bg())
      .borderRadius(6)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .maxLines(2)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .onClick(() => this.tap())
  }
}
