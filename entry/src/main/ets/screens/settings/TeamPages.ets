// The team data pages (settings-pages.tsx + manage.tsx): team usage totals,
// the saved computers, secrets, and the team location. Secret writes are
// gated by the link's ensureUnlock; computer switching reloads the link.

import { appStore, type } from '../../components/Theme'
import { t } from '../../common/ui/i18n'
import { sha256 } from '../../common/sha256'
import { utf8Encode } from '../../common/bytes'
import { listComputers, removeComputer, setActiveComputer, type StoredComputer } from '../../common/team/store-core'
import type { Bot, TeamState } from '../../common/team/types'
import { FormSection, FormRow, SectionDivider, BackRow } from '../../components/FormControls'
import type { FolderParam } from '../routes'

interface OwnerEntry {
  name: string
  kind: string
  deleted?: boolean
}

interface ModelEntry {
  name: string
}

interface UsageAllReply {
  owners?: OwnerEntry[]
  models?: ModelEntry[]
  rows?: Object[][]
}

interface UsageCallPayload {
  timeZone: string
}

interface Tokens {
  input: number
  output: number
}

interface FolderRecentsReply {
  team?: string
}

interface TeamStateHolder {
  dataPath?: string
}

interface SecretItem {
  name: string
  description?: string
  scope?: string | string[]
}

interface SecretSetPayload {
  name: string
  value: string
}

interface SecretDeletePayload {
  name: string
}

interface CodedError {
  code?: string
}

function timeZoneId(): string {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone
  } catch {
    return 'UTC'
  }
}

function toHex(bytes: Uint8Array): string {
  let hex = ''
  for (const byte of bytes) {
    hex += (byte < 16 ? '0' : '') + byte.toString(16)
  }
  return hex
}

// The host key fingerprint, as the pairing screen shows it.
async function fingerprintOf(key: string): Promise<string> {
  const digest = sha256(utf8Encode(key))
  const hex = toHex(digest).slice(0, 16).toUpperCase()
  return `${hex.slice(0, 4)} ${hex.slice(4, 8)} ${hex.slice(8, 12)} ${hex.slice(12, 16)}`
}

function sumRows(rows: Object[][], ownerIndex: number, modelIndex: number): Tokens {
  const totals: Tokens = { input: 0, output: 0 }
  for (const row of rows) {
    if (row.length < 8) continue
    const owner = Number(row[1])
    const model = Number(row[2])
    if (ownerIndex >= 0 && owner !== ownerIndex) continue
    if (modelIndex >= 0 && model !== modelIndex) continue
    totals.input += Number(row[4]) + Number(row[5]) + Number(row[6])
    totals.output += Number(row[7])
  }
  return totals
}

// ------------------------------------------------------------ Team usage

@ComponentV2
export struct TeamUsage {
  @Local pathStack: NavPathStack | null = null
  @Local view: UsageAllReply | null = null

  private goBack(): void {
    if (this.pathStack !== null) this.pathStack.pop()
  }

  private rows(): Object[][] {
    return this.view?.rows ?? []
  }

  private all(): Tokens {
    return sumRows(this.rows(), -1, -1)
  }

  private fmt(value: number): string {
    return value.toLocaleString()
  }

  private owners(): string[] {
    const out: string[] = []
    const owners = this.view?.owners ?? []
    for (let index = 0; index < owners.length; index++) {
      const owner = owners[index]
      const total = sumRows(this.rows(), index, -1)
      if (total.input + total.output > 0) out.push(`${owner.name}|${this.fmt(total.input + total.output)}`)
    }
    return out
  }

  private ownerName(entry: string): string {
    const parts = entry.split('|')
    return parts.length > 0 ? parts[0] : ''
  }

  private ownerValue(entry: string): string {
    const parts = entry.split('|')
    return parts.length > 1 ? parts[1] : ''
  }

  private models(): string[] {
    const out: string[] = []
    const models = this.view?.models ?? []
    for (let index = 0; index < models.length; index++) {
      const model = models[index]
      const total = sumRows(this.rows(), -1, index)
      if (total.input + total.output > 0) out.push(`${model.name}|${this.fmt(total.input + total.output)}`)
    }
    return out
  }

  private modelName(entry: string): string {
    const parts = entry.split('|')
    return parts.length > 0 ? parts[0] : ''
  }

  private modelValue(entry: string): string {
    const parts = entry.split('|')
    return parts.length > 1 ? parts[1] : ''
  }

  private inValue(): string {
    if (this.view === null) return '—'
    return this.fmt(this.all().input)
  }

  private outValue(): string {
    if (this.view === null) return '—'
    return this.fmt(this.all().output)
  }

  private async load(): Promise<void> {
    const controller = appStore.link.controller
    if (controller === null) return
    const payload: UsageCallPayload = { timeZone: timeZoneId() }
    try {
      const reply = (await controller.call('usage', payload)) as UsageAllReply | null
      this.view = reply
    } catch {
      // The view stays as it was.
    }
  }

  build() {
    NavDestination() {
      Column() {
        BackRow({
          label: t('Usage'),
          onBack: (): void => this.goBack(),
        })
        Scroll() {
          Column() {
            FormSection({ label: t('Usage') }) {
              this.valueRow(t('Tokens in'), this.inValue())
              Divider()
                .strokeWidth(this.hairline())
                .color(appStore.theme.p.line)
              this.valueRow(t('Tokens out'), this.outValue())
            }
            FormSection({ label: t('Bots') }) {
              ForEach(this.owners(), (entry: string, index: number) => {
                if (index > 0) {
                  Divider()
                    .strokeWidth(this.hairline())
                    .color(appStore.theme.p.line)
                }
                this.valueRow(this.ownerName(entry), this.ownerValue(entry))
              }, (entry: string) => entry)
            }
            FormSection({ label: t('Models') }) {
              ForEach(this.models(), (entry: string, index: number) => {
                if (index > 0) {
                  Divider()
                    .strokeWidth(this.hairline())
                    .color(appStore.theme.p.line)
                }
                this.valueRow(this.modelName(entry), this.modelValue(entry))
              }, (entry: string) => entry)
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

  @Builder
  valueRow(label: string, value: string) {
    Row({ space: 10 }) {
      Text(label)
        .fontSize(type.settingsRow.fontSize)
        .lineHeight(type.settingsRow.lineHeight)
        .fontColor(appStore.theme.p.ink)
        .layoutWeight(1)
      Text(value)
        .fontSize(type.settingsRow.fontSize)
        .lineHeight(type.settingsRow.lineHeight)
        .fontColor(appStore.theme.p.ink2)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.End)
        .constraintSize({ maxWidth: '52%' })
    }
    .constraintSize({ minHeight: 50 })
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
  }
}

// ------------------------------------------------------------ Computers

@ComponentV2
export struct Computers {
  @Local pathStack: NavPathStack | null = null
  @Local list: StoredComputer[] = []
  @Local prints: Map<string, string> = new Map<string, string>()
  @Local armedForget: string = ''
  @Local refreshTick: number = 0
  private forgetTimer: number = -1

  private goBack(): void {
    if (this.pathStack !== null) this.pathStack.pop()
  }

  private hairline(): number {
    return this.getUIContext().px2vp(1)
  }

  private nameOf(item: StoredComputer): string {
    if (item.name !== '') return item.name
    return item.server
  }

  private isActive(item: StoredComputer): boolean {
    return item.hostDeviceId === appStore.computers.active?.hostDeviceId
  }

  private online(): boolean {
    void this.refreshTick
    return appStore.link.online
  }

  private statusOf(item: StoredComputer): string {
    const print = this.prints.get(item.hostDeviceId) ?? '…'
    if (this.isActive(item)) {
      return `${this.online() ? t('Connected') : t('Connecting…')} · ${print}`
    }
    return `${t('Not connected')} · ${print}`
  }

  private async load(): Promise<void> {
    const result = await listComputers()
    this.list = result.computers
    for (const item of this.list) {
      if (this.prints.get(item.hostDeviceId) !== undefined) continue
      void fingerprintOf(item.hostKey).then((text: string): void => {
        this.prints.set(item.hostDeviceId, text)
      }).catch((): void => {})
    }
  }

  private async switchTo(item: StoredComputer): Promise<void> {
    await appStore.computers.switchTo(item.hostDeviceId)
    appStore.ensureLink()
  }

  // First tap arms the Forget, the second tap within 3s drops the computer.
  private tapForget(item: StoredComputer): void {
    if (this.armedForget === item.hostDeviceId) {
      this.clearTimer()
      this.armedForget = ''
      void this.forget(item)
      return
    }
    this.armedForget = item.hostDeviceId
    this.clearTimer()
    this.forgetTimer = setTimeout(() => {
      this.armedForget = ''
      this.forgetTimer = -1
    }, 3000)
  }

  private clearTimer(): void {
    if (this.forgetTimer >= 0) {
      clearTimeout(this.forgetTimer)
      this.forgetTimer = -1
    }
  }

  aboutToDisappear(): void {
    this.clearTimer()
  }

  private async forget(item: StoredComputer): Promise<void> {
    await appStore.computers.forget(item.hostDeviceId)
    await this.load()
  }

  private addComputer(): void {
    // Adding goes through the pair gate; leaving to it stops the link.
    appStore.computers.adding = true
    appStore.ensureLink()
    if (this.pathStack !== null) this.pathStack.clear()
  }

  private forgetColor(item: StoredComputer): string {
    if (this.armedForget === item.hostDeviceId) {
      return appStore.theme.p.danger
    }
    return appStore.theme.p.ink3
  }

  build() {
    NavDestination() {
      Column() {
        BackRow({
          label: t('Computers'),
          onBack: (): void => this.goBack(),
        })
        Scroll() {
          Column() {
            FormSection({ label: t('Computers') }) {
              ForEach(this.list, (item: StoredComputer, index: number) => {
                if (index > 0) {
                  Divider()
                    .strokeWidth(this.hairline())
                    .color(appStore.theme.p.line)
                }
                this.computerRow(item)
              }, (item: StoredComputer) => item.hostDeviceId)
              Divider()
                .strokeWidth(this.hairline())
                .color(appStore.theme.p.line)
              FormRow({
                label: t('Add a computer'),
                hasAction: true,
                onPress: (): void => this.addComputer(),
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
      this.refreshTick += 1
    })
  }

  @Builder
  computerRow(item: StoredComputer) {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text(this.nameOf(item))
          .fontSize(type.settingsRow.fontSize)
          .lineHeight(type.settingsRow.lineHeight)
          .fontColor(appStore.theme.p.ink)
        Text(this.statusOf(item))
          .fontSize(type.small.fontSize)
          .lineHeight(type.small.lineHeight)
          .fontColor(appStore.theme.p.ink3)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      if (!this.isActive(item)) {
        Text(t('Switch'))
          .fontSize(type.settingsRow.fontSize)
          .lineHeight(type.settingsRow.lineHeight)
          .fontColor(appStore.theme.p.accent)
          .onClick(() => {
            void this.switchTo(item)
          })
      }
      Text(t('Forget'))
        .fontSize(type.settingsRow.fontSize)
        .lineHeight(type.settingsRow.lineHeight)
        .fontColor(this.forgetColor(item))
        .constraintSize({ minWidth: 44 })
        .textAlign(TextAlign.End)
        .onClick(() => this.tapForget(item))
    }
    .constraintSize({ minHeight: 50 })
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
  }
}

// ------------------------------------------------------------ Secrets

@ComponentV2
export struct Secrets {
  @Local pathStack: NavPathStack | null = null
  @Local name: string = ''
  @Local value: string = ''
  @Local writeError: string = ''
  @Local armedDelete: string = ''
  @Local refreshTick: number = 0
  private deleteTimer: number = -1

  private team(): TeamState | null {
    void this.refreshTick
    return appStore.link.team
  }

  private hairline(): number {
    return this.getUIContext().px2vp(1)
  }

  private goBack(): void {
    if (this.pathStack !== null) this.pathStack.pop()
  }

  private secrets(): SecretItem[] {
    return this.team()?.secrets ?? []
  }

  private bots(): Bot[] {
    return this.team()?.bots ?? []
  }

  private scopeText(secret: SecretItem): string {
    const scope = secret.scope
    if (scope === undefined) return ''
    if (scope === 'all') return t('All Bots')
    const ids: string[] = Array.isArray(scope) ? scope : [scope]
    const names: string[] = []
    for (const id of ids) {
      let name = id
      for (const bot of this.bots()) {
        if (bot.id === id) name = bot.name
      }
      names.push(name)
    }
    return names.join(', ')
  }

  private async run(endpoint: string, payload: Object, after?: () => void): Promise<void> {
    const controller = appStore.link.controller
    if (controller === null) return
    try {
      await controller.call(endpoint, payload)
      this.writeError = ''
      if (after !== undefined) after()
    } catch (failure) {
      if ((failure as CodedError)?.code === 'unlock/canceled') return
      this.writeError = failure instanceof Error ? failure.message : String(failure)
    }
  }

  private save(): void {
    if (this.name.trim() === '' || this.value === '') return
    const next = this.value
    this.value = ''
    const payload: SecretSetPayload = { name: this.name.trim(), value: next }
    void this.run('secret-set', payload, (): void => {
      this.name = ''
      this.refreshTick += 1
    })
  }

  private tapDelete(secret: SecretItem): void {
    if (this.armedDelete === secret.name) {
      this.clearTimer()
      this.armedDelete = ''
      const payload: SecretDeletePayload = { name: secret.name }
      void this.run('secret-delete', payload)
      return
    }
    this.armedDelete = secret.name
    this.clearTimer()
    this.deleteTimer = setTimeout(() => {
      this.armedDelete = ''
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

  private deleteColor(): string {
    if (this.armedDelete !== '') {
      return appStore.theme.p.danger
    }
    return appStore.theme.p.ink3
  }

  private saveDisabled(): boolean {
    return this.name.trim() === '' || this.value === ''
  }

  build() {
    NavDestination() {
      Column() {
        BackRow({
          label: t('Secrets'),
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
            FormSection({ label: t('Secrets') }) {
              ForEach(this.secrets(), (secret: SecretItem, index: number) => {
                if (index > 0) {
                  SectionDivider()
                }
                this.secretRow(secret)
              }, (secret: SecretItem) => secret.name)
              if (this.secrets().length === 0) {
                Text(t('Nothing saved yet'))
                  .fontSize(type.settingsRow.fontSize)
                  .lineHeight(type.settingsRow.lineHeight)
                  .fontColor(appStore.theme.p.ink2)
                  .width('100%')
                  .padding({ left: 16, right: 16, top: 10, bottom: 10 })
              }
            }
            FormSection({ label: t('Add') }) {
              TextInput({ text: this.name, placeholder: t('Name') })
                .fontSize(type.settingsRow.fontSize)
                .fontColor(appStore.theme.p.ink)
                .placeholderColor(appStore.theme.p.ink3)
                .backgroundColor(Color.Transparent)
                .padding({ left: 16, right: 16, top: 10, bottom: 10 })
                .width('100%')
                .onChange((value: string): void => {
                  this.name = value
                })
              SectionDivider()
              TextInput({ text: this.value, placeholder: t('Paste or type the key') })
                .fontSize(type.settingsRow.fontSize)
                .fontColor(appStore.theme.p.ink)
                .placeholderColor(appStore.theme.p.ink3)
                .backgroundColor(Color.Transparent)
                .padding({ left: 16, right: 16, top: 10, bottom: 10 })
                .width('100%')
                .type(InputType.Password)
                .onChange((value: string): void => {
                  this.value = value
                })
            }
            Column() {
              Column() {
                Text(t('Save'))
                  .fontSize(type.settingsRow.fontSize)
                  .lineHeight(type.settingsRow.lineHeight)
                  .fontWeight('600')
                  .fontColor(appStore.theme.p.accentInk)
                  .opacity(this.saveDisabled() ? 0.5 : 1)
              }
              .constraintSize({ minHeight: 48 })
              .width('100%')
              .borderRadius(24)
              .backgroundColor(appStore.theme.p.accent)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              .onClick(() => {
                if (!this.saveDisabled()) this.save()
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
    })
    .onShown(() => {
      this.refreshTick += 1
    })
  }

  @Builder
  secretRow(secret: SecretItem) {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text(secret.name)
          .fontSize(type.settingsRow.fontSize)
          .lineHeight(type.settingsRow.lineHeight)
          .fontColor(appStore.theme.p.ink)
        if (this.scopeText(secret) !== '') {
          Text(this.scopeText(secret))
            .fontSize(type.small.fontSize)
            .lineHeight(type.small.lineHeight)
            .fontColor(appStore.theme.p.ink3)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text(t('Delete'))
        .fontSize(type.settingsRow.fontSize)
        .lineHeight(type.settingsRow.lineHeight)
        .fontColor(this.armedDelete === secret.name ? appStore.theme.p.danger : appStore.theme.p.ink3)
        .constraintSize({ minWidth: 44 })
        .textAlign(TextAlign.End)
        .onClick(() => this.tapDelete(secret))
    }
    .constraintSize({ minHeight: 50 })
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
  }
}

// ------------------------------------------------------------ Location

@ComponentV2
export struct Location {
  @Local pathStack: NavPathStack | null = null
  @Local workspace: string = ''
  @Local refreshTick: number = 0

  private team(): TeamState | null {
    void this.refreshTick
    return appStore.link.team
  }

  private goBack(): void {
    if (this.pathStack !== null) this.pathStack.pop()
  }

  private dataPath(): string {
    const holder = this.team() as TeamStateHolder
    return holder.dataPath ?? ''
  }

  // The workspace comes from `folders`; it is read again on show so a change
  // made in the folder picker shows on return.
  private async load(): Promise<void> {
    const controller = appStore.link.controller
    if (controller === null) return
    try {
      const reply = (await controller.call('folders')) as FolderRecentsReply | null
      this.workspace = reply?.team ?? ''
    } catch {
      // The workspace stays as it was.
    }
  }

  private pickWorkspace(): void {
    if (this.pathStack === null) return
    const param: FolderParam = { pick: 'team', current: this.workspace }
    this.pathStack.pushPathByName('folder', param)
  }

  build() {
    NavDestination() {
      Column() {
        BackRow({
          label: t('Location'),
          onBack: (): void => this.goBack(),
        })
        Scroll() {
          Column() {
            FormSection({ label: t('Location') }) {
              FormRow({
                label: t('Team workspace'),
                value: this.workspace,
                hasAction: true,
                onPress: (): void => this.pickWorkspace(),
              })
              if (this.dataPath() !== '') {
                SectionDivider()
                FormRow({
                  label: t('Data location'),
                  value: this.dataPath(),
                })
              }
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
}

@Builder
export function TeamUsageBuilder() {
  TeamUsage()
}

@Builder
export function ComputersBuilder() {
  Computers()
}

@Builder
export function SecretsBuilder() {
  Secrets()
}

@Builder
export function LocationBuilder() {
  Location()
}
