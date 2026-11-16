// The connectors page (settings-pages.tsx Connectors): each connector with its
// status, connect-by-token, disconnect and retry. The token call is gated by
// the link's ensureUnlock.

import { appStore, type } from '../../components/Theme'
import { t } from '../../common/ui/i18n'
import { FormSection, BackRow, FormRow } from '../../components/FormControls'
import { Icon } from '../../components/Icon'
import { openExternalUrl } from '../chat/MarkdownText'
import { common } from '@kit.AbilityKit'

interface ConnectorItem {
  id: string
  name: string
  state?: string
  account?: string
  error?: string
}

interface ConnectorPayload {
  id: string
  token?: string
}

interface CodedError {
  code?: string
}

const CONNECTOR_ABOUT: Record<string, string> = { 'github': 'Repositories, issues, and pull requests' }
const TOKEN_URLS: Record<string, string> = { 'github': 'https://github.com/settings/personal-access-tokens/new' }

function connectorStatus(item: ConnectorItem): string {
  if (item.state === 'connecting') return t('Connecting…')
  if (item.state === 'error') return t('Could not connect: {error}', { 'error': item.error ?? '' })
  if (item.state === 'ready') {
    if (item.account !== undefined && item.account !== '') {
      return t('Connected as {account}', { 'account': item.account })
    }
    return t('Connected')
  }
  const about = CONNECTOR_ABOUT[item.id]
  if (about !== undefined) return t(about)
  return ''
}

@ComponentV2
export struct Connectors {
  @Local pathStack: NavPathStack | null = null
  @Local formId: string = ''
  @Local token: string = ''
  @Local busyId: string = ''
  @Local error: string = ''
  @Local refreshTick: number = 0

  private hairline(): number {
    return this.getUIContext().px2vp(1)
  }

  private goBack(): void {
    if (this.pathStack !== null) this.pathStack.pop()
  }

  private connectors(): ConnectorItem[] {
    void this.refreshTick
    const raw = appStore.link.team?.connectors
    // The host sends the roster view here: { connectors: [...], mail: {...} } —
    // not the flat array the REF's connection.ts sketched.
    if (Array.isArray(raw)) return raw as ConnectorItem[]
    if (raw !== null && raw !== undefined) {
      const holder = raw as Record<string, Object>
      const list = holder['connectors']
      if (Array.isArray(list)) return list as ConnectorItem[]
    }
    return []
  }

  private async run(id: string, endpoint: string, payload: Object, after?: () => void): Promise<void> {
    this.busyId = id
    const controller = appStore.link.controller
    if (controller === null) {
      this.busyId = ''
      return
    }
    try {
      await controller.call(endpoint, payload)
      this.error = ''
      if (after !== undefined) after()
    } catch (failure) {
      if ((failure as CodedError)?.code === 'unlock/canceled') return
      this.error = failure instanceof Error ? failure.message : String(failure)
    } finally {
      this.busyId = ''
    }
  }

  private tokenUrl(id: string): string {
    return TOKEN_URLS[id] ?? ''
  }

  private openTokenUrl(url: string): void {
    // The token page lives on the web; the system browser takes it.
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    openExternalUrl(context, url)
  }

  build() {
    NavDestination() {
      Column() {
        BackRow({
          label: t('Connectors'),
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
            FormSection({ label: t('Connectors') }) {
              ForEach(this.connectors(), (item: ConnectorItem, index: number) => {
                if (index > 0) {
                  Divider()
                    .strokeWidth(this.hairline())
                    .color(appStore.theme.p.line)
                }
                this.connectorBlock(item)
              }, (item: ConnectorItem) => item.id)
              if (this.connectors().length === 0) {
                FormRow({ label: t('No connectors') })
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
      this.refreshTick += 1
    })
  }

  @Builder
  connectorBlock(item: ConnectorItem) {
    Column() {
      Row({ space: 10 }) {
        Column({ space: 2 }) {
          Text(item.name)
            .fontSize(type.settingsRow.fontSize)
            .lineHeight(type.settingsRow.lineHeight)
            .fontColor(appStore.theme.p.ink)
          Text(connectorStatus(item))
            .fontSize(type.small.fontSize)
            .lineHeight(type.small.lineHeight)
            .fontColor(item.state === 'error' ? appStore.theme.p.danger : appStore.theme.p.ink3)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        if (item.state === 'error') {
          Text(t('Try again'))
            .fontSize(type.settingsRow.fontSize)
            .lineHeight(type.settingsRow.lineHeight)
            .fontColor(appStore.theme.p.accent)
            .onClick(() => {
              const payload: ConnectorPayload = { id: item.id }
              void this.run(item.id, 'connector-retry', payload)
            })
        }
        if (item.state !== 'off') {
          Text(t('Disconnect'))
            .fontSize(type.settingsRow.fontSize)
            .lineHeight(type.settingsRow.lineHeight)
            .fontColor(appStore.theme.p.ink2)
            .onClick(() => {
              const payload: ConnectorPayload = { id: item.id }
              void this.run(item.id, 'connector-disconnect', payload)
            })
        } else if (this.formId !== item.id) {
          Text(t('Connect'))
            .fontSize(type.settingsRow.fontSize)
            .lineHeight(type.settingsRow.lineHeight)
            .fontColor(appStore.theme.p.accent)
            .onClick(() => {
              this.formId = item.id
              this.token = ''
            })
        }
      }
      .constraintSize({ minHeight: 50 })
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
      .alignItems(VerticalAlign.Center)
      if (item.state === 'off' && this.formId === item.id) {
        Column({ space: 8 }) {
          TextInput({ text: this.token, placeholder: t('{name} token', { 'name': item.name }) })
            .fontSize(type.settingsRow.fontSize)
            .fontColor(appStore.theme.p.ink)
            .placeholderColor(appStore.theme.p.ink3)
            .backgroundColor(Color.Transparent)
            .border({ width: 1, color: appStore.theme.p.line })
            .borderRadius(10)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .constraintSize({ minHeight: 40 })
            .type(InputType.Password)
            .width('100%')
            .onChange((value: string): void => {
              this.token = value
            })
          if (this.tokenUrl(item.id) !== '') {
            Text(t('Create a token on {name}', { 'name': item.name }))
              .fontSize(type.small.fontSize)
              .lineHeight(type.small.lineHeight)
              .fontColor(appStore.theme.p.accent)
              .onClick(() => this.openTokenUrl(this.tokenUrl(item.id)))
          }
          Row({ space: 14 }) {
            Text(t('Cancel'))
              .fontSize(type.settingsRow.fontSize)
              .lineHeight(type.settingsRow.lineHeight)
              .fontColor(appStore.theme.p.ink2)
              .onClick(() => {
                this.formId = ''
                this.token = ''
              })
            Text(this.busyId === item.id ? t('Connecting…') : t('Connect'))
              .fontSize(type.settingsRow.fontSize)
              .lineHeight(type.settingsRow.lineHeight)
              .fontWeight('600')
              .fontColor(this.token.trim() === '' ? appStore.theme.p.ink3 : appStore.theme.p.accent)
              .onClick(() => {
                if (this.token.trim() === '' || this.busyId === item.id) return
                const next = this.token
                this.token = ''
                const payload: ConnectorPayload = { id: item.id, token: next }
                void this.run(item.id, 'connector-connect', payload, (): void => {
                  this.formId = ''
                })
              })
          }
          .justifyContent(FlexAlign.End)
          .width('100%')
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
}

@Builder
export function ConnectorsBuilder() {
  Connectors()
}
