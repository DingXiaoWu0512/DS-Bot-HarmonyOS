// The Bot's details pane (mobile/src/screens/manage.tsx BotDetails): who it
// is, then model, permission, folder, instructions, memory, usage and
// scheduled tasks. Its gear opens the Bot settings; its Browser tab jumps to
// the Bot browser route.

import { appStore, type, radius } from '../components/Theme'
import { t } from '../common/ui/i18n'
import type { Bot, TeamState } from '../common/team/types'
import { Avatar } from '../components/Marks'
import { Icon } from '../components/Icon'
import { ModelMenu } from './ModelMenu'
import { readStringParam } from './routes'
import type { MemoryParam, SchedulesParam, FolderParam, UsageParam, BotEditParam, BotBrowserParam } from './routes'

interface PermissionOption {
  value: string
  name: string
}

interface TokenUsage {
  uncachedInputTokens?: number
  cacheReadTokens?: number
  cacheWriteTokens?: number
  outputTokens?: number
}

interface RunStatsReply {
  tokenUsage?: TokenUsage | null
}

interface MemoryViewReply {
  entries?: Object[]
}

interface ScheduleTask {
  id: string
  botId?: string
  status?: string
  title?: string
}

interface SchedulesReply {
  available?: boolean
  tasks?: ScheduleTask[]
}

interface CodedError {
  code?: string
}

const PRESET_LABELS: Record<string, string> = {
  'read-only': 'Read only',
  'workspace-write': 'Workspace',
  'danger-full-access': 'Full access',
}

function botOf(team: TeamState | null, id: string): Bot | null {
  for (const bot of team?.bots ?? []) {
    if (bot.id === id) return bot
  }
  return null
}

function isMain(team: TeamState | null, id: string): boolean {
  const mains: string[] = team?.mainBotIds ?? (team?.mainBotId !== undefined && team.mainBotId !== null ? [team.mainBotId] : [])
  for (const main of mains) {
    if (main === id) return true
  }
  return false
}

// text.js formatTokens: compact token counts for the usage line.
function formatTokens(count: number): string {
  if (count >= 1000000) return `${(count / 1000000).toFixed(1)}M`
  if (count >= 1000) return `${(count / 1000).toFixed(1)}K`
  return String(count)
}

// The folder row names the folder by its last segment, as the desktop does.
function folderName(workDir: string | undefined): string {
  if (workDir === undefined || workDir === '') return t('Team workspace')
  const parts = workDir.split('\\').join('/').split('/')
  let last = ''
  for (const part of parts) {
    if (part !== '') last = part
  }
  if (last !== '') return last
  return t('Team workspace')
}

@ComponentV2
export struct BotDetails {
  @Local pathStack: NavPathStack | null = null
  @Local botId: string = ''
  @Local refreshTick: number = 0
  @Local writeError: string = ''
  @Local pendingPermission: string = ''
  @Local memoryCount: number = -1
  @Local usageText: string = ''
  @Local schedulesAvailable: boolean = true
  @Local scheduleTasks: ScheduleTask[] = []

  private team(): TeamState | null {
    void this.refreshTick
    return appStore.link.team
  }

  private bot(): Bot | null {
    return botOf(this.team(), this.botId)
  }

  private avatarBot(): Bot | undefined {
    const bot = this.bot()
    if (bot === null) return undefined
    return bot
  }

  // A Bot to hand the model menu; only reached while the pane has one.
  private menuBot(): Bot {
    const bot = this.bot()
    if (bot !== null) return bot
    return { id: '', name: '' }
  }

  private main(): boolean {
    return isMain(this.team(), this.botId)
  }

  private hairline(): number {
    return this.getUIContext().px2vp(1)
  }

  private permissionOptions(): PermissionOption[] {
    return this.team()?.permissions?.options ?? []
  }

  private savedPermission(): string {
    const bot = this.bot()
    if (bot === null) return ''
    const fallback = this.team()?.permissions?.defaultPreset
    if (bot.permission !== undefined) return bot.permission
    if (fallback !== undefined) return fallback
    return ''
  }

  private currentPermission(): string {
    if (this.pendingPermission !== '') return this.pendingPermission
    return this.savedPermission()
  }

  private isOn(value: string): boolean {
    return value === this.currentPermission()
  }

  private presetLabel(option: PermissionOption): string {
    const mapped = PRESET_LABELS[option.value]
    if (mapped !== undefined) return t(mapped)
    return option.name
  }

  private memoryLabel(): string {
    if (this.memoryCount < 0) return t('Loading…')
    if (this.memoryCount === 0) return t('Nothing saved yet')
    if (this.memoryCount === 1) return t('1 entry')
    return t('{count} entries', { 'count': this.memoryCount })
  }

  private activeTasks(): ScheduleTask[] {
    const tasks: ScheduleTask[] = []
    for (const task of this.scheduleTasks) {
      if (task.botId === this.botId && task.status === 'active') tasks.push(task)
    }
    return tasks
  }

  private scheduleTitle(): string {
    const count = this.activeTasks().length
    if (count === 0) return t('Scheduled tasks')
    return t('Scheduled tasks · {count}', { 'count': count })
  }

  private goBack(): void {
    if (this.pathStack !== null) this.pathStack.pop()
  }

  private push(route: string, param: Object | null): void {
    if (this.pathStack !== null) this.pathStack.pushPathByName(route, param)
  }

  private botEditParam(): BotEditParam {
    return { botId: this.botId }
  }

  private browserParam(): BotBrowserParam {
    return { botId: this.botId }
  }

  private memoryParam(): MemoryParam {
    return { botId: this.botId }
  }

  private schedulesParam(): SchedulesParam {
    return { botId: this.botId, sessionId: this.bot()?.sessionId ?? '' }
  }

  private folderParam(): FolderParam {
    return { pick: 'bot', botId: this.botId, current: this.bot()?.workDir ?? '' }
  }

  private usageParam(): UsageParam {
    return { botId: this.botId }
  }

  private refresh(): void {
    this.refreshTick += 1
    void this.loadMemory()
    void this.loadUsage()
    void this.loadSchedules()
  }

  private async loadMemory(): Promise<void> {
    const controller = appStore.link.controller
    if (controller === null) return
    const payload: Record<string, Object> = { 'botId': this.botId }
    try {
      const view = (await controller.call('memory-view', payload)) as MemoryViewReply | null
      this.memoryCount = view?.entries?.length ?? 0
    } catch {
      // The count stays at its loading label.
    }
  }

  private async loadUsage(): Promise<void> {
    const controller = appStore.link.controller
    if (controller === null) return
    const payload: Record<string, Object> = { 'botId': this.botId }
    try {
      const stats = (await controller.call('run-stats', payload)) as RunStatsReply | null
      const usage: TokenUsage | null | undefined = stats?.tokenUsage
      if (usage === null || usage === undefined) return
      const input = (usage.uncachedInputTokens ?? 0) + (usage.cacheReadTokens ?? 0) + (usage.cacheWriteTokens ?? 0)
      const output = usage.outputTokens ?? 0
      if (input + output === 0) {
        this.usageText = ''
        return
      }
      const hit = input > 0 ? Math.round((usage.cacheReadTokens ?? 0) / input * 100) : 0
      this.usageText = t('{tokens} tok · Cache hit {hit}%', { 'tokens': formatTokens(input + output), 'hit': hit })
    } catch {
      // Usage stays hidden.
    }
  }

  private async loadSchedules(): Promise<void> {
    const controller = appStore.link.controller
    if (controller === null) return
    try {
      const view = (await controller.call('schedules')) as SchedulesReply | null
      if (view === null || view === undefined) return
      this.schedulesAvailable = view.available !== false
      const tasks: ScheduleTask[] = []
      for (const task of view.tasks ?? []) {
        if (task.botId === this.botId && task.status === 'active') tasks.push(task)
      }
      this.scheduleTasks = tasks
    } catch {
      // The schedule list stays as it was.
    }
  }

  private async savePermission(value: string): Promise<void> {
    this.pendingPermission = value
    const controller = appStore.link.controller
    if (controller === null) {
      this.pendingPermission = ''
      return
    }
    const payload: Record<string, Object> = { 'id': this.botId, 'permission': value }
    try {
      await controller.call('update-bot', payload)
      this.writeError = ''
    } catch (failure) {
      if ((failure as CodedError)?.code === 'unlock/canceled') return
      this.writeError = failure instanceof Error ? failure.message : String(failure)
    } finally {
      this.pendingPermission = ''
    }
  }

  @Builder
  roundButton(icon: string, iconSize: number, label: string, action: () => void) {
    Column() {
      Icon({ name: icon, iconSize: iconSize, color: appStore.theme.p.ink2 })
    }
    .width(40)
    .height(40)
    .borderRadius(20)
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .border({ width: this.hairline(), color: appStore.theme.p.line })
    .backgroundColor(appStore.theme.p.card)
    .accessibilityText(label)
    .onClick(() => action())
  }

  @Builder
  detailTitle(text: string) {
    Text(text)
      .fontSize(type.caption.fontSize)
      .lineHeight(type.caption.lineHeight)
      .fontColor(appStore.theme.p.ink2)
      .margin({ top: 18, bottom: 8 })
  }

  @Builder
  tabs() {
    Row() {
      Column() {
        Text(t('Details'))
          .fontSize(type.small.fontSize)
          .lineHeight(type.small.lineHeight)
          .fontWeight('500')
          .fontColor(appStore.theme.p.ink)
      }
      .constraintSize({ minWidth: 64 })
      .height(32)
      .borderRadius(8)
      .padding({ left: 12, right: 12 })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(appStore.theme.p.card)
      Column() {
        Text(t('Browser'))
          .fontSize(type.small.fontSize)
          .lineHeight(type.small.lineHeight)
          .fontColor(appStore.theme.p.ink2)
      }
      .constraintSize({ minWidth: 64 })
      .height(32)
      .borderRadius(8)
      .padding({ left: 12, right: 12 })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .onClick(() => this.push('botBrowser', this.browserParam()))
    }
    .borderRadius(10)
    .padding(2)
    .backgroundColor(appStore.theme.p.hover)
    .margin({ top: 14 })
    .alignSelf(ItemAlign.Center)
  }

  @Builder
  permissionPicker() {
    Row() {
      ForEach(this.permissionOptions(), (option: PermissionOption) => {
        Column() {
          Text(this.presetLabel(option))
            .fontSize(type.small.fontSize)
            .lineHeight(type.small.lineHeight)
            .fontWeight(this.isOn(option.value) ? '500' : '400')
            .fontColor(option.value === 'danger-full-access' ? appStore.theme.p.danger
              : (this.isOn(option.value) ? appStore.theme.p.ink : appStore.theme.p.ink2))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .constraintSize({ minHeight: 36 })
        .padding({ left: 6, right: 6, top: 6, bottom: 6 })
        .borderRadius(8)
        .backgroundColor(this.isOn(option.value) ? appStore.theme.p.card : Color.Transparent)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .onClick(() => {
          if (!this.isOn(option.value)) void this.savePermission(option.value)
        })
      }, (option: PermissionOption) => option.value)
    }
    .borderRadius(10)
    .padding(2)
    .width('100%')
    .backgroundColor(appStore.theme.p.hover)
  }

  @Builder
  dropdownRow(label: string, action: () => void) {
    Row({ space: 8 }) {
      Text(label)
        .fontSize(type.settingsRow.fontSize)
        .lineHeight(type.settingsRow.lineHeight)
        .fontColor(appStore.theme.p.ink)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text('⌄')
        .fontSize(12)
        .fontColor(appStore.theme.p.ink3)
    }
    .constraintSize({ minHeight: 48 })
    .width('100%')
    .borderRadius(radius.card)
    .border({ width: this.hairline(), color: appStore.theme.p.line })
    .backgroundColor(appStore.theme.p.card)
    .padding({ left: 14, right: 14 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => action())
  }

  @Builder
  memoryRow() {
    Row({ space: 8 }) {
      Text(this.memoryLabel())
        .fontSize(type.settingsRow.fontSize)
        .lineHeight(type.settingsRow.lineHeight)
        .fontColor(appStore.theme.p.ink)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(t('Manage'))
        .fontSize(type.small.fontSize)
        .lineHeight(type.small.lineHeight)
        .fontColor(appStore.theme.p.ink3)
      Icon({ name: 'chevronRight', iconSize: 20, color: appStore.theme.p.ink3 })
    }
    .constraintSize({ minHeight: 48 })
    .width('100%')
    .borderRadius(radius.card)
    .border({ width: this.hairline(), color: appStore.theme.p.line })
    .backgroundColor(appStore.theme.p.card)
    .padding({ left: 14, right: 14 })
    .alignItems(VerticalAlign.Center)
    .accessibilityText(t("Manage {name}'s memory", { 'name': this.bot()?.name ?? '' }))
    .onClick(() => this.push('memory', this.memoryParam()))
  }

  @Builder
  usageRow() {
    if (this.usageText !== '') {
      Row() {
        Text(this.bot()?.name ?? '')
          .fontSize(type.small.fontSize)
          .lineHeight(type.small.lineHeight)
          .fontColor(appStore.theme.p.ink2)
        Text(this.usageText)
          .fontSize(type.small.fontSize)
          .lineHeight(type.small.lineHeight)
          .fontColor(appStore.theme.p.ink)
      }
      .width('100%')
      .constraintSize({ minHeight: 32 })
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.SpaceBetween)
      .onClick(() => this.push('usage', this.usageParam()))
    }
  }

  @Builder
  scheduleRows() {
    if (this.activeTasks().length === 0) {
      Text(this.schedulesAvailable ? t('No scheduled tasks yet. Add one')
        : t('Switch on Automation tasks on the Plugins page in Settings.'))
        .fontSize(type.small.fontSize)
        .lineHeight(type.small.lineHeight)
        .fontColor(appStore.theme.p.ink3)
        .width('100%')
        .constraintSize({ minHeight: 32 })
        .onClick(() => this.push('schedules', this.schedulesParam()))
    } else {
      ForEach(this.activeTasks().slice(0, 3), (task: ScheduleTask) => {
        Text(task.title ?? '')
          .fontSize(type.small.fontSize)
          .lineHeight(type.small.lineHeight)
          .fontColor(appStore.theme.p.ink)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .constraintSize({ minHeight: 36 })
          .onClick(() => this.push('schedules', this.schedulesParam()))
      }, (task: ScheduleTask) => task.id)
    }
  }

  @Builder
  instructionsBlock() {
    if ((this.bot()?.instructions ?? '') !== '') {
      Text(this.bot()?.instructions ?? '')
        .fontSize(type.small.fontSize)
        .lineHeight(type.small.lineHeight)
        .fontColor(appStore.theme.p.ink2)
        .maxLines(5)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ top: 14 })
    } else {
      Column() {
        Text(t('Add instructions in Bot settings'))
          .fontSize(type.small.fontSize)
          .lineHeight(type.small.lineHeight)
          .fontColor(appStore.theme.p.ink3)
      }
      .width('100%')
      .padding({ top: 14, bottom: 14 })
      .alignItems(HorizontalAlign.Center)
      .onClick(() => this.push('botEdit', this.botEditParam()))
    }
  }

  build() {
    NavDestination() {
      Stack() {
        Scroll() {
          Column() {
            if (this.bot() === null) {
              Column()
                .width('100%')
                .layoutWeight(1)
            } else {
              Column() {
                Avatar({
                  bot: this.avatarBot(),
                  dark: appStore.theme.dark,
                  markSize: 64,
                  ring: appStore.theme.p.main,
                  main: this.main(),
                })
                Text(this.bot()?.name ?? '')
                  .fontSize(18)
                  .lineHeight(24)
                  .fontWeight(type.rowName.fontWeight)
                  .fontColor(appStore.theme.p.ink)
                  .margin({ top: 10 })
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if ((this.bot()?.role ?? '') !== '') {
                  Text(this.bot()?.role ?? '')
                    .fontSize(type.caption.fontSize)
                    .lineHeight(type.caption.lineHeight)
                    .fontColor(appStore.theme.p.ink3)
                    .margin({ top: 2 })
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
              }
              .width('100%')
              .padding({ top: 4 })
              .alignItems(HorizontalAlign.Center)
              this.tabs()
              if (this.writeError !== '') {
                Text(this.writeError)
                  .fontSize(type.small.fontSize)
                  .lineHeight(type.small.lineHeight)
                  .fontColor(appStore.theme.p.danger)
                  .width('100%')
                  .margin({ top: 10 })
              }
              this.detailTitle(t('Model'))
              ModelMenu({
                bot: this.menuBot(),
                onManage: (): void => this.push('settings', null),
              })
              if (this.permissionOptions().length > 0) {
                this.detailTitle(t('Permissions'))
                this.permissionPicker()
              }
              this.detailTitle(t('Working folder'))
              this.dropdownRow(folderName(this.bot()?.workDir), (): void => this.push('folder', this.folderParam()))
              this.instructionsBlock()
              if (this.team()?.memory !== false) {
                this.detailTitle(t('Memory'))
                this.memoryRow()
              }
              if (this.usageText !== '') {
                this.detailTitle(t('Usage'))
                this.usageRow()
              }
              this.detailTitle(this.scheduleTitle())
              this.scheduleRows()
            }
          }
          .width('100%')
          // Full-bleed: the list scrolls under the status bar and the floating
          // header row; both safe insets live in the scrolled content so no
          // fixed solid band shows.
          .padding({ left: 18, right: 18, top: appStore.safeTop + 56, bottom: appStore.safeBottom + 40 })
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .align(Alignment.Top)

        // Floating header row: back and gear over the full-bleed list —
        // transparent chrome, no fixed header band.
        Row({ space: 8 }) {
          this.roundButton('chevronLeft', 20, t('Back'), (): void => this.goBack())
          Column()
            .layoutWeight(1)
          this.roundButton('gear', 18, t('Edit Bot'), (): void => this.push('botEdit', this.botEditParam()))
        }
        .width('100%')
        .padding({ left: 12, right: 12 })
        .alignItems(VerticalAlign.Center)
        .position({ x: 0, y: appStore.safeTop })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(appStore.theme.p.main)
    }
    .hideTitleBar(true)
    .backgroundColor(appStore.theme.p.main)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack
      this.botId = readStringParam(ctx.pathInfo.param, 'botId')
    })
    .onShown(() => {
      // Summaries refresh while the pane is open, the way the REF re-read on
      // every team revision.
      this.refresh()
    })
  }
}

@Builder
export function BotDetailsBuilder() {
  BotDetails()
}
