// The two "new" sheets from manage.tsx: Create new Bot and Create group chat.
// Both are pushed screens (the NavDestination host keeps them in the safe
// area); the Bot opens its chat once create-bot answers, the group opens
// create-room's room.

import { appStore, type } from '../components/Theme'
import { t } from '../common/ui/i18n'
import type { Bot, BotAvatar, TeamState } from '../common/team/types'
import { Avatar } from '../components/Marks'
import { Icon } from '../components/Icon'
import { SheetView, SheetHeader } from '../components/Sheet'
import { FormSection } from '../components/FormControls'
import { CharacterShapeGrid as ShapeGrid, CharacterColorGrid as ColorGrid } from '../components/CharacterPick'
import { ModelPicker } from './ModelMenu'
import type { ChatTarget } from '../appstate/AppStore'

interface CreateBotPayload {
  name: string
  color: string
  avatar: BotAvatar
  model?: string
}

interface CreateBotReply {
  id?: string
}

interface CreateRoomPayload {
  members: string[]
  admin: string
  greet: boolean
}

interface CreateRoomReply {
  id?: string
}

interface CodedError {
  code?: string
}

// ------------------------------------------------------------ Create new Bot

@ComponentV2
export struct NewBot {
  @Local pathStack: NavPathStack | null = null
  @Local name: string = ''
  @Local shape: string = 'star'
  @Local color: string = 'blue'
  @Local model: string | undefined = undefined
  @Local busy: boolean = false
  @Local writeError: string = ''

  aboutToAppear(): void {
    // Start on the team's default model, else its first one.
    const models = appStore.link.team?.models ?? []
    const defaultModel = appStore.link.team?.defaultModel
    let picked: string | undefined = undefined
    for (const model of models) {
      if (model.ref === defaultModel) picked = model.ref
    }
    if (picked === undefined && models.length > 0) {
      picked = models[0]?.ref
    }
    this.model = picked
  }

  private team(): TeamState | null {
    return appStore.link.team
  }

  private finalName(): string {
    if (this.name.trim() !== '') return this.name.trim()
    return t('New Bot')
  }

  private clash(): boolean {
    const lower = this.finalName().toLowerCase()
    for (const bot of this.team()?.bots ?? []) {
      if (bot.name.toLowerCase() === lower) return true
    }
    return false
  }

  private draftBot(): Bot {
    const avatar: BotAvatar = { shape: this.shape }
    return { id: '', name: this.finalName(), color: this.color, avatar: avatar }
  }

  private goBack(): void {
    if (this.pathStack !== null) this.pathStack.pop()
  }

  private openBot(botId: string): void {
    const target: ChatTarget = { kind: 'bot', id: botId }
    appStore.openChat(target)
    if (this.pathStack !== null) this.pathStack.clear()
  }

  private async createItem(): Promise<void> {
    if (this.busy || this.clash()) return
    this.busy = true
    const payload: CreateBotPayload = {
      name: this.finalName(),
      color: this.color,
      avatar: { shape: this.shape },
    }
    if (this.model !== undefined) payload.model = this.model
    const controller = appStore.link.controller
    if (controller === null) {
      this.busy = false
      return
    }
    try {
      const value = (await controller.call('create-bot', payload)) as CreateBotReply | null
      this.busy = false
      this.writeError = ''
      if (value !== null && value !== undefined && value.id !== undefined && value.id !== '') {
        this.openBot(value.id)
      }
    } catch (failure) {
      this.busy = false
      if ((failure as CodedError)?.code === 'unlock/canceled') return
      this.writeError = failure instanceof Error ? failure.message : String(failure)
    }
  }

  private createDisabled(): boolean {
    return this.busy || this.clash()
  }

  build() {
    NavDestination() {
      SheetView() {
        SheetHeader({
          title: t('Create new Bot'),
          leftLabel: t('Cancel'),
          onLeft: (): void => this.goBack(),
          rightLabel: t('Create'),
          rightDisabled: this.createDisabled(),
          rightStrong: true,
          onRight: (): void => { void this.createItem() },
        })
        Scroll() {
          Column() {
            if (this.writeError !== '') {
              Text(this.writeError)
                .fontSize(type.small.fontSize)
                .lineHeight(type.small.lineHeight)
                .fontColor(appStore.theme.p.danger)
                .width('100%')
                .padding({ left: 18, right: 18, top: 10 })
            }
            // The Bot as it will look, over its name, as the picks change.
            Column() {
              Avatar({
                bot: this.draftBot(),
                dark: appStore.theme.dark,
                markSize: 72,
                ring: appStore.theme.p.main,
              })
            }
            .width('100%')
            .padding({ top: 8 })
            .alignItems(HorizontalAlign.Center)
            FormSection({ label: t('Name') }) {
              Column() {
                Row() {
                  TextInput({ text: this.name, placeholder: t('New Bot') })
                    .fontSize(type.settingsRow.fontSize)
                    .fontColor(appStore.theme.p.ink)
                    .placeholderColor(appStore.theme.p.ink3)
                    .backgroundColor(Color.Transparent)
                    .padding({ top: 4, bottom: 4 })
                    .layoutWeight(1)
                    .onChange((value: string): void => {
                      this.name = value
                    })
                }
                .constraintSize({ minHeight: 50 })
                .width('100%')
                .padding({ left: 16, right: 16 })
                .alignItems(VerticalAlign.Center)
                if (this.clash()) {
                  Text(t('Another Bot has this name.'))
                    .fontSize(type.small.fontSize)
                    .lineHeight(type.small.lineHeight)
                    .fontColor(appStore.theme.p.danger)
                    .width('100%')
                    .padding({ left: 16, right: 16, bottom: 10 })
                }
              }
              .width('100%')
            }
            FormSection({ label: t('Character shape') }) {
              ShapeGrid({
                bot: this.draftBot(),
                color: this.color,
                picked: this.shape,
                onPick: (id: string): void => {
                  this.shape = id
                },
              })
            }
            FormSection({ label: t('Character color') }) {
              ColorGrid({
                picked: this.color,
                dark: appStore.theme.dark,
                onPick: (id: string): void => {
                  this.color = id
                },
              })
            }
            Column({ space: 6 }) {
              Text(t('Model'))
                .fontSize(type.caption.fontSize)
                .lineHeight(type.caption.lineHeight)
                .fontColor(appStore.theme.p.ink3)
                .margin({ left: 4 })
              ModelPicker({
                current: this.model,
                onPick: (ref: string): void => {
                  this.model = ref
                },
              })
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 18 })
            .alignItems(HorizontalAlign.Start)
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
    }
    .hideTitleBar(true)
    .padding({ top: appStore.safeTop })
    .backgroundColor(appStore.theme.p.main)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack
    })
  }
}

// ------------------------------------------------------------ Create group chat

@ComponentV2
export struct NewGroup {
  @Local pathStack: NavPathStack | null = null
  @Local picked: Set<string> = new Set<string>()
  @Local admin: string = ''
  @Local busy: boolean = false
  @Local writeError: string = ''

  private team(): TeamState | null {
    return appStore.link.team
  }

  private bots(): Bot[] {
    return this.team()?.bots ?? []
  }

  private firstPicked(): string {
    for (const id of this.picked) return id
    return ''
  }

  // The first Bot picked leads until another is chosen.
  private lead(): string {
    if (this.admin !== '' && this.picked.has(this.admin)) return this.admin
    return this.firstPicked()
  }

  private ready(): boolean {
    return this.lead() !== '' && this.picked.size >= 2
  }

  private members(): string[] {
    const lead = this.lead()
    const members: string[] = [lead]
    for (const id of this.picked) {
      if (id !== lead) members.push(id)
    }
    return members
  }

  private leads(botId: string): boolean {
    return this.picked.has(botId) && this.lead() === botId
  }

  private goBack(): void {
    if (this.pathStack !== null) this.pathStack.pop()
  }

  private openRoom(roomId: string): void {
    const target: ChatTarget = { kind: 'room', id: roomId }
    appStore.openChat(target)
    if (this.pathStack !== null) this.pathStack.clear()
  }

  private togglePick(botId: string): void {
    const next: Set<string> = new Set<string>(this.picked)
    if (next.has(botId)) {
      next.delete(botId)
    } else {
      next.add(botId)
    }
    this.picked = next
  }

  private makeAdmin(botId: string): void {
    this.admin = botId
  }

  private async createItem(): Promise<void> {
    if (!this.ready() || this.busy) return
    this.busy = true
    const payload: CreateRoomPayload = {
      members: this.members(),
      admin: this.lead(),
      greet: true,
    }
    const controller = appStore.link.controller
    if (controller === null) {
      this.busy = false
      return
    }
    try {
      const value = (await controller.call('create-room', payload)) as CreateRoomReply | null
      this.busy = false
      this.writeError = ''
      if (value !== null && value !== undefined && value.id !== undefined && value.id !== '') {
        this.openRoom(value.id)
      }
    } catch (failure) {
      this.busy = false
      if ((failure as CodedError)?.code === 'unlock/canceled') return
      this.writeError = failure instanceof Error ? failure.message : String(failure)
    }
  }

  private hairline(): number {
    return this.getUIContext().px2vp(1)
  }

  @Builder
  memberRow(bot: Bot) {
    Row({ space: 10 }) {
      Row() {
        Avatar({
          bot: bot,
          dark: appStore.theme.dark,
          markSize: 32,
          ring: appStore.theme.p.card,
        })
        Text(bot.name)
          .fontSize(type.settingsRow.fontSize)
          .lineHeight(type.settingsRow.lineHeight)
          .fontColor(appStore.theme.p.ink)
          .margin({ left: 10 })
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .constraintSize({ minWidth: 0 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => this.togglePick(bot.id))
      if (this.leads(bot.id)) {
        Text(t('Admin'))
          .fontSize(11)
          .lineHeight(16)
          .fontColor(appStore.theme.p.accent)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(6)
          .backgroundColor(appStore.theme.p.hover)
      } else if (this.picked.has(bot.id) && this.picked.size > 1) {
        Text(t('Make admin'))
          .fontSize(type.caption.fontSize)
          .lineHeight(type.caption.lineHeight)
          .fontColor(appStore.theme.p.ink3)
          .padding({ left: 6, right: 6, top: 6, bottom: 6 })
          .onClick(() => this.makeAdmin(bot.id))
      }
      Column() {
        if (this.picked.has(bot.id)) {
          Icon({ name: 'check', iconSize: 14, color: appStore.theme.p.accentInk })
        }
      }
      .width(22)
      .height(22)
      .borderRadius(11)
      .border({ width: 1.5, color: this.picked.has(bot.id) ? appStore.theme.p.accent : appStore.theme.p.line2 })
      .backgroundColor(this.picked.has(bot.id) ? appStore.theme.p.accent : Color.Transparent)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .margin({ left: 4 })
      .onClick(() => this.togglePick(bot.id))
    }
    .constraintSize({ minHeight: 50 })
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .alignItems(VerticalAlign.Center)
  }

  build() {
    NavDestination() {
      SheetView() {
        SheetHeader({
          title: t('Create group chat'),
          leftLabel: t('Cancel'),
          onLeft: (): void => this.goBack(),
          rightLabel: t('Create'),
          rightDisabled: !this.ready() || this.busy,
          rightStrong: true,
          onRight: (): void => { void this.createItem() },
        })
        Scroll() {
          Column() {
            Text(t('Pick at least two Bots. The admin leads the group.'))
              .fontSize(type.small.fontSize)
              .lineHeight(type.small.lineHeight)
              .fontColor(appStore.theme.p.ink3)
              .width('100%')
              .padding({ left: 18, right: 18, top: 14 })
            if (this.writeError !== '') {
              Text(this.writeError)
                .fontSize(type.small.fontSize)
                .lineHeight(type.small.lineHeight)
                .fontColor(appStore.theme.p.danger)
                .width('100%')
                .padding({ left: 18, right: 18, top: 10 })
            }
            FormSection({ label: t('Members') }) {
              ForEach(this.bots(), (bot: Bot, index: number) => {
                if (index > 0) {
                  Divider()
                    .strokeWidth(this.hairline())
                    .color(appStore.theme.p.line)
                }
                this.memberRow(bot)
              }, (bot: Bot) => bot.id)
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
    }
    .hideTitleBar(true)
    .padding({ top: appStore.safeTop })
    .backgroundColor(appStore.theme.p.main)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack
    })
  }
}

@Builder
export function NewBotBuilder() {
  NewBot()
}

@Builder
export function NewGroupBuilder() {
  NewGroup()
}
