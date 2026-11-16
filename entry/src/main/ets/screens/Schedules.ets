// The schedule screen (mobile/src/screens/manage.tsx Schedules): the Bot's
// tasks with a human-readable "when", and the new-task form — title, prompt,
// and one of four timings (once / every day / every week / repeat).

import { appStore, type } from '../components/Theme'
import { t, timeLabel, weekdayShort } from '../common/ui/i18n'
import { FormSection, Segmented, BackRow } from '../components/FormControls'
import type { SegmentOption } from '../components/FormControls'
import { readStringParam } from './routes'

interface ScheduleTaskFull {
  id: string
  botId?: string
  sessionId: string
  title: string
  prompt?: string
  kind: string
  status?: string
  time?: string
  everySeconds?: number
  minutes?: number
  weekdays?: number[]
  expression?: string
  scheduledAt?: number
}

interface SchedulesReply {
  tasks?: ScheduleTaskFull[]
}

interface ScheduleWhen {
  kind: string
  at?: string
  minutes?: number
  time?: string
  timeZone?: string
  weekdays?: number[]
}

interface ScheduleCreatePayload {
  target: string
  title: string
  prompt: string
  when: ScheduleWhen
}

interface ScheduleDeletePayload {
  sessionId: string
  id: string
}

interface CodedError {
  code?: string
}

interface UnitOption {
  id: string
  factor: number
  label: string
}

const KIND_IDS: string[] = ['at', 'daily', 'weekly', 'every']
const KIND_LABELS: Record<string, string> = {
  'at': 'Once',
  'daily': 'Every day',
  'weekly': 'Every week',
  'every': 'Repeat',
}
const UNITS: UnitOption[] = [
  { id: 'minutes', factor: 1, label: 'minutes' },
  { id: 'hours', factor: 60, label: 'hours' },
  { id: 'days', factor: 1440, label: 'days' },
]

function kindOptions(): SegmentOption[] {
  const options: SegmentOption[] = []
  for (const id of KIND_IDS) {
    const label = KIND_LABELS[id]
    if (label !== undefined) options.push({ id: id, label: t(label) })
  }
  return options
}

function unitOptions(): SegmentOption[] {
  const options: SegmentOption[] = []
  for (const unit of UNITS) {
    options.push({ id: unit.id, label: t(unit.label) })
  }
  return options
}

function todayString(): string {
  const now = new Date()
  const month = `${now.getMonth() + 1}`.padStart(2, '0')
  const day = `${now.getDate()}`.padStart(2, '0')
  return `${now.getFullYear()}-${month}-${day}`
}

// schedules.js whenText: a human phrase per timing kind.
function whenText(task: ScheduleTaskFull): string {
  const time = task.time ?? ''
  switch (task.kind) {
    case 'at':
      return t('Once, {time}', { 'time': timeLabel(task.scheduledAt ?? 0) })
    case 'every': {
      const seconds = task.everySeconds ?? (task.minutes ?? 0) * 60
      if (seconds % 86400 === 0) {
        return seconds === 86400 ? t('Every day') : t('Every {count} days', { 'count': seconds / 86400 })
      }
      if (seconds % 3600 === 0) {
        return seconds === 3600 ? t('Every hour') : t('Every {count} hours', { 'count': seconds / 3600 })
      }
      return t('Every {count} minutes', { 'count': Math.round(seconds / 60) })
    }
    case 'daily':
      return t('Every day at {time}', { 'time': time })
    case 'weekly': {
      const days = task.weekdays ?? []
      const joined = days.join()
      if (joined === '1,2,3,4,5') return t('Every weekday at {time}', { 'time': time })
      if (joined === '6,7') return t('Every weekend at {time}', { 'time': time })
      if (joined === '1,2,3,4,5,6,7') return t('Every day at {time}', { 'time': time })
      const labels: string[] = []
      for (const day of days) {
        const short = weekdayShort(day)
        labels.push(/^[\u4e00-\u9fff]$/.test(short) ? `周${short}` : short)
      }
      const joinedLabels = labels.length > 0 && labels[0].startsWith('周') ? labels.join('、') : labels.join(', ')
      return t('Every {days} at {time}', { 'days': joinedLabels, 'time': time })
    }
    case 'cron':
      return t('On the schedule {expression}', { 'expression': task.expression ?? '' })
    default:
      return ''
  }
}

@ComponentV2
export struct Schedules {
  @Local pathStack: NavPathStack | null = null
  @Local botId: string = ''
  @Local sessionId: string = ''
  @Local refreshTick: number = 0
  @Local tasks: ScheduleTaskFull[] = []
  @Local writeError: string = ''
  @Local title: string = ''
  @Local prompt: string = ''
  @Local kind: string = 'daily'
  @Local time: string = '09:00'
  @Local atDate: string = todayString()
  @Local atTime: string = '09:00'
  @Local weekdays: number[] = [1, 2, 3, 4, 5]
  @Local count: string = '1'
  @Local unit: string = 'hours'
  @Local adding: boolean = false

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
      const view = (await controller.call('schedules')) as SchedulesReply | null
      const tasks: ScheduleTaskFull[] = []
      for (const task of view?.tasks ?? []) {
        if (task.botId === undefined || task.botId === this.botId) tasks.push(task)
      }
      this.tasks = tasks
    } catch {
      // The list stays as it was.
    }
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

  private remove(task: ScheduleTaskFull): void {
    const payload: ScheduleDeletePayload = { sessionId: task.sessionId !== '' ? task.sessionId : this.sessionId, id: task.id }
    void this.run('schedule-delete', payload, (): void => {
      void this.load()
    })
  }

  // The timing half of the payload for the picked kind.
  private when(): ScheduleWhen | null {
    if (this.kind === 'at') {
      const at = new Date(`${this.atDate}T${this.atTime}`)
      if (Number.isNaN(at.getTime())) return null
      const when: ScheduleWhen = { kind: 'at', at: at.toISOString() }
      return when
    }
    if (this.kind === 'every') {
      let factor = 60
      for (const unit of UNITS) {
        if (unit.id === this.unit) factor = unit.factor
      }
      const minutes = Math.round(Number(this.count) * factor)
      if (minutes <= 0 || Number.isNaN(minutes)) return null
      const when: ScheduleWhen = { kind: 'every', minutes: minutes }
      return when
    }
    const when: ScheduleWhen = {
      kind: this.kind,
      time: this.time,
      timeZone: this.timeZone(),
    }
    if (this.kind === 'weekly') when.weekdays = this.weekdays
    return when
  }

  private timeZone(): string {
    try {
      return Intl.DateTimeFormat().resolvedOptions().timeZone
    } catch {
      return 'UTC'
    }
  }

  private createDisabled(): boolean {
    return this.title.trim() === '' || this.prompt.trim() === '' || this.adding
  }

  private createTask(): void {
    const timing = this.when()
    if (this.title.trim() === '' || this.prompt.trim() === '' || timing === null || this.adding) return
    this.adding = true
    const payload: ScheduleCreatePayload = {
      target: this.botId,
      title: this.title.trim(),
      prompt: this.prompt.trim(),
      when: timing,
    }
    void this.run('schedule-create', payload, (): void => {
      this.title = ''
      this.prompt = ''
      this.adding = false
      void this.load()
    })
    this.adding = false
  }

  private hasDay(day: number): boolean {
    for (const d of this.weekdays) {
      if (d === day) return true
    }
    return false
  }

  private toggleDay(day: number): void {
    const days: number[] = []
    for (const d of this.weekdays) {
      if (d !== day) days.push(d)
    }
    if (!this.hasDay(day)) days.push(day)
    days.sort((a: number, b: number): number => a - b)
    this.weekdays = days
  }

  private ctaOpacity(): number {
    if (this.title.trim() === '' || this.prompt.trim() === '') return 0.5
    return 1
  }

  build() {
    NavDestination() {
      Column() {
        BackRow({
          label: t('Schedules'),
          onBack: (): void => this.goBack(),
        })
        Scroll() {
          Column() {
            FormSection({ label: t('Schedules') }) {
              ForEach(this.tasks, (task: ScheduleTaskFull, index: number) => {
                if (index > 0) {
                  Divider()
                    .strokeWidth(this.hairline())
                    .color(appStore.theme.p.line)
                }
                this.taskRow(task)
              }, (task: ScheduleTaskFull) => task.id)
              if (this.tasks.length === 0) {
                Text(t('Nothing saved yet'))
                  .fontSize(type.settingsRow.fontSize)
                  .lineHeight(type.settingsRow.lineHeight)
                  .fontColor(appStore.theme.p.ink2)
                  .width('100%')
                  .padding({ left: 16, right: 16, top: 10, bottom: 10 })
              }
            }
            FormSection({ label: t('New task') }) {
              Row() {
                TextInput({ text: this.title, placeholder: t('Morning briefing') })
                  .fontSize(type.settingsRow.fontSize)
                  .fontColor(appStore.theme.p.ink)
                  .placeholderColor(appStore.theme.p.ink3)
                  .backgroundColor(Color.Transparent)
                  .padding(0)
                  .layoutWeight(1)
                  .onChange((value: string): void => {
                    this.title = value
                  })
              }
              .constraintSize({ minHeight: 50 })
              .width('100%')
              .padding({ left: 16, right: 16, top: 10, bottom: 10 })
              .alignItems(VerticalAlign.Center)
              Divider()
                .strokeWidth(this.hairline())
                .color(appStore.theme.p.line)
              Row() {
                TextArea({ text: this.prompt, placeholder: t('Sum up what changed since yesterday and what needs me today.') })
                  .fontSize(type.settingsRow.fontSize)
                  .fontColor(appStore.theme.p.ink)
                  .placeholderColor(appStore.theme.p.ink3)
                  .backgroundColor(Color.Transparent)
                  .constraintSize({ minHeight: 70 })
                  .layoutWeight(1)
                  .onChange((value: string): void => {
                    this.prompt = value
                  })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 10, bottom: 10 })
              .alignItems(VerticalAlign.Center)
              Divider()
                .strokeWidth(this.hairline())
                .color(appStore.theme.p.line)
              Column({ space: 6 }) {
                Text(t('When'))
                  .fontSize(type.small.fontSize)
                  .lineHeight(type.small.lineHeight)
                  .fontColor(appStore.theme.p.ink3)
                Segmented({
                  value: this.kind,
                  onPick: (id: string): void => {
                    this.kind = id
                  },
                  options: kindOptions(),
                })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 10, bottom: 10 })
              .alignItems(HorizontalAlign.Start)
              if (this.kind === 'at') {
                Row({ space: 10 }) {
                  TextInput({ text: this.atDate, placeholder: 'YYYY-MM-DD' })
                    .fontSize(type.settingsRow.fontSize)
                    .fontColor(appStore.theme.p.ink)
                    .placeholderColor(appStore.theme.p.ink3)
                    .backgroundColor(Color.Transparent)
                    .padding(0)
                    .layoutWeight(1)
                    .onChange((value: string): void => {
                      this.atDate = value
                    })
                  TextInput({ text: this.atTime, placeholder: '09:00' })
                    .fontSize(type.settingsRow.fontSize)
                    .fontColor(appStore.theme.p.ink)
                    .placeholderColor(appStore.theme.p.ink3)
                    .backgroundColor(Color.Transparent)
                    .padding(0)
                    .width(70)
                    .onChange((value: string): void => {
                      this.atTime = value
                    })
                }
                .constraintSize({ minHeight: 50 })
                .width('100%')
                .padding({ left: 16, right: 16, top: 10, bottom: 10 })
                .alignItems(VerticalAlign.Center)
              }
              if (this.kind === 'weekly') {
                Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
                  ForEach([1, 2, 3, 4, 5, 6, 7], (day: number) => {
                    Column() {
                      Text(weekdayShort(day))
                        .fontSize(type.caption.fontSize)
                        .lineHeight(type.caption.lineHeight)
                        .fontColor(this.hasDay(day) ? appStore.theme.p.accentInk : appStore.theme.p.ink2)
                    }
                    .constraintSize({ minWidth: 36 })
                    .height(36)
                    .padding({ left: 8, right: 8 })
                    .borderRadius(18)
                    .border({ width: 1, color: this.hasDay(day) ? appStore.theme.p.accent : appStore.theme.p.line })
                    .backgroundColor(this.hasDay(day) ? appStore.theme.p.accent : Color.Transparent)
                    .justifyContent(FlexAlign.Center)
                    .alignItems(HorizontalAlign.Center)
                    .margin({ right: 6, bottom: 6 })
                    .onClick(() => this.toggleDay(day))
                  }, (day: number) => `${day}`)
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 10, bottom: 10 })
              }
              if (this.kind === 'daily' || this.kind === 'weekly') {
                Row({ space: 10 }) {
                  Text(t('Time'))
                    .fontSize(type.settingsRow.fontSize)
                    .lineHeight(type.settingsRow.lineHeight)
                    .fontColor(appStore.theme.p.ink3)
                    .layoutWeight(1)
                  TextInput({ text: this.time, placeholder: '09:00' })
                    .fontSize(type.settingsRow.fontSize)
                    .fontColor(appStore.theme.p.ink)
                    .placeholderColor(appStore.theme.p.ink3)
                    .backgroundColor(Color.Transparent)
                    .padding(0)
                    .constraintSize({ minWidth: 70 })
                    .textAlign(TextAlign.End)
                    .onChange((value: string): void => {
                      this.time = value
                    })
                }
                .constraintSize({ minHeight: 50 })
                .width('100%')
                .padding({ left: 16, right: 16, top: 10, bottom: 10 })
                .alignItems(VerticalAlign.Center)
              }
              if (this.kind === 'every') {
                Column({ space: 8 }) {
                  Row({ space: 10 }) {
                    Text(t('Every'))
                      .fontSize(type.settingsRow.fontSize)
                      .lineHeight(type.settingsRow.lineHeight)
                      .fontColor(appStore.theme.p.ink3)
                    Blank()
                    TextInput({ text: this.count, placeholder: '1' })
                      .fontSize(type.settingsRow.fontSize)
                      .fontColor(appStore.theme.p.ink)
                      .placeholderColor(appStore.theme.p.ink3)
                      .backgroundColor(Color.Transparent)
                      .border({ width: 1, color: appStore.theme.p.line })
                      .borderRadius(8)
                      .constraintSize({ minWidth: 72 })
                      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                      .textAlign(TextAlign.Center)
                      .inputFilter('[0-9]')
                      .onChange((value: string): void => {
                        this.count = value
                      })
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Center)
                  Segmented({
                    value: this.unit,
                    onPick: (id: string): void => {
                      this.unit = id
                    },
                    options: unitOptions(),
                  })
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 10, bottom: 10 })
                .alignItems(HorizontalAlign.Start)
              }
            }
            Column({ space: 6 }) {
              if (this.writeError !== '') {
                Text(this.writeError)
                  .fontSize(type.caption.fontSize)
                  .lineHeight(type.caption.lineHeight)
                  .fontColor(appStore.theme.p.danger)
                  .width('100%')
              }
              Column() {
                Text(t('Create task'))
                  .fontSize(type.settingsRow.fontSize)
                  .lineHeight(type.settingsRow.lineHeight)
                  .fontWeight('600')
                  .fontColor(appStore.theme.p.accentInk)
              }
              .constraintSize({ minHeight: 48 })
              .width('100%')
              .borderRadius(24)
              .backgroundColor(appStore.theme.p.accent)
              .opacity(this.ctaOpacity())
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              .onClick(() => {
                void this.createTask()
              })
            }
            .width('100%')
            .padding({ left: 18, right: 18, top: 14 })
            .alignItems(HorizontalAlign.Start)
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
      this.sessionId = readStringParam(ctx.pathInfo.param, 'sessionId')
    })
    .onShown(() => {
      void this.load()
    })
  }

  @Builder
  taskRow(task: ScheduleTaskFull) {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text(task.title)
          .fontSize(type.settingsRow.fontSize)
          .lineHeight(type.settingsRow.lineHeight)
          .fontColor(appStore.theme.p.ink)
        Text(whenText(task))
          .fontSize(type.small.fontSize)
          .lineHeight(type.small.lineHeight)
          .fontColor(appStore.theme.p.ink3)
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Column() {
        Text('×')
          .fontSize(17)
          .fontColor(appStore.theme.p.ink3)
      }
      .constraintSize({ minWidth: 44, minHeight: 44 })
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .accessibilityText(t('Delete task'))
      .onClick(() => this.remove(task))
    }
    .constraintSize({ minHeight: 50 })
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .alignItems(VerticalAlign.Center)
  }
}

@Builder
export function SchedulesBuilder() {
  Schedules()
}
