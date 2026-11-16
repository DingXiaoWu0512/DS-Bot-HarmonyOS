// The folder browser (mobile/src/screens/manage.tsx Folder): recent folders,
// level-by-level listing, and "Use this folder", which writes the picked path
// to the Bot's workDir, the team workspace or a room's workDir.

import { appStore, type } from '../components/Theme'
import { t } from '../common/ui/i18n'
import { FormSection, BackRow } from '../components/FormControls'
import { Icon } from '../components/Icon'
import { readStringParam, optionalStringParam } from './routes'

interface FolderEntry {
  name: string
  path: string
}

interface FolderListing {
  path: string
  parent?: string | null
  entries?: FolderEntry[]
  truncated?: boolean
}

interface FolderRecent {
  path: string
  title: string
}

interface FoldersReply {
  folders?: FolderRecent[]
}

interface UpdateBotWorkDirPayload {
  id: string
  workDir: string
}

interface TeamWorkspacePayload {
  path: string
}

interface UpdateRoomWorkDirPayload {
  id: string
  workDir: string
}

@ComponentV2
export struct Folder {
  @Local pathStack: NavPathStack | null = null
  @Local pick: string = ''
  @Local botId: string = ''
  @Local roomId: string = ''
  @Local path: string = ''
  @Local listing: FolderListing | null = null
  @Local recent: FolderRecent[] = []

  private goBack(): void {
    if (this.pathStack !== null) this.pathStack.pop()
  }

  private async load(next: string): Promise<void> {
    this.path = next
    const controller = appStore.link.controller
    if (controller === null) return
    const payload: FolderListPayload = { path: next }
    try {
      const view = (await controller.call('folder-list', payload)) as FolderListing | null
      this.listing = view
    } catch {
      // The listing stays as it was.
    }
  }

  private async loadRecent(): Promise<void> {
    const controller = appStore.link.controller
    if (controller === null) return
    try {
      const view = (await controller.call('folders')) as FoldersReply | null
      const folders: FolderRecent[] = []
      for (const folder of view?.folders ?? []) {
        folders.push({ path: folder.path, title: folder.title })
      }
      this.recent = folders
    } catch {
      // Recents stay as they were.
    }
  }

  private async choose(): Promise<void> {
    const controller = appStore.link.controller
    if (controller === null) return
    try {
      if (this.pick === 'room') {
        const payload: UpdateRoomWorkDirPayload = { id: this.roomId, workDir: this.path }
        await controller.call('update-room', payload)
      } else if (this.pick === 'team') {
        const payload: TeamWorkspacePayload = { path: this.path }
        await controller.call('team-workspace', payload)
      } else {
        const payload: UpdateBotWorkDirPayload = { id: this.botId, workDir: this.path }
        await controller.call('update-bot', payload)
      }
      this.goBack()
    } catch {
      // A failed write keeps the browser open.
    }
  }

  private pathTitle(): string {
    if (this.path !== '') return this.path
    return '/'
  }

  private parent(): string {
    return this.listing?.parent ?? ''
  }

  private entries(): FolderEntry[] {
    return this.listing?.entries ?? []
  }

  private truncated(): boolean {
    return this.listing?.truncated === true
  }

  build() {
    NavDestination() {
      Column() {
        BackRow({
          label: t('Working folder'),
          onBack: (): void => this.goBack(),
        })
        Scroll() {
          Column() {
            if (this.recent.length > 0) {
              FormSection({ label: t('Folders') }) {
                ForEach(this.recent, (folder: FolderRecent, index: number) => {
                  if (index > 0) {
                    Divider()
                      .strokeWidth(this.hairline())
                      .color(appStore.theme.p.line)
                  }
                  this.recentRow(folder)
                }, (folder: FolderRecent) => folder.path)
              }
            }
            FormSection({ label: this.pathTitle() }) {
              if (this.parent() !== '') {
                Row({ space: 10 }) {
                  Text(t('Up one level'))
                    .fontSize(type.settingsRow.fontSize)
                    .lineHeight(type.settingsRow.lineHeight)
                    .fontColor(appStore.theme.p.ink)
                    .layoutWeight(1)
                  Icon({ name: 'chevronLeft', iconSize: 16, color: appStore.theme.p.ink3 })
                }
                .constraintSize({ minHeight: 50 })
                .width('100%')
                .padding({ left: 16, right: 16, top: 10, bottom: 10 })
                .alignItems(VerticalAlign.Center)
                .onClick(() => {
                  void this.load(this.parent())
                })
                Divider()
                  .strokeWidth(this.hairline())
                  .color(appStore.theme.p.line)
              }
              ForEach(this.entries(), (entry: FolderEntry, index: number) => {
                if (this.parent() !== '' || index > 0) {
                  Divider()
                    .strokeWidth(this.hairline())
                    .color(appStore.theme.p.line)
                }
                this.entryRow(entry)
              }, (entry: FolderEntry) => entry.path)
              if (this.listing !== null && this.entries().length === 0) {
                Text(t('No folders inside.'))
                  .fontSize(type.settingsRow.fontSize)
                  .lineHeight(type.settingsRow.lineHeight)
                  .fontColor(appStore.theme.p.ink2)
                  .width('100%')
                  .padding({ left: 16, right: 16, top: 10, bottom: 10 })
              }
              if (this.truncated()) {
                Text(t('Some folders are not shown.'))
                  .fontSize(type.settingsRow.fontSize)
                  .lineHeight(type.settingsRow.lineHeight)
                  .fontColor(appStore.theme.p.ink2)
                  .width('100%')
                  .padding({ left: 16, right: 16, top: 10, bottom: 10 })
              }
            }
            Column() {
              Column() {
                Text(t('Use this folder'))
                  .fontSize(type.settingsRow.fontSize)
                  .lineHeight(type.settingsRow.lineHeight)
                  .fontWeight('600')
                  .fontColor(appStore.theme.p.accentInk)
              }
              .constraintSize({ minHeight: 48 })
              .width('100%')
              .borderRadius(24)
              .backgroundColor(appStore.theme.p.accent)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              .onClick(() => {
                void this.choose()
              })
            }
            .width('100%')
            .padding({ left: 18, right: 18, top: 14 })
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
      this.pick = readStringParam(ctx.pathInfo.param, 'pick')
      this.botId = optionalStringParam(ctx.pathInfo.param, 'botId') ?? ''
      this.roomId = optionalStringParam(ctx.pathInfo.param, 'roomId') ?? ''
      this.path = readStringParam(ctx.pathInfo.param, 'current')
      void this.loadRecent()
      void this.load(this.path)
    })
  }

  private hairline(): number {
    return this.getUIContext().px2vp(1)
  }

  @Builder
  recentRow(folder: FolderRecent) {
    Row({ space: 10 }) {
      Text(folder.title)
        .fontSize(type.settingsRow.fontSize)
        .lineHeight(type.settingsRow.lineHeight)
        .fontColor(appStore.theme.p.ink)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(folder.path)
        .fontSize(type.settingsRow.fontSize)
        .lineHeight(type.settingsRow.lineHeight)
        .fontColor(appStore.theme.p.ink2)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.End)
        .constraintSize({ maxWidth: '52%' })
      Icon({ name: 'chevronRight', iconSize: 16, color: appStore.theme.p.ink3 })
    }
    .constraintSize({ minHeight: 50 })
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      void this.load(folder.path)
    })
  }

  @Builder
  entryRow(entry: FolderEntry) {
    Row({ space: 10 }) {
      Text(entry.name)
        .fontSize(type.settingsRow.fontSize)
        .lineHeight(type.settingsRow.lineHeight)
        .fontColor(appStore.theme.p.ink)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Icon({ name: 'chevronRight', iconSize: 16, color: appStore.theme.p.ink3 })
    }
    .constraintSize({ minHeight: 50 })
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      void this.load(entry.path)
    })
  }
}

interface FolderListPayload {
  path: string
}

@Builder
export function FolderBuilder() {
  Folder()
}