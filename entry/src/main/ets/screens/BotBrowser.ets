// The Bot browser takeover (manage.tsx BotBrowser): the Bot's browser frame
// streams as base64 every couple of seconds while the screen is up, with the
// page title and URL under it and the handoff actions — Done/Skip while the
// Bot waits for the user, Give back / Take over, and Stop.

import { appStore, type, radius } from '../components/Theme'
import { t } from '../common/ui/i18n'
import { BackRow } from '../components/FormControls'
import type { TeamState } from '../common/team/types'
import { readStringParam } from './routes'

interface BrowserFrameReply {
  mime?: string
  data?: string
  url?: string
  title?: string
}

interface BrowserFramePayload {
  botId: string
}

interface BrowserActPayload {
  botId: string
  outcome?: string
  callId?: string
}

interface CodedError {
  code?: string
}

const POLL_MS = 2000

@ComponentV2
export struct BotBrowser {
  @Local pathStack: NavPathStack | null = null
  @Local botId: string = ''
  @Local frameUri: string = ''
  @Local frameTitle: string = ''
  @Local frameUrl: string = ''
  @Local error: string = ''
  @Local refreshTick: number = 0
  private pollTimer: number = -1

  private team(): TeamState | null {
    void this.refreshTick
    return appStore.link.team
  }

  private holdNote(): string {
    const hold = this.team()?.browserHolds?.[this.botId]
    return hold?.note ?? ''
  }

  private holdCallId(): string {
    const hold = this.team()?.browserHolds?.[this.botId]
    return hold?.callId ?? ''
  }

  private holdByUser(): boolean {
    const hold = this.team()?.browserHolds?.[this.botId]
    return hold?.by === 'user'
  }

  // A host with Bot browsers off has nothing to take over or stop.
  private actionsVisible(): boolean {
    return this.team()?.browser !== false
  }

  private hairline(): number {
    return this.getUIContext().px2vp(1)
  }

  private goBack(): void {
    if (this.pathStack !== null) this.pathStack.pop()
  }

  private async refresh(): Promise<void> {
    const controller = appStore.link.controller
    if (controller === null) return
    const payload: BrowserFramePayload = { botId: this.botId }
    try {
      const reply = (await controller.call('browser-frame', payload)) as BrowserFrameReply | null
      if (reply !== null && reply !== undefined && (reply.data ?? '') !== '') {
        this.frameUri = `data:${reply.mime ?? 'image/png'};base64,${reply.data}`
        this.frameTitle = reply.title ?? ''
        this.frameUrl = reply.url ?? ''
      } else {
        this.frameUri = ''
        this.frameTitle = ''
        this.frameUrl = ''
      }
      this.error = ''
    } catch (failure) {
      this.frameUri = ''
      this.frameTitle = ''
      this.frameUrl = ''
      if ((failure as CodedError)?.code === 'bot/not-found') {
        this.error = t('This Bot has no open browser')
      } else {
        this.error = failure instanceof Error ? failure.message : String(failure)
      }
    }
  }

  private setPolling(active: boolean): void {
    if (active && this.pollTimer < 0) {
      this.pollTimer = setInterval((): void => {
        void this.refresh()
      }, POLL_MS)
    } else if (!active && this.pollTimer >= 0) {
      clearInterval(this.pollTimer)
      this.pollTimer = -1
    }
  }

  aboutToDisappear(): void {
    this.setPolling(false)
  }

  // Every action refreshes the frame right away.
  private act(endpoint: string, payload: BrowserActPayload): void {
    const controller = appStore.link.controller
    if (controller === null) return
    void controller.call(endpoint, payload).catch((): void => {}).then((): void => {
      void this.refresh()
    })
  }

  private actPayload(outcome?: string, callId?: string): BrowserActPayload {
    const payload: BrowserActPayload = { botId: this.botId }
    if (outcome !== undefined) payload.outcome = outcome
    if (callId !== undefined) payload.callId = callId
    return payload
  }

  build() {
    NavDestination() {
      Column() {
        BackRow({
          label: t('Browser'),
          onBack: (): void => this.goBack(),
        })
        Scroll() {
          Column() {
            if (this.frameUri !== '') {
              Image(this.frameUri)
                .width('100%')
                .aspectRatio(0.62)
                .objectFit(ImageFit.Contain)
                .borderRadius(radius.card)
                .backgroundColor(appStore.theme.p.hover)
            }
            if (this.frameTitle !== '') {
              Text(this.frameTitle)
                .fontSize(type.settingsRow.fontSize)
                .lineHeight(type.settingsRow.lineHeight)
                .fontColor(appStore.theme.p.ink)
                .width('100%')
                .margin({ top: 10 })
            }
            if (this.frameUrl !== '') {
              Text(this.frameUrl)
                .fontSize(type.small.fontSize)
                .lineHeight(type.small.lineHeight)
                .fontColor(appStore.theme.p.ink3)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
                .margin({ top: 2 })
            }
            if (this.error !== '') {
              Text(this.error)
                .fontSize(type.small.fontSize)
                .lineHeight(type.small.lineHeight)
                .fontColor(appStore.theme.p.danger)
                .width('100%')
                .margin({ top: 12 })
            }
            if (this.holdNote() !== '') {
              Text(this.holdNote())
                .fontSize(type.small.fontSize)
                .lineHeight(type.small.lineHeight)
                .fontColor(appStore.theme.p.ink2)
                .width('100%')
                .margin({ top: 12 })
            }
            if (this.actionsVisible()) {
              Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
                if (this.holdCallId() !== '') {
                  Column() {
                    Text(t('Done'))
                      .fontSize(type.settingsRow.fontSize)
                      .lineHeight(type.settingsRow.lineHeight)
                      .fontWeight('600')
                      .fontColor(appStore.theme.p.accentInk)
                  }
                  .borderRadius(20)
                  .padding({ left: 18, right: 18, top: 8, bottom: 8 })
                  .constraintSize({ minHeight: 40 })
                  .backgroundColor(appStore.theme.p.accent)
                  .justifyContent(FlexAlign.Center)
                  .alignItems(HorizontalAlign.Center)
                  .margin({ right: 10, bottom: 10 })
                  .onClick(() => this.act('browser-give-back', this.actPayload('done', this.holdCallId())))
                  Column() {
                    Text(t('Skip'))
                      .fontSize(type.settingsRow.fontSize)
                      .lineHeight(type.settingsRow.lineHeight)
                      .fontColor(appStore.theme.p.ink)
                  }
                  .borderRadius(20)
                  .padding({ left: 18, right: 18, top: 8, bottom: 8 })
                  .constraintSize({ minHeight: 40 })
                  .backgroundColor(appStore.theme.p.hover)
                  .justifyContent(FlexAlign.Center)
                  .alignItems(HorizontalAlign.Center)
                  .margin({ right: 10, bottom: 10 })
                  .onClick(() => this.act('browser-give-back', this.actPayload('skip', this.holdCallId())))
                } else if (this.holdByUser()) {
                  Column() {
                    Text(t('Give back'))
                      .fontSize(type.settingsRow.fontSize)
                      .lineHeight(type.settingsRow.lineHeight)
                      .fontWeight('600')
                      .fontColor(appStore.theme.p.accentInk)
                  }
                  .borderRadius(20)
                  .padding({ left: 18, right: 18, top: 8, bottom: 8 })
                  .constraintSize({ minHeight: 40 })
                  .backgroundColor(appStore.theme.p.accent)
                  .justifyContent(FlexAlign.Center)
                  .alignItems(HorizontalAlign.Center)
                  .margin({ right: 10, bottom: 10 })
                  .onClick(() => this.act('browser-give-back', this.actPayload()))
                } else {
                  Column() {
                    Text(t('Take over'))
                      .fontSize(type.settingsRow.fontSize)
                      .lineHeight(type.settingsRow.lineHeight)
                      .fontColor(appStore.theme.p.ink)
                  }
                  .borderRadius(20)
                  .padding({ left: 18, right: 18, top: 8, bottom: 8 })
                  .constraintSize({ minHeight: 40 })
                  .backgroundColor(appStore.theme.p.hover)
                  .justifyContent(FlexAlign.Center)
                  .alignItems(HorizontalAlign.Center)
                  .margin({ right: 10, bottom: 10 })
                  .onClick(() => this.act('browser-takeover', this.actPayload()))
                }
                Column() {
                  Text(t('Stop'))
                    .fontSize(type.settingsRow.fontSize)
                    .lineHeight(type.settingsRow.lineHeight)
                    .fontColor(appStore.theme.p.danger)
                }
                .borderRadius(20)
                .padding({ left: 18, right: 18, top: 8, bottom: 8 })
                .constraintSize({ minHeight: 40 })
                .backgroundColor(appStore.theme.p.hover)
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
                .margin({ bottom: 10 })
                .onClick(() => this.act('browser-stop', this.actPayload()))
              }
              .width('100%')
              .margin({ top: 16 })
            }
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 14, bottom: appStore.safeBottom + 14 })
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(appStore.theme.p.main)
    }
    .hideTitleBar(true)
    .padding({ top: appStore.safeTop })
    .backgroundColor(appStore.theme.p.main)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack
      this.botId = readStringParam(ctx.pathInfo.param, 'botId')
    })
    .onShown(() => {
      // Frames stream only while the screen is up.
      void this.refresh()
      this.setPolling(true)
    })
    .onHidden(() => {
      this.setPolling(false)
    })
  }
}

@Builder
export function BotBrowserBuilder() {
  BotBrowser()
}
