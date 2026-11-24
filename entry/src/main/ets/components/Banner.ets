// The top notice banner ported from mobile/src/nav/ShellB.tsx (NoticeBanner).
// A question, approval, message, group or done notice that lands while the app
// is open shows at the top; a tap opens the chat it belongs to, and it
// dismisses itself after 8 seconds. The host supplies the current notice (from
// the team feed, gated by the banner preference and the chat on screen), the
// status-bar inset, and wires the open/dismiss events to navigation and its
// own notice state.

import { appStore, type, radius, shadowOf } from './Theme'

export class BannerNotice {
  text: string
  kind: string
  targetId: string

  constructor(text: string, kind: string, targetId: string) {
    this.text = text
    this.kind = kind
    this.targetId = targetId
  }
}

@ComponentV2
export struct Banner {
  @Param notice: BannerNotice | undefined = undefined
  @Param topInset: number = 0
  @Event onOpen: (notice: BannerNotice) => void = (notice: BannerNotice) => {}
  @Event onDismiss: () => void = () => {}
  private timerId: number = -1

  aboutToAppear(): void {
    this.restartTimer()
  }

  aboutToDisappear(): void {
    this.clearTimer()
  }

  @Monitor('notice')
  onNoticeChange(monitor: IMonitor): void {
    this.restartTimer()
  }

  private restartTimer(): void {
    this.clearTimer()
    if (this.notice !== undefined) {
      this.timerId = setTimeout(() => {
        this.timerId = -1
        this.onDismiss()
      }, 8000)
    }
  }

  private clearTimer(): void {
    if (this.timerId >= 0) {
      clearTimeout(this.timerId)
      this.timerId = -1
    }
  }

  private noticeText(): string {
    const n = this.notice
    if (n !== undefined) {
      return n.text
    }
    return ''
  }

  private tap(): void {
    const n = this.notice
    if (n !== undefined) {
      this.onOpen(n)
    }
  }

  build() {
    if (this.notice !== undefined) {
      Column() {
        Text(this.noticeText())
          .width('100%')
          .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .borderRadius(radius.card)
          .backgroundColor(appStore.theme.p.card)
          .border({ width: 1, color: appStore.theme.p.accent })
          .shadow(shadowOf(2))
          .fontSize(type.small.fontSize)
          .lineHeight(type.small.lineHeight)
          .fontWeight(type.small.fontWeight)
          .fontColor(appStore.theme.p.ink)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .onClick(() => this.tap())
          // The covering Column passes touches through (HitTestMode.None) so
          // the chat below stays reachable; this card blocks the pass-through
          // so its own tap lands (faqs-arkui-1052, scenario one).
          .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Center)
      .padding({ left: 12, right: 12, top: this.topInset + 8 })
      .hitTestBehavior(HitTestMode.None)
    } else {
      Stack()
    }
  }
}
