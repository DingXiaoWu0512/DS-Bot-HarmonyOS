// Demo mode: no computer, no link. The fixture answers with exactly the shapes
// the real host returns (channel.js state view + live(), parts.js chat pages).
// Compiled in through common/config.ts DEMO; the UI opens a DemoLink instead of
// a TeamLink when the flag is on.
import { demoData } from './demo-team.ts'
import { ensureUnlock } from '../team/team-link.ts'
import { validateViewAnswer } from '../deepview/views-core.ts'
import type { TeamState } from '../team/types.ts'
import type { ChatItem } from '../team/types.ts'

const DEMO_IMG_1 = 'iVBORw0KGgoAAAANSUhEUgAAAPAAAADwCAYAAAA+VemSAAAACXBIWXMAAAsTAAALEwEAmpwYAAAOnUlEQVR4nO2d6XPVRRaG+QdbQQTK+TAuzCeEsJlyA1xAwaiMo0jYIlJMKVsAmapRWcYpnREFoyOguBFZAgncEPwLzpk696o1MkIW7s053f18eKsoCEnu2+9zTv+W7p6RHhZFeEAGJEsPZnj/AggPyIAAMCGgEKQKPaADBxgEhAcJgAkBhUCq84AOHGAQEB4kACYEFAKpzgM6cIBBQHiQAJgQUAikOg/owAEGAeFBAmBCQCGQ6jygAwcYBIQHCYAJgQUAikOg8oAMHGASEBwmACQGFQKrzgA4cYBAQHiQAJgQUAikOg/owAEGAeFBAmBCQCGQ6jygAwcYBIQHCYAJgQUAikOg8oAMHGASEBwmACQGFQKrzgA4cYBAQHiQAJgQUAikOg/owAEGAeFBAmBCQCGQ6jygAwcYBIQHCYAJgQUAikOg8oAMHGASEBwmACQGFQKrzgA4cYBAQHiQAJgQUAikOg/owAEGAeFBAmBCQCGQ6jygAwcYBIQHCYAJgQUAqnOAzpwgEFAeJAAmBBQCqc4DOnCAQUB4kACYEFAIpDoP6MABBgHhQQJgQkAhkOo8oAMHGASEBwmACQGFQKrzgA4cYBAQHiQAJgQUAikOg/owAEGAeFBAmBCQCGQ6jygAwcYBIQHCYAJgQUAqnOAzpwgEFAeJAAmBBQCqc4DOnCAQUB4kACYEFAIpDoP6MABBgHhQQJgQkAhkOo8oAMHGASEBwmACQGFQKrzgA4cYBAQHiQAJgQUAqnOAzpwgEFAeJAAmBBQCqc4DOnCAQUB4kACYEFAIpDoP6MABBgHhQQJgQkAhkOo8oAMHGASEBwmACQGFQKrzgA4cYBAQHiQAJgQUAqnOAzpwgEFAeJAAmBBQCqc4DOnCAQUB4kACYEFAIpDoP6MABBgHhQQJgQkAhkOo8oAMHGASEBwmACQGFQKrzgA4cYBAQHiQAJgQUAqnOAzpwgEFAeJAAmBBQCqc4DOnCAQUB4kIB+A6FnVvHt2H8QAAAAAElFTkSuQmCC'
const DEMO_IMG_2 = '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'

export interface DemoChatPage { sessionId: string; items: ChatItem[]; cursor: { part: number; beforeSeq?: number } | null }

// The side-chat shape inside TeamState.sideChats, named so the demo answers
// can stay strictly typed instead of reaching through Object.values.
export interface DemoSideEntry {
  id: string
  question?: string
  answer?: string
  status?: string
  failure?: string
}

export interface DemoSideChat {
  chatId: string
  entries?: DemoSideEntry[]
}

function sideChatsFlat(sideChats: Record<string, DemoSideChat[]> | undefined): DemoSideChat[] {
  const out: DemoSideChat[] = []
  if (sideChats === undefined) return out
  for (const key of Object.keys(sideChats)) {
    const chats = sideChats[key]
    if (chats !== undefined) out.push(...chats)
  }
  return out
}

export class DemoLink {
  readonly team: TeamState
  readonly chats: Record<string, DemoChatPage[]>
  online = true
  error: string | null = null
  private listeners = new Set<() => void>()

  constructor() {
    const data = demoData()
    this.team = data.state
    this.chats = data.chats
  }

  onChange(listener: () => void): () => void {
    this.listeners.add(listener)
    return () => this.listeners.delete(listener)
  }

  private notify(): void {
    for (const listener of [...this.listeners]) listener()
  }

  private lastSeq(page: { items: ChatItem[] }): number {
    const items = page.items
    return items.length > 0 ? (items[items.length - 1]?.seq ?? 0) : 0
  }

  private touch(): void {
    this.team.revision += 1
    this.notify()
  }

  // Arrow property like TeamLink.call: bare `controller.call` references must
  // keep `this`.
  call = async (endpoint: string, payload: unknown = {}): Promise<unknown> => {
    const body = (payload ?? {}) as Record<string, unknown>
    await ensureUnlock(endpoint)
    const state = this.team
    const bots = state.bots ?? []
    const sessionOf = (id: string): string => bots.find(bot => bot.id === id)?.sessionId ?? id
    const chatOf = (id: string): DemoChatPage[] | undefined => this.chats[id] ?? this.chats[bots.find(bot => bot.sessionId === id)?.id ?? '']

    switch (endpoint) {
      case 'hello':
        return { api: 1, min: 1, capabilities: ['state', 'state-avatar-refs', 'avatar', 'chat', 'room-chat', 'send', 'feed', 'feed-room', 'notices', 'questions', 'views', 'approvals', 'stop-member-work', 'memory', 'memory-edit', 'usage-summary', 'stop-chat', 'row-meta', 'chat-steps', 'link-feed', 'images', 'write-state'], boot: 'demo', seq: 0 }
      case 'notices':
        return { boot: 'demo', seq: 0, notices: [], reset: false }
      case 'room-chat': {
        const pages = this.chats[String(body.roomId ?? '')] ?? []
        const page = pages[0] ?? { items: [], cursor: null }
        return { roomId: String(body.roomId ?? ''), items: page.items, cursor: page.cursor, running: false, speaking: null }
      }
      case 'stop-chat': {
        const id = sessionOf(String(body.botId ?? ''))
        if (state.work?.bots?.[id] !== undefined) delete state.work.bots[id]
        this.touch()
        return true
      }
      case 'view-reply': {
        const sid = String(body.sessionId ?? '')
        const pending = state.views?.[sid]
        // Same check as the computer, so a wrong answer shape fails here too.
        const checked = pending === undefined ? { error: 'This view is no longer open' } : validateViewAnswer(pending.view, body.action, body.values)
        if (checked.error !== undefined) throw Object.assign(new Error(checked.error), { code: 'bot/invalid' })
        delete state.views![sid]; this.touch()
        return { ok: true }
      }
      case 'dismiss-view': {
        const sid = String(body.sessionId ?? '')
        if (state.views?.[sid] !== undefined) { delete state.views[sid]; this.touch() }
        return { ok: true }
      }
      case 'image': {
        const id = String(body.attachmentId ?? '')
        const data = id === 'demo-img-1' ? DEMO_IMG_1 : id === 'demo-img-2' ? DEMO_IMG_2 : undefined
        if (data === undefined) throw Object.assign(new Error('Unknown attachment'), { code: 'bot/not-found' })
        return { mime: 'image/png', data }
      }
      case 'state':
        if (body.since === state.revision) return { revision: state.revision, unchanged: true, work: state.work, activity: state.activity }
        return state
      case 'chat': {
        const pages = chatOf(String(body.botId ?? ''))
        if (pages === undefined || pages.length === 0) throw Object.assign(new Error('Unknown Bot'), { code: 'bot/not-found' })
        const part = typeof (body.cursor as { part?: number })?.part === 'number' ? (body.cursor as { part: number }).part : 0
        const page = pages[part] ?? { sessionId: pages[0].sessionId, items: [], cursor: null }
        return { sessionId: pages[0].sessionId, items: page.items, cursor: page.cursor }
      }
      case 'send': {
        const id = String(body.sessionId ?? '')
        const pages = chatOf(id) ?? this.chats[id]
        if (pages === undefined || pages.length === 0) throw Object.assign(new Error('Unknown Bot'), { code: 'bot/not-found' })
        const item: ChatItem = { kind: 'user', text: String(body.text ?? ''), time: Date.now(), seq: (this.lastSeq(pages[0])) + 1 }
        pages[0] = { ...pages[0], items: [...pages[0].items, item] }
        this.touch()
        return true
      }
      case 'answer-question': {
        const sid = sessionOf(String(body.sessionId ?? ''))
        const question = state.questions?.[sid]
        if (question === undefined || question.id !== body.questionId) throw Object.assign(new Error('This question is no longer open'), { code: 'bot/stale' })
        delete state.questions![sid]
        const pages = chatOf(sid)
        const answer = (body.answer ?? {}) as { selected?: string[]; custom?: string }
        if (pages !== undefined) {
          const item: ChatItem = { kind: 'answer', questions: [{ question: question.question }], answers: [{ selected: answer.selected ?? [], custom: answer.custom ?? '' }], time: Date.now(), seq: (this.lastSeq(pages[0])) + 1 }
          pages[0] = { ...pages[0], items: [...pages[0].items, item] }
        }
        this.touch()
        return true
      }
      case 'approval-answer': {
        const list = state.work?.approvals ?? []
        const index = list.findIndex(entry => entry.id === body.id)
        if (index === -1) throw Object.assign(new Error('This approval is no longer open'), { code: 'bot/stale' })
        if (body.choice !== 'allow' && body.choice !== 'reject') throw Object.assign(new Error('Choose allow or reject'), { code: 'bot/invalid' })
        list.splice(index, 1)
        this.touch()
        return true
      }
      case 'stop-room-work': {
        const roomId = String(body.roomId ?? '')
        if (state.work?.rooms?.[roomId] !== undefined) delete state.work.rooms[roomId]
        this.touch()
        return true
      }
      case 'update-bot': {
        const bot = state.bots.find(b => b.id === String(body.id ?? ''))
        if (bot === undefined) throw Object.assign(new Error('Unknown Bot'), { code: 'bot/not-found' })
        const { id: _ignored, ...patch } = body as Record<string, unknown>
        Object.assign(bot, { name: undefined, role: undefined, instructions: undefined, model: undefined, effort: undefined, color: undefined, avatar: undefined, workDir: undefined, private: undefined, permission: undefined }, patch)
        state.revision += 1; this.touch()
        return { ok: true }
      }
      case 'create-bot': {
        const id = `b-${Math.random().toString(36).slice(2, 8)}`
        state.bots.push({ id, name: String(body.name ?? 'New Bot'), color: body.color as string | undefined, avatar: body.avatar as { shape?: string; image?: string } | undefined, model: body.model as string | undefined, sessionId: `s-${id}`, createdAt: Date.now() })
        state.revision += 1; this.touch()
        return { id }
      }
      case 'duplicate-bot': {
        const bot = state.bots.find(b => b.id === String(body.id ?? ''))
        if (bot === undefined) throw Object.assign(new Error('Unknown Bot'), { code: 'bot/not-found' })
        const id = `b-${Math.random().toString(36).slice(2, 8)}`
        const copy = { ...bot, id, name: `${bot.name} (copy)`, sessionId: `s-${id}`, createdAt: Date.now() }
        state.bots.push(copy)
        state.revision += 1; this.touch()
        return { id }
      }
      case 'delete-bot': {
        state.bots = state.bots.filter(b => b.id !== String(body.id ?? ''))
        state.revision += 1; this.touch()
        return { ok: true }
      }
      case 'set-main': {
        const mains = new Set(state.mainBotIds ?? [])
        if (body.main === true) mains.add(String(body.id)); else mains.delete(String(body.id))
        state.mainBotIds = [...mains]
        state.mainBotId = state.mainBotIds[0] ?? null
        state.revision += 1; this.touch()
        return { ok: true }
      }
      case 'update-room': {
        const room = state.rooms?.find(r => r.id === String(body.id ?? ''))
        if (room === undefined) throw Object.assign(new Error('Unknown group'), { code: 'bot/not-found' })
        const { id: _ignored, ...patch } = body as Record<string, unknown>
        Object.assign(room, { name: undefined, notice: undefined, mode: undefined, admin: undefined, members: undefined }, patch)
        state.revision += 1; this.touch()
        return { ok: true }
      }
      case 'create-room': {
        const id = `r-${Math.random().toString(36).slice(2, 8)}`
        const members = (Array.isArray(body.members) ? body.members : []).map(String)
        const name = members.map(id => state.bots.find(b => b.id === id)?.name).filter(Boolean).join(', ') || 'New group'
        state.rooms = [...(state.rooms ?? []), { id, name, members, createdAt: Date.now() }]
        state.revision += 1; this.touch()
        return { id }
      }
      case 'delete-room': {
        state.rooms = (state.rooms ?? []).filter(r => r.id !== String(body.id ?? ''))
        state.revision += 1; this.touch()
        return { ok: true }
      }
      case 'models': return state.models ?? []
      case 'efforts': return { efforts: [{ id: 'low', name: 'Quick' }, { id: 'medium', name: 'Balanced' }, { id: 'high', name: 'Careful' }], defaultEffort: 'medium' }
      case 'memory-view': return { summary: { text: 'Chief keeps the launch plan moving.', at: Date.now() - 600e3 }, sizes: { own: 420, team: 180 }, limits: { main: 4000 }, entries: [
        { scope: 'own', topic: 'Release', text: 'Tag lands Friday once screenshots are in', added: '2 天前', by: 'Coder', source: 'chat' },
        { scope: 'own', topic: null, text: 'Prefers concise status lines', added: '上周', by: null, source: 'memory panel' },
        { scope: 'team', topic: 'Team', text: 'Writer drafts docs first, Coder tests before merge', added: '本月', by: 'Chief', source: 'chat' },
      ] }
      case 'memory-add': case 'memory-edit': return { ok: true }
      case 'memory-forget': return { ok: true }
      case 'memory-ask': return { reply: 'The tag is held until the screenshots land — see Release notes.', changes: [], view: { summary: { text: 'Chief keeps the launch plan moving.', at: Date.now() - 600e3 }, sizes: { own: 420, team: 180 }, limits: { main: 4000 }, entries: [
        { scope: 'own', topic: 'Release', text: 'Tag lands Friday once screenshots are in', added: '2 天前', by: 'Coder', source: 'chat' },
        { scope: 'own', topic: null, text: 'Prefers concise status lines', added: '上周', by: null, source: 'memory panel' },
        { scope: 'team', topic: 'Team', text: 'Writer drafts docs first, Coder tests before merge', added: '本月', by: 'Chief', source: 'chat' },
      ] } }
      case 'schedules': return { available: true, tasks: [
        { id: 'sch-1', botId: 'b-chief', sessionId: 's-chief', title: 'Morning standup', prompt: 'Post the team status', kind: 'daily', time: '09:00', scheduledAt: Date.now() + 3600e3, status: 'active' },
        { id: 'sch-2', botId: 'b-chief', sessionId: 's-chief', title: 'Weekly review', prompt: 'Summarize the week', kind: 'weekly', weekdays: [5], time: '17:00', scheduledAt: Date.now() + 86400e3, status: 'active' },
        { id: 'sch-3', botId: 'b-chief', sessionId: 's-chief', title: 'Tag reminder', kind: 'at', scheduledAt: Date.now() + 7200e3, status: 'active' },
      ] }
      case 'schedule-create': case 'schedule-delete': return { ok: true }
      case 'folders': return { team: '/work', picker: 'browse', folders: [{ path: '/work/ds-bot', title: 'ds-bot' }, { path: '/work/docs', title: 'docs' }] }
      case 'folder-list': {
        const path = String(body.path ?? '')
        const tree: Record<string, string[]> = { '': ['work'], '/work': ['ds-bot', 'docs', 'notes'], '/work/ds-bot': ['mobile', 'ds-bot', 'app'] }
        const kids = tree[path] ?? []
        return { path, parent: path.split('/').slice(0, -1).join('/') || null, entries: kids.map(name => ({ name, path: `${path}/${name}` })), truncated: false }
      }
      case 'usage-summary': return { botId: String(body.botId ?? ''), day: { input: 12400, output: 3200, cacheRead: 8800 }, week: { input: 98200, output: 21400, cacheRead: 61100 }, month: { input: 402100, output: 90300, cacheRead: 251000 }, models: [{ key: 'deepseek-official/deepseek-v4.1', name: 'DeepSeek v4.1', input: 300100, output: 70100 }, { key: 'deepseek-official/deepseek-flash', name: 'DeepSeek Flash', input: 102000, output: 20200 }], scanning: false }
      case 'run-stats': return { sessionStats: { turns: 96, steps: 311 }, tokenUsage: { uncachedInputTokens: 52000, outputTokens: 9000, cacheReadTokens: 480000, cacheWriteTokens: 0 }, contextPressure: { pressureTokens: 61000, contextWindow: 1000000 } }
      case 'providers': return { available: true, protocols: ['openai'], providers: [
        { id: 'deepseek', name: 'DeepSeek', key: { configured: true, writable: true }, models: [{ name: 'DeepSeek v4.1' }, { name: 'DeepSeek Flash' }] },
        { id: 'openrouter', name: 'OpenRouter', key: { configured: true, writable: true }, models: [{ name: 'Auto' }, { name: 'Kimi K2.5' }] },
        { id: 'openai', name: 'OpenAI', key: { configured: false, writable: true }, removable: true, models: [{ name: 'GPT-5.2' }] },
      ], addable: [
        { id: 'anthropic', name: 'Anthropic' }, { id: 'google', name: 'Google' }, { id: 'openai-compat', name: 'OpenAI-compatible' },
      ] }
      case 'provider-models': return [{ name: 'DeepSeek v4.1' }, { name: 'DeepSeek Flash' }, { name: 'DeepSeek Reasoner' }]
      case 'provider-key': case 'provider-add': case 'provider-remove': return { ok: true }
      // connectors ride in state, not their own endpoint
      case 'connector-connect': case 'connector-disconnect': case 'connector-retry': return { ok: true }
      // capabilities ride in state, not their own endpoint
      case 'capability-save': case 'capability-delete': case 'capability-approve': return { ok: true }
      case 'bot-capability': {
        const bot = state.bots.find(b => b.id === body.botId)
        if (bot !== undefined) {
          const list = new Set(bot.capabilities ?? [])
          if (body.attached === true) list.add(String(body.name)); else list.delete(String(body.name))
          bot.capabilities = [...list]
        }
        return { ok: true }
      }
      case 'team-workspace': return { ok: true }
      case 'side-new': {
        const chatId = `sc-${Math.random().toString(36).slice(2, 8)}`
        const botId = String(body.sessionId ?? '').split(':')[0] || 'b-chief'
        ;((state.sideChats ??= {})[botId] ??= []).push({ chatId, entries: [] })
        return { chatId }
      }
      case 'side-ask': {
        const entry: DemoSideEntry = { id: `se-${Math.random().toString(36).slice(2, 8)}`, question: String(body.text ?? ''), answer: '从目前的进展看：这一步还卡在迁移脚本上，其余都在轨。', status: 'done' }
        const chat = sideChatsFlat(state.sideChats).find(c => c.chatId === body.chatId)
        if (chat !== undefined) (chat.entries ??= []).push(entry)
        return entry
      }
      case 'side-cancel': {
        const chat = sideChatsFlat(state.sideChats).find(c => c.chatId === body.chatId)
        const entry = (chat?.entries ?? []).find(e => e.id === body.entryId)
        if (entry !== undefined) entry.status = 'cancelled'
        return { ok: true }
      }
      case 'side-close': {
        const sideChats = state.sideChats
        if (sideChats !== undefined) {
          for (const botId of Object.keys(sideChats)) {
            const chats = sideChats[botId]
            if (chats !== undefined) sideChats[botId] = chats.filter(c => c.chatId !== body.chatId)
          }
        }
        return { ok: true }
      }
      case 'browser-frame': {
        const hold = state.browserHolds?.[String(body.botId ?? '')]
        if (hold === undefined && body.botId !== 'b-coder') return { ok: false, error: { code: 'bot/not-found', message: 'This Bot has no open browser' } }
        return { mime: 'image/png', data: 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==', url: 'https://github.com/fei2411/ds-bot', title: 'DS Bot — GitHub' }
      }
      case 'browser-takeover': { (state.browserHolds ??= {})[String(body.botId ?? '')] = { by: 'user', reason: 'takeover', note: 'The user is controlling this browser.' }; return { ok: true } }
      case 'browser-give-back': { delete (state.browserHolds ??= {})[String(body.botId ?? '')]; return { ok: true } }
      case 'browser-stop': { (state.browserHolds ??= {})[String(body.botId ?? '')] = { by: 'user', reason: 'stopped', note: 'The user is controlling this browser.' }; return { ok: true } }
      case 'btw-delete': {
        const cards = state.btwCards
        if (cards !== undefined) {
          for (const botId of Object.keys(cards)) {
            const list = cards[botId]
            if (list !== undefined) cards[botId] = list.filter(card => card.id !== body.cardId)
          }
        }
        return { ok: true }
      }
      case 'file-text': return { text: '# Release notes\n\n- Drawer lands today\n- Mobile cards render natively\n- Needs-you groups the queue\n', truncated: false }
      case 'usage': return {
        total: { input: 402100, output: 90300 },
        bots: [
          { name: 'Chief', input: 152100, output: 40100 }, { name: 'Writer', input: 120100, output: 30400 },
          { name: 'Coder', input: 80000, output: 13000 }, { name: 'Researcher', input: 50000, output: 6800 },
        ],
        models: [
          { name: 'DeepSeek v4.1', input: 300100, output: 70100 }, { name: 'DeepSeek Flash', input: 102000, output: 20200 },
        ],
      }
      case 'update-check': return { update: { phase: 'current', latest: '0.1.2', available: false, checkedAt: Date.now() - 3600e3, source: 'registry' }, dsh: { phase: 'installed', installed: '0.0.1', available: false } }
      case 'update-install': case 'dsh-update-install': return { ok: true }
      case 'diagnostics': return { size: 48200, entries: 214, last: 'Turn 96 on Coder failed once and retried.' }
      case 'diagnostics-log': return { lines: ['12:00 Chief ran 3 tools', '12:01 Coder failed once and retried', '12:02 Writer posted a draft', '12:03 Researcher finished a compare'] }
      case 'diagnostics-clear': return { ok: true }
      case 'avatar-library': return { entries: [], done: true }
      case 'avatar-import': return { ok: true }
      case 'avatar-delete': return { ok: true }
      case 'set-flags': return { ok: true }
      case 'stop-member-work': {
        const roomId = String(body.roomId ?? '')
        const list = state.work?.rooms?.[roomId]
        if (list !== undefined) state.work!.rooms![roomId] = list.filter(entry => entry.botId !== body.botId)
        this.touch()
        return true
      }
      default:
        throw Object.assign(new Error(`Demo cannot answer ${endpoint}`), { code: 'bot/not-found' })
    }
  }
}

