// The usage screen (mobile/src/screens/manage.tsx Usage): day/week/month
// token totals, per-model totals, and the run stats — turns, steps, and how
// much of the context window the Bot's chat uses.

import { appStore, type } from '../components/Theme'
import { t } from '../common/ui/i18n'
import { FormSection, BackRow } from '../components/FormControls'
import { readStringParam } from './routes'

interface UsageTotals {
  input: number
  cacheRead?: number
  cacheWrite?: number
  output: number
}

interface UsageModelRow extends UsageTotals {
  key?: string
  name: string
}

interface UsageSummaryReply {
  day?: UsageTotals
  week?: UsageTotals
  month?: UsageTotals
  models?: UsageModelRow[]
}

interface SessionStats {
  turns?: number
  steps?: number
}

interface ContextPressure {
  pressureTokens?: number
  contextWindow?: number
}

interface RunStatsReply {
  sessionStats?: SessionStats
  contextPressure?: ContextPressure
}

interface UsagePayload {
  botId: string
}

function sumOf(totals: UsageTotals): number {
  return totals.input + (totals.cacheRead ?? 0) + (totals.cacheWrite ?? 0) + totals.output
}

function totalOf(totals: UsageTotals | undefined): string {
  if (totals === undefined) return '—'
  return sumOf(totals).toLocaleString()
}

@ComponentV2
export struct Usage {
  @Local pathStack: NavPathStack | null = null
  @Local botId: string = ''
  @Local summary: UsageSummaryReply | null = null
  @Local stats: RunStatsReply | null = null
  @Local refreshTick: number = 0

  private goBack(): void {
    if (this.pathStack !== null) this.pathStack.pop()
  }

  private models(): UsageModelRow[] {
    void this.refreshTick
    return this.summary?.models ?? []
  }

  private dayTotal(): string {
    return totalOf(this.summary?.day)
  }

  private weekTotal(): string {
    return totalOf(this.summary?.week)
  }

  private monthTotal(): string {
    return totalOf(this.summary?.month)
  }

  private turns(): string {
    const turns = this.stats?.sessionStats?.turns
    return turns !== undefined ? String(turns) : '—'
  }

  private steps(): string {
    const steps = this.stats?.sessionStats?.steps
    return steps !== undefined ? String(steps) : '—'
  }

  private contextUsed(): string {
    const pressure = this.stats?.contextPressure
    if (pressure === undefined || pressure === null) return '—'
    const used = pressure.pressureTokens
    const window = pressure.contextWindow
    if (used === undefined || window === undefined || window === 0) return '—'
    return `${Math.round(used / window * 100)}%`
  }

  private async load(): Promise<void> {
    const controller = appStore.link.controller
    if (controller === null) return
    const payload: UsagePayload = { botId: this.botId }
    try {
      const reply = (await controller.call('usage-summary', payload)) as UsageSummaryReply | null
      this.summary = reply
    } catch {
      // The summary stays as it was.
    }
    try {
      const reply = (await controller.call('run-stats', payload)) as RunStatsReply | null
      this.stats = reply
    } catch {
      // The stats stay as they were.
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
              this.usageRow(t('Day'), this.dayTotal())
              Divider()
                .strokeWidth(this.hairline())
                .color(appStore.theme.p.line)
              this.usageRow(t('Week'), this.weekTotal())
              Divider()
                .strokeWidth(this.hairline())
                .color(appStore.theme.p.line)
              this.usageRow(t('Month'), this.monthTotal())
            }
            if (this.models().length > 0) {
              FormSection({ label: t('Model') }) {
                ForEach(this.models(), (model: UsageModelRow, index: number) => {
                  if (index > 0) {
                    Divider()
                      .strokeWidth(this.hairline())
                      .color(appStore.theme.p.line)
                  }
                  this.usageRow(model.name, sumOf(model).toLocaleString())
                }, (model: UsageModelRow) => model.key ?? model.name)
              }
            }
            FormSection({ label: t('Runs') }) {
              this.usageRow(t('Turns'), this.turns())
              Divider()
                .strokeWidth(this.hairline())
                .color(appStore.theme.p.line)
              this.usageRow(t('Steps'), this.steps())
              Divider()
                .strokeWidth(this.hairline())
                .color(appStore.theme.p.line)
              this.usageRow(t('Context used'), this.contextUsed())
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
      void this.load()
    })
  }

  private hairline(): number {
    return this.getUIContext().px2vp(1)
  }

  @Builder
  usageRow(label: string, value: string) {
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

@Builder
export function UsageBuilder() {
  Usage()
}
