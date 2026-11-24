// The IM page (desktop im-page.js): IM bots bound to team Bots. Requests that
// wait for the owner on top, the IM bots already added, then the platform
// grid; an added IM bot opens a detail view with its Bot binding, accounts
// and chats. QR-login platforms (WeChat) are desktop-only for now.

import { appStore, type, radius } from '../../components/Theme'
import { t } from '../../common/ui/i18n'
import { common } from '@kit.AbilityKit'
import type { Bot, ImChatTarget, ImConnection, ImPaired, ImRequest, ImStatusEntry, Room } from '../../common/team/types'
import { openExternalUrl } from '../chat/MarkdownText'
import { FormSection, BackRow, SwitchRow, SectionDivider, Segmented } from '../../components/FormControls'
import type { SegmentOption } from '../../components/FormControls'
import { Icon } from '../../components/Icon'
import { BotMark } from '../../components/Marks'

// The platform definitions of shared/im-platforms.js, embedded: imView gives
// only the platform ids, and the field shapes live in the host's source.
interface ImFieldDef {
  key: string
  label: string
  secret?: boolean
  hint?: string
  options?: SegmentOption[]
}

interface ImPlatformDef {
  id: string
  name: string
  mark: string
  color: string
  fields: ImFieldDef[]
}

// Guide steps per platform (desktop im-page.js GUIDES): what to create on the
// platform's side before the phone's fields can connect.
interface ImGuide {
  steps: string[]
  link?: string
  linkLabel?: string
}

const PLATFORM_DEFS: ImPlatformDef[] = [
  {
    id: 'telegram', name: 'Telegram', mark: 'T', color: '#2AABEE',
    fields: [{ key: 'token', label: 'Bot token', secret: true }],
  },
  {
    id: 'weixin', name: 'WeChat', mark: '微', color: '#07C160',
    fields: [],
  },
  {
    id: 'feishu', name: 'Feishu / Lark', mark: '飞', color: '#3370FF',
    fields: [
      {
        key: 'domain', label: 'Edition',
        options: [{ id: 'feishu', label: 'Feishu' }, { id: 'lark', label: 'Lark' }],
      },
      { key: 'appId', label: 'App ID' },
      { key: 'appSecret', label: 'App Secret', secret: true },
    ],
  },
  {
    id: 'dingtalk', name: 'DingTalk', mark: '钉', color: '#0089FF',
    fields: [
      { key: 'clientId', label: 'Client ID' },
      { key: 'clientSecret', label: 'Client Secret', secret: true },
    ],
  },
  {
    id: 'wecom', name: 'WeCom', mark: '企', color: '#07C160',
    fields: [
      { key: 'botId', label: 'Bot ID' },
      { key: 'secret', label: 'Secret', secret: true },
    ],
  },
  {
    id: 'qq', name: 'QQ', mark: 'Q', color: '#EB1923',
    fields: [
      { key: 'appId', label: 'App ID' },
      { key: 'appSecret', label: 'App Secret', secret: true },
    ],
  },
  {
    id: 'discord', name: 'Discord', mark: 'D', color: '#5865F2',
    fields: [{ key: 'token', label: 'Bot token', secret: true }],
  },
  {
    id: 'slack', name: 'Slack', mark: 'S', color: '#4A154B',
    fields: [
      { key: 'appToken', label: 'App-Level Token', secret: true, hint: 'xapp-' },
      { key: 'botToken', label: 'Bot Token', secret: true, hint: 'xoxb-' },
    ],
  },
]

const GUIDES: Record<string, ImGuide> = {
  'telegram': {
    steps: [
      'In Telegram, open @BotFather and send /newbot.',
      'Give the bot a name and a username.',
      'Paste the token that BotFather sends.',
    ],
    link: 'https://t.me/BotFather',
    linkLabel: 'BotFather',
  },
  'feishu': {
    steps: [
      'Create a custom app in the developer console and add the bot capability.',
      'Grant the permissions to read and send messages.',
      'Paste the App ID and App Secret from Credentials, then connect.',
      'Under Events & callbacks, receive events through a long connection, add the receive message event, and publish a version.',
    ],
    link: 'https://open.feishu.cn/app',
    linkLabel: 'open.feishu.cn',
  },
  'dingtalk': {
    steps: [
      'Create an app in the developer console and add a robot.',
      'Set the robot to receive messages in Stream mode, then publish it.',
      'Paste the Client ID and Client Secret.',
    ],
    link: 'https://open-dev.dingtalk.com/',
    linkLabel: 'open-dev.dingtalk.com',
  },
  'wecom': {
    steps: [
      'In WeCom, create an intelligent robot in API mode with a long connection.',
      'Paste the Bot ID and Secret.',
    ],
    link: 'https://work.weixin.qq.com/',
    linkLabel: 'work.weixin.qq.com',
  },
  'qq': {
    steps: [
      'Create a bot on the QQ Open Platform.',
      'Paste the App ID and App Secret from the development settings.',
      'Until the bot is published, add your QQ account to its sandbox.',
    ],
    link: 'https://q.qq.com/qqbot/',
    linkLabel: 'q.qq.com',
  },
  'discord': {
    steps: [
      'Create an application in the Developer Portal and open Bot.',
      'Turn on Message Content Intent, then reset and copy the token.',
      'Invite the bot to your server with the bot scope.',
    ],
    link: 'https://discord.com/developers/applications',
    linkLabel: 'Developer Portal',
  },
  'slack': {
    steps: [
      'Create an app and turn on Socket Mode.',
      'Make an app-level token with connections:write.',
      'Add the scopes app_mentions:read, chat:write, im:history and files:read, and subscribe to app_mention and message.im.',
      'Install the app to the workspace and paste both tokens.',
    ],
    link: 'https://api.slack.com/apps',
    linkLabel: 'api.slack.com',
  },
}

function platformDef(id: string): ImPlatformDef {
  for (const def of PLATFORM_DEFS) {
    if (def.id === id) return def
  }
  return { id: id, name: id, mark: id.substring(0, 1).toUpperCase(), color: '#8A8F98', fields: [] }
}

interface CodedError {
  code?: string
}

interface ImAddPayload {
  platform: string
  botId: string
  fields: Record<string, string>
}

interface ImIdPayload {
  id: string
}

interface ImUpdatePayload {
  id: string
  botId?: string
  enabled?: boolean
}

interface ImPairPayload {
  id: string
  senderId: string
  allow: boolean
}

interface ImUnpairPayload {
  id: string
  senderId: string
}

interface ImChatPayload {
  id: string
  chatKey: string
  target?: ImChatTarget | null
  remove?: boolean
}

// The IM platform's mark: a colored tile with the platform's monogram.
@ComponentV2
struct ImMark {
  @Param platformId: string = ''
  @Param markSize: number = 36
  @Param dim: boolean = false

  build() {
    Stack() {
      Text(platformDef(this.platformId).mark)
        .fontSize(Math.round(this.markSize * 0.36))
        .fontWeight('600')
        .fontColor('#ffffff')
    }
    .width(this.markSize)
    .height(this.markSize)
    .borderRadius(Math.round(this.markSize * 0.28))
    .backgroundColor(platformDef(this.platformId).color)
    .opacity(this.dim ? 0.5 : 1)
    .alignContent(Alignment.Center)
  }
}

// One request that waits for the owner: name, then Allow / Deny.
@ComponentV2
struct ImRequestRow {
  @Param request: ImRequest | undefined = undefined
  @Param sourceName: string = ''
  @Param withSource: boolean = false
  @Event onPair: (allow: boolean) => void = (allow: boolean) => {}

  build() {
    Row({ space: 12 }) {
      Text((this.request?.name ?? '?').replace(/^@/, '').substring(0, 1).toUpperCase())
        .fontSize(type.small.fontSize)
        .fontWeight('600')
        .fontColor(appStore.theme.p.ink2)
        .width(28)
        .height(28)
        .borderRadius(14)
        .backgroundColor(appStore.theme.p.hover)
        .textAlign(TextAlign.Center)
      Column({ space: 2 }) {
        Text(this.request?.name ?? '')
          .fontSize(type.settingsRow.fontSize)
          .lineHeight(type.settingsRow.lineHeight)
          .fontColor(appStore.theme.p.ink)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.withSource && this.sourceName !== '') {
          Text(t('Wants to talk through {bot}', { 'bot': this.sourceName }))
            .fontSize(type.small.fontSize)
            .lineHeight(type.small.lineHeight)
            .fontColor(appStore.theme.p.ink3)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text(t('Deny'))
        .fontSize(type.small.fontSize)
        .lineHeight(type.small.lineHeight)
        .fontColor(appStore.theme.p.ink2)
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .borderRadius(16)
        .backgroundColor(appStore.theme.p.hover)
        .onClick(() => this.onPair(false))
      Text(t('Allow'))
        .fontSize(type.small.fontSize)
        .lineHeight(type.small.lineHeight)
        .fontWeight('500')
        .fontColor(appStore.theme.p.accentInk)
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .borderRadius(16)
        .backgroundColor(appStore.theme.p.accent)
        .onClick(() => this.onPair(true))
    }
    .constraintSize({ minHeight: 50 })
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
  }
}

@ComponentV2
export struct Im {
  @Local pathStack: NavPathStack | null = null
  @Local mode: string = 'list'
  @Local addPlatform: string = ''
  @Local detailId: string = ''
  @Local error: string = ''
  @Local addError: string = ''
  @Local addBusy: boolean = false
  @Local addBotId: string = ''
  @Local addFields: Record<string, string> = {}
  // The bot picker sheet: which binding the pick lands in.
  @Local botPickFor: string = ''
  @Local botPickOpen: boolean = false
  // The chat-target picker sheet: 'chatKey:<key>' of the chat being bound.
  @Local chatPickKey: string = ''
  @Local chatPickOpen: boolean = false
  // Two-tap confirm keys: 'conn' removes the IM bot, 'p:<id>' unpairs an
  // account, 'c:<key>' removes a chat.
  @Local confirmKey: string = ''

  private hairline(): number {
    return this.getUIContext().px2vp(1)
  }

  private goBack(): void {
    if (this.mode !== 'list') {
      this.mode = 'list'
      this.detailId = ''
      this.addPlatform = ''
      this.confirmKey = ''
      return
    }
    if (this.pathStack !== null) this.pathStack.pop()
  }

  private team() {
    return appStore.link.team
  }

  private connections(): ImConnection[] {
    return this.team()?.im?.connections ?? []
  }

  private detail(): ImConnection | null {
    for (const conn of this.connections()) {
      if (conn.id === this.detailId) return conn
    }
    return null
  }

  private bots(): Bot[] {
    return this.team()?.bots ?? []
  }

  private botName(id: string | null | undefined): string {
    if (id === undefined || id === null || id === '') return ''
    for (const bot of this.bots()) {
      if (bot.id === id) return bot.name
    }
    return ''
  }

  private rooms() {
    return this.team()?.rooms ?? []
  }

  private roomName(id: string): string {
    for (const room of this.rooms()) {
      if (room.id === id) return room.name
    }
    return ''
  }

  // The platform ids the host reports as addable; the phone skips QR login.
  private platformIds(): string[] {
    const ids = this.team()?.im?.platforms ?? []
    const out: string[] = []
    for (const id of ids) {
      if (platformDef(id).fields.length > 0) out.push(id)
    }
    return out
  }

  private async call(endpoint: string, payload: Object): Promise<boolean> {
    const controller = appStore.link.controller
    if (controller === null) return false
    try {
      await controller.call(endpoint, payload)
      return true
    } catch (failure) {
      if ((failure as CodedError)?.code === 'unlock/canceled') return false
      this.error = failure instanceof Error ? failure.message : String(failure)
      return false
    }
  }

  private pair(connId: string, request: ImRequest, allow: boolean): void {
    const payload: ImPairPayload = { id: connId, senderId: request.id, allow: allow }
    void this.call('im-pair', payload)
  }

  private setEnabled(conn: ImConnection, on: boolean): void {
    const payload: ImUpdatePayload = { id: conn.id, enabled: on }
    void this.call('im-update', payload)
  }

  private setBot(connId: string, botId: string): void {
    const payload: ImUpdatePayload = { id: connId, botId: botId }
    void this.call('im-update', payload)
  }

  private removeConn(conn: ImConnection): void {
    if (this.confirmKey !== 'conn') {
      this.confirmKey = 'conn'
      return
    }
    this.confirmKey = ''
    const payload: ImIdPayload = { id: conn.id }
    void this.call('im-remove', payload).then((ok: boolean): void => {
      if (ok) this.mode = 'list'
    })
  }

  private unpair(conn: ImConnection, senderId: string): void {
    if (this.confirmKey !== `p:${senderId}`) {
      this.confirmKey = `p:${senderId}`
      return
    }
    this.confirmKey = ''
    const payload: ImUnpairPayload = { id: conn.id, senderId: senderId }
    void this.call('im-unpair', payload)
  }

  private removeChat(conn: ImConnection, chatKey: string): void {
    if (this.confirmKey !== `c:${chatKey}`) {
      this.confirmKey = `c:${chatKey}`
      return
    }
    this.confirmKey = ''
    const payload: ImChatPayload = { id: conn.id, chatKey: chatKey, remove: true }
    void this.call('im-chat', payload)
  }

  // The add form's fields: the segmented default (feishu/lark) counts as set.
  private fieldOf(key: string): string {
    return this.addFields[key] ?? ''
  }

  private setField(key: string, value: string): void {
    const next: Record<string, string> = {}
    for (const known of Object.keys(this.addFields)) {
      next[known] = this.addFields[known]
    }
    next[key] = value
    this.addFields = next
  }

  private openAdd(platformId: string): void {
    this.addPlatform = platformId
    this.addFields = {}
    this.addError = ''
    const first = this.bots()[0]
    this.addBotId = first !== undefined ? first.id : ''
    this.botPickFor = 'add'
    this.mode = 'add'
  }

  private addMissing(): boolean {
    for (const field of platformDef(this.addPlatform).fields) {
      if (field.options !== undefined) continue
      if (this.fieldOf(field.key).trim() === '') return true
    }
    return false
  }

  private addConnection(): void {
    if (this.addBotId === '' || this.addMissing() || this.addBusy) return
    this.addBusy = true
    this.addError = ''
    const payload: ImAddPayload = { platform: this.addPlatform, botId: this.addBotId, fields: this.addFields }
    const controller = appStore.link.controller
    if (controller === null) {
      this.addBusy = false
      return
    }
    controller.call('im-add', payload).then((): void => {
      this.addBusy = false
      this.mode = 'list'
      this.error = ''
    }, (failure: Object): void => {
      this.addBusy = false
      this.addError = failure instanceof Error ? failure.message : String(failure)
    })
  }

  private sheetOptions(): SheetOptions {
    return {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: false,
      backgroundColor: appStore.theme.p.card,
      onDisappear: (): void => {
        this.botPickOpen = false
        this.chatPickOpen = false
      },
    }
  }

  @Builder
  botPickSheet() {
    Column() {
      ForEach(this.bots(), (bot: Bot) => {
        Row({ space: 10 }) {
          BotMark({ bot: bot, markSize: 28 })
          Text(bot.name)
            .fontSize(type.settingsRow.fontSize)
            .lineHeight(type.settingsRow.lineHeight)
            .fontColor(appStore.theme.p.ink)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.pickTargetBotId() === bot.id) {
            Icon({ name: 'check', iconSize: 15, color: appStore.theme.p.accent })
          }
        }
        .constraintSize({ minHeight: 50 })
        .padding({ left: 16, right: 16 })
        .alignItems(VerticalAlign.Center)
        .width('100%')
        .onClick(() => this.applyBotPick(bot.id))
      }, (bot: Bot) => bot.id)
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
  }

  // Which bot id the picker marks as current: the add form's or the detail's.
  private pickTargetBotId(): string {
    if (this.botPickFor === 'add') return this.addBotId
    const conn = this.detail()
    if (conn === null) return ''
    return conn.botId ?? ''
  }

  private applyBotPick(botId: string): void {
    if (this.botPickFor === 'add') {
      this.addBotId = botId
    } else {
      const conn = this.detail()
      if (conn !== null) this.setBot(conn.id, botId)
    }
    this.botPickOpen = false
  }

  @Builder
  chatPickSheet() {
    Column() {
      Text(t('Bots'))
        .fontSize(type.caption.fontSize)
        .lineHeight(type.caption.lineHeight)
        .fontColor(appStore.theme.p.ink3)
        .width('100%')
        .padding({ left: 16, top: 8 })
      ForEach(this.bots(), (bot: Bot) => {
        Row({ space: 10 }) {
          BotMark({ bot: bot, markSize: 28 })
          Text(bot.name)
            .fontSize(type.settingsRow.fontSize)
            .lineHeight(type.settingsRow.lineHeight)
            .fontColor(appStore.theme.p.ink)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.chatPickCurrent() === `bot:${bot.id}`) {
            Icon({ name: 'check', iconSize: 15, color: appStore.theme.p.accent })
          }
        }
        .constraintSize({ minHeight: 50 })
        .padding({ left: 16, right: 16 })
        .alignItems(VerticalAlign.Center)
        .width('100%')
        .onClick(() => this.applyChatPick({ botId: bot.id }))
      }, (bot: Bot) => bot.id)
      if (this.rooms().length > 0) {
        Text(t('Group chats'))
          .fontSize(type.caption.fontSize)
          .lineHeight(type.caption.lineHeight)
          .fontColor(appStore.theme.p.ink3)
          .width('100%')
          .padding({ left: 16, top: 8 })
        ForEach(this.rooms(), (room: Room) => {
          Row({ space: 10 }) {
            Text(room.name.substring(0, 1).toUpperCase())
              .fontSize(type.small.fontSize)
              .fontWeight('600')
              .fontColor(appStore.theme.p.ink2)
              .width(28)
              .height(28)
              .borderRadius(14)
              .backgroundColor(appStore.theme.p.hover)
              .textAlign(TextAlign.Center)
            Text(room.name)
              .fontSize(type.settingsRow.fontSize)
              .lineHeight(type.settingsRow.lineHeight)
              .fontColor(appStore.theme.p.ink)
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (this.chatPickCurrent() === `room:${room.id}`) {
              Icon({ name: 'check', iconSize: 15, color: appStore.theme.p.accent })
            }
          }
          .constraintSize({ minHeight: 50 })
          .padding({ left: 16, right: 16 })
          .alignItems(VerticalAlign.Center)
          .width('100%')
          .onClick(() => this.applyChatPick({ roomId: room.id }))
        }, (room: Room) => room.id)
      }
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
  }

  private chatPickCurrent(): string {
    const conn = this.detail()
    if (conn === null) return ''
    const chat = conn.chats?.[this.chatPickKey]
    if (chat === undefined || chat.target === undefined) return ''
    if (chat.target.botId !== undefined) return `bot:${chat.target.botId}`
    if (chat.target.roomId !== undefined) return `room:${chat.target.roomId}`
    return ''
  }

  private applyChatPick(target: ImChatTarget): void {
    const conn = this.detail()
    if (conn !== null && this.chatPickKey !== '') {
      const payload: ImChatPayload = { id: conn.id, chatKey: this.chatPickKey, target: target }
      void this.call('im-chat', payload)
    }
    this.chatPickOpen = false
  }

  private chatName(conn: ImConnection, key: string): string {
    const chat = conn.chats?.[key]
    if (chat === undefined) return key
    if ((chat.title ?? '') !== '') return chat.title ?? key
    for (const entry of conn.paired ?? []) {
      if (entry.id === key) return entry.name ?? key
    }
    return t('Direct message')
  }

  build() {
    NavDestination() {
      Column() {
        BackRow({
          label: this.headerLabel(),
          onBack: (): void => this.goBack(),
        })
        Scroll() {
          Column() {
            if (this.error !== '') {
              Text(this.error)
                .fontSize(type.small.fontSize)
                .lineHeight(type.small.lineHeight)
                .fontColor(appStore.theme.p.danger)
                .width('100%')
                .padding(18)
            }
            if (this.mode === 'add') {
              this.addBlock()
            } else if (this.mode === 'detail') {
              this.detailBlock()
            } else {
              this.listBlock()
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
      .bindSheet($$this.botPickOpen, this.botPickSheet(), this.sheetOptions())
      .bindSheet($$this.chatPickOpen, this.chatPickSheet(), this.sheetOptions())
    }
    .hideTitleBar(true)
    .padding({ top: appStore.safeTop })
    .backgroundColor(appStore.theme.p.main)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack
    })
  }

  private headerLabel(): string {
    if (this.mode === 'add') return t(platformDef(this.addPlatform).name)
    if (this.mode === 'detail') {
      const conn = this.detail()
      if (conn !== null) {
        const account = conn.account?.name ?? ''
        if (account !== '') return account
        return t(platformDef(conn.platform).name)
      }
    }
    return t('IM')
  }

  // The connection list, the waiting requests and the platform grid.
  @Builder
  listBlock() {
    if (this.waitingConnections().length > 0) {
      FormSection({ label: t('Waiting for approval') }) {
        ForEach(this.waitingConnections(), (conn: ImConnection) => {
          ForEach(conn.requests ?? [], (request: ImRequest) => {
            ImRequestRow({
              request: request,
              sourceName: conn.account?.name ?? t(platformDef(conn.platform).name),
              withSource: true,
              onPair: (allow: boolean): void => this.pair(conn.id, request, allow),
            })
          }, (request: ImRequest) => request.id)
        }, (conn: ImConnection) => conn.id)
      }
    }
    if (this.connections().length > 0) {
      FormSection({ label: t('Your IM bots') }) {
        ForEach(this.connections(), (conn: ImConnection, index: number) => {
          if (index > 0) {
            SectionDivider()
          }
          this.connRow(conn)
        }, (conn: ImConnection) => conn.id)
      }
    }
    FormSection({ label: this.connections().length > 0 ? t('Add an IM bot') : t('Choose a platform') }) {
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.platformIds(), (id: string) => {
          this.platformTile(id)
        }, (id: string) => id)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    }
  }

  private waitingConnections(): ImConnection[] {
    const out: ImConnection[] = []
    for (const conn of this.connections()) {
      if ((conn.requests ?? []).length > 0) out.push(conn)
    }
    return out
  }

  @Builder
  connRow(conn: ImConnection) {
    Row({ space: 12 }) {
      ImMark({ platformId: conn.platform, markSize: 36, dim: conn.enabled === false })
      Column({ space: 2 }) {
        Text(conn.account?.name ?? platformDef(conn.platform).name)
          .fontSize(type.settingsRow.fontSize)
          .lineHeight(type.settingsRow.lineHeight)
          .fontColor(appStore.theme.p.ink)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.connStatusLine(conn))
          .fontSize(type.small.fontSize)
          .lineHeight(type.small.lineHeight)
          .fontColor(appStore.theme.p.ink3)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      if ((conn.requests ?? []).length > 0) {
        Text(`${(conn.requests ?? []).length}`)
          .fontSize(type.caption.fontSize)
          .fontWeight('600')
          .fontColor(appStore.theme.p.accentInk)
          .constraintSize({ minWidth: 20 })
          .textAlign(TextAlign.Center)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(10)
          .backgroundColor(appStore.theme.p.accent)
      }
      Icon({ name: 'chevronRight', iconSize: 16, color: appStore.theme.p.ink3 })
    }
    .constraintSize({ minHeight: 50 })
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.detailId = conn.id
      this.confirmKey = ''
      this.mode = 'detail'
    })
  }

  // The live status entry of one connection (team.imStatus, keyed by id).
  private imStatusOf(conn: ImConnection): ImStatusEntry | undefined {
    return this.team()?.imStatus?.[conn.id]
  }

  // The connection's live state (desktop stateOf): disabled is always off, a
  // known status state wins, anything else counts as connecting.
  private connStateOf(conn: ImConnection): string {
    if (conn.enabled === false) return 'off'
    const state = this.imStatusOf(conn)?.state
    if (state === 'ready' || state === 'error' || state === 'retrying' || state === 'connecting') {
      return state
    }
    return 'connecting'
  }

  // The state's status text (desktop stateText).
  private connStateText(conn: ImConnection): string {
    const state = this.connStateOf(conn)
    if (state === 'off') return t('Disabled')
    if (state === 'ready') return t('Connected')
    if (state === 'retrying') return t('Retrying…')
    if (state === 'error') {
      return t('Could not connect: {error}', { 'error': this.imStatusOf(conn)?.error ?? '' })
    }
    return t('Connecting…')
  }

  private connStatusLine(conn: ImConnection): string {
    const parts: string[] = [t(platformDef(conn.platform).name), this.connStateText(conn)]
    const bound = this.botName(conn.botId)
    if (bound !== '') parts.push(t('Talks to {bot}', { 'bot': bound }))
    return parts.join(' · ')
  }

  // The error state's way out: ask the host to retry the connection.
  private retryConn(conn: ImConnection): void {
    const payload: ImIdPayload = { id: conn.id }
    void this.call('im-retry', payload)
  }

  @Builder
  platformTile(id: string) {
    Column({ space: 8 }) {
      ImMark({ platformId: id, markSize: 40 })
      Text(t(platformDef(id).name))
        .fontSize(type.small.fontSize)
        .lineHeight(type.small.lineHeight)
        .fontColor(appStore.theme.p.ink)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(t('Connect'))
        .fontSize(type.caption.fontSize)
        .lineHeight(type.caption.lineHeight)
        .fontWeight('500')
        .fontColor(appStore.theme.p.accentInk)
        .padding({ left: 14, right: 14, top: 4, bottom: 4 })
        .borderRadius(13)
        .backgroundColor(appStore.theme.p.accent)
    }
    .width('50%')
    .padding({ left: 4, right: 4, top: 6, bottom: 6 })
    .alignItems(HorizontalAlign.Center)
    .onClick(() => this.openAdd(id))
  }

  // The add form: guide steps, the Bot it talks to, and the platform's fields.
  @Builder
  addBlock() {
    if (this.guideOf(this.addPlatform) !== null) {
      FormSection({ label: t(platformDef(this.addPlatform).name) }) {
        Column({ space: 8 }) {
          Row({ space: 12 }) {
            ImMark({ platformId: this.addPlatform, markSize: 40 })
            Column({ space: 6 }) {
              ForEach((this.guideOf(this.addPlatform) ?? { steps: [] as string[] }).steps, (step: string, index: number) => {
                Row({ space: 8 }) {
                  Text(`${index + 1}`)
                    .fontSize(type.caption.fontSize)
                    .fontWeight('600')
                    .fontColor(appStore.theme.p.ink2)
                    .width(20)
                    .height(20)
                    .borderRadius(10)
                    .backgroundColor(appStore.theme.p.hover)
                    .textAlign(TextAlign.Center)
                  Text(t(step))
                    .fontSize(type.small.fontSize)
                    .lineHeight(type.small.lineHeight)
                    .fontColor(appStore.theme.p.ink2)
                    .layoutWeight(1)
                }
                .alignItems(VerticalAlign.Top)
              }, (step: string) => step)
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .alignItems(VerticalAlign.Top)
          if (this.guideLinkOf(this.addPlatform) !== '') {
            Text(this.guideOf(this.addPlatform)?.linkLabel ?? this.guideLinkOf(this.addPlatform))
              .fontSize(type.small.fontSize)
              .lineHeight(type.small.lineHeight)
              .fontColor(appStore.theme.p.accent)
              .decoration({ type: TextDecorationType.Underline })
              .onClick(() => this.openGuideLink(this.addPlatform))
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .alignItems(HorizontalAlign.Start)
      }
    }
    FormSection({ label: t('Connect') }) {
      this.botPickRow()
      SectionDivider()
      ForEach(platformDef(this.addPlatform).fields, (field: ImFieldDef) => {
        if (field.options !== undefined) {
          Segmented({
            label: t(field.label),
            value: this.fieldOf(field.key) !== '' ? this.fieldOf(field.key) : (field.options[0]?.id ?? ''),
            options: field.options,
            onPick: (id: string): void => this.setField(field.key, id),
          })
        } else {
          Column({ space: 4 }) {
            Text(t(field.label))
              .fontSize(type.small.fontSize)
              .lineHeight(type.small.lineHeight)
              .fontColor(appStore.theme.p.ink3)
            TextInput({
              text: this.fieldOf(field.key),
              placeholder: field.secret === true && field.hint !== undefined ? `${field.hint}…` : t(field.label),
            })
              .fontSize(type.settingsRow.fontSize)
              .fontColor(appStore.theme.p.ink)
              .placeholderColor(appStore.theme.p.ink3)
              .backgroundColor(Color.Transparent)
              .border({ width: 1, color: appStore.theme.p.line })
              .borderRadius(10)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .constraintSize({ minHeight: 40 })
              .width('100%')
              .onChange((value: string): void => this.setField(field.key, value))
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 10, bottom: 10 })
          .alignItems(HorizontalAlign.Start)
        }
      }, (field: ImFieldDef) => field.key)
    }
    Column({ space: 6 }) {
      if (this.addError !== '') {
        Text(this.addError)
          .fontSize(type.caption.fontSize)
          .lineHeight(type.caption.lineHeight)
          .fontColor(appStore.theme.p.danger)
          .width('100%')
      }
      Column() {
        Text(this.addBusy ? t('Connecting…') : t('Connect'))
          .fontSize(type.settingsRow.fontSize)
          .lineHeight(type.settingsRow.lineHeight)
          .fontWeight('600')
          .fontColor(this.addBotId === '' || this.addMissing() ? appStore.theme.p.ink3 : appStore.theme.p.accentInk)
      }
      .constraintSize({ minHeight: 48 })
      .width('100%')
      .borderRadius(24)
      .backgroundColor(appStore.theme.p.accent)
      .opacity(this.addBotId === '' || this.addMissing() || this.addBusy ? 0.5 : 1)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .onClick(() => this.addConnection())
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 14 })
    .alignItems(HorizontalAlign.Start)
  }

  private guideOf(platformId: string): ImGuide | null {
    const guide = GUIDES[platformId]
    return guide ?? null
  }

  // The guide's link, opened below the steps; '' when the platform has none.
  private guideLinkOf(platformId: string): string {
    return this.guideOf(platformId)?.link ?? ''
  }

  private openGuideLink(platformId: string): void {
    const link = this.guideLinkOf(platformId)
    if (link === '') return
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    openExternalUrl(context, link)
  }

  // The "Talks to" row: the bound Bot's mark and name; opens the bot picker.
  @Builder
  botPickRow() {
    Row({ space: 10 }) {
      Text(t('Talks to'))
        .fontSize(type.settingsRow.fontSize)
        .lineHeight(type.settingsRow.lineHeight)
        .fontColor(appStore.theme.p.ink)
        .layoutWeight(1)
      Text(this.pickTargetBotId() !== '' ? this.botName(this.pickTargetBotId()) : t('Not bound'))
        .fontSize(type.settingsRow.fontSize)
        .lineHeight(type.settingsRow.lineHeight)
        .fontColor(appStore.theme.p.ink2)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text('⌄')
        .fontSize(12)
        .fontColor(appStore.theme.p.ink3)
    }
    .constraintSize({ minHeight: 50 })
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.botPickOpen = true
    })
  }

  // The detail view: header with the enabled switch, the Bot binding, the
  // waiting requests, the paired accounts, the chats, and removal.
  @Builder
  detailBlock() {
    if (this.detail() !== null) {
      Column({ space: 0 }) {
        Row({ space: 12 }) {
          ImMark({ platformId: (this.detail() ?? { platform: '' }).platform, markSize: 40, dim: (this.detail() ?? { enabled: true }).enabled === false })
          Column({ space: 2 }) {
            Text(this.headerLabel())
              .fontSize(type.settingsRow.fontSize)
              .lineHeight(type.settingsRow.lineHeight)
              .fontWeight('500')
              .fontColor(appStore.theme.p.ink)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.connStatusLine(this.detail() as ImConnection))
              .fontSize(type.small.fontSize)
              .lineHeight(type.small.lineHeight)
              .fontColor(appStore.theme.p.ink3)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          if (this.detail() !== null && this.connStateOf(this.detail() as ImConnection) === 'error') {
            Text(t('Try again'))
              .fontSize(type.small.fontSize)
              .lineHeight(type.small.lineHeight)
              .fontWeight('500')
              .fontColor(appStore.theme.p.ink)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .borderRadius(16)
              .backgroundColor(appStore.theme.p.hover)
              .onClick(() => this.retryConn(this.detail() as ImConnection))
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .alignItems(VerticalAlign.Center)
        SectionDivider()
        SwitchRow({
          label: t('Enabled'),
          on: (this.detail() ?? { enabled: true }).enabled !== false,
          onChange: (on: boolean): void => this.setEnabled(this.detail() as ImConnection, on),
        })
        SectionDivider()
        Row({ space: 10 }) {
          Text(t('Talks to'))
            .fontSize(type.settingsRow.fontSize)
            .lineHeight(type.settingsRow.lineHeight)
            .fontColor(appStore.theme.p.ink)
            .layoutWeight(1)
          Text(this.botName((this.detail() as ImConnection).botId) !== '' ? this.botName((this.detail() as ImConnection).botId) : t('Not bound'))
            .fontSize(type.settingsRow.fontSize)
            .lineHeight(type.settingsRow.lineHeight)
            .fontColor(appStore.theme.p.ink2)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('⌄')
            .fontSize(12)
            .fontColor(appStore.theme.p.ink3)
        }
        .constraintSize({ minHeight: 50 })
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.botPickFor = 'detail'
          this.botPickOpen = true
        })
      }
      .width('calc(100% - 28vp)')
      .backgroundColor(appStore.theme.p.card)
      .borderRadius(radius.card)
      .border({ width: this.hairline(), color: appStore.theme.p.line })
      .margin({ left: 14, right: 14, top: 16 })
      .clip(true)
      .shadow({ radius: 0, color: Color.Transparent, offsetX: 0, offsetY: 0 })

      if ((this.detail()?.requests ?? []).length > 0) {
        FormSection({ label: t('Waiting for approval') }) {
          ForEach(this.detail()?.requests ?? [], (request: ImRequest) => {
            ImRequestRow({
              request: request,
              onPair: (allow: boolean): void => this.pair(this.detailId, request, allow),
            })
          }, (request: ImRequest) => request.id)
        }
      }

      FormSection({ label: t('Accounts') }) {
        if ((this.detail()?.paired ?? []).length === 0) {
          Text(t('Send the IM bot a message to connect your account'))
            .fontSize(type.small.fontSize)
            .lineHeight(type.small.lineHeight)
            .fontColor(appStore.theme.p.ink3)
            .width('100%')
            .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        } else {
          ForEach(this.detail()?.paired ?? [], (entry: ImPaired, index: number) => {
            if (index > 0) {
              SectionDivider()
            }
            Row({ space: 12 }) {
              Text((entry.name ?? '?').replace(/^@/, '').substring(0, 1).toUpperCase())
                .fontSize(type.small.fontSize)
                .fontWeight('600')
                .fontColor(appStore.theme.p.ink2)
                .width(28)
                .height(28)
                .borderRadius(14)
                .backgroundColor(appStore.theme.p.hover)
                .textAlign(TextAlign.Center)
              Text(entry.name ?? '')
                .fontSize(type.settingsRow.fontSize)
                .lineHeight(type.settingsRow.lineHeight)
                .fontColor(appStore.theme.p.ink)
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.confirmKey === `p:${entry.id}` ? t('Remove?') : t('Remove'))
                .fontSize(type.small.fontSize)
                .lineHeight(type.small.lineHeight)
                .fontColor(appStore.theme.p.danger)
                .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                .borderRadius(14)
                .backgroundColor(this.confirmKey === `p:${entry.id}` ? appStore.theme.p.danger : Color.Transparent)
                .onClick(() => this.unpair(this.detail() as ImConnection, entry.id))
            }
            .constraintSize({ minHeight: 50 })
            .width('100%')
            .padding({ left: 16, right: 16, top: 10, bottom: 10 })
            .alignItems(VerticalAlign.Center)
          }, (entry: ImPaired) => entry.id)
        }
      }

      if (Object.keys((this.detail() as ImConnection).chats ?? {}).length > 0) {
        FormSection({ label: t('Chats') }) {
          ForEach(Object.keys((this.detail() as ImConnection).chats ?? {}), (key: string, index: number) => {
            if (index > 0) {
              SectionDivider()
            }
            this.chatRow(this.detail() as ImConnection, key)
          }, (key: string) => key)
        }
      }

      Column() {
        Text(this.confirmKey === 'conn' ? t('Remove this IM bot? Its accounts and chats are removed too.') : t('Remove IM bot'))
          .fontSize(type.settingsRow.fontSize)
          .lineHeight(type.settingsRow.lineHeight)
          .fontColor(appStore.theme.p.danger)
          .width('100%')
          .constraintSize({ minHeight: 50 })
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .backgroundColor(this.confirmKey === 'conn' ? appStore.theme.p.danger : Color.Transparent)
          .onClick(() => this.removeConn(this.detail() as ImConnection))
      }
      .width('calc(100% - 28vp)')
      .backgroundColor(appStore.theme.p.card)
      .borderRadius(radius.card)
      .border({ width: this.hairline(), color: appStore.theme.p.line })
      .margin({ left: 14, right: 14, top: 16 })
      .clip(true)
      .shadow({ radius: 0, color: Color.Transparent, offsetX: 0, offsetY: 0 })
    }
  }

  // One chat: its name, the group binding, and removal.
  @Builder
  chatRow(conn: ImConnection, key: string) {
    Column({ space: 0 }) {
      Row({ space: 10 }) {
        Column({ space: 2 }) {
          Text(this.chatName(conn, key))
            .fontSize(type.settingsRow.fontSize)
            .lineHeight(type.settingsRow.lineHeight)
            .fontColor(appStore.theme.p.ink)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text((conn.chats?.[key]?.kind === 'group' ? t('Group') : t('Direct')) + this.chatTargetNote(conn, key))
            .fontSize(type.small.fontSize)
            .lineHeight(type.small.lineHeight)
            .fontColor(appStore.theme.p.ink3)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Text(this.confirmKey === `c:${key}` ? t('Remove?') : t('Remove'))
          .fontSize(type.small.fontSize)
          .lineHeight(type.small.lineHeight)
          .fontColor(appStore.theme.p.danger)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .borderRadius(14)
          .backgroundColor(this.confirmKey === `c:${key}` ? appStore.theme.p.danger : Color.Transparent)
          .onClick(() => this.removeChat(conn, key))
      }
      .constraintSize({ minHeight: 50 })
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
      .alignItems(VerticalAlign.Center)
      if (conn.chats?.[key]?.kind === 'group') {
        Row({ space: 10 }) {
          Text(t('Bound to'))
            .fontSize(type.settingsRow.fontSize)
            .lineHeight(type.settingsRow.lineHeight)
            .fontColor(appStore.theme.p.ink)
            .layoutWeight(1)
          Text(this.chatTargetName(conn, key))
            .fontSize(type.settingsRow.fontSize)
            .lineHeight(type.settingsRow.lineHeight)
            .fontColor(appStore.theme.p.ink2)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('⌄')
            .fontSize(12)
            .fontColor(appStore.theme.p.ink3)
        }
        .constraintSize({ minHeight: 50 })
        .width('100%')
        .padding({ left: 16, right: 16, top: 4, bottom: 10 })
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.chatPickKey = key
          this.chatPickOpen = true
        })
      }
    }
    .width('100%')
  }

  private chatTargetName(conn: ImConnection, key: string): string {
    const target = conn.chats?.[key]?.target
    if (target === undefined) return t('Not bound')
    if (target.botId !== undefined) return this.botName(target.botId)
    if (target.roomId !== undefined) return this.roomName(target.roomId)
    return t('Not bound')
  }

  private chatTargetNote(conn: ImConnection, key: string): string {
    const target = conn.chats?.[key]?.target
    if (target === undefined) return ''
    const name = this.chatTargetName(conn, key)
    return name !== t('Not bound') ? ` · ${t('Talks to {bot}', { 'bot': name })}` : ''
  }
}

@Builder
export function ImBuilder() {
  Im()
}
