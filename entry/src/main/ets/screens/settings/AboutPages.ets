// The updates & diagnostics page and the about page (settings-pages.tsx):
// DS Bot / DSH update state with install, the diagnostics log with copy and
// clear, and the version / license / repository rows. Update installs are
// gated by the link's ensureUnlock.

import { appStore, type } from '../../components/Theme'
import { t } from '../../common/ui/i18n'
import { FormSection, FormRow, BackRow } from '../../components/FormControls'
import { copyToClipboard } from '../../platform/Platform'
import { openExternalUrl } from '../chat/MarkdownText'
import { common } from '@kit.AbilityKit'
import { readAppVersion } from '../../platform/AppInfo'
import type { UpdateState, DshState, DiagnosticsView, UpdateCheckReply } from '../../common/team/update-types'

@ComponentV2
export struct Updates {
  @Local pathStack: NavPathStack | null = null
  @Local update: UpdateState | null = null
  @Local dsh: DshState | null = null
  @Local diag: DiagnosticsView | null = null
  @Local log: string[] | null = null
  @Local copied: boolean = false
  @Local busy: boolean = false
  private copyTimer: number = -1

  private goBack(): void {
    if (this.pathStack !== null) this.pathStack.pop()
  }

  private async check(): Promise<void> {
    this.busy = true
    const controller = appStore.link.controller
    if (controller === null) {
      this.busy = false
      return
    }
    try {
      const reply = (await controller.call('update-check')) as UpdateCheckReply | null
      this.update = reply?.update ?? null
      this.dsh = reply?.dsh ?? null
    } catch {
      // The state stays as it was.
    } finally {
      this.busy = false
    }
  }

  private async loadDiag(): Promise<void> {
    const controller = appStore.link.controller
    if (controller === null) return
    try {
      const reply = (await controller.call('diagnostics')) as DiagnosticsView | null
      this.diag = reply
    } catch {
      // The view stays as it was.
    }
  }

  private updateText(): string {
    const info = this.update
    if (info === null) return '—'
    if (info.phase === 'installing') return t('Updating DS Bot…')
    if (info.phase === 'installed') return t('Restart DSH to start using DS Bot {version}.', { 'version': info.installed ?? info.latest ?? '' })
    if (info.phase === 'updated') return t('DS Bot {version} is installed.', { 'version': info.installed ?? info.latest ?? '' })
    if (info.phase === 'failed') return t('The update did not finish: {reason}', { 'reason': info.error ?? '' })
    if (info.available === true) return t('DS Bot {version} is available', { 'version': info.latest ?? '' })
    if (info.source === 'app') return t('Updates come with the DS Bot app.')
    if (info.enabled === false) return t('Update checks are off.')
    if (info.source === 'path') return t('Installed from a local folder; update it there.')
    if (info.latest === undefined || info.latest === null) return t('Could not check for updates.')
    return t('Up to date')
  }

  private dshText(): string {
    const info = this.dsh
    if (info === null) return '—'
    if (info.phase === 'installing') return t('Updating DSH…')
    if (info.phase === 'installed') return t('Restart DSH to start using DSH {version}.', { 'version': info.installed ?? info.verified ?? '' })
    if (info.phase === 'failed') return t('The update did not finish: {reason}', { 'reason': info.error ?? '' })
    if (info.available === false && info.blockedBy !== undefined && info.blockedBy !== '') {
      return t('Update DS Bot {version} first.', { 'version': info.blockedBy })
    }
    if (info.available === true) return t('DSH {version} is available', { 'version': info.verified ?? info.latest ?? '' })
    return t('Up to date')
  }

  private async callQuiet(endpoint: string): Promise<void> {
    const controller = appStore.link.controller
    if (controller === null) return
    try {
      await controller.call(endpoint)
    } catch {
      // Install failures surface on the next check.
    }
  }

  private async toggleLog(): Promise<void> {
    if (this.log !== null) {
      this.log = null
      return
    }
    const controller = appStore.link.controller
    if (controller === null) return
    try {
      const value = (await controller.call('diagnostics-log')) as Object | null
      if (typeof value === 'string') {
        const lines: string[] = value.split('\n')
        this.log = lines
      } else {
        this.log = []
      }
    } catch {
      // The log stays hidden.
    }
  }

  private async copyLog(): Promise<void> {
    const log = this.log
    if (log === null) return
    await copyToClipboard(log.join('\n'))
    this.copied = true
    this.clearCopyTimer()
    this.copyTimer = setTimeout(() => {
      this.copied = false
      this.copyTimer = -1
    }, 1500)
  }

  private clearCopyTimer(): void {
    if (this.copyTimer >= 0) {
      clearTimeout(this.copyTimer)
      this.copyTimer = -1
    }
  }

  aboutToDisappear(): void {
    this.clearCopyTimer()
  }

  private diagCount(): string {
    if (this.diag === null) return '—'
    const entries = this.diag.entries ?? []
    return String(this.diag.total ?? entries.length)
  }

  private lastEntry(): string {
    const entries = this.diag?.entries ?? []
    if (entries.length === 0) return ''
    const last = entries[entries.length - 1]
    return last?.text ?? ''
  }

  private updateAvailable(): boolean {
    return this.update?.available === true
  }

  private dshAvailable(): boolean {
    return this.dsh?.available === true
  }

  private hasEntries(): boolean {
    return (this.diag?.entries ?? []).length > 0
  }

  private currentLabel(): string {
    const current = this.update?.current
    if (current !== undefined && current !== '') return `DS Bot ${current}`
    return t('DS Bot')
  }

  private dshLabel(): string {
    const current = this.dsh?.current
    if (current !== undefined && current !== '') return `DSH ${current}`
    return t('DSH')
  }

  build() {
    NavDestination() {
      Column() {
        BackRow({
          label: t('Updates & diagnostics'),
          onBack: (): void => this.goBack(),
        })
        Scroll() {
          Column() {
            FormSection({ label: t('DS Bot') }) {
              FormRow({
                label: this.currentLabel(),
                value: this.updateText(),
              })
              if ((this.update?.notes ?? '') !== '') {
                Divider()
                  .strokeWidth(this.hairline())
                  .color(appStore.theme.p.line)
                FormRow({
                  label: t('What is new'),
                  value: this.update?.notes ?? '',
                })
              }
              if (this.updateAvailable()) {
                Divider()
                  .strokeWidth(this.hairline())
                  .color(appStore.theme.p.line)
                FormRow({
                  label: t('Install update'),
                  hasAction: true,
                  onPress: (): void => {
                    void this.callQuiet('update-install')
                  },
                })
              }
              Divider()
                .strokeWidth(this.hairline())
                .color(appStore.theme.p.line)
              FormRow({
                label: this.busy ? t('Checking for updates…') : t('Check for updates'),
                hasAction: !this.busy,
                onPress: (): void => {
                  void this.check()
                },
              })
            }
            FormSection({ label: t('DSH') }) {
              FormRow({
                label: this.dshLabel(),
                value: this.dshText(),
              })
              if (this.dshAvailable()) {
                Divider()
                  .strokeWidth(this.hairline())
                  .color(appStore.theme.p.line)
                FormRow({
                  label: t('Install DSH update'),
                  hasAction: true,
                  onPress: (): void => {
                    void this.callQuiet('dsh-update-install')
                  },
                })
              }
            }
            FormSection({ label: t('Diagnostics') }) {
              FormRow({
                label: t('Log entries'),
                value: this.diagCount(),
              })
              if (this.hasEntries()) {
                Divider()
                  .strokeWidth(this.hairline())
                  .color(appStore.theme.p.line)
                FormRow({
                  label: t('Last entry'),
                  value: this.lastEntry(),
                })
              }
              Divider()
                .strokeWidth(this.hairline())
                .color(appStore.theme.p.line)
              FormRow({
                label: this.log === null ? t('Diagnostics log') : t('Hide log'),
                hasAction: true,
                onPress: (): void => {
                  void this.toggleLog()
                },
              })
              if (this.log !== null) {
                this.logBlock()
              }
              Divider()
                .strokeWidth(this.hairline())
                .color(appStore.theme.p.line)
              FormRow({
                label: t('Clear diagnostics'),
                hasAction: true,
                onPress: (): void => {
                  void this.callQuiet('diagnostics-clear')
                },
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
    })
    .onShown(() => {
      void this.check()
      void this.loadDiag()
    })
  }

  private hairline(): number {
    return this.getUIContext().px2vp(1)
  }

  @Builder
  logBlock() {
    Column() {
      Scroll() {
        Column() {
          ForEach(this.log ?? [], (line: string, index: number) => {
            Text(line)
              .fontSize(type.small.fontSize)
              .lineHeight(type.small.lineHeight)
              .fontColor(appStore.theme.p.ink2)
              .fontFamily('monospace')
              .width('100%')
          }, (line: string, index: number) => `${index}-${line}`)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .constraintSize({ maxHeight: 200 })
      .width('100%')
      .scrollBar(BarState.Off)
      Text(this.copied ? t('Copied') : t('Copy all'))
        .fontSize(type.settingsRow.fontSize)
        .lineHeight(type.settingsRow.lineHeight)
        .fontColor(appStore.theme.p.accent)
        .margin({ top: 8 })
        .onClick(() => {
          void this.copyLog()
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .border({ width: { top: this.hairline() }, color: appStore.theme.p.line })
    .alignItems(HorizontalAlign.Start)
  }
}

@ComponentV2
export struct About {
  @Local pathStack: NavPathStack | null = null
  @Local versions: UpdateCheckReply | null = null

  private goBack(): void {
    if (this.pathStack !== null) this.pathStack.pop()
  }

  // The state carries no versions; the update check knows both.
  private async load(): Promise<void> {
    const controller = appStore.link.controller
    if (controller === null) return
    try {
      const reply = (await controller.call('update-check')) as UpdateCheckReply | null
      this.versions = reply
    } catch {
      // Versions stay as they were.
    }
  }

  private version(): string {
    const current = this.versions?.current
    if (current !== undefined && current !== '') return current
    return '—'
  }

  private dshVersion(): string {
    const current = this.versions?.dsh?.current
    if (current !== undefined && current !== '') return current
    return '—'
  }

  private hasDsh(): boolean {
    return this.versions?.dsh?.current !== undefined
  }

  private computerName(): string {
    return appStore.computers.active?.name ?? '—'
  }

  private open(url: string): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    openExternalUrl(context, url)
  }

  build() {
    NavDestination() {
      Column() {
        BackRow({
          label: t('About'),
          onBack: (): void => this.goBack(),
        })
        Scroll() {
          Column() {
            FormSection({ label: t('About') }) {
              FormRow({
                label: t('DS Bot'),
                value: this.version(),
              })
              if (this.hasDsh()) {
                Divider()
                  .strokeWidth(this.hairline())
                  .color(appStore.theme.p.line)
                FormRow({
                  label: t('DSH'),
                  value: this.dshVersion(),
                })
              }
              Divider()
                .strokeWidth(this.hairline())
                .color(appStore.theme.p.line)
              FormRow({
                label: t('Phone app'),
                value: readAppVersion(),
              })
              Divider()
                .strokeWidth(this.hairline())
                .color(appStore.theme.p.line)
              FormRow({
                label: t('Computer'),
                value: this.computerName(),
              })
            }
            FormSection({ label: t('Licenses') }) {
              FormRow({
                label: t('DS Bot'),
                hint: t('Apache License 2.0'),
                hasAction: true,
                onPress: (): void => this.open('https://github.com/Fei2411/DS-Bot/blob/main/LICENSE'),
              })
              Divider()
                .strokeWidth(this.hairline())
                .color(appStore.theme.p.line)
              FormRow({
                label: t('Repository'),
                hint: 'github.com/Fei2411/DS-Bot',
                hasAction: true,
                onPress: (): void => this.open('https://github.com/Fei2411/DS-Bot'),
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
    })
    .onShown(() => {
      void this.load()
    })
  }

  private hairline(): number {
    return this.getUIContext().px2vp(1)
  }
}

@Builder
export function UpdatesBuilder() {
  Updates()
}

@Builder
export function AboutBuilder() {
  About()
}
