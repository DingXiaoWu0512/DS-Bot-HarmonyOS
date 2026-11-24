// The composer card: the port of mobile/src/screens/chat/composer.tsx. Min
// height 44 with radius 22 (18 once multi-line) and a level-1 shadow; send is a
// 36px accent circle that becomes Stop while the Bot runs and the draft is
// empty. "+" opens the attach menu — photos and files, each shown by the host's
// capabilities; picked photos shrink on the phone to a 2048px long side as
// JPEG, picked files ride along as base64 up to the host's 10 MB cap — every
// draft entry removable before the message goes. In a group, typing "@"
// filters the members (and everyone) into the mention panel above the card.

import { appStore, type, radius, shadowOf, Palette } from '../../components/Theme'
import { t } from '../../common/ui/i18n'
import type { Bot } from '../../common/team/types'
import { Icon } from '../../components/Icon'
import { hapticLight, pickPhotos, pickFiles } from '../../platform/Platform'
import type { PickedFile } from '../../platform/Platform'
import { MentionPanel } from './MentionPanel'
import type { MentionCandidate } from './MentionPanel'

// A photo ready to send: shown from `uri` (a data URI), sent as base64 JPEG.
export interface ComposerPhoto {
  uri: string
  mediaType: string
  data: string
}

// A file ready to send: shown by name and size in the draft area, staged on the
// host through stage-file as base64 with its decoded byte count.
export interface ComposerFile {
  name: string
  bytes: number
  data: string
}

@ComponentV2
export struct Composer {
  @Param name: string = ''
  @Param running: boolean = false
  @Param canStop: boolean = false
  @Param canPhoto: boolean = false
  @Param canFile: boolean = false
  @Param inRoom: boolean = false
  @Param members: Bot[] = []
  @Param bottomInset: number = 10
  @Event onSend: (text: string, photos: ComposerPhoto[], files: ComposerFile[]) => void =
    (_text: string, _photos: ComposerPhoto[], _files: ComposerFile[]): void => {}
  @Event onStop: () => void = (): void => {}

  @Local text: string = ''
  @Local photos: ComposerPhoto[] = []
  @Local files: ComposerFile[] = []
  @Local preparing: boolean = false
  @Local pickError: string = ''
  @Local menuOpen: boolean = false
  @Local mentionOpen: boolean = false
  @Local mentionCandidates: MentionCandidate[] = []
  private areaController: TextAreaController = new TextAreaController()
  // The [@, caret) span a picked candidate replaces.
  private mentionAt: number = -1
  private mentionEnd: number = -1

  private p(): Palette {
    return appStore.theme.p
  }

  private canAttach(): boolean {
    return this.canPhoto || this.canFile
  }

  private ready(): boolean {
    return (this.text.trim() !== '' || this.photos.length > 0 || this.files.length > 0) && !this.preparing
  }

  private multi(): boolean {
    return this.text.includes('\n') || this.text.length > 80
      || this.photos.length > 0 || this.files.length > 0
  }

  // The message shows in the chat at once; the composer is free for the next one.
  private send(): void {
    if (!this.ready()) {
      return
    }
    void hapticLight()
    const draft: string = this.text.trim()
    const sending: ComposerPhoto[] = this.photos
    const sendingFiles: ComposerFile[] = this.files
    this.text = ''
    this.photos = []
    this.files = []
    this.menuOpen = false
    this.closeMention()
    this.onSend(draft, sending, sendingFiles)
  }

  private pickPhoto(): void {
    this.pickError = ''
    this.menuOpen = false
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

  private pickFile(): void {
    this.pickError = ''
    this.menuOpen = false
    this.preparing = true
    void pickFiles((file: PickedFile): void => {
      const entry: ComposerFile = { name: file.name, bytes: file.bytes, data: file.data }
      this.files = this.files.concat([entry])
    }, (name: string): void => {
      this.pickError = `${name} · ${t('This file is over 10 MB')}`
    }).then((): void => {
      this.preparing = false
    }).catch((): void => {
      this.preparing = false
    })
  }

  private removeFile(index: number): void {
    const next: ComposerFile[] = this.files.slice()
    next.splice(index, 1)
    this.files = next
  }

  private removePhoto(photo: ComposerPhoto): void {
    this.photos = this.photos.filter((entry: ComposerPhoto): boolean => entry.uri !== photo.uri)
  }

  // "+" with both channels opens the little attach menu; with one it runs that
  // channel at once.
  private plusTap(): void {
    if (this.canPhoto && this.canFile) {
      this.menuOpen = !this.menuOpen
      return
    }
    if (this.canPhoto) {
      this.pickPhoto()
      return
    }
    if (this.canFile) {
      this.pickFile()
    }
  }

  // A byte count the draft rows show: B, then KB and MB to one decimal.
  private sizeLabel(bytes: number): string {
    if (bytes < 1024) return `${bytes} B`
    if (bytes < 1024 * 1024) return `${Math.round(bytes / 102.4) / 10} KB`
    return `${Math.round(bytes / 104857.6) / 10} MB`
  }

  // ---- @ mentions -----------------------------------------------------------

  private closeMention(): void {
    this.mentionOpen = false
    this.mentionCandidates = []
    this.mentionAt = -1
    this.mentionEnd = -1
  }

  // The mention token at the caret: '@' followed by non-blank characters, the
  // '@' itself at a line start or after whitespace — the host's own mention
  // rule, so whatever the panel inserts the host can parse. Private chats and
  // groups without members never open it.
  private updateMention(): void {
    if (!this.inRoom || this.members.length === 0) {
      this.closeMention()
      return
    }
    const caretOffset: CaretOffset = this.areaController.getCaretOffset()
    const caret: number = caretOffset.index
    const text: string = this.text
    if (caret <= 0 || caret > text.length) {
      this.closeMention()
      return
    }
    let start: number = caret
    while (start > 0 && !/\s/.test(text.charAt(start - 1))) {
      start -= 1
    }
    const token: string = text.substring(start, caret)
    if (!token.startsWith('@')) {
      this.closeMention()
      return
    }
    const query: string = token.substring(1)
    const lower: string = query.toLowerCase()
    const out: MentionCandidate[] = []
    for (const bot of this.members) {
      if (bot.name.toLowerCase().startsWith(lower)) {
        out.push({ name: bot.name, title: bot.name, role: bot.role, botId: bot.id, isAll: false })
      }
    }
    const allWord: string = t('everyone')
    if (lower === '' || allWord.startsWith(query) || 'everyone'.startsWith(lower)) {
      out.push({ name: allWord, title: allWord, isAll: true })
    }
    if (out.length === 0) {
      this.closeMention()
      return
    }
    this.mentionAt = start
    this.mentionEnd = caret
    this.mentionCandidates = out
    this.mentionOpen = true
  }

  // The picked candidate replaces [@, caret) with "@name " through the state
  // text (never the controller's mutating calls, which would fight the input
  // method); the caret lands right after the inserted mention.
  private pickMention(candidate: MentionCandidate): void {
    const at: number = this.mentionAt
    const end: number = this.mentionEnd
    const text: string = this.text
    if (at < 0 || end < at || end > text.length) {
      this.closeMention()
      return
    }
    const inserted: string = `@${candidate.name} `
    this.text = text.substring(0, at) + inserted + text.substring(end)
    this.closeMention()
    const caret: number = at + inserted.length
    setTimeout((): void => {
      this.areaController.caretPosition(caret)
    }, 50)
  }

  // Another chat, another member set: whatever the panel held is stale.
  @Monitor('inRoom', 'members')
  onRoomChange(): void {
    this.closeMention()
  }

  // A different chat means the draft was written for somewhere else: nothing
  // picked or typed carries over (a picker still in flight resolves on its
  // own into the cleared state).
  @Monitor('name')
  onNameChange(): void {
    this.text = ''
    this.photos = []
    this.files = []
    this.pickError = ''
    this.menuOpen = false
    this.closeMention()
  }

  // The attach menu, floating above the "+" button: only when both channels
  // exist (a single channel runs at once, no menu). Drawn as an overlay on
  // the input row — aligned to its bottom-start and lifted 100vp — so the
  // menu never takes part in the card's own layout.
  @Builder
  attachMenu() {
    if (this.menuOpen && this.canPhoto && this.canFile) {
      Column() {
        Row() {
          Text(t('Photos'))
            .fontSize(type.rowPreview.fontSize)
            .lineHeight(type.rowPreview.lineHeight)
            .fontColor(this.p().ink)
        }
        .height(44)
        .alignItems(VerticalAlign.Center)
        .padding({ left: 16, right: 16 })
        .width('100%')
        .accessibilityText(t('Add photos'))
        .onClick((): void => this.pickPhoto())
        Row() {
          Text(t('File'))
            .fontSize(type.rowPreview.fontSize)
            .lineHeight(type.rowPreview.lineHeight)
            .fontColor(this.p().ink)
        }
        .height(44)
        .alignItems(VerticalAlign.Center)
        .padding({ left: 16, right: 16 })
        .width('100%')
        .accessibilityText(t('Add file'))
        .onClick((): void => this.pickFile())
      }
      .width(140)
      .borderRadius(radius.dialog)
      .border({ width: 0.5, color: this.p().line2 })
      .backgroundColor(this.p().card)
      .shadow(shadowOf(2))
      .offset({ x: 0, y: -100 })
    }
  }

  build() {
    Column() {
      if (this.mentionOpen && this.mentionCandidates.length > 0) {
        MentionPanel({
          candidates: this.mentionCandidates,
          onPick: (candidate: MentionCandidate): void => this.pickMention(candidate),
        })
      }
      if (this.pickError !== '') {
        Text(this.pickError)
          .fontSize(type.small.fontSize)
          .lineHeight(type.small.lineHeight)
          .fontColor(this.p().danger)
          .textAlign(TextAlign.Center)
          .margin({ bottom: 4, left: 16, right: 16 })
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
        if (this.files.length > 0) {
          Column() {
            ForEach(this.files, (file: ComposerFile, index: number) => {
              Row({ space: 8 }) {
                Column({ space: 1 }) {
                  Text(file.name)
                    .fontSize(type.small.fontSize)
                    .lineHeight(type.small.lineHeight)
                    .fontWeight('500')
                    .fontColor(this.p().ink)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(this.sizeLabel(file.bytes))
                    .fontSize(type.caption.fontSize)
                    .lineHeight(type.caption.lineHeight)
                    .fontColor(this.p().ink3)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Column() {
                  Icon({ name: 'close', iconSize: 10, color: this.p().ink2 })
                }
                .width(26)
                .height(26)
                .borderRadius(13)
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
                .backgroundColor(this.p().hover)
                .accessibilityText(t('Remove'))
                .onClick((): void => this.removeFile(index))
              }
              .alignItems(VerticalAlign.Center)
              .width('100%')
              .padding({ left: 8, right: 4, top: 5, bottom: 5 })
            }, (file: ComposerFile, index: number): string => `${index}-${file.name}-${file.bytes}`)
          }
          .width('100%')
          .padding({ left: 6, right: 6 })
        }
        Stack({ alignContent: Alignment.BottomStart }) {
          Row() {
            if (this.canAttach()) {
              Column() {
                Icon({ name: 'plus', iconSize: 20, color: this.p().ink2 })
              }
              .width(36)
              .height(36)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              .accessibilityText(this.canFile && !this.canPhoto ? t('Add file') : t('Add photos'))
              .onClick((): void => this.plusTap())
            }
            TextArea({
              text: this.text,
              placeholder: t('Message {name}', { 'name': this.name }),
              controller: this.areaController,
            })
              .onChange((value: string): void => {
                this.text = value
                this.updateMention()
              })
              .placeholderColor(this.p().ink3)
              .fontSize(type.bubble.fontSize)
              .fontColor(this.p().ink)
              .caretColor(this.p().accent)
              .backgroundColor('transparent')
              .padding({ top: 7, bottom: 7, left: this.canAttach() ? 2 : 6, right: 6 })
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
          // The attach menu floats over the "+" button as an overlay: an
          // overlay never joins the card's layout, so opening the menu
          // cannot stretch the card or push the input row down.
          .overlay(this.attachMenu, { align: Alignment.BottomStart })
        }
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
