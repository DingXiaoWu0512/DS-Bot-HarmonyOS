// The group's settings form (mobile/src/screens/manage.tsx GroupSettings):
// name and notice, who answers, member ticks with the admin role, and the
// delete group danger row. Every change writes through update-room.

import { appStore, type } from '../components/Theme'
import { t } from '../common/ui/i18n'
import type { Bot, Room, TeamState } from '../common/team/types'
import { Avatar } from '../components/Marks'
import { Icon } from '../components/Icon'
import { BackRow, FormSection, FormFieldBlock, Segmented, SectionDivider, DangerRow } from '../components/FormControls'
import type { SegmentOption } from '../components/FormControls'
import { readStringParam } from './routes'

interface UpdateRoomPayload {
  id: string
  name?: string
  notice?: string
  mode?: string
  admin?: string | null
  members?: string[]
}

interface RoomIdPayload {
  id: string
}

interface CodedError {
  code?: string
}

function roomOf(team: TeamState | null, id: string): Room | null {
  for (const room of team?.rooms ?? []) {
    if (room.id === id) return room
  }
  return null
}

// Built per render so the labels follow the language setting.
function roomModes(): SegmentOption[] {
  const modes: SegmentOption[] = [
    { id: 'admin', label: t('Admin leads') },
    { id: 'everyone', label: t('Everyone') },
  ]
  return modes
}

@ComponentV2
export struct GroupSettings {
  @Local pathStack: NavPathStack | null = null
  @Local roomId: string = ''
  @Local refreshTick: number = 0
  @Local writeError: string = ''

  private team(): TeamState | null {
    void this.refreshTick
    return appStore.link.team
  }

  private room(): Room | null {
    return roomOf(this.team(), this.roomId)
  }

  private bots(): Bot[] {
    return this.team()?.bots ?? []
  }

  private hairline(): number {
    return this.getUIContext().px2vp(1)
  }

  private memberIds(): string[] {
    return this.room()?.members ?? []
  }

  private inRoom(botId: string): boolean {
    for (const id of this.memberIds()) {
      if (id === botId) return true
    }
    return false
  }

  // The mode stays a leader mode only while that leader is still a Bot.
  private mode(): string {
    const admin = this.room()?.admin
    if (admin !== undefined && admin !== '') {
      for (const bot of this.bots()) {
        if (bot.id === admin) return this.room()?.mode ?? 'admin'
      }
    }
    return 'everyone'
  }

  private goBack(): void {
    if (this.pathStack !== null) this.pathStack.pop()
  }

  private home(): void {
    appStore.forgetChat()
    if (this.pathStack !== null) this.pathStack.clear()
  }

  private async run(endpoint: string, payload: Object, done?: () => void): Promise<void> {
    const controller = appStore.link.controller
    if (controller === null) return
    try {
      await controller.call(endpoint, payload)
      this.writeError = ''
      if (done !== undefined) done()
    } catch (failure) {
      if ((failure as CodedError)?.code === 'unlock/canceled') return
      this.writeError = failure instanceof Error ? failure.message : String(failure)
    }
  }

  private update(patch: UpdateRoomPatch): void {
    const payload: UpdateRoomPayload = { id: this.roomId }
    if (patch.name !== undefined) payload.name = patch.name
    if (patch.notice !== undefined) payload.notice = patch.notice
    if (patch.mode !== undefined) payload.mode = patch.mode
    if (patch.adminSet) payload.admin = patch.admin ?? null
    if (patch.adminClear) payload.admin = null
    if (patch.members !== undefined) payload.members = patch.members
    void this.run('update-room', payload)
  }

  private toggleMember(botId: string): void {
    const next: string[] = []
    for (const id of this.memberIds()) {
      if (id !== botId) next.push(id)
    }
    if (!this.inRoom(botId)) next.push(botId)
    this.update({ members: next })
  }

  private remove(): void {
    const payload: RoomIdPayload = { id: this.roomId }
    void this.run('delete-room', payload, (): void => this.home())
  }

  private roomName(): string {
    return this.room()?.name ?? ''
  }

  private savedName(): string {
    if (this.room()?.named === true) return this.room()?.name ?? ''
    return ''
  }

  private adminId(): string {
    return this.room()?.admin ?? ''
  }

  build() {
    NavDestination() {
      Column() {
        BackRow({
          label: t('Group settings'),
          onBack: (): void => this.goBack(),
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
            FormSection({ label: t('Profile') }) {
              FormFieldBlock({
                label: t('Name'),
                text: this.savedName(),
                placeholder: t('Name after members'),
                onSave: (next: string): void => this.update({ name: next }),
              })
              SectionDivider()
              FormFieldBlock({
                label: t('Notice'),
                text: this.room()?.notice ?? '',
                placeholder: t('Shared instructions every member reads before speaking…'),
                multiline: true,
                onSave: (next: string): void => this.update({ notice: next }),
              })
            }
            FormSection({ label: t('Who answers') }) {
              Column() {
                Segmented({
                  value: this.mode(),
                  onPick: (id: string): void => this.update({ mode: id }),
                  options: roomModes(),
                })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 12 })
            }
            FormSection({ label: t('Members · {count}', { 'count': this.memberIds().length }) }) {
              ForEach(this.bots(), (bot: Bot, index: number) => {
                if (index > 0) {
                  SectionDivider()
                }
                this.memberRow(bot)
              }, (bot: Bot) => bot.id)
            }
            FormSection({ label: t('Danger') }) {
              DangerRow({
                label: t('Delete group'),
                confirmLabel: t('Delete {name}?', { 'name': this.roomName() }),
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
      this.roomId = readStringParam(ctx.pathInfo.param, 'roomId')
    })
    .onShown(() => {
      this.refreshTick += 1
    })
  }

  // Tick to add or remove a member; among members, the admin is marked and
  // another member can take the role.
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
      .onClick(() => this.toggleMember(bot.id))
      if (bot.id === this.adminId()) {
        Text(t('Admin'))
          .fontSize(type.caption.fontSize)
          .lineHeight(type.caption.lineHeight)
          .fontColor(appStore.theme.p.accent)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(6)
          .backgroundColor(appStore.theme.p.hover)
          .onClick(() => this.update({ adminClear: true }))
      } else if (this.inRoom(bot.id)) {
        Text(t('Make admin'))
          .fontSize(type.caption.fontSize)
          .lineHeight(type.caption.lineHeight)
          .fontColor(appStore.theme.p.ink3)
          .padding({ left: 6, right: 6, top: 6, bottom: 6 })
          .onClick(() => this.update({ adminSet: true, admin: bot.id }))
      }
      Column() {
        if (this.inRoom(bot.id)) {
          Icon({ name: 'check', iconSize: 14, color: appStore.theme.p.accentInk })
        }
      }
      .width(22)
      .height(22)
      .borderRadius(11)
      .border({ width: 1.5, color: this.inRoom(bot.id) ? appStore.theme.p.accent : appStore.theme.p.line2 })
      .backgroundColor(this.inRoom(bot.id) ? appStore.theme.p.accent : Color.Transparent)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .margin({ left: 4 })
      .onClick(() => this.toggleMember(bot.id))
    }
    .constraintSize({ minHeight: 50 })
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .alignItems(VerticalAlign.Center)
  }
}

// The update-room patch shape; `adminSet`/`adminClear` mark explicit writes
// (the wire value is a string or null).
interface UpdateRoomPatch {
  name?: string
  notice?: string
  mode?: string
  admin?: string
  adminSet?: boolean
  adminClear?: boolean
  members?: string[]
}

@Builder
export function GroupSettingsBuilder() {
  GroupSettings()
}
