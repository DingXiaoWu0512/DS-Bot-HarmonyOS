// The memory panel (mobile/src/screens/manage.tsx Memory): the summary line,
// an ask box that answers from memory, the entry list with edit and forget,
// and the add/edit dialog. Reads and writes go through memory-view / memory-ask
// / memory-add / memory-edit / memory-forget.

import { appStore, type, radius } from '../components/Theme'
import { t } from '../common/ui/i18n'
import { memorySummaryText } from '../common/team/state-utils'
import { Icon } from '../components/Icon'
import { FormSection, BackRow } from '../components/FormControls'
import { readStringParam } from './routes'

interface MemoryEntry {
  scope: string
  topic?: string | null
  text: string
  added?: string | null
  by?: string | null
  source?: string | null
}

interface MemoryViewReply {
  summary?: Object | null
  entries?: MemoryEntry[]
  error?: string | null
}

interface MemoryOwnerPayload {
  botId?: string
  roomId?: string
  scope?: string
  topic?: string | null
  text?: string
  next?: string
}

interface MemoryAskPayload {
  botId?: string
  roomId?: string
  text: string
}

interface MemoryAskReply {
  reply?: string
  view?: MemoryViewReply | null
}

@ComponentV2
export struct Memory {
  @Local pathStack: NavPathStack | null = null
  @Local botId: string = ''
  @Local roomId: string = ''
  @Local refreshTick: number = 0
  @Local view: MemoryViewReply | null = null
  @Local question: string = ''
  @Local asking: boolean = false
  @Local answer: string = ''
  @Local editing: boolean = false
  @Local editIndex: number = -1
  @Local editScope: string = 'own'
  @Local editTopic: string = ''
  @Local editText: string = ''
  @Local armedDelete: number = -1
  private deleteTimer: number = -1

  private goBack(): void {
    if (this.pathStack !== null) this.pathStack.pop()
  }

  private isGroup(): boolean {
    return this.roomId !== ''
  }

  private owner(): MemoryOwnerPayload {
    if (this.isGroup()) {
      return { roomId: this.roomId }
    }
    return { botId: this.botId }
  }

  private summary(): string {
    void this.refreshTick
    return memorySummaryText(this.view?.summary ?? null) ?? ''
  }

  private entries(): MemoryEntry[] {
    return this.view?.entries ?? []
  }

  private hairline(): number {
    return this.getUIContext().px2vp(1)
  }

  private async load(): Promise<void> {
    const controller = appStore.link.controller
    if (controller === null) return
    try {
      const reply = (await controller.call('memory-view', this.owner())) as MemoryViewReply | null
      this.view = reply
    } catch {
      // The list stays as it was.
    }
  }

  private async ask(): Promise<void> {
    if (this.question.trim() === '' || this.asking) return
    this.asking = true
    const payload: MemoryAskPayload = { botId: this.owner().botId, roomId: this.owner().roomId, text: this.question.trim() }
    const controller = appStore.link.controller
    if (controller === null) {
      this.asking = false
      return
    }
    try {
      const value = (await controller.call('memory-ask', payload)) as MemoryAskReply | null
      this.asking = false
      if (value !== null && value !== undefined) {
        this.answer = typeof value.reply === 'string' ? value.reply : ''
        if (value.view !== undefined && value.view !== null) this.view = value.view
      }
    } catch {
      this.asking = false
    }
  }

  // First tap arms the ×, the second tap within 3s forgets the entry.
  private tapDelete(index: number): void {
    if (this.armedDelete === index) {
      this.clearTimer()
      this.armedDelete = -1
      void this.forget(index)
      return
    }
    this.armedDelete = index
    this.clearTimer()
    this.deleteTimer = setTimeout(() => {
      this.armedDelete = -1
      this.deleteTimer = -1
    }, 3000)
  }

  private clearTimer(): void {
    if (this.deleteTimer >= 0) {
      clearTimeout(this.deleteTimer)
      this.deleteTimer = -1
    }
  }

  aboutToDisappear(): void {
    this.clearTimer()
  }

  private async forget(index: number): Promise<void> {
    const entry = this.entries()[index]
    if (entry === undefined) return
    const payload: MemoryOwnerPayload = {
      botId: this.owner().botId,
      roomId: this.owner().roomId,
      scope: entry.scope,
      topic: entry.topic ?? null,
      text: entry.text,
    }
    const controller = appStore.link.controller
    if (controller === null) return
    try {
      await controller.call('memory-forget', payload)
      await this.load()
    } catch {
      // The list stays as it was.
    }
  }

  private openEditor(index: number): void {
    const entry = this.entries()[index]
    this.editIndex = index
    this.editScope = entry !== undefined ? entry.scope : 'own'
    this.editTopic = entry !== undefined ? (entry.topic ?? '') : ''
    this.editText = entry !== undefined ? entry.text : ''
    this.editing = true
  }

  private closeEditor(): void {
    this.editing = false
  }

  private async saveEditor(): Promise<void> {
    if (this.editText.trim() === '') {
      this.closeEditor()
      return
    }
    const existing = this.editIndex >= 0 ? this.entries()[this.editIndex] : undefined
    const controller = appStore.link.controller
    if (controller === null) {
      this.closeEditor()
      return
    }
    if (existing === undefined) {
      const payload: MemoryOwnerPayload = {
        botId: this.owner().botId,
        roomId: this.owner().roomId,
        scope: this.editScope,
        topic: this.editTopic.trim() !== '' ? this.editTopic.trim() : null,
        text: this.editText.trim(),
      }
      this.closeEditor()
      try {
        await controller.call('memory-add', payload)
        await this.load()
      } catch {
        // The list stays as it was.
      }
    } else {
      const payload: MemoryOwnerPayload = {
        botId: this.owner().botId,
        roomId: this.owner().roomId,
        scope: this.editScope,
        topic: this.editTopic.trim() !== '' ? this.editTopic.trim() : null,
        text: existing.text,
        next: this.editText.trim(),
      }
      this.closeEditor()
      try {
        await controller.call('memory-edit', payload)
        await this.load()
      } catch {
        // The list stays as it was.
      }
    }
  }

  private metaOf(entry: MemoryEntry): string {
    const parts: string[] = []
    if (entry.added !== undefined && entry.added !== null && entry.added !== '') parts.push(entry.added)
    if (entry.source === 'memory panel') {
      parts.push(t('by you'))
    } else if (entry.by !== undefined && entry.by !== null && entry.by !== '') {
      parts.push(t('by {name}', { 'name': entry.by }))
    }
    return parts.join(' · ')
  }

  private deleteColor(): string {
    if (this.armedDelete >= 0) {
      return appStore.theme.p.danger
    }
    return appStore.theme.p.ink3
  }

  @Builder
  entryRow(entry: MemoryEntry, index: number) {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        if ((entry.topic ?? '') !== '') {
          Text(entry.topic ?? '')
            .fontSize(type.small.fontSize)
            .lineHeight(type.small.lineHeight)
            .fontColor(appStore.theme.p.ink3)
        }
        Text(entry.text)
          .fontSize(type.settingsRow.fontSize)
          .lineHeight(type.settingsRow.lineHeight)
          .fontColor(appStore.theme.p.ink)
        if (this.metaOf(entry) !== '') {
          Text(this.metaOf(entry))
            .fontSize(type.small.fontSize)
            .lineHeight(type.small.lineHeight)
            .fontColor(appStore.theme.p.ink3)
            .margin({ top: 2 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .onClick(() => this.openEditor(index))
      Column() {
        Text('×')
          .fontSize(17)
          .fontColor(this.armedDelete === index ? appStore.theme.p.danger : appStore.theme.p.ink3)
      }
      .constraintSize({ minWidth: 44, minHeight: 44 })
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .onClick(() => this.tapDelete(index))
    }
    .constraintSize({ minHeight: 50 })
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .alignItems(VerticalAlign.Center)
  }

  build() {
    NavDestination() {
      Stack() {
        Column() {
          BackRow({
            label: t('Memory'),
            onBack: (): void => this.goBack(),
          })
          Scroll() {
            Column() {
              if (this.summary() !== '') {
                Text(this.summary())
                  .fontSize(type.caption.fontSize)
                  .lineHeight(type.caption.lineHeight)
                  .fontColor(appStore.theme.p.ink3)
                  .width('100%')
                  .padding(18)
              }
              // The ask box, its answer under the input.
              Column() {
                Row({ space: 10 }) {
                  TextInput({ text: this.question, placeholder: t('Ask memory') })
                    .fontSize(type.settingsRow.fontSize)
                    .fontColor(appStore.theme.p.ink)
                    .placeholderColor(appStore.theme.p.ink3)
                    .backgroundColor(Color.Transparent)
                    .padding(0)
                    .layoutWeight(1)
                    .onChange((value: string): void => {
                      this.question = value
                    })
                    .onSubmit(() => {
                    void this.ask()
                  })
                  Text(this.asking ? '…' : t('Ask'))
                    .fontSize(type.settingsRow.fontSize)
                    .lineHeight(type.settingsRow.lineHeight)
                    .fontColor(appStore.theme.p.accent)
                    .onClick(() => {
                    void this.ask()
                  })
                }
                .constraintSize({ minHeight: 50 })
                .width('100%')
                .padding({ left: 16, right: 16, top: 10, bottom: 10 })
                .alignItems(VerticalAlign.Center)
                if (this.answer !== '') {
                  Text(this.answer)
                    .fontSize(type.settingsRow.fontSize)
                    .lineHeight(type.settingsRow.lineHeight)
                    .fontColor(appStore.theme.p.ink)
                    .width('100%')
                    .padding({ left: 16, right: 16, bottom: 12 })
                }
              }
              .width('100%')
              .margin({ top: 14 })
              .borderRadius(radius.card)
              .border({ width: this.hairline(), color: appStore.theme.p.line })
              .backgroundColor(appStore.theme.p.card)
              .alignItems(HorizontalAlign.Start)
              FormSection({ label: t('{count} entries', { 'count': this.entries().length }) }) {
                ForEach(this.entries(), (entry: MemoryEntry, index: number) => {
                  this.entryRow(entry, index)
                }, (entry: MemoryEntry, index: number) => `${index}-${entry.text}`)
                if (this.view !== null && this.entries().length === 0) {
                  Text(t('Nothing saved yet'))
                    .fontSize(type.settingsRow.fontSize)
                    .lineHeight(type.settingsRow.lineHeight)
                    .fontColor(appStore.theme.p.ink2)
                    .width('100%')
                    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
                }
                Row({ space: 10 }) {
                  Text(t('Add'))
                    .fontSize(type.settingsRow.fontSize)
                    .lineHeight(type.settingsRow.lineHeight)
                    .fontColor(appStore.theme.p.ink)
                    .layoutWeight(1)
                  Icon({ name: 'plus', iconSize: 16, color: appStore.theme.p.ink3 })
                }
                .constraintSize({ minHeight: 50 })
                .width('100%')
                .padding({ left: 16, right: 16, top: 10, bottom: 10 })
                .alignItems(VerticalAlign.Center)
                .onClick(() => this.openEditor(-1))
              }
            }
            .width('100%')
            .padding({ bottom: appStore.safeBottom + 40 })
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
        // The add/edit dialog over the panel.
        if (this.editing) {
          Column() {
            Column() {
              Row() {
                TextInput({ text: this.editTopic, placeholder: t('Topic') })
                  .fontSize(type.settingsRow.fontSize)
                  .fontColor(appStore.theme.p.ink)
                  .placeholderColor(appStore.theme.p.ink3)
                  .backgroundColor(Color.Transparent)
                  .padding(0)
                  .layoutWeight(1)
                  .onChange((value: string): void => {
                    this.editTopic = value
                  })
              }
              .constraintSize({ minHeight: 50 })
              .width('100%')
              .padding({ left: 16, right: 16, top: 10, bottom: 10 })
              Divider()
                .strokeWidth(this.hairline())
                .color(appStore.theme.p.line)
              Row() {
                TextArea({ text: this.editText, placeholder: t('Text') })
                  .fontSize(type.settingsRow.fontSize)
                  .fontColor(appStore.theme.p.ink)
                  .placeholderColor(appStore.theme.p.ink3)
                  .backgroundColor(Color.Transparent)
                  .constraintSize({ minHeight: 80, maxHeight: 180 })
                  .layoutWeight(1)
                  .onChange((value: string): void => {
                    this.editText = value
                  })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 10, bottom: 10 })
              .alignItems(VerticalAlign.Center)
              Divider()
                .strokeWidth(this.hairline())
                .color(appStore.theme.p.line)
              Row() {
                Column() {
                  Text(t('Cancel'))
                    .fontSize(type.settingsRow.fontSize)
                    .lineHeight(type.settingsRow.lineHeight)
                    .fontColor(appStore.theme.p.ink2)
                }
                .layoutWeight(1)
                .constraintSize({ minHeight: 36 })
                .alignItems(HorizontalAlign.Center)
                .justifyContent(FlexAlign.Center)
                .onClick(() => this.closeEditor())
                Column() {
                  Text(t('Save'))
                    .fontSize(type.settingsRow.fontSize)
                    .lineHeight(type.settingsRow.lineHeight)
                    .fontWeight('600')
                    .fontColor(appStore.theme.p.accent)
                }
                .layoutWeight(1)
                .constraintSize({ minHeight: 36 })
                .alignItems(HorizontalAlign.Center)
                .justifyContent(FlexAlign.Center)
                .onClick(() => {
                  void this.saveEditor()
                })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 10, bottom: 10 })
              .alignItems(VerticalAlign.Center)
            }
            .width('100%')
            .borderRadius(radius.card)
            .border({ width: this.hairline(), color: appStore.theme.p.line })
            .backgroundColor(appStore.theme.p.card)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .height('100%')
          .padding({ left: 20, right: 20 })
          .justifyContent(FlexAlign.Center)
          .backgroundColor('rgba(0,0,0,0.4)')
          .onClick(() => this.closeEditor())
        }
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .padding({ top: appStore.safeTop })
    .backgroundColor(appStore.theme.p.main)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack
      this.botId = readStringParam(ctx.pathInfo.param, 'botId')
      this.roomId = readStringParam(ctx.pathInfo.param, 'roomId')
    })
    .onShown(() => {
      void this.load()
    })
  }
}

@Builder
export function MemoryBuilder() {
  Memory()
}
