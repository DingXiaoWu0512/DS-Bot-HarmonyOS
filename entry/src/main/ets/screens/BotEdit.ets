// The Bot settings screen (mobile/src/screens/manage.tsx BotEdit): profile
// fields, character shape and color, photo, model, instructions, privacy,
// Main Bot, capabilities, duplicate and delete. Every change saves through the
// same update-bot endpoint the desktop calls.

import { common } from '@kit.AbilityKit'
import { appStore, type } from '../components/Theme'
import { t } from '../common/ui/i18n'
import type { Bot, BotAvatar, CapabilityInfo, TeamState } from '../common/team/types'
import { Avatar } from '../components/Marks'
import { FormRow, FormSection, FormFieldBlock, SwitchRow, SectionDivider, DangerRow, BackRow } from '../components/FormControls'
import { CharacterShapeGrid, CharacterColorGrid } from '../components/CharacterPick'
import { ModelMenu } from './ModelMenu'
import { readStringParam } from './routes'
import { pickAvatar } from '../platform/Platform'
import type { ChatTarget } from '../appstate/AppStore'

interface SetMainPayload {
  id: string
  main: boolean
}

interface BotCapabilityPayload {
  botId: string
  name: string
  attached: boolean
}

interface BotIdPayload {
  id: string
}

interface DuplicateReply {
  id?: string
}

interface CodedError {
  code?: string
}

export interface CapabilityStatus {
  state?: string
  error?: string
}

// settings-pages.tsx capabilityStatusText: the attach status line under a
// capability switch, shown while the library item is attached.
export function capabilityStatusText(status: CapabilityStatus | undefined): string | undefined {
  if (status === undefined) return undefined
  if (status.state === 'ready') return t('Ready')
  if (status.state === 'needs-approval') return t('Needs approval')
  if (status.state === 'error') return t('Could not connect: {error}', { 'error': status.error ?? '' })
  return t('Connecting…')
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

// The per-Bot capability statuses; the host also carries a bare team-wide
// status under the same key, which carries no per-Bot map.
function botStatuses(team: TeamState | null, botId: string): Record<string, CapabilityStatus> {
  const all = team?.capabilityStatuses
  if (all === undefined) return {}
  const entry = all[botId]
  if (entry === undefined || entry === null) return {}
  const probe = entry as Record<string, Object>
  if (typeof probe['state'] === 'string') return {}
  return entry as Record<string, CapabilityStatus>
}

// The desktop's BotCapabilitiesCard: packs first, then by name.
function libraryItems(team: TeamState | null): CapabilityInfo[] {
  const packs: CapabilityInfo[] = []
  const rest: CapabilityInfo[] = []
  for (const item of team?.capabilities ?? []) {
    const entry: CapabilityInfo = { name: item.name, kind: item.kind }
    if (entry.kind === 'pack') packs.push(entry)
    else rest.push(entry)
  }
  const sorted = rest.sort((a: CapabilityInfo, b: CapabilityInfo): number => a.name.localeCompare(b.name))
  return packs.concat(sorted)
}

@ComponentV2
export struct BotEdit {
  @Local pathStack: NavPathStack | null = null
  @Local botId: string = ''
  @Local refreshTick: number = 0
  @Local writeError: string = ''
  @Local busy: boolean = false

  private team(): TeamState | null {
    void this.refreshTick
    return appStore.link.team
  }

  private bot(): Bot | null {
    return botOf(this.team(), this.botId)
  }

  private main(): boolean {
    return isMain(this.team(), this.botId)
  }

  private hairline(): number {
    return this.getUIContext().px2vp(1)
  }

  private library(): CapabilityInfo[] {
    return libraryItems(this.team())
  }

  private statuses(): Record<string, CapabilityStatus> {
    return botStatuses(this.team(), this.botId)
  }

  private goBack(): void {
    if (this.pathStack !== null) this.pathStack.pop()
  }

  private home(): void {
    // Back to the chat home; the shell falls back to its Main Bot when the
    // remembered chat is gone.
    appStore.forgetChat()
    if (this.pathStack !== null) this.pathStack.clear()
  }

  private openBot(botId: string): void {
    const target: ChatTarget = { kind: 'bot', id: botId }
    appStore.openChat(target)
    if (this.pathStack !== null) this.pathStack.clear()
  }

  private async run(endpoint: string, payload: Object, done?: (value: Object | null) => void): Promise<void> {
    const controller = appStore.link.controller
    if (controller === null) return
    this.busy = true
    try {
      const value = (await controller.call(endpoint, payload)) as Object | null
      this.writeError = ''
      if (done !== undefined) done(value)
    } catch (failure) {
      if ((failure as CodedError)?.code === 'unlock/canceled') return
      this.writeError = failure instanceof Error ? failure.message : String(failure)
    } finally {
      this.busy = false
    }
  }

  private save(patch: UpdateBotPatch): void {
    const payload: Record<string, Object> = { 'id': this.botId }
    if (patch.name !== undefined) payload['name'] = patch.name
    if (patch.role !== undefined) payload['role'] = patch.role
    if (patch.avatar !== undefined) payload['avatar'] = patch.avatar
    if (patch.color !== undefined) payload['color'] = patch.color
    if (patch.privat !== undefined) payload['private'] = patch.privat
    if (patch.instructions !== undefined) payload['instructions'] = patch.instructions
    void this.run('update-bot', payload)
  }

  private avatarWithShape(shape: string): BotAvatar {
    const next: BotAvatar = { shape: shape }
    const image = this.bot()?.avatar?.image
    if (image !== undefined) next.image = image
    const imageRef = this.bot()?.avatar?.imageRef
    if (imageRef !== undefined) next.imageRef = imageRef
    return next
  }

  private avatarWithImage(image: string): BotAvatar {
    const next: BotAvatar = { image: image }
    const shape = this.bot()?.avatar?.shape
    if (shape !== undefined) next.shape = shape
    return next
  }

  private avatarWithoutImage(): BotAvatar {
    const next: BotAvatar = {}
    const shape = this.bot()?.avatar?.shape
    if (shape !== undefined) next.shape = shape
    return next
  }

  private uploadPhoto(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    void pickAvatar(context).then((image: string | null): void => {
      if (image !== null) this.save({ avatar: this.avatarWithImage(image) })
    })
  }

  private duplicate(): void {
    const payload: BotIdPayload = { id: this.botId }
    void this.run('duplicate-bot', payload, (value: Object | null): void => {
      const newBot = (value ?? {}) as DuplicateReply
      if (newBot.id !== undefined && newBot.id !== '') this.openBot(newBot.id)
    })
  }

  private remove(): void {
    const payload: BotIdPayload = { id: this.botId }
    void this.run('delete-bot', payload, (): void => this.home())
  }

  private setMain(next: boolean): void {
    const payload: SetMainPayload = { id: this.botId, main: next }
    void this.run('set-main', payload)
  }

  private setCapability(name: string, attached: boolean): void {
    const payload: BotCapabilityPayload = { botId: this.botId, name: name, attached: attached }
    void this.run('bot-capability', payload)
  }

  private botName(): string {
    return this.bot()?.name ?? ''
  }

  // A Bot to hand the sections; only reached while the screen has one.
  private editBot(): Bot {
    const bot = this.bot()
    if (bot !== null) return bot
    return { id: '', name: '' }
  }

  private botRole(): string {
    return this.bot()?.role ?? ''
  }

  private botShape(): string {
    return this.bot()?.avatar?.shape ?? 'star'
  }

  private botColor(): string {
    return this.bot()?.color ?? 'blue'
  }

  private hasPhoto(): boolean {
    return (this.bot()?.avatar?.image ?? '') !== ''
  }

  private isPrivate(): boolean {
    return this.bot()?.private === true
  }

  private attachedOf(item: CapabilityInfo): boolean {
    const attached: string[] = this.bot()?.capabilities ?? []
    for (const name of attached) {
      if (name === item.name) return true
    }
    return false
  }

  private statusHint(item: CapabilityInfo): string {
    if (!this.attachedOf(item)) return ''
    const text = capabilityStatusText(this.statuses()[item.name])
    if (text === undefined) return ''
    return text
  }

  @Builder
  capabilitySwitches() {
    ForEach(this.library(), (item: CapabilityInfo, index: number) => {
      if (index > 0) {
        SectionDivider()
      }
      SwitchRow({
        label: item.name,
        hint: this.statusHint(item),
        on: this.attachedOf(item),
        onChange: (next: boolean): void => this.setCapability(item.name, next),
      })
    }, (item: CapabilityInfo) => item.name)
  }

  build() {
    NavDestination() {
      Column() {
        BackRow({
          label: t('Settings'),
          onBack: (): void => this.goBack(),
        })
        Scroll() {
          Column() {
            Avatar({
              bot: this.editBot(),
              dark: appStore.theme.dark,
              markSize: 56,
              ring: appStore.theme.p.main,
            })
            if (this.writeError !== '') {
              Text(this.writeError)
                .fontSize(type.small.fontSize)
                .lineHeight(type.small.lineHeight)
                .fontColor(appStore.theme.p.danger)
                .width('100%')
                .padding({ left: 18, right: 18, top: 10 })
            }
            FormSection({ label: t('Profile') }) {
              FormFieldBlock({
                label: t('Name'),
                text: this.botName(),
                placeholder: 'Bob',
                onSave: (next: string): void => {
                  if (next !== '') this.save({ name: next })
                },
              })
              SectionDivider()
              FormFieldBlock({
                label: t('Label'),
                text: this.botRole(),
                placeholder: t('Research, admin…'),
                onSave: (next: string): void => this.save({ role: next }),
              })
            }
            FormSection({ label: t('Character shape') }) {
              CharacterShapeGrid({
                bot: this.editBot(),
                color: this.botColor(),
                picked: this.botShape(),
                onPick: (id: string): void => this.save({ avatar: this.avatarWithShape(id) }),
              })
            }
            FormSection({ label: t('Character color') }) {
              CharacterColorGrid({
                picked: this.botColor(),
                dark: appStore.theme.dark,
                onPick: (id: string): void => this.save({ color: id }),
              })
            }
            FormSection({ label: t('Photo') }) {
              FormRow({
                label: t('Upload photo'),
                hasAction: true,
                onPress: (): void => this.uploadPhoto(),
              })
              if (this.hasPhoto()) {
                SectionDivider()
                FormRow({
                  label: t('Remove photo'),
                  hasAction: true,
                  onPress: (): void => this.save({ avatar: this.avatarWithoutImage() }),
                })
              }
            }
            FormSection({ label: t('Model') }) {
              Column() {
                ModelMenu({
                  bot: this.editBot(),
                  onManage: (): void => {
                    if (this.pathStack !== null) this.pathStack.pushPathByName('settings', null)
                  },
                })
              }
              .width('100%')
              .padding(12)
            }
            FormSection({ label: t('Instructions') }) {
              FormFieldBlock({
                label: t('What this Bot does'),
                text: this.bot()?.instructions ?? '',
                placeholder: t('What this Bot is responsible for…'),
                multiline: true,
                onSave: (next: string): void => this.save({ instructions: next }),
              })
            }
            FormSection({ label: t('Privacy') }) {
              SwitchRow({
                label: t('Private'),
                hint: t('Other Bots cannot read its folder, memory or chats, and you approve what it shares with them.'),
                on: this.isPrivate(),
                onChange: (next: boolean): void => this.save({ privat: next }),
              })
            }
            if (!this.isPrivate()) {
              FormSection({ label: t('Main Bot') }) {
                SwitchRow({
                  label: t('Main Bot'),
                  hint: t('Can create and change Bots, and runs every group chat.'),
                  on: this.main(),
                  onChange: (next: boolean): void => this.setMain(next),
                })
              }
            }
            if (this.library().length > 0) {
              FormSection({ label: t('Capabilities') }) {
                this.capabilitySwitches()
              }
            }
            FormSection({ label: t('Bot') }) {
              if (!this.isPrivate()) {
                FormRow({
                  label: t('Duplicate'),
                  hint: t('A copy with the same job and model, and fresh memory.'),
                  hasAction: true,
                  onPress: (): void => this.duplicate(),
                })
                SectionDivider()
              }
              DangerRow({
                label: t('Delete Bot'),
                confirmLabel: t('Delete {name}?', { 'name': this.botName() }),
                onConfirm: (): void => this.remove(),
              })
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
    }
    .hideTitleBar(true)
    .padding({ top: appStore.safeTop })
    .backgroundColor(appStore.theme.p.main)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack
      this.botId = readStringParam(ctx.pathInfo.param, 'botId')
    })
    .onShown(() => {
      this.refreshTick += 1
    })
  }
}

// The update-bot patch shape for this screen; `privat` avoids the reserved
// word on the wire field `private`.
interface UpdateBotPatch {
  name?: string
  role?: string
  avatar?: BotAvatar
  color?: string
  privat?: boolean
  instructions?: string
}

@Builder
export function BotEditBuilder() {
  BotEdit()
}
