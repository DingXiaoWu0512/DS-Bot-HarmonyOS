// The composer card: the port of mobile/src/screens/chat/composer.tsx. Min
// height 44 with radius 22 (18 once multi-line) and a level-1 shadow; send is a
// 36px accent circle that becomes Stop while the Bot runs and the draft is
// empty. "+" adds photos — picked several at once and shrunk on the phone to a
// 2048px long side as JPEG — each removable before the message goes.

import { appStore, type, radius, shadowOf, Palette } from '../../components/Theme'
import { t } from '../../common/ui/i18n'
import { Icon } from '../../components/Icon'
import { hapticLight, pickPhotos } from '../../platform/Platform'

// A photo ready to send: shown from `uri` (a data URI), sent as base64 JPEG.
export interface ComposerPhoto {
  uri: string
  mediaType: string
  data: string
}

@ComponentV2
export struct Composer {
  @Param name: string = ''
  @Param running: boolean = false
  @Param canStop: boolean = false
  @Param canAttach: boolean = false
  @Param bottomInset: number = 10
  @Event onSend: (text: string, photos: ComposerPhoto[]) => void =
    (_text: string, _photos: ComposerPhoto[]): void => {}
  @Event onStop: () => void = (): void => {}

  @Local text: string = ''
  @Local photos: ComposerPhoto[] = []
  @Local preparing: boolean = false
  @Local pickError: string = ''

  private p(): Palette {
    return appStore.theme.p
  }

  private ready(): boolean {
    return (this.text.trim() !== '' || this.photos.length > 0) && !this.preparing
  }

  private multi(): boolean {
    return this.text.includes('\n') || this.text.length > 80 || this.photos.length > 0
  }

  // The message shows in the chat at once; the composer is free for the next one.
  private send(): void {
    if (!this.ready()) {
      return
    }
    void hapticLight()
    const draft: string = this.text.trim()
    const sending: ComposerPhoto[] = this.photos
    this.text = ''
    this.photos = []
    this.onSend(draft, sending)
  }

  private pick(): void {
    this.pickError = ''
    this.preparing = true
    void pickPhotos((data: string): void => {
      const photo: ComposerPhoto = {
        uri: `data:image/jpeg;base64,${data}`,
        mediaType: 'image/jpeg',
        data: data,
      }
      this.photos = this.photos.concat([photo])
    }).then((): void => {
      this.preparing = false
    }).catch((): void => {
      this.preparing = false
      this.pickError = t('This is not a photo DS Bot can send')
    })
  }

  private removePhoto(photo: ComposerPhoto): void {
    this.photos = this.photos.filter((entry: ComposerPhoto): boolean => entry.uri !== photo.uri)
  }

  build() {
    Column() {
      if (this.pickError !== '') {
        Text(this.pickError)
          .fontSize(type.small.fontSize)
          .lineHeight(type.small.lineHeight)
          .fontColor(this.p().danger)
          .textAlign(TextAlign.Center)
          .margin({ bottom: 4 })
      }
      Column() {
        if (this.photos.length > 0 || this.preparing) {
          Scroll() {
            Row({ space: 8 }) {
              ForEach(this.photos, (photo: ComposerPhoto) => {
                Stack({ alignContent: Alignment.TopEnd }) {
                  Image(photo.uri)
                    .width(64)
                    .height(64)
                    .borderRadius(12)
                    .objectFit(ImageFit.Cover)
                    .backgroundColor(this.p().hover)
                  Column() {
                    Icon({ name: 'close', iconSize: 10, color: this.p().main })
                  }
                  .width(20)
                  .height(20)
                  .borderRadius(10)
                  .justifyContent(FlexAlign.Center)
                  .alignItems(HorizontalAlign.Center)
                  .backgroundColor(this.p().ink)
                  .offset({ x: 5, y: -5 })
                  .accessibilityText(t('Remove'))
                  .onClick((): void => this.removePhoto(photo))
                }
              }, (photo: ComposerPhoto): string => photo.uri)
              if (this.preparing) {
                Column() {
                  LoadingProgress()
                    .width(22)
                    .height(22)
                    .color(this.p().ink3)
                }
                .width(64)
                .height(64)
                .borderRadius(12)
                .backgroundColor(this.p().hover)
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
              }
            }
            .padding({ left: 6, right: 6, top: 6, bottom: 8 })
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
        }
        Row() {
          if (this.canAttach) {
            Column() {
              Icon({ name: 'plus', iconSize: 20, color: this.p().ink2 })
            }
            .width(36)
            .height(36)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .accessibilityText(t('Add photos'))
            .onClick((): void => this.pick())
          }
          TextArea({ text: this.text, placeholder: t('Message {name}', { 'name': this.name }) })
            .onChange((value: string): void => {
              this.text = value
            })
            .placeholderColor(this.p().ink3)
            .fontSize(type.bubble.fontSize)
            .fontColor(this.p().ink)
            .caretColor(this.p().accent)
            .backgroundColor('transparent')
            .padding({ top: 7, bottom: 7, left: this.canAttach ? 2 : 6, right: 6 })
            .constraintSize({ maxHeight: 130 })
            .layoutWeight(1)
            .accessibilityText(t('Message {name}', { 'name': this.name }))
          if (this.running && this.canStop && !this.ready()) {
            Column() {
              Icon({ name: 'stop', iconSize: 14 })
            }
            .width(36)
            .height(36)
            .borderRadius(18)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .backgroundColor(this.p().accent)
            .accessibilityText(t('Stop'))
            .onClick((): void => this.onStop())
          } else {
            Column() {
              Icon({ name: 'arrowUp', iconSize: 18 })
            }
            .width(36)
            .height(36)
            .borderRadius(18)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .backgroundColor(this.p().accent)
            .opacity(this.ready() ? 1 : 0.35)
            .accessibilityText(t('Send'))
            .onClick((): void => this.send())
          }
        }
        .alignItems(VerticalAlign.Bottom)
        .width('100%')
      }
      .padding({ left: 7.5, right: 7.5, top: 7.5, bottom: 7.5 })
      .borderRadius(this.multi() ? radius.composerLong : radius.composer)
      .border({ width: 0.5, color: this.p().line2 })
      .backgroundColor(this.p().card)
      .shadow(shadowOf(1))
      .margin({ left: 12, right: 12 })
    }
    .margin({ bottom: this.bottomInset })
  }
}
