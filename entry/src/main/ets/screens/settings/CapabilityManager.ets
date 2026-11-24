// The reusable capability management body (settings-pages.tsx Capabilities):
// the team's capability library with status lines, the content viewer,
// approve/delete, the add/edit form for MCP servers (local command or HTTP),
// skills and packs, and the per-Bot attach switches. Save and delete are
// gated by the link's ensureUnlock. The Capabilities page and the Plugins page
// both embed this component, so the two entries share one implementation and
// one data source (appStore.link.team); hosts pass their own refreshTick so a
// shown page re-reads the shared team state.

import { appStore, type } from '../../components/Theme'
import { t } from '../../common/ui/i18n'
import type { Bot, CapabilityInfo, CapabilityStatus, TeamState } from '../../common/team/types'
import {
  capabilityStatusFor, capabilityStatusText, unapprovedCapabilitiesFor,
  type CapabilityStatuses,
} from '../../common/team/capabilities'
import { FormSection, FormRow, SwitchRow } from '../../components/FormControls'
import { Icon } from '../../components/Icon'

interface CapabilitySavePayload {
  name: string
  kind?: string
  description?: string
  originalName?: string
  transport?: string
  command?: string
  args?: string[]
  env?: Record<string, string>
  url?: string
  headers?: Record<string, string>
  content?: string
  items?: string[]
}

interface CapabilityNamePayload {
  name: string
}

interface BotCapabilityPayload {
  botId: string
  name: string
  attached: boolean
}

interface EditDraft {
  name: string
  kind: string
  description: string
  transport: string
  command: string
  argsText: string
  envText: string
  url: string
  headersText: string
  content: string
  items: string[]
  originalName: string
}

interface CodedError {
  code?: string
}

function statusColor(status: CapabilityStatus | undefined): string {
  if (status?.state === 'needs-approval') {
    return appStore.theme.p.accent
  }
  if (status?.state === 'error') {
    return appStore.theme.p.danger
  }
  return appStore.theme.p.ink3
}

function detailOf(item: CapabilityInfo): string {
  if (item.kind === 'pack') {
    const items = (item.items ?? []).join(', ')
    return `${t('Pack')}: ${items !== '' ? items : t('No items')}`
  }
  if (item.kind === 'mcp') {
    return item.transport === 'stdio' ? t('Local command') : t('HTTP server')
  }
  if (item.kind === 'skill') {
    return t('Skill')
  }
  return ''
}

// A JSON object field ({...}), shared by env and headers.
function parseMap(text: string, label: string): Record<string, string> {
  const out: Record<string, string> = {}
  const trimmed = text.trim()
  if (trimmed === '') return out
  const parsed = JSON.parse(trimmed) as Record<string, string> | null
  if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
    throw new Error(t('{label} must be a JSON object.', { 'label': label }))
  }
  const keys = Object.keys(parsed)
  for (const key of keys) {
    const value = parsed[key]
    if (typeof value === 'string') out[key] = value
  }
  return out
}

// A saved env/headers map back into editable JSON text.
function mapText(map: Record<string, string> | undefined): string {
  if (map === undefined || map === null) return ''
  if (Object.keys(map).length === 0) return ''
  return JSON.stringify(map, null, 2)
}

@ComponentV2
export struct CapabilityManager {
  // The section card's caption; hosts name their entry ('Capabilities' or
  // 'Capability plugins'), and empty falls back to the page's own label.
  @Param sectionLabel: string = ''
  // Bumped by the host page each time it is shown, so the shared team state
  // is re-read after changes made in the other entry.
  @Param refreshTick: number = 0
  @Local openName: string = ''
  @Local error: string = ''
  @Local editing: EditDraft | null = null
  @Local armedDelete: string = ''
  private deleteTimer: number = -1

  private team(): TeamState | null {
    void this.refreshTick
    return appStore.link.team
  }

  private hairline(): number {
    return this.getUIContext().px2vp(1)
  }

  private items(): CapabilityInfo[] {
    return this.team()?.capabilities ?? []
  }

  private libraryNames(): string[] {
    const names: string[] = []
    for (const item of this.items()) names.push(item.name)
    return names
  }

  private statuses(): CapabilityStatuses {
    const all = this.team()?.capabilityStatuses
    if (all === undefined || all === null) {
      const empty: CapabilityStatuses = {}
      return empty
    }
    return all as CapabilityStatuses
  }

  // The overall status of one capability: the highest-ranked state across the
  // per-bot maps or the flat map, with the item itself as fallback.
  private statusOf(item: CapabilityInfo): CapabilityStatus | undefined {
    const team = this.team()
    return capabilityStatusFor(this.statuses(), item.name, { bots: team?.bots ?? [], item })
  }

  // The stdio MCP names an Approve tap approves: the server itself, or the
  // pack's unapproved children.
  private approvableOf(item: CapabilityInfo): string[] {
    const team = this.team()
    return unapprovedCapabilitiesFor(this.items(), this.statuses(), item, team?.bots ?? [])
  }

  private lineOf(item: CapabilityInfo): string {
    const parts: string[] = []
    const detail = detailOf(item)
    if (detail !== '') parts.push(detail)
    parts.push(capabilityStatusText(this.statusOf(item)))
    return parts.join(' · ')
  }

  private async act(endpoint: string, payload: Object): Promise<void> {
    const controller = appStore.link.controller
    if (controller === null) return
    try {
      await controller.call(endpoint, payload)
      this.error = ''
    } catch (failure) {
      if ((failure as CodedError)?.code === 'unlock/canceled') return
      this.error = failure instanceof Error ? failure.message : String(failure)
    }
  }

  // One tap approves everything the row can approve; the first failure stops
  // the loop and surfaces.
  private async approveAll(item: CapabilityInfo): Promise<void> {
    const names = this.approvableOf(item)
    if (names.length === 0) return
    const controller = appStore.link.controller
    if (controller === null) return
    this.error = ''
    try {
      for (const name of names) {
        const payload: CapabilityNamePayload = { name: name }
        await controller.call('capability-approve', payload)
      }
    } catch (failure) {
      if ((failure as CodedError)?.code === 'unlock/canceled') return
      this.error = failure instanceof Error ? failure.message : String(failure)
    }
  }

  // The delete's two-tap confirm: the first tap arms the row for 3 seconds,
  // the second takes the capability out; a slow second tap disarms itself.
  private tapDelete(item: CapabilityInfo): void {
    if (this.armedDelete !== item.name) {
      this.armedDelete = item.name
      this.clearDeleteTimer()
      this.deleteTimer = setTimeout(() => {
        this.armedDelete = ''
        this.deleteTimer = -1
      }, 3000)
      return
    }
    this.clearDeleteTimer()
    this.armedDelete = ''
    const payload: CapabilityNamePayload = { name: item.name }
    void this.act('capability-delete', payload)
  }

  private clearDeleteTimer(): void {
    if (this.deleteTimer >= 0) {
      clearTimeout(this.deleteTimer)
      this.deleteTimer = -1
    }
  }

  aboutToDisappear(): void {
    this.clearDeleteTimer()
  }

  private saveCapability(): void {
    const draft = this.editing
    if (draft === null || draft.name.trim() === '') return
    try {
      const payload: CapabilitySavePayload = {
        name: draft.name.trim(),
        kind: draft.kind,
        description: draft.description,
        originalName: draft.originalName !== '' ? draft.originalName : undefined,
      }
      if (draft.kind === 'mcp' && draft.transport === 'stdio') {
        payload.transport = 'stdio'
        payload.command = draft.command
        payload.args = this.linesOf(draft.argsText)
        payload.env = parseMap(draft.envText, t('Environment'))
      } else if (draft.kind === 'mcp') {
        payload.transport = 'streamable-http'
        payload.url = draft.url
        payload.headers = parseMap(draft.headersText, t('Headers'))
      } else if (draft.kind === 'skill') {
        payload.content = draft.content
      } else {
        payload.items = draft.items
      }
      void this.act('capability-save', payload).then((): void => {
        this.editing = null
      })
    } catch (failure) {
      this.error = failure instanceof Error ? failure.message : String(failure)
    }
  }

  private linesOf(text: string): string[] {
    const lines: string[] = []
    for (const line of text.split('\n')) {
      if (line !== '') lines.push(line)
    }
    return lines
  }

  private startEdit(item: CapabilityInfo): void {
    const draft: EditDraft = {
      name: item.name,
      kind: item.kind ?? 'mcp',
      description: item.description ?? '',
      transport: item.transport ?? 'stdio',
      command: item.command ?? '',
      argsText: (item.args ?? []).join('\n'),
      envText: mapText(item.env),
      url: item.url ?? '',
      headersText: mapText(item.headers),
      content: item.content ?? '',
      items: item.items ?? [],
      originalName: item.name,
    }
    this.editing = draft
  }

  private startAdd(): void {
    const draft: EditDraft = {
      name: '',
      kind: 'mcp',
      description: '',
      transport: 'stdio',
      command: '',
      argsText: '',
      envText: '',
      url: '',
      headersText: '',
      content: '',
      items: [],
      originalName: '',
    }
    this.editing = draft
  }

  private toggleItem(name: string): void {
    const draft = this.editing
    if (draft === null) return
    const items: string[] = []
    for (const item of draft.items) {
      if (item !== name) items.push(item)
    }
    let included = false
    for (const item of draft.items) {
      if (item === name) included = true
    }
    if (!included) items.push(name)
    this.editing = {
      name: draft.name,
      kind: draft.kind,
      description: draft.description,
      transport: draft.transport,
      command: draft.command,
      argsText: draft.argsText,
      envText: draft.envText,
      url: draft.url,
      headersText: draft.headersText,
      content: draft.content,
      items: items,
      originalName: draft.originalName,
    }
  }

  private includesItem(name: string): boolean {
    const draft = this.editing
    if (draft === null) return false
    for (const item of draft.items) {
      if (item === name) return true
    }
    return false
  }

  private contentText(item: CapabilityInfo): string {
    if ((item.content ?? '') !== '') return item.content ?? ''
    return item.description ?? ''
  }

  private bots(): Bot[] {
    return this.team()?.bots ?? []
  }

  // The Bot's capability list carries the attach state (bot.capabilities).
  private botHas(item: CapabilityInfo, bot: Bot): boolean {
    for (const name of bot.capabilities ?? []) {
      if (name === item.name) return true
    }
    return false
  }

  private setAttached(item: CapabilityInfo, bot: Bot, on: boolean): void {
    const payload: BotCapabilityPayload = { botId: bot.id, name: item.name, attached: on }
    void this.act('bot-capability', payload)
  }

  build() {
    Column() {
      if (this.error !== '') {
        Text(this.error)
          .fontSize(type.small.fontSize)
          .lineHeight(type.small.lineHeight)
          .fontColor(appStore.theme.p.danger)
          .width('100%')
          .padding(18)
      }
      FormSection({ label: this.sectionLabel !== '' ? this.sectionLabel : t('Capabilities') }) {
        ForEach(this.items(), (item: CapabilityInfo, index: number) => {
          if (index > 0) {
            Divider()
              .strokeWidth(this.hairline())
              .color(appStore.theme.p.line)
          }
          this.capabilityBlock(item)
        }, (item: CapabilityInfo) => item.name)
        if (this.items().length === 0 && this.editing === null) {
          FormRow({ label: t('Save an MCP server or skill first.') })
        }
      }
      if (this.editing === null) {
        Column() {
          Column() {
            Text(t('Add capability'))
              .fontSize(type.settingsRow.fontSize)
              .lineHeight(type.settingsRow.lineHeight)
              .fontColor(appStore.theme.p.ink)
          }
          .constraintSize({ minHeight: 48 })
          .width('100%')
          .borderRadius(24)
          .backgroundColor(appStore.theme.p.hover)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .onClick(() => this.startAdd())
        }
        .width('100%')
        .padding({ left: 18, right: 18, top: 14 })
      } else {
        this.editBlock()
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  capabilityBlock(item: CapabilityInfo) {
    Column() {
      Row({ space: 10 }) {
        Column({ space: 2 }) {
          Text(item.name)
            .fontSize(type.settingsRow.fontSize)
            .lineHeight(type.settingsRow.lineHeight)
            .fontColor(appStore.theme.p.ink)
          if ((item.description ?? '') !== '') {
            Text(item.description ?? '')
              .fontSize(type.small.fontSize)
              .lineHeight(type.small.lineHeight)
              .fontColor(appStore.theme.p.ink3)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          Text(this.lineOf(item))
            .fontSize(type.small.fontSize)
            .lineHeight(type.small.lineHeight)
            .fontColor(statusColor(this.statusOf(item)))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Icon({ name: 'chevronRight', iconSize: 16, color: appStore.theme.p.ink3 })
      }
      .constraintSize({ minHeight: 50 })
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.openName = this.openName === item.name ? '' : item.name
      })
      if (this.openName === item.name) {
        Column() {
          Scroll() {
            Text(this.contentText(item))
              .fontSize(type.small.fontSize)
              .lineHeight(type.small.lineHeight)
              .fontColor(appStore.theme.p.ink2)
              .width('100%')
          }
          .constraintSize({ maxHeight: 180 })
          .width('100%')
          .scrollBar(BarState.Off)
          if (this.bots().length > 0) {
            Divider()
              .strokeWidth(this.hairline())
              .color(appStore.theme.p.line)
              .margin({ top: 10 })
            Text(t('Used by'))
              .fontSize(type.caption.fontSize)
              .lineHeight(type.caption.lineHeight)
              .fontColor(appStore.theme.p.ink3)
              .margin({ top: 10 })
            ForEach(this.bots(), (bot: Bot) => {
              SwitchRow({
                label: bot.name,
                on: this.botHas(item, bot),
                onChange: (on: boolean): void => this.setAttached(item, bot, on),
              })
            }, (bot: Bot) => `${bot.id}-${this.botHas(item, bot)}`)
          }
          Row({ space: 14 }) {
            Text(t('Edit'))
              .fontSize(type.settingsRow.fontSize)
              .lineHeight(type.settingsRow.lineHeight)
              .fontColor(appStore.theme.p.ink2)
              .onClick(() => this.startEdit(item))
            if (this.approvableOf(item).length > 0) {
              Text(t('Approve'))
                .fontSize(type.settingsRow.fontSize)
                .lineHeight(type.settingsRow.lineHeight)
                .fontWeight('600')
                .fontColor(appStore.theme.p.accent)
                .onClick(() => {
                  void this.approveAll(item)
                })
            }
            Text(this.armedDelete === item.name ? t('Click again to delete') : t('Delete'))
              .fontSize(type.settingsRow.fontSize)
              .lineHeight(type.settingsRow.lineHeight)
              .fontColor(appStore.theme.p.danger)
              .onClick(() => this.tapDelete(item))
          }
          .justifyContent(FlexAlign.End)
          .width('100%')
          .margin({ top: 10 })
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .border({ width: { top: this.hairline() }, color: appStore.theme.p.line })
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
  }

  // The add/edit form: kind tabs, then the fields the kind wants.
  @Builder
  editBlock() {
    FormSection({ label: this.editing?.originalName !== '' && this.editing !== null ? t('Edit capability') : t('Add capability') }) {
      Column({ space: 8 }) {
        TextInput({ text: this.editing?.name ?? '', placeholder: t('Name') })
          .fontSize(type.settingsRow.fontSize)
          .fontColor(appStore.theme.p.ink)
          .placeholderColor(appStore.theme.p.ink3)
          .backgroundColor(Color.Transparent)
          .border({ width: 1, color: appStore.theme.p.line })
          .borderRadius(10)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .constraintSize({ minHeight: 40 })
          .enabled(this.editing?.originalName === '')
          .width('100%')
          .onChange((value: string): void => this.setField('name', value))
        Row({ space: 0 }) {
          this.kindTab('mcp', t('MCP'))
          this.kindTab('skill', t('Skill'))
          this.kindTab('pack', t('Pack'))
        }
        .width('100%')
        .border({ width: 1, color: appStore.theme.p.line })
        .borderRadius(20)
        TextInput({ text: this.editing?.description ?? '', placeholder: t('Description') })
          .fontSize(type.settingsRow.fontSize)
          .fontColor(appStore.theme.p.ink)
          .placeholderColor(appStore.theme.p.ink3)
          .backgroundColor(Color.Transparent)
          .border({ width: 1, color: appStore.theme.p.line })
          .borderRadius(10)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .constraintSize({ minHeight: 40 })
          .width('100%')
          .onChange((value: string): void => this.setField('description', value))
        if (this.editing?.kind === 'mcp') {
          Row({ space: 0 }) {
            this.transportTab('stdio', t('Local command'))
            this.transportTab('streamable-http', t('HTTP server'))
          }
          .width('100%')
          .border({ width: 1, color: appStore.theme.p.line })
          .borderRadius(20)
          if (this.editing?.transport === 'stdio') {
            TextInput({ text: this.editing?.command ?? '', placeholder: t('Command') })
              .fontSize(type.settingsRow.fontSize)
              .fontColor(appStore.theme.p.ink)
              .placeholderColor(appStore.theme.p.ink3)
              .backgroundColor(Color.Transparent)
              .border({ width: 1, color: appStore.theme.p.line })
              .borderRadius(10)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .constraintSize({ minHeight: 40 })
              .width('100%')
              .onChange((value: string): void => this.setField('command', value))
            TextArea({ text: this.editing?.argsText ?? '', placeholder: t('Arguments (one per line)') })
              .fontSize(type.small.fontSize)
              .fontColor(appStore.theme.p.ink)
              .placeholderColor(appStore.theme.p.ink3)
              .backgroundColor(Color.Transparent)
              .border({ width: 1, color: appStore.theme.p.line })
              .borderRadius(10)
              .padding({ left: 12, right: 12, top: 10, bottom: 10 })
              .constraintSize({ minHeight: 80 })
              .width('100%')
              .onChange((value: string): void => this.setField('argsText', value))
            TextArea({ text: this.editing?.envText ?? '', placeholder: '{"API_KEY": "$DSH_SECRET_MY_KEY"}' })
              .fontSize(type.small.fontSize)
              .fontColor(appStore.theme.p.ink)
              .placeholderColor(appStore.theme.p.ink3)
              .backgroundColor(Color.Transparent)
              .border({ width: 1, color: appStore.theme.p.line })
              .borderRadius(10)
              .padding({ left: 12, right: 12, top: 10, bottom: 10 })
              .constraintSize({ minHeight: 80 })
              .width('100%')
              .onChange((value: string): void => this.setField('envText', value))
          } else {
            TextInput({ text: this.editing?.url ?? '', placeholder: t('URL') })
              .fontSize(type.settingsRow.fontSize)
              .fontColor(appStore.theme.p.ink)
              .placeholderColor(appStore.theme.p.ink3)
              .backgroundColor(Color.Transparent)
              .border({ width: 1, color: appStore.theme.p.line })
              .borderRadius(10)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .constraintSize({ minHeight: 40 })
              .width('100%')
              .onChange((value: string): void => this.setField('url', value))
            TextArea({ text: this.editing?.headersText ?? '', placeholder: '{"API_KEY": "$DSH_SECRET_MY_KEY"}' })
              .fontSize(type.small.fontSize)
              .fontColor(appStore.theme.p.ink)
              .placeholderColor(appStore.theme.p.ink3)
              .backgroundColor(Color.Transparent)
              .border({ width: 1, color: appStore.theme.p.line })
              .borderRadius(10)
              .padding({ left: 12, right: 12, top: 10, bottom: 10 })
              .constraintSize({ minHeight: 80 })
              .width('100%')
              .onChange((value: string): void => this.setField('headersText', value))
          }
        } else if (this.editing?.kind === 'skill') {
          TextArea({ text: this.editing?.content ?? '', placeholder: t('Skill instructions') })
            .fontSize(type.small.fontSize)
            .fontColor(appStore.theme.p.ink)
            .placeholderColor(appStore.theme.p.ink3)
            .backgroundColor(Color.Transparent)
            .border({ width: 1, color: appStore.theme.p.line })
            .borderRadius(10)
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .constraintSize({ minHeight: 80 })
            .width('100%')
            .onChange((value: string): void => this.setField('content', value))
        } else {
          if (this.libraryNames().length === 0) {
            Text(t('Save an MCP server or skill first.'))
              .fontSize(type.small.fontSize)
              .lineHeight(type.small.lineHeight)
              .fontColor(appStore.theme.p.ink3)
          } else {
            Column({ space: 6 }) {
              ForEach(this.libraryNames(), (name: string) => {
                Row({ space: 8 }) {
                  Text(this.includesItem(name) ? '✓' : '○')
                    .fontSize(type.settingsRow.fontSize)
                    .fontColor(this.includesItem(name) ? appStore.theme.p.accent : appStore.theme.p.ink3)
                  Text(name)
                    .fontSize(type.settingsRow.fontSize)
                    .lineHeight(type.settingsRow.lineHeight)
                    .fontColor(appStore.theme.p.ink)
                }
                .alignItems(VerticalAlign.Center)
                .onClick(() => this.toggleItem(name))
              }, (name: string) => name)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
        }
        Row({ space: 14 }) {
          Text(t('Cancel'))
            .fontSize(type.settingsRow.fontSize)
            .lineHeight(type.settingsRow.lineHeight)
            .fontColor(appStore.theme.p.ink2)
            .onClick(() => {
              this.editing = null
            })
          Text(this.editing?.originalName !== '' ? t('Save changes') : t('Add capability'))
            .fontSize(type.settingsRow.fontSize)
            .lineHeight(type.settingsRow.lineHeight)
            .fontWeight('600')
            .fontColor((this.editing?.name ?? '').trim() === '' ? appStore.theme.p.ink3 : appStore.theme.p.accent)
            .onClick(() => {
              if ((this.editing?.name ?? '').trim() !== '') this.saveCapability()
            })
        }
        .justifyContent(FlexAlign.End)
        .width('100%')
        .margin({ top: 4 })
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  kindTab(id: string, label: string) {
    Column() {
      Text(label)
        .fontSize(type.caption.fontSize)
        .lineHeight(type.caption.lineHeight)
        .fontWeight('500')
        .fontColor(this.editing?.kind === id ? appStore.theme.p.accentInk : appStore.theme.p.ink2)
    }
    .layoutWeight(1)
    .constraintSize({ minHeight: 38 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.editing?.kind === id ? appStore.theme.p.accent : Color.Transparent)
    .enabled(this.editing?.originalName === '')
    .onClick(() => this.setField('kind', id))
  }

  @Builder
  transportTab(id: string, label: string) {
    Column() {
      Text(label)
        .fontSize(type.caption.fontSize)
        .lineHeight(type.caption.lineHeight)
        .fontWeight('500')
        .fontColor(this.editing?.transport === id ? appStore.theme.p.accentInk : appStore.theme.p.ink2)
    }
    .layoutWeight(1)
    .constraintSize({ minHeight: 38 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.editing?.transport === id ? appStore.theme.p.accent : Color.Transparent)
    .onClick(() => this.setField('transport', id))
  }

  private setField(field: string, value: string): void {
    const draft = this.editing
    if (draft === null) return
    const next: EditDraft = {
      name: field === 'name' ? value : draft.name,
      kind: field === 'kind' ? value : draft.kind,
      description: field === 'description' ? value : draft.description,
      transport: field === 'transport' ? value : draft.transport,
      command: field === 'command' ? value : draft.command,
      argsText: field === 'argsText' ? value : draft.argsText,
      envText: field === 'envText' ? value : draft.envText,
      url: field === 'url' ? value : draft.url,
      headersText: field === 'headersText' ? value : draft.headersText,
      content: field === 'content' ? value : draft.content,
      items: draft.items,
      originalName: draft.originalName,
    }
    this.editing = next
  }
}
