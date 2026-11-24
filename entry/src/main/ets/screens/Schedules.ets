// The schedule screen (mobile/src/screens/manage.tsx Schedules): the Bot's
// tasks with a human-readable "when", and the new-task form — title, prompt,
// and one of four timings (once / every day / every week / repeat).

import { appStore, type } from '../components/Theme'
import { t, timeLabel, weekdayShort } from '../common/ui/i18n'
import { FormSection, Segmented, BackRow } from '../components/FormControls'
import type { SegmentOption } from '../components/FormControls'
import { readStringParam } from './routes'
import { BotMark, RoomAvatar } from '../components/Marks'
import { Icon } from '../components/Icon'
import type { Bot, Room } from '../common/team/types'

interface ScheduleTaskFull {
  id: string
  botId?: string
  roomId?: string
  sessionId: string
  title: string
  prompt?: string
  kind: string
  status?: string
  state?: string
  time?: string
  everySeconds?: number
  minutes?: number
  weekdays?: number[]
  expression?: string
  scheduledAt?: string | number
}

interface SchedulesReply {
  tasks?: ScheduleTaskFull[]
  canPause?: boolean
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

interface SchedulePausePayload {
  sessionId: string
  id: string
  active: boolean
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

// The task's scheduled time in ms: the demo link feeds numbers, real hosts
// ISO strings — both normalize (NaN means missing or unparseable, callers
// judge with Number.isFinite).
function scheduledMs(task: ScheduleTaskFull): number {
  const at = task.scheduledAt
  if (typeof at === 'number') return at
  if (typeof at === 'string') return Date.parse(at)
  return Number.NaN
}

// schedules.js whenText: a human phrase per timing kind.
function whenText(task: ScheduleTaskFull): string {
  const time = task.time ?? ''
  switch (task.kind) {
    case 'at': {
      const when = scheduledMs(task)
      return t('Once, {time}', { 'time': timeLabel(Number.isFinite(when) ? when : 0) })
    }
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

// schedules.js state(): active→overdue/scheduled, paused→paused, else
// finished; only the off-nominal ones earn a label on the row.
function stateLabel(state: string | undefined): string {
  if (state === 'overdue') return t('Overdue')
  if (state === 'paused') return t('Paused')
  if (state === 'finished') return t('Finished')
  return ''
}

@ComponentV2
export struct Schedules {
  @Local pathStack: NavPathStack | null = null
  @Local botId: string = ''
  @Local sessionId: string = ''
  // The global page Settings leads to: every Bot's and group's tasks, with a
  // target picker on the new-task form.
  @Local all: boolean = false
  @Local targetId: string = ''
  @Local targetPickOpen: boolean = false
  @Local refreshTick: number = 0
  @Local tasks: ScheduleTaskFull[] = []
  @Local writeError: string = ''
  // Whether the host can pause and resume a schedule (schedules.canPause).
  @Local canPause: boolean = false
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
  // The task row whose delete is armed, and the timer that disarms it.
  @Local confirmingId: string = ''
  private confirmTimer: number = -1

  private hairline(): number {
    return this.getUIContext().px2vp(1)
  }

  private goBack(): void {
    if (this.pathStack !== null) this.pathStack.pop()
  }

  private bots(): Bot[] {
    void this.refreshTick
    return appStore.link.team?.bots ?? []
  }

  private rooms(): Room[] {
    void this.refreshTick
    return appStore.link.team?.rooms ?? []
  }

  private ownerName(task: ScheduleTaskFull): string {
    if (task.botId !== undefined && task.botId !== '') {
      for (const bot of this.bots()) {
        if (bot.id === task.botId) return bot.name
      }
    }
    if (task.roomId !== undefined && task.roomId !== '') {
      for (const room of this.rooms()) {
        if (room.id === task.roomId) return room.name
      }
    }
    return ''
  }

  private targetName(): string {
    if (this.targetId === '') return ''
    for (const bot of this.bots()) {
      if (bot.id === this.targetId) return bot.name
    }
    for (const room of this.rooms()) {
      if (room.id === this.targetId) return room.name
    }
    return ''
  }

  private async load(): Promise<void> {
    const controller = appStore.link.controller
    if (controller === null) return
    try {
      const view = (await controller.call('schedules')) as SchedulesReply | null
      this.canPause = view?.canPause === true
      const tasks: ScheduleTaskFull[] = []
      for (const task of view?.tasks ?? []) {
        if (this.all) {
          tasks.push(task)
        } else if (task.botId === undefined || task.botId === this.botId) {
          tasks.push(task)
        }
      }
      this.tasks = tasks
    } catch {
      // The list stays as it was.
    }
  }

  // As on the desktop: a one-time task whose time has passed is neither paused
  // nor resumed.
  private pausable(task: ScheduleTaskFull): boolean {
    if (!this.canPause) return false
    if (task.status !== 'active' && task.status !== 'paused') return false
    if (task.kind === 'at' || task.kind === 'after') {
      const when = scheduledMs(task)
      if (Number.isFinite(when) && when <= Date.now()) {
        return false
      }
    }
    return true
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

  // The delete's two-tap confirm: the first tap arms the row for a few
  // seconds, the second takes the task out.
  private confirmDelete(task: ScheduleTaskFull): void {
    const key = `${task.sessionId}:${task.id}`
    if (this.confirmingId !== key) {
      this.confirmingId = key
      this.clearConfirmTimer()
      this.confirmTimer = setTimeout(() => {
        this.confirmingId = ''
        this.confirmTimer = -1
      }, 3000)
      return
    }
    this.clearConfirmTimer()
    this.confirmingId = ''
    this.remove(task)
  }

  private clearConfirmTimer(): void {
    if (this.confirmTimer >= 0) {
      clearTimeout(this.confirmTimer)
      this.confirmTimer = -1
    }
  }

  aboutToDisappear(): void {
    this.clearConfirmTimer()
  }

  private remove(task: ScheduleTaskFull): void {
    const payload: ScheduleDeletePayload = { sessionId: task.sessionId !== '' ? task.sessionId : this.sessionId, id: task.id }
    void this.run('schedule-delete', payload, (): void => {
      void this.load()
    })
  }

  private pause(task: ScheduleTaskFull): void {
    const payload: SchedulePausePayload = {
      sessionId: task.sessionId !== '' ? task.sessionId : this.sessionId,
      id: task.id,
      active: task.status !== 'active',
    }
    void this.run('schedule-pause', payload, (): void => {
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
    if (this.title.trim() === '' || this.prompt.trim() === '' || this.adding) return true
    if (this.all && this.targetId === '') return true
    return false
  }

  // A timing the host would refuse gets its own words instead of silence.
  private async createTask(): Promise<void> {
    const timing = this.when()
    if (this.adding) return
    if (this.title.trim() === '' || this.prompt.trim() === '') return
    if (this.all && this.targetId === '') return
    if (timing === null) {
      this.writeError = t('Pick a date and time')
      return
    }
    this.adding = true
    let created = false
    const payload: ScheduleCreatePayload = {
      target: this.all ? this.targetId : this.botId,
      title: this.title.trim(),
      prompt: this.prompt.trim(),
      when: timing,
    }
    // The await keeps a second tap from sending the task twice; the form
    // stays filled when the host refuses it.
    await this.run('schedule-create', payload, (): void => {
      created = true
    })
    if (created) {
      this.title = ''
      this.prompt = ''
      void this.load()
    }
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
              if (this.all) {
                Row() {
                  Text(t('For'))
                    .fontSize(type.settingsRow.fontSize)
                    .lineHeight(type.settingsRow.lineHeight)
                    .fontColor(appStore.theme.p.ink3)
                  Blank()
                  Text(this.targetId === '' ? t('Pick a Bot or group') : this.targetName())
                    .fontSize(type.settingsRow.fontSize)
                    .lineHeight(type.settingsRow.lineHeight)
                    .fontWeight('600')
                    .fontColor(this.targetId === '' ? appStore.theme.p.ink3 : appStore.theme.p.accentInk)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .constraintSize({ minHeight: 50 })
                .width('100%')
                .padding({ left: 16, right: 16, top: 10, bottom: 10 })
                .alignItems(VerticalAlign.Center)
                .onClick(() => {
                  this.targetPickOpen = true
                })
                Divider()
                  .strokeWidth(this.hairline())
                  .color(appStore.theme.p.line)
              }
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
      .bindSheet($$this.targetPickOpen, this.targetPicker(), {
        height: SheetSize.FIT_CONTENT,
        dragBar: true,
        showClose: false,
        backgroundColor: appStore.theme.p.card,
        onDisappear: (): void => {
          this.targetPickOpen = false
        },
      })
    }
    .hideTitleBar(true)
    .padding({ top: appStore.safeTop })
    .backgroundColor(appStore.theme.p.main)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack
      this.botId = readStringParam(ctx.pathInfo.param, 'botId')
      this.sessionId = readStringParam(ctx.pathInfo.param, 'sessionId')
      this.all = readStringParam(ctx.pathInfo.param, 'all') === '1'
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
        if (this.all && this.ownerName(task) !== '') {
          Text(this.ownerName(task))
            .fontSize(type.small.fontSize)
            .lineHeight(type.small.lineHeight)
            .fontColor(appStore.theme.p.ink2)
        }
        Text(task.status === 'paused' ? `${whenText(task)} · ${t('Paused')}` : whenText(task))
          .fontSize(type.small.fontSize)
          .lineHeight(type.small.lineHeight)
          .fontColor(appStore.theme.p.ink3)
          .margin({ top: 2 })
        if (this.all && stateLabel(task.state) !== '') {
          Text(stateLabel(task.state))
            .fontSize(type.caption.fontSize)
            .lineHeight(type.caption.lineHeight)
            .fontColor(task.state === 'overdue' ? appStore.theme.p.danger : appStore.theme.p.ink3)
            .margin({ top: 2 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      if (this.pausable(task)) {
        Column() {
          Text(task.status === 'active' ? '‖' : '▶')
            .fontSize(15)
            .fontColor(appStore.theme.p.ink3)
        }
        .constraintSize({ minWidth: 36, minHeight: 44 })
        .margin({ right: 4 })
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
        .accessibilityText(task.status === 'active' ? t('Pause task') : t('Resume task'))
        .onClick(() => this.pause(task))
      }
      if (this.confirmingId === `${task.sessionId}:${task.id}`) {
        Column() {
          Text(t('Click again to delete'))
            .fontSize(type.caption.fontSize)
            .lineHeight(type.caption.lineHeight)
            .fontWeight('500')
            .fontColor(appStore.theme.p.danger)
            .maxLines(2)
            .textAlign(TextAlign.End)
        }
        .constraintSize({ maxWidth: 120 })
        .padding({ left: 4 })
        .alignItems(HorizontalAlign.End)
        .justifyContent(FlexAlign.Center)
        .onClick(() => this.confirmDelete(task))
      } else {
        Column() {
          Text('×')
            .fontSize(17)
            .fontColor(appStore.theme.p.ink3)
        }
        .constraintSize({ minWidth: 44, minHeight: 44 })
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
        .accessibilityText(t('Delete task'))
        .onClick(() => this.confirmDelete(task))
      }
    }
    .constraintSize({ minHeight: 50 })
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  targetPicker() {
    Column() {
      Scroll() {
        Column() {
          ForEach(this.bots(), (bot: Bot) => {
            Row({ space: 10 }) {
              BotMark({ bot: bot, markSize: 28 })
              Text(bot.name)
                .fontSize(type.settingsRow.fontSize)
                .lineHeight(type.settingsRow.lineHeight)
                .fontColor(appStore.theme.p.ink)
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (this.targetId === bot.id) {
                Icon({ name: 'check', iconSize: 15, color: appStore.theme.p.accent })
              }
            }
            .constraintSize({ minHeight: 50 })
            .padding({ left: 16, right: 16 })
            .alignItems(VerticalAlign.Center)
            .width('100%')
            .onClick(() => {
              this.targetId = bot.id
              this.targetPickOpen = false
            })
          }, (bot: Bot) => bot.id)
          ForEach(this.rooms(), (room: Room) => {
            Row({ space: 10 }) {
              RoomAvatar({ room: room, markSize: 28 })
              Column({ space: 2 }) {
                Text(room.name)
                  .fontSize(type.settingsRow.fontSize)
                  .lineHeight(type.settingsRow.lineHeight)
                  .fontColor(appStore.theme.p.ink)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(t('Group'))
                  .fontSize(type.caption.fontSize)
                  .lineHeight(type.caption.lineHeight)
                  .fontColor(appStore.theme.p.ink3)
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              if (this.targetId === room.id) {
                Icon({ name: 'check', iconSize: 15, color: appStore.theme.p.accent })
              }
            }
            .constraintSize({ minHeight: 50 })
            .padding({ left: 16, right: 16 })
            .alignItems(VerticalAlign.Center)
            .width('100%')
            .onClick(() => {
              this.targetId = room.id
              this.targetPickOpen = false
            })
          }, (room: Room) => room.id)
          if (this.bots().length === 0 && this.rooms().length === 0) {
            Text(t('Nothing saved yet'))
              .fontSize(type.settingsRow.fontSize)
              .lineHeight(type.settingsRow.lineHeight)
              .fontColor(appStore.theme.p.ink2)
              .width('100%')
              .padding({ left: 16, right: 16, top: 16, bottom: 16 })
          }
        }
        .constraintSize({ minHeight: 300 })
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .scrollBar(BarState.Off)
    }
    .width('100%')
  }
}

@Builder
export function SchedulesBuilder() {
  Schedules()
}
