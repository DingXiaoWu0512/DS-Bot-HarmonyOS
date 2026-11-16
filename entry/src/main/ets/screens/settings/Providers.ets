// The model providers page (settings-pages.tsx Providers): the configured
// providers with key state and model counts, the key editor, and adding a
// known provider or a custom API (with Find models). Key calls are gated by
// the link's ensureUnlock.

import { appStore, type } from '../../components/Theme'
import { t } from '../../common/ui/i18n'
import { FormSection, BackRow } from '../../components/FormControls'
import { Icon } from '../../components/Icon'

interface ProviderKeyInfo {
  configured?: boolean
  writable?: boolean
}

interface ProviderModelInfo {
  name?: string
  id?: string
}

interface ProviderItem {
  id: string
  name: string
  key?: ProviderKeyInfo
  models?: ProviderModelInfo[]
  removable?: boolean
  error?: string
}

interface ProvidersView {
  available?: boolean
  providers?: ProviderItem[]
  addable?: ProviderAddable[]
  protocols?: string[]
}

interface ProviderKeyPayload {
  provider: string
  value?: string | null
}

interface ProviderRemovePayload {
  provider: string
}

interface ProviderAddPayload {
  custom?: boolean
  provider: string
  name?: string
  baseURL?: string
  api?: string
  key?: string
  models?: ProviderModelInfo[]
}

interface ProviderModelsPayload {
  baseURL: string
  api?: string
  key?: string
}

interface ProviderModelsReply {
  models?: ProviderModelInfo[]
}

interface CodedError {
  code?: string
}

interface ProviderAddable {
  id: string
  name: string
}

// The key line under a provider name.
function keyLabel(key: ProviderKeyInfo | undefined): string {
  if (key?.configured !== true) return t('Needs an API key')
  if (key.writable === true) return t('Key set')
  return t('Key set outside DS Bot')
}

@ComponentV2
export struct Providers {
  @Local pathStack: NavPathStack | null = null
  @Local view: ProvidersView | null = null
  @Local openId: string = ''
  @Local adding: boolean = false
  @Local mode: string = 'known'
  @Local keyDraft: string = ''
  @Local draftProvider: string = ''
  @Local draftName: string = ''
  @Local draftBaseURL: string = ''
  @Local draftApi: string = ''
  @Local draftKey: string = ''
  @Local draftTyped: string = ''
  @Local found: ProviderModelInfo[] | null = null
  @Local picked: string[] = []
  @Local confirmId: string = ''
  @Local error: string = ''
  @Local savedId: string = ''
  @Local refreshTick: number = 0

  private hairline(): number {
    return this.getUIContext().px2vp(1)
  }

  private goBack(): void {
    if (this.pathStack !== null) this.pathStack.pop()
  }

  private async load(): Promise<void> {
    const controller = appStore.link.controller
    if (controller === null) return
    try {
      const reply = (await controller.call('providers')) as ProvidersView | null
      this.view = reply
      this.refreshTick += 1
    } catch {
      // The list stays as it was.
    }
  }

  private async run(endpoint: string, payload: Object, after?: () => void): Promise<void> {
    const controller = appStore.link.controller
    if (controller === null) return
    try {
      await controller.call(endpoint, payload)
      this.error = ''
      if (after !== undefined) after()
    } catch (failure) {
      if ((failure as CodedError)?.code === 'unlock/canceled') return
      this.error = failure instanceof Error ? failure.message : String(failure)
    }
  }

  private saveKey(providerId: string): void {
    if (this.keyDraft === '') return
    const next = this.keyDraft
    this.keyDraft = ''
    const payload: ProviderKeyPayload = { provider: providerId, value: next }
    void this.run('provider-key', payload, (): void => {
      this.savedId = providerId
      void this.load()
    })
  }

  private removeKey(providerId: string): void {
    const payload: ProviderKeyPayload = { provider: providerId, value: null }
    void this.run('provider-key', payload, (): void => {
      void this.load()
    })
  }

  private typedIds(): string[] {
    const ids: string[] = []
    for (const piece of this.draftTyped.split(/[\s,]+/)) {
      const id = piece.trim()
      if (id !== '') ids.push(id)
    }
    return ids
  }

  private pickedModels(): ProviderModelInfo[] {
    const models: ProviderModelInfo[] = []
    for (const model of this.found ?? []) {
      const id = model.id ?? ''
      if (id !== '' && this.picked.includes(id)) models.push(model)
    }
    for (const id of this.typedIds()) {
      if (!this.picked.includes(id)) models.push({ id: id })
    }
    return models
  }

  private customReady(): boolean {
    return this.draftProvider.trim() !== '' && this.draftBaseURL.trim() !== '' && this.pickedModels().length > 0
  }

  private firstProtocol(): string {
    const protocols = this.view?.protocols ?? []
    return protocols.length > 0 ? protocols[0] : ''
  }

  private discover(): void {
    if (this.draftBaseURL.trim() === '') return
    const payload: ProviderModelsPayload = { baseURL: this.draftBaseURL, api: this.draftApi !== '' ? this.draftApi : this.firstProtocol(), key: this.draftKey }
    void this.run('provider-models', payload, (): void => {})
  }

  private addKnown(): void {
    if (this.draftProvider === '') return
    const payload: ProviderAddPayload = { provider: this.draftProvider, key: this.draftKey }
    void this.run('provider-add', payload, (): void => {
      this.adding = false
      this.draftProvider = ''
      this.draftKey = ''
      void this.load()
    })
  }

  private addCustom(): void {
    if (!this.customReady()) return
    const payload: ProviderAddPayload = {
      custom: true,
      provider: this.draftProvider.trim(),
      name: this.draftName,
      baseURL: this.draftBaseURL,
      api: this.draftApi !== '' ? this.draftApi : this.firstProtocol(),
      key: this.draftKey,
      models: this.pickedModels(),
    }
    void this.run('provider-add', payload, (): void => {
      this.adding = false
      this.found = null
      this.picked = []
      this.draftProvider = ''
      this.draftName = ''
      this.draftBaseURL = ''
      this.draftApi = ''
      this.draftKey = ''
      this.draftTyped = ''
      void this.load()
    })
  }

  private providers(): ProviderItem[] {
    void this.refreshTick
    return this.view?.providers ?? []
  }

  private modelsLine(provider: ProviderItem): string {
    const models = provider.models ?? []
    if (models.length === 0) return t('No models')
    const names: string[] = []
    for (const model of models.slice(0, 4)) {
      names.push(model.name ?? model.id ?? '')
    }
    let line = names.join(' · ')
    if (models.length > 4) line += t(' and {count} more', { 'count': models.length - 4 })
    return line
  }

  private keyColor(provider: ProviderItem): string {
    if (provider.key?.configured !== true) {
      return appStore.theme.p.danger
    }
    return appStore.theme.p.ink3
  }

  private protocols(): string[] {
    return this.view?.protocols ?? []
  }

  build() {
    NavDestination() {
      Column() {
        BackRow({
          label: t('Model providers'),
          onBack: (): void => this.goBack(),
        })
        Scroll() {
          Column() {
            if (this.view === null && this.error === '') {
              // The providers call refreshes the model catalog first and can
              // take a while; show that it is loading, not a blank page.
              Column() {
                LoadingProgress()
                  .width(28)
                  .height(28)
                  .color(appStore.theme.p.accent)
              }
              .width('100%')
              .padding({ top: 40 })
              .alignItems(HorizontalAlign.Center)
            }
            if (this.view?.available === false) {
              Text(t('This DSH cannot set up model providers.'))
                .fontSize(type.small.fontSize)
                .lineHeight(type.small.lineHeight)
                .fontColor(appStore.theme.p.ink3)
                .width('100%')
                .padding(18)
            }
            if (this.error !== '') {
              Text(this.error)
                .fontSize(type.small.fontSize)
                .lineHeight(type.small.lineHeight)
                .fontColor(appStore.theme.p.danger)
                .width('100%')
                .padding(18)
            }
            FormSection({ label: t('Model providers · {count}', { 'count': this.providers().length }) }) {
              ForEach(this.providers(), (provider: ProviderItem, index: number) => {
                if (index > 0) {
                  Divider()
                    .strokeWidth(this.hairline())
                    .color(appStore.theme.p.line)
                }
                this.providerBlock(provider)
              }, (provider: ProviderItem) => provider.id)
            }
            if (this.adding) {
              this.addingBlock()
            } else {
              Column() {
                Column() {
                  Text(t('Add a provider'))
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
                .onClick(() => {
                  this.adding = true
                })
              }
              .width('100%')
              .padding({ left: 18, right: 18, top: 14 })
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

  // One provider row; expanded it holds the key editor, the model list and
  // the remove flow.
  @Builder
  providerBlock(provider: ProviderItem) {
    Column() {
      Row({ space: 10 }) {
        Column({ space: 2 }) {
          Text(provider.name)
            .fontSize(type.settingsRow.fontSize)
            .lineHeight(type.settingsRow.lineHeight)
            .fontColor(appStore.theme.p.ink)
          Text(keyLabel(provider.key))
            .fontSize(type.small.fontSize)
            .lineHeight(type.small.lineHeight)
            .fontColor(this.keyColor(provider))
          if ((provider.error ?? '') !== '') {
            Text(provider.error ?? '')
              .fontSize(type.small.fontSize)
              .lineHeight(type.small.lineHeight)
              .fontColor(appStore.theme.p.danger)
          }
        }
        .layoutWeight(1)
        .constraintSize({ minWidth: 0 })
        .alignItems(HorizontalAlign.Start)
        Text((provider.models ?? []).length === 0 ? t('No models') : t('{count} models', { 'count': (provider.models ?? []).length }))
          .fontSize(type.settingsRow.fontSize)
          .lineHeight(type.settingsRow.lineHeight)
          .fontColor(appStore.theme.p.ink2)
        Icon({ name: 'chevronRight', iconSize: 16, color: appStore.theme.p.ink3 })
      }
      .constraintSize({ minHeight: 50 })
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.openId = this.openId === provider.id ? '' : provider.id
        this.savedId = ''
        this.keyDraft = ''
      })
      if (this.openId === provider.id) {
        Column() {
          if (provider.key?.writable === true) {
            Column({ space: 6 }) {
              Text(provider.key.configured === true ? t('Replace the API key') : t('API key'))
                .fontSize(type.small.fontSize)
                .lineHeight(type.small.lineHeight)
                .fontColor(appStore.theme.p.ink3)
              TextInput({ text: this.keyDraft, placeholder: t('{provider} API key', { 'provider': provider.name }) })
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
                  this.keyDraft = value
                })
              Row({ space: 8 }) {
                if (provider.key.configured === true) {
                  Text(t('Remove key'))
                    .fontSize(14)
                    .lineHeight(20)
                    .fontColor(appStore.theme.p.danger)
                    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                    .borderRadius(10)
                    .backgroundColor(appStore.theme.p.hover)
                    .onClick(() => this.removeKey(provider.id))
                }
                Text(t('Save'))
                  .fontSize(14)
                  .lineHeight(20)
                  .fontWeight('600')
                  .fontColor(appStore.theme.p.accentInk)
                  .opacity(this.keyDraft === '' ? 0.4 : 1)
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .borderRadius(10)
                  .backgroundColor(appStore.theme.p.accent)
                  .onClick(() => {
                    if (this.keyDraft !== '') this.saveKey(provider.id)
                  })
              }
              .justifyContent(FlexAlign.End)
              .width('100%')
              if (this.savedId === provider.id) {
                Text(t('Saved.'))
                  .fontSize(type.small.fontSize)
                  .lineHeight(type.small.lineHeight)
                  .fontColor(appStore.theme.p.accent)
              }
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 10, bottom: 10 })
            .alignItems(HorizontalAlign.Start)
          } else if (provider.key !== undefined) {
            Text(t('This key comes from outside DS Bot, such as an environment variable, and cannot be changed here.'))
              .fontSize(type.small.fontSize)
              .lineHeight(type.small.lineHeight)
              .fontColor(appStore.theme.p.ink3)
              .width('100%')
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          }
          if ((provider.models ?? []).length > 0) {
            Column({ space: 4 }) {
              Text(t('Models'))
                .fontSize(type.small.fontSize)
                .lineHeight(type.small.lineHeight)
                .fontColor(appStore.theme.p.ink3)
              Text(this.modelsLine(provider))
                .fontSize(type.small.fontSize)
                .lineHeight(type.small.lineHeight)
                .fontColor(appStore.theme.p.ink2)
            }
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 10 })
            .alignItems(HorizontalAlign.Start)
          }
          if (provider.removable === true) {
            if (this.confirmId === provider.id) {
              Row({ space: 12 }) {
                Text(t('Remove {name}? Bots on its models need another model.', { 'name': provider.name }))
                  .fontSize(type.small.fontSize)
                  .lineHeight(type.small.lineHeight)
                  .fontColor(appStore.theme.p.ink2)
                  .layoutWeight(1)
                Text(t('Keep'))
                  .fontSize(14)
                  .lineHeight(20)
                  .fontColor(appStore.theme.p.ink2)
                  .onClick(() => {
                    this.confirmId = ''
                  })
                Text(t('Remove'))
                  .fontSize(14)
                  .lineHeight(20)
                  .fontWeight('600')
                  .fontColor(appStore.theme.p.danger)
                  .onClick(() => {
                    this.confirmId = ''
                    const payload: ProviderRemovePayload = { provider: provider.id }
                    void this.run('provider-remove', payload, (): void => {
                      void this.load()
                    })
                  })
              }
              .constraintSize({ minHeight: 50 })
              .width('100%')
              .padding({ left: 16, right: 16, top: 10, bottom: 10 })
              .alignItems(VerticalAlign.Center)
            } else {
              Row({ space: 10 }) {
                Text(t('Remove provider'))
                  .fontSize(type.settingsRow.fontSize)
                  .lineHeight(type.settingsRow.lineHeight)
                  .fontColor(appStore.theme.p.ink)
                  .layoutWeight(1)
                Icon({ name: 'chevronRight', iconSize: 16, color: appStore.theme.p.ink3 })
              }
              .constraintSize({ minHeight: 50 })
              .width('100%')
              .padding({ left: 16, right: 16, top: 10, bottom: 10 })
              .alignItems(VerticalAlign.Center)
              .onClick(() => {
                this.confirmId = provider.id
              })
            }
          }
        }
        .width('100%')
        .border({ width: { top: this.hairline() }, color: appStore.theme.p.line })
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
  }

  // The add form: known provider chips or the custom API fields.
  @Builder
  addingBlock() {
    FormSection({ label: t('Add a provider') }) {
      Column() {
        Row({ space: 0 }) {
          Column() {
            Text(t('Known provider'))
              .fontSize(type.caption.fontSize)
              .lineHeight(type.caption.lineHeight)
              .fontWeight('500')
              .fontColor(this.mode === 'known' ? appStore.theme.p.accentInk : appStore.theme.p.ink2)
          }
          .layoutWeight(1)
          .constraintSize({ minHeight: 38 })
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor(this.mode === 'known' ? appStore.theme.p.accent : Color.Transparent)
          .onClick(() => {
            this.mode = 'known'
          })
          Column() {
            Text(t('Custom API'))
              .fontSize(type.caption.fontSize)
              .lineHeight(type.caption.lineHeight)
              .fontWeight('500')
              .fontColor(this.mode === 'custom' ? appStore.theme.p.accentInk : appStore.theme.p.ink2)
          }
          .layoutWeight(1)
          .constraintSize({ minHeight: 38 })
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor(this.mode === 'custom' ? appStore.theme.p.accent : Color.Transparent)
          .onClick(() => {
            this.mode = 'custom'
          })
        }
        .width('100%')
        .border({ width: 1, color: appStore.theme.p.line })
        .borderRadius(20)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
      Divider()
        .strokeWidth(this.hairline())
        .color(appStore.theme.p.line)
      if (this.mode === 'known') {
        Column({ space: 8 }) {
          Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
            ForEach(this.view?.addable ?? [], (option: ProviderAddable) => {
              Text(option.name)
                .fontSize(14)
                .lineHeight(20)
                .fontColor(this.draftProvider === option.id ? appStore.theme.p.accentInk : appStore.theme.p.ink2)
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .borderRadius(10)
                .backgroundColor(this.draftProvider === option.id ? appStore.theme.p.accent : appStore.theme.p.hover)
                .margin({ right: 8, bottom: 8 })
                .onClick(() => {
                  this.draftProvider = option.id
                })
            }, (option: ProviderAddable) => option.id)
          }
          .width('100%')
          TextInput({ text: this.draftKey, placeholder: t('API key') })
            .fontSize(type.settingsRow.fontSize)
            .fontColor(appStore.theme.p.ink)
            .placeholderColor(appStore.theme.p.ink3)
            .backgroundColor(Color.Transparent)
            .border({ width: 1, color: appStore.theme.p.line })
            .borderRadius(10)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .height(40)
            .type(InputType.Password)
            .width('100%')
            .onChange((value: string): void => {
              this.draftKey = value
            })
          Row({ space: 12 }) {
            Text(t('Cancel'))
              .fontSize(type.settingsRow.fontSize)
              .lineHeight(type.settingsRow.lineHeight)
              .fontColor(appStore.theme.p.ink2)
              .onClick(() => {
                this.adding = false
              })
            Text(t('Add'))
              .fontSize(type.settingsRow.fontSize)
              .lineHeight(type.settingsRow.lineHeight)
              .fontWeight('600')
              .fontColor(this.draftProvider === '' ? appStore.theme.p.ink3 : appStore.theme.p.accent)
              .onClick(() => {
                if (this.draftProvider !== '') this.addKnown()
              })
          }
          .justifyContent(FlexAlign.End)
          .width('100%')
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 12 })
        .alignItems(HorizontalAlign.Start)
      } else {
        this.customBlock()
      }
    }
  }

  @Builder
  fieldInput(draft: string, placeholder: string, isPassword: boolean, onDone: (value: string) => void) {
    TextInput({ text: draft, placeholder: placeholder })
      .fontSize(type.settingsRow.fontSize)
      .fontColor(appStore.theme.p.ink)
      .placeholderColor(appStore.theme.p.ink3)
      .backgroundColor(Color.Transparent)
      .border({ width: 1, color: appStore.theme.p.line })
      .borderRadius(10)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .constraintSize({ minHeight: 40 })
      .type(isPassword ? InputType.Password : InputType.Normal)
      .width('100%')
      .onChange((value: string): void => onDone(value))
  }

  @Builder
  customBlock() {
    Column({ space: 6 }) {
      this.fieldInput(this.draftName, t('Provider name'), false, (value: string): void => {
        this.draftName = value
      })
      this.fieldInput(this.draftBaseURL, t('API base URL'), false, (value: string): void => {
        this.draftBaseURL = value
      })
      this.fieldInput(this.draftProvider, t('Provider id'), false, (value: string): void => {
        this.draftProvider = value
      })
      Row({ space: 8 }) {
        TextInput({ text: this.draftKey, placeholder: t('API key') })
          .fontSize(type.settingsRow.fontSize)
          .fontColor(appStore.theme.p.ink)
          .placeholderColor(appStore.theme.p.ink3)
          .backgroundColor(Color.Transparent)
          .border({ width: 1, color: appStore.theme.p.line })
          .borderRadius(10)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .constraintSize({ minHeight: 40 })
          .type(InputType.Password)
          .layoutWeight(1)
          .onChange((value: string): void => {
            this.draftKey = value
          })
        Text(t('Find models'))
          .fontSize(14)
          .lineHeight(20)
          .fontColor(appStore.theme.p.ink)
          .opacity(this.draftBaseURL.trim() === '' ? 0.4 : 1)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .borderRadius(10)
          .backgroundColor(appStore.theme.p.hover)
          .onClick(() => this.discover())
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      if (this.found !== null) {
        Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
          ForEach(this.found, (model: ProviderModelInfo) => {
            Text(model.name ?? model.id ?? '')
              .fontSize(14)
              .lineHeight(20)
              .fontColor(this.picked.includes(model.id ?? '') ? appStore.theme.p.accentInk : appStore.theme.p.ink2)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .borderRadius(10)
              .backgroundColor(this.picked.includes(model.id ?? '') ? appStore.theme.p.accent : appStore.theme.p.hover)
              .margin({ right: 8, bottom: 8 })
              .onClick(() => this.togglePicked(model.id ?? ''))
          }, (model: ProviderModelInfo) => model.id ?? model.name ?? '')
        }
        .width('100%')
      }
      this.fieldInput(this.draftTyped, t('Or type model ids, comma separated'), false, (value: string): void => {
        this.draftTyped = value
      })
      Row({ space: 12 }) {
        Text(t('Cancel'))
          .fontSize(type.settingsRow.fontSize)
          .lineHeight(type.settingsRow.lineHeight)
          .fontColor(appStore.theme.p.ink2)
          .onClick(() => {
            this.adding = false
          })
        Text(t('Add'))
          .fontSize(type.settingsRow.fontSize)
          .lineHeight(type.settingsRow.lineHeight)
          .fontWeight('600')
          .fontColor(this.customReady() ? appStore.theme.p.accent : appStore.theme.p.ink3)
          .onClick(() => {
            if (this.customReady()) this.addCustom()
          })
      }
      .justifyContent(FlexAlign.End)
      .width('100%')
      .margin({ top: 4 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: 12 })
    .alignItems(HorizontalAlign.Start)
  }

  private togglePicked(id: string): void {
    if (id === '') return
    const next: string[] = []
    for (const item of this.picked) {
      if (item !== id) next.push(item)
    }
    if (!this.picked.includes(id)) next.push(id)
    this.picked = next
  }
}


@Builder
export function ProvidersBuilder() {
  Providers()
}
