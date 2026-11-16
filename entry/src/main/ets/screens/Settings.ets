// The settings panel (mobile/src/screens/Settings.tsx): phone prefs —
// computers, appearance, language, in-app banners — and the team pages in the
// desktop's order. The phone choices write saved prefs at once; the team rows
// lead to the settings sub pages.

import { appStore, shadowOf } from '../components/Theme'
import { t } from '../common/ui/i18n'
import type { LangSetting } from '../common/ui/i18n'
import { FormSection, FormRow, Segmented, SectionDivider, SwitchRow } from '../components/FormControls'
import type { SegmentOption } from '../components/FormControls'
import { Icon } from '../components/Icon'

function themeOptions(): SegmentOption[] {
  const options: SegmentOption[] = [
    { id: 'system', label: t('System') },
    { id: 'light', label: t('Light') },
    { id: 'dark', label: t('Dark') },
  ]
  return options
}

function langOptions(): SegmentOption[] {
  const options: SegmentOption[] = [
    { id: 'system', label: t('Follow system') },
    { id: 'zh', label: '简体中文' },
    { id: 'en', label: 'English' },
  ]
  return options
}

@ComponentV2
export struct Settings {
  @Local pathStack: NavPathStack | null = null

  private hairline(): number {
    return this.getUIContext().px2vp(1)
  }

  private goBack(): void {
    if (this.pathStack !== null) this.pathStack.pop()
  }

  private push(route: string, param: Object | null): void {
    if (this.pathStack !== null) this.pathStack.pushPathByName(route, param)
  }

  private computerName(): string {
    return appStore.computers.active?.name ?? ''
  }

  private themeValue(): string {
    return appStore.prefs.theme
  }

  private langValue(): string {
    return appStore.prefs.lang
  }

  private pickTheme(id: string): void {
    void appStore.prefs.setTheme(id)
    appStore.applyTheme()
  }

  private pickLang(id: string): void {
    void appStore.prefs.setLang(id as LangSetting)
  }

  private pickBanners(on: boolean): void {
    void appStore.prefs.setBanners(on)
  }

  build() {
    NavDestination() {
      Stack() {
        Scroll() {
          Column() {
            FormSection({ label: t('Phone') }) {
              FormRow({
                label: t('Computers'),
                value: this.computerName(),
                hasAction: true,
                onPress: (): void => this.push('computers', null),
              })
              SectionDivider()
              Column() {
                Segmented({
                  label: t('Appearance'),
                  value: this.themeValue(),
                  onPick: (id: string): void => this.pickTheme(id),
                  options: themeOptions(),
                })
              }
              .width('100%')
              SectionDivider()
              Column() {
                Segmented({
                  label: t('Language'),
                  value: this.langValue(),
                  onPick: (id: string): void => this.pickLang(id),
                  options: langOptions(),
                })
              }
              .width('100%')
              SectionDivider()
              SwitchRow({
                label: t('In-app banners'),
                on: appStore.prefs.banners,
                onChange: (on: boolean): void => this.pickBanners(on),
              })
            }
            // The desktop settings pages, in the desktop's order.
            FormSection({ label: t('Team') }) {
              FormRow({
                label: t('Models'),
                hasAction: true,
                onPress: (): void => this.push('providers', null),
              })
              SectionDivider()
              FormRow({
                label: t('Connectors'),
                hasAction: true,
                onPress: (): void => this.push('connectors', null),
              })
              SectionDivider()
              FormRow({
                label: t('Capabilities'),
                hasAction: true,
                onPress: (): void => this.push('capabilities', null),
              })
              SectionDivider()
              FormRow({
                label: t('Usage'),
                hasAction: true,
                onPress: (): void => this.push('teamUsage', null),
              })
              SectionDivider()
              FormRow({
                label: t('Secrets'),
                hasAction: true,
                onPress: (): void => this.push('secrets', null),
              })
              SectionDivider()
              FormRow({
                label: t('Location'),
                hasAction: true,
                onPress: (): void => this.push('location', null),
              })
              SectionDivider()
              FormRow({
                label: t('Updates & diagnostics'),
                hasAction: true,
                onPress: (): void => this.push('updates', null),
              })
              SectionDivider()
              FormRow({
                label: t('About DS Bot'),
                hasAction: true,
                onPress: (): void => this.push('about', null),
              })
            }
          }
          .width('100%')
          // Full-bleed: the list scrolls under the status bar and the floating
          // back button; both safe insets live in the scrolled content so no
          // fixed solid band shows.
          .padding({ top: appStore.safeTop + 60, bottom: appStore.safeBottom + 40 })
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .align(Alignment.Top)

        // The floating back button: transparent chrome over the scrolling
        // list, dropped below the status bar only — no fixed header band.
        Column() {
          Icon({ name: 'chevronLeft', iconSize: 20, color: appStore.theme.p.ink })
        }
        .width(40)
        .height(40)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .borderRadius(20)
        .backgroundColor(appStore.theme.p.card)
        .border({ width: this.hairline(), color: appStore.theme.p.line2 })
        .shadow(shadowOf(1))
        .accessibilityText(t('Back'))
        .position({ x: 12, y: appStore.safeTop })
        .onClick(() => this.goBack())
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .backgroundColor(appStore.theme.p.main)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack
    })
    .onShown(() => {
      // The computers list refreshes so the row names the active computer.
      void appStore.computers.refresh()
    })
  }
}

@Builder
export function SettingsBuilder() {
  Settings()
}
