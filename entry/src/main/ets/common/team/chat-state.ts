// Chat reads and the outbox: page cache keys, row keys, and the pending-send
// queue that survives chat switches. Ports of Chat.tsx module state and
// chat/settled.ts helpers.
import type { ChatItem, RelayReplyData, SettledQuestionData, ShownView } from './types.ts'
import { t, messageClock } from '../ui/i18n.ts'
import { isRecord, viewAnswerText, type ViewNode } from '../deepview/views-core.ts'

// Row keys that stay the same when older pages load above or new rows arrive
// below, so the list moves rows instead of rebuilding them.
export function keysOf(items: ChatItem[]): string[] {
  const seen = new Map<string, number>()
  return items.map(item => {
    const base = item.localId !== undefined
      ? `local-${item.localId}`
      : `${item.kind}-${item.seq ?? item.time ?? (item.kind === 'steps' ? `t${item.turn ?? ''}` : '')}`
    const count = seen.get(base) ?? 0
    seen.set(base, count + 1)
    return count === 0 ? base : `${base}#${count}`
  })
}

// A refreshed page reuses the item objects that did not change, so only new or
// changed rows render again.
export function keepSame(prev: ChatItem[], next: ChatItem[]): ChatItem[] {
  const prevKeys = keysOf(prev)
  const known = new Map<string, ChatItem>()
  prev.forEach((item, index) => known.set(prevKeys[index] ?? '', item))
  const nextKeys = keysOf(next)
  let same = prev.length === next.length
  const merged = next.map((item, index) => {
    const old = known.get(nextKeys[index] ?? '')
    if (old !== undefined && JSON.stringify(old) === JSON.stringify(item)) {
      if (prev[index] !== old) same = false
      return old
    }
    same = false
    return item
  })
  return same ? prev : merged
}

// The same message as the phone sent: the text the computer keeps (trimmed) and
// as many photos.
export function sameMessage(item: ChatItem, sent: ChatItem): boolean {
  return item.kind === 'user'
    && (item.text ?? '').trim() === (sent.text ?? '').trim()
    && (item.imageRefs?.length ?? item.images ?? 0) === (sent.localImages?.length ?? 0)
}

// As on the desktop, a run of one Bot's bubbles ends with the time of its last
// one, and each user message carries its own.
export function stampOf(items: ChatItem[], index: number): string | undefined {
  const item = items[index]
  if (item === undefined || typeof item.time !== 'number') return undefined
  if (item.kind === 'user') return messageClockOf(item.time)
  if (item.kind !== 'bot' && item.kind !== 'post') return undefined
  const next = items[index + 1]
  if (next !== undefined && (next.kind === 'bot' || next.kind === 'post') && (next.name ?? '') === (item.name ?? '')) return undefined
  return messageClockOf(item.time)
}

function messageClockOf(time: number): string {
  return messageClock(time)
}

// ---- via label ------------------------------------------------------------

// The IM a message arrived through, by the ids the computer sends (the plugin's
// IM_PLATFORMS); the label keeps each product's official spelling, an unknown
// id shows as is.
const IM_PLATFORM_NAMES: Record<string, string> = {
  'telegram': 'Telegram',
  'weixin': 'WeChat',
  'feishu': 'Feishu / Lark',
  'dingtalk': 'DingTalk',
  'wecom': 'WeCom',
  'qq': 'QQ',
  'discord': 'Discord',
  'slack': 'Slack',
}

export function imPlatformName(id: string): string {
  return IM_PLATFORM_NAMES[id] ?? id
}

// ---- settled.ts ----------------------------------------------------------

export function stripLongNote(text: string): string {
  return text.replace(/^\[A long message: \d+ characters\.[^\]\n]*\]\r?\n/, '')
}

// Host previews come from historyEntry/replyText, which frame card replies as
// "[Browser handoff] …" or "[Answer to question card] …" for compaction context.
export function cleanPreview(raw?: string): string | undefined {
  if (raw === undefined || raw.trim() === '') return undefined
  const text = stripLongNote(raw).trim()
  const handoff = /^\[Browser handoff\]\s*([^\s—]+)(?:\s*—\s*(.+?))?\s+Answer:\s*\S+$/s.exec(text)
  if (handoff !== null) {
    const title = handoffTitleOf(handoff[1])
    return handoff[2] ? `${title} · ${handoff[2].trim()}` : title
  }
  const qAnswer = /^\[Answer to question card\]\s*(.+?)\s+Answer:\s*(.+)$/s.exec(text)
  if (qAnswer !== null) return qAnswer[2].trim() === '(skipped)' ? qAnswer[1].trim() : qAnswer[2].trim()
  const qCard = /^\[Question card\]\s*(.+?)(?:\s+Options:\s*.+)?$/s.exec(text)
  if (qCard !== null) return qCard[1].trim()
  return text
}

export function settledQuestionPicks(
  question: SettledQuestionData | undefined,
  answer: { selected?: string[]; custom?: string } | undefined,
): { label: string; letter: string }[] {
  const options = (question?.options ?? []).map(opt => (typeof opt === 'string' ? opt : opt.label))
  const selected = Array.isArray(answer?.selected) ? answer.selected : []
  const custom = typeof answer?.custom === 'string' ? answer.custom.trim() : ''
  return [
    ...selected.map((label, j) => {
      const idx = options.indexOf(label)
      return { label, letter: String.fromCharCode(65 + (idx >= 0 ? idx : j)) }
    }),
    ...(custom !== '' ? [{ label: custom, letter: String.fromCharCode(65 + options.length) }] : []),
  ]
}

export function handoffTitleOf(reason?: string): string {
  switch (reason) {
    case 'sign-in': return t('Sign-in needed')
    case 'verification': return t('Verification needed')
    case 'confirmation': return t('Confirmation needed')
    default: return t('Your turn in the browser')
  }
}

export function roundEventText(name: string, event: string | undefined, text?: string, code?: string): string | undefined {
  if (event === undefined) return undefined
  switch (event) {
    case 'failed': return t('{name} could not answer: {reason}', { name, reason: text ?? code ?? '' })
    case 'lookup': return text !== undefined && text !== '' ? t('{name} looked up its own chat for "{text}"', { name, text }) : t('{name} looked up its own chat', { name })
    case 'missed': return t("{name} didn't answer in time", { name })
    case 'admin-passed': return t('{name} did not answer or call anyone; call a member with @Name', { name })
    case 'resumed': return t('{name} was cut off by a restart and picked its work back up', { name })
    case 'cut': return t('{name} was cut off by a restart again and stopped', { name })
    case 'approval': return t('{name} paused for your approval', { name })
    case 'working': return t('{name} started on it', { name })
    case 'folder': return text ?? ''
    case 'stopped': return t("You stopped {name}'s work", { name })
    case 'done': return t('{name} finished its work', { name })
    case 'schedule': return text ?? ''
    default: return undefined
  }
}

export function relayReplyText(reply?: RelayReplyData): string | undefined {
  if (reply === undefined) return undefined
  const kind = reply.kind ?? reply.event
  const name = reply.name ?? t('a Bot')
  if (kind === 'paused') {
    const joiner = t(' and ')
    return reply.idle === true
      ? t('{names} went back and forth {count} times without progress and paused. Write here to go on', { count: reply.count ?? 0, names: [name, ...(reply.names ?? [])].join(joiner) })
      : t('Paused after {count} Bot relays. Waiting: {names}', { count: reply.count ?? 0, names: (reply.names ?? []).join(joiner) })
  }
  return roundEventText(name, kind, reply.text, reply.code)
}

// ---- Pending sends -------------------------------------------------------

export interface Outgoing {
  item: ChatItem
  photos: { uri: string; mediaType: string; data: string }[]
  sessionId: string
  known?: Set<string>
}

const outbox = new Map<string, Outgoing[]>()
const outboxListeners = new Set<() => void>()

export function outboxOf(key: string): Outgoing[] {
  return outbox.get(key) ?? []
}

export function setOutbox(key: string, update: (list: Outgoing[]) => Outgoing[]): void {
  const next = update(outboxOf(key))
  if (next.length === 0) outbox.delete(key)
  else outbox.set(key, next)
  for (const listener of [...outboxListeners]) listener()
}

export function subscribeOutbox(listener: () => void): () => void {
  outboxListeners.add(listener)
  return () => outboxListeners.delete(listener)
}

// Marks one pending send's state (and, after the send call, the row keys the
// chat already held, so only a new row of the same text counts as this one).
export function markOutgoing(key: string, localId: string, local: 'sending' | 'failed', known?: Set<string>): void {
  setOutbox(key, list => list.map(entry => entry.item.localId === localId
    ? { ...entry, item: { ...entry.item, local }, known: known ?? entry.known }
    : entry))
}

export function queueOutgoing(key: string, entry: Outgoing): void {
  setOutbox(key, list => [...list, entry])
}

export function dropOutgoing(key: string, localId: string): void {
  setOutbox(key, list => list.filter(entry => entry.item.localId !== localId))
}

export function findOutgoing(key: string, localId: string): Outgoing | undefined {
  return outboxOf(key).find(entry => entry.item.localId === localId)
}

// A sent message leaves the outbox once the chat shows a new row with its text
// (and as many photos) that the page it was sent against did not hold.
export function dropShownOutbox(key: string, items: ChatItem[]): void {
  const pending = outboxOf(key)
  if (pending.length === 0) return
  const keys = keysOf(items)
  const shown = pending.filter(entry => {
    const known = entry.known
    if (known === undefined) return false
    return items.some((item, index) => !known.has(keys[index] ?? '') && sameMessage(item, entry.item))
  })
  if (shown.length === 0) return
  const drop = new Set(shown)
  setOutbox(key, list => list.filter(entry => !drop.has(entry)))
}

// ---- items.tsx helpers ------------------------------------------------------

// items.tsx dataUri: one image call's {mime, data} answer as a data URI.
export function imageDataUri(value: unknown): string {
  const mime = (value as { mime?: string } | null | undefined)?.mime ?? 'image/png'
  const data = (value as { data?: string } | null | undefined)?.data ?? ''
  return `data:${mime};base64,${data}`
}

// The phone's 'image' call already mapped to a data URI, so .ets callers never
// touch an untyped promise answer.
export function imageUriOf(pending: Promise<unknown>): Promise<string> {
  return pending.then((value: unknown): string => imageDataUri(value))
}

// The 'file-text' call's answer, normalized: the raw string answer or its
// {text} field, so .ets callers never touch an untyped promise answer.
export function fileTextOf(pending: Promise<unknown>): Promise<string> {
  return pending.then((value: unknown): string => {
    if (typeof value === 'string') return value
    const read = value as { text?: string } | null | undefined
    return read?.text ?? ''
  })
}

// The 'stage-image' call's answer, normalized: a non-empty staged id, or the
// localized failure the composer shows when a photo never reached the host.
export function stageImageId(pending: Promise<unknown>): Promise<string> {
  return pending.then((value: unknown): string => {
    const id = (value as { id?: string } | null | undefined)?.id
    if (typeof id === 'string' && id !== '') return id
    throw new Error(t('A photo did not arrive. Send it again.'))
  })
}

// A chat 'view' item's blueprint as a renderable deep-view node; null when absent.
export function itemViewNode(item: ChatItem): ViewNode | null {
  return isRecord(item.view) ? item.view as ViewNode : null
}

// A shown view's (team.views entry) blueprint as a renderable deep-view node.
export function shownViewNode(view: ShownView | undefined): ViewNode | null {
  if (view === undefined) return null
  return isRecord(view.view) ? view.view as ViewNode : null
}

export interface ViewReplyDetail {
  title: string
  detail: string
}

// items.tsx viewReplies: each answered view with its answer folded to one line.
export function viewRepliesOf(item: ChatItem): ViewReplyDetail[] {
  const answers = item.answers ?? []
  const out: ViewReplyDetail[] = []
  const views = item.views ?? []
  for (let i = 0; i < views.length; i++) {
    const entry = views[i]!
    const answer = answers.find(a => a.id === entry.id) ?? answers[i]
    const detail = answer !== undefined && entry.view !== undefined ? viewAnswerText(entry.view, answer) : ''
    out.push({ title: entry.title, detail })
  }
  return out
}

export interface SettledPick {
  label: string
  letter: string
}

export interface SettledLine {
  question: string
  picks: SettledPick[]
}

// items.tsx settled question lines: each question with its matched answer's picks.
export function settledLinesOf(item: ChatItem): SettledLine[] {
  const answers = item.answers ?? []
  const out: SettledLine[] = []
  const questions = item.questions ?? []
  for (let i = 0; i < questions.length; i++) {
    const question = questions[i]!
    const answer = answers.find(a => question.id !== undefined && a.id === question.id) ?? answers[i]
    out.push({ question: question.question, picks: settledQuestionPicks(question, answer) })
  }
  return out
}
