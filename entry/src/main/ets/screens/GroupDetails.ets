// The group's overview (mobile/src/screens/manage.tsx GroupDetails): the
// members with the admin marked, the notice, who answers, and the memory
// entry. Its gear opens the group settings.

import { appStore, type, radius } from '../components/Theme'
import { t } from '../common/ui/i18n'
import type { Bot, Room, TeamState } from '../common/team/types'
import { Avatar, RoomAvatar } from '../components/Marks'
import { Icon } from '../components/Icon'
import { readStringParam } from './routes'
import type { MemoryParam, GroupSettingsParam, BotDetailsParam } from './routes'

function roomOf(team: TeamState | null, id: string): Room | null {
  for (const room of team?.rooms ?? []) {
    if (room.id === id) return room
  }
  return null
}

function botOf(team: TeamState | null, id: string): Bot | null {
  for (const bot of team?.bots ?? []) {
    if (bot.id === id) return bot
  }
  return null
}

@ComponentV2
export struct GroupDetails {
  @Local pathStack: NavPathStack | null = null
  @Local roomId: string = ''
  @Local refreshTick: number = 0

  private team(): TeamState | null {
    void this.refreshTick
    return appStore.link.team
  }

  private room(): Room | null {
    return roomOf(this.team(), this.roomId)
  }

  private roomAvatarRoom(): Room | undefined {
    const room = this.room()
    if (room === null) return undefined
    return room
  }

  private hairline(): number {
    return this.getUIContext().px2vp(1)
  }

  private members(): Bot[] {
    const ids = this.room()?.members ?? []
    const members: Bot[] = []
    for (const id of ids) {
      const bot = botOf(this.team(), id)
      if (bot !== null) members.push(bot)
    }
    return members
  }

  private admin(): Bot | null {
    const admin = this.room()?.admin
    if (admin === undefined || admin === '') return null
    return botOf(this.team(), admin)
  }

  // The mode the desktop shows: the admin leads unless there is none.
  private mode(): string {
    if (this.admin() !== null) return this.room()?.mode ?? 'admin'
    return 'everyone'
  }

  private membersLine(): string {
    const admin = this.admin()
    const parts: string[] = [t('{count} members', { 'count': this.members().length })]
    if (admin !== null) {
      parts.push(t('Admin {name}', { 'name': admin.name }))
    } else {
      parts.push(t('No admin'))
    }
    return parts.join(' · ')
  }

  private goBack(): void {
    if (this.pathStack !== null) this.pathStack.pop()
  }

  private push(route: string, param: Object | null): void {
    if (this.pathStack !== null) this.pathStack.pushPathByName(route, param)
  }

  private settingsParam(): GroupSettingsParam {
    return { roomId: this.roomId }
  }

  private memberParam(botId: string): BotDetailsParam {
    return { botId: botId }
  }

  private memoryParam(): MemoryParam {
    return { roomId: this.roomId }
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
  memberRow(member: Bot) {
    Row({ space: 10 }) {
      Avatar({
        bot: member,
        dark: appStore.theme.dark,
        markSize: 32,
        ring: appStore.theme.p.main,
      })
      Column({ space: 2 }) {
        Row({ space: 6 }) {
          Text(member.name)
            .fontSize(type.settingsRow.fontSize)
            .lineHeight(type.settingsRow.lineHeight)
            .fontColor(appStore.theme.p.ink)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (member.id === (this.room()?.admin ?? '')) {
            Text(t('Admin'))
              .fontSize(11)
              .lineHeight(16)
              .fontColor(appStore.theme.p.ink3)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(6)
              .backgroundColor(appStore.theme.p.hover)
          }
        }
        .alignItems(VerticalAlign.Center)
        if ((member.role ?? '') !== '') {
          Text(member.role ?? '')
            .fontSize(type.caption.fontSize)
            .lineHeight(type.caption.lineHeight)
            .fontColor(appStore.theme.p.ink3)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .constraintSize({ minHeight: 48 })
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .onClick(() => this.push('botDetails', this.memberParam(member.id)))
  }

  build() {
    NavDestination() {
      Column() {
        Row({ space: 8 }) {
          this.roundButton('chevronLeft', 20, t('Back'), (): void => this.goBack())
          Column()
            .layoutWeight(1)
          this.roundButton('gear', 18, t('Group settings'), (): void => this.push('groupSettings', this.settingsParam()))
        }
        .width('100%')
        .padding({ left: 12, right: 12, bottom: 4 })
        .alignItems(VerticalAlign.Center)
        Scroll() {
          Column() {
            if (this.room() === null) {
              Column()
                .width('100%')
                .layoutWeight(1)
            } else {
              Column() {
                RoomAvatar({
                  room: this.roomAvatarRoom(),
                  bots: this.team()?.bots ?? [],
                  dark: appStore.theme.dark,
                  markSize: 56,
                  ring: appStore.theme.p.main,
                })
                Text(this.room()?.name ?? '')
                  .fontSize(18)
                  .lineHeight(24)
                  .fontWeight(type.rowName.fontWeight)
                  .fontColor(appStore.theme.p.ink)
                  .margin({ top: 10 })
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .textAlign(TextAlign.Center)
                Text(this.membersLine())
                  .fontSize(type.caption.fontSize)
                  .lineHeight(type.caption.lineHeight)
                  .fontColor(appStore.theme.p.ink3)
                  .margin({ top: 2 })
              }
              .width('100%')
              .padding({ top: 4 })
              .alignItems(HorizontalAlign.Center)
              if ((this.room()?.notice ?? '') !== '') {
                Text(this.room()?.notice ?? '')
                  .fontSize(type.small.fontSize)
                  .lineHeight(type.small.lineHeight)
                  .fontColor(appStore.theme.p.ink2)
                  .maxLines(5)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                  .margin({ top: 14 })
              } else {
                Column() {
                  Text(t('Add a notice in group settings'))
                    .fontSize(type.small.fontSize)
                    .lineHeight(type.small.lineHeight)
                    .fontColor(appStore.theme.p.ink3)
                }
                .width('100%')
                .padding({ top: 14, bottom: 14 })
                .alignItems(HorizontalAlign.Center)
                .onClick(() => this.push('groupSettings', this.settingsParam()))
              }
              this.detailTitle(t('Members · {count}', { 'count': this.members().length }))
              ForEach(this.members(), (member: Bot) => {
                this.memberRow(member)
              }, (member: Bot) => member.id)
              this.detailTitle(t('Who answers'))
              Text(this.mode() === 'admin' ? t('Admin leads') : t('Everyone'))
                .fontSize(type.small.fontSize)
                .lineHeight(type.small.lineHeight)
                .fontColor(appStore.theme.p.ink)
              if (this.team()?.memory !== false) {
                this.detailTitle(t('Memory'))
                Row({ space: 8 }) {
                  Text(t('Memory'))
                    .fontSize(type.settingsRow.fontSize)
                    .lineHeight(type.settingsRow.lineHeight)
                    .fontColor(appStore.theme.p.ink)
                    .layoutWeight(1)
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
                .onClick(() => this.push('memory', this.memoryParam()))
              }
            }
          }
          .width('100%')
          .padding({ left: 18, right: 18, bottom: appStore.safeBottom + 40 })
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
}

@Builder
export function GroupDetailsBuilder() {
  GroupDetails()
}
