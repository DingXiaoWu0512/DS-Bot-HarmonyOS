// Pair screen (US1): port of mobile/src/screens/Pair.tsx — guide text, the
// system QR scanner behind 「使用相机」, a paste-the-link field with a 「配对」
// button, and busy/error feedback with retry. The host mounts it as the
// unpaired boot gate or as the dsbot://pair overlay (T016); it is never
// route-pushed (plan: Pair 不入栈).

import { common } from '@kit.AbilityKit'

import { appStore, type, radius, Palette } from '../components/Theme'
import { t } from '../common/ui/i18n'
import { launchScanner } from '../platform/Platform'
import { parsePairingUri } from '../common/link/pairing'
import { openLink, errorText } from '../common/team/team-link'
import { addComputer, type PhoneIdentity, type SavedComputer } from '../common/team/store-core'
import { RpcClient } from '../common/link/rpc-client'

@ComponentV2
export struct Pair {
  @Require @Param identity: PhoneIdentity
  @Param offer: string | null = null
  @Param cancellable: boolean = false
  @Event onPaired: (computer: SavedComputer) => void = (_computer: SavedComputer) => {}
  @Event onCancel: () => void = () => {}
  @Local link: string = ''
  @Local busy: boolean = false
  @Local error: string | null = null
  private busyNow: boolean = false

  aboutToAppear(): void {
    // A deep link that arrives with the screen (cold start) pairs at once.
    if (this.offer !== null && this.offer !== '') {
      this.link = this.offer
      void this.pair(this.offer)
    }
  }

  @Monitor('offer')
  onOffer(): void {
    // A deep link that arrives while the screen is up (warm start).
    if (this.offer === null || this.offer === '') return
    this.link = this.offer
    void this.pair(this.offer)
  }

  private pairDisabled(): boolean {
    return this.busy || this.link.trim() === ''
  }

  private async scan(): Promise<void> {
    if (this.busyNow) return
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    const uri = await launchScanner(context)
    if (uri === null || uri === '') return
    this.link = uri
    await this.pair(uri)
  }

  private async pair(uri: string): Promise<void> {
    if (this.busyNow) return
    this.busyNow = true
    this.busy = true
    this.error = null
    try {
      const offer = parsePairingUri(uri.trim())
      // Validate the link end to end before saving: connect, then hang up.
      const candidate: SavedComputer = {
        server: offer.server,
        hostDeviceId: offer.hostDeviceId,
        hostKey: offer.hostKey,
        name: offer.name,
      }
      const client: RpcClient = await openLink(candidate, this.identity, offer.code)
      await client.close()
      this.onPaired(await addComputer(offer))
    } catch (failure) {
      this.error = errorText(failure)
    }
    this.busyNow = false
    this.busy = false
  }

  build() {
    Scroll() {
      Column() {
        Text(t('Pair with your computer'))
          .fontSize(type.largeTitle.fontSize)
          .lineHeight(type.largeTitle.lineHeight)
          .fontWeight(type.largeTitle.fontWeight)
          .fontColor(appStore.theme.p.ink)
          .textAlign(TextAlign.Center)
        Text(t('On the computer, open DS Bot, go to Settings → Phone and show a QR code. Then scan it here.'))
          .fontSize(type.settingsRow.fontSize)
          .lineHeight(type.settingsRow.lineHeight)
          .fontWeight(type.settingsRow.fontWeight)
          .fontColor(appStore.theme.p.ink2)
          .textAlign(TextAlign.Center)
          .margin({ top: 12 })
        Column() {
          Button(t('Use the camera'))
            .fontSize(type.settingsRow.fontSize)
            .fontWeight('600')
            .fontColor(appStore.theme.p.accentInk)
            .backgroundColor(appStore.theme.p.accent)
            .height(44)
            .borderRadius(radius.pill)
            .padding({ left: 18, right: 18 })
            .onClick(() => {
              void this.scan()
            })
        }
        .width(260)
        .constraintSize({ maxWidth: '100%' })
        .height(260)
        .backgroundColor(appStore.theme.p.sidebar)
        .borderRadius(radius.card)
        .border({
          width: this.getUIContext().px2vp(1),
          color: appStore.theme.p.line,
        })
        .clip(true)
        .justifyContent(FlexAlign.Center)
        .margin({ top: 20 })
        Text(t('No camera? Paste the pairing link.'))
          .fontSize(type.settingsRow.fontSize)
          .lineHeight(type.settingsRow.lineHeight)
          .fontWeight(type.settingsRow.fontWeight)
          .fontColor(appStore.theme.p.ink2)
          .textAlign(TextAlign.Center)
          .margin({ top: 16 })
        Row({ space: 8 }) {
          TextInput({ text: this.link, placeholder: 'dsbot://pair?…' })
            .layoutWeight(1)
            .height(44)
            .backgroundColor(appStore.theme.p.hover)
            .borderRadius(radius.input)
            .padding({ left: 12, right: 12 })
            .fontSize(16)
            .fontColor(appStore.theme.p.ink)
            .placeholderColor(appStore.theme.p.ink3)
            .onChange((value: string) => {
              this.link = value
            })
            .onSubmit((enterKey: EnterKeyType) => {
              if (this.link.trim() !== '') {
                void this.pair(this.link)
              }
            })
          Button(t('Pair'))
            .fontSize(type.settingsRow.fontSize)
            .fontWeight('600')
            .fontColor(appStore.theme.p.accentInk)
            .backgroundColor(appStore.theme.p.accent)
            .height(44)
            .borderRadius(radius.pill)
            .padding({ left: 18, right: 18 })
            .enabled(!this.pairDisabled())
            .opacity(this.pairDisabled() ? 0.35 : 1)
            .onClick(() => {
              if (!this.pairDisabled()) {
                void this.pair(this.link)
              }
            })
        }
        .width('100%')
        .margin({ top: 12 })
        if (this.busy) {
          LoadingProgress()
            .width(28)
            .height(28)
            .color(appStore.theme.p.accent)
            .margin({ top: 20 })
        }
        if (this.error !== null) {
          Text(this.error)
            .fontSize(type.settingsRow.fontSize)
            .lineHeight(type.settingsRow.lineHeight)
            .fontWeight(type.settingsRow.fontWeight)
            .fontColor(appStore.theme.p.danger)
            .textAlign(TextAlign.Center)
            .margin({ top: 12 })
        }
        if (this.cancellable) {
          Text(t('Cancel'))
            .fontSize(type.settingsRow.fontSize)
            .lineHeight(type.settingsRow.lineHeight)
            .fontWeight(type.settingsRow.fontWeight)
            .fontColor(appStore.theme.p.ink2)
            .textAlign(TextAlign.Center)
            .constraintSize({ minHeight: 44 })
            .margin({ top: 20 })
            .onClick(() => this.onCancel())
        }
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
      .justifyContent(FlexAlign.Center)
      .padding({ left: 24, right: 24, top: 24, bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .backgroundColor(appStore.theme.p.main)
  }
}
