// Last-read time per bot or room id, kept in memory and on the phone, plus the
// in-memory LRU of latest chat pages and the pending count. Ports of seen.ts,
// chat-cache.ts and pending.ts.

// ---- Seen -------------------------------------------------------------

const SEEN_KEY = 'dsbot.seenAt'
const seen = new Map<string, number>()
let seenLoaded = false
let seenStore: ((value: string) => Promise<void>) | null = null

/** The platform layer installs the persistent store (Asset kit / preferences). */
export function installSeenStore(store: (value: string) => Promise<void>): void {
  seenStore = store
}

export async function loadSeen(text: string | null): Promise<void> {
  if (seenLoaded) return
  seenLoaded = true
  if (text === null) return
  try {
    const parsed = JSON.parse(text) as Record<string, number>
    for (const [id, at] of Object.entries(parsed)) seen.set(id, at)
  } catch {
    // start fresh
  }
}

export async function persistSeen(): Promise<void> {
  if (seenStore === null) return
  const value: Record<string, number> = {}
  for (const [id, at] of seen) value[id] = at
  await seenStore(JSON.stringify(value))
}

export function seenAt(id: string): number {
  return seen.get(id) ?? 0
}

export function markSeen(id: string, at = Date.now()): void {
  seen.set(id, at)
  void persistSeen()
}

export function isUnread(id: string, lastAt: number | undefined, open: boolean): boolean {
  return !open && lastAt !== undefined && lastAt > seenAt(id)
}

// ---- Chat page cache ----------------------------------------------------

export interface CachedChatEntry<P, I> {
  page: P
  older: I[]
  cursor: unknown
}

export function createChatCache<P, I>(limit = 16) {
  const map = new Map<string, CachedChatEntry<P, I>>()
  return {
    get: (key: string): CachedChatEntry<P, I> | undefined => map.get(key),
    has: (key: string): boolean => map.has(key),
    keep(chatKey: string, ownerKey: string, entry: CachedChatEntry<P, I>): boolean {
      if (chatKey === '' || ownerKey !== chatKey) return false
      map.delete(chatKey)
      map.set(chatKey, entry)
      if (map.size > limit) {
        const first = map.keys().next()
        if (!first.done) map.delete(first.value)
      }
      return true
    },
    size: (): number => map.size,
    clear: (): void => map.clear(),
  }
}

// ---- Pending count ------------------------------------------------------

import type { TeamState } from './types.ts'

// Everything the Needs you page lists: questions, approvals, secret requests,
// browser handoffs and cards waiting for an answer. The count and the page agree.
export function pendingCountOf(team: TeamState | null): number {
  const questions = Object.keys(team?.questions ?? {}).length
  const approvals = (team?.work?.approvals ?? []).filter(a => a.answerable !== false).length
  const secrets = Object.values(team?.secretRequests ?? {}).flat().filter(r => r.status === 'pending').length
  const holds = Object.values(team?.browserHolds ?? {}).filter(hold => hold.callId !== undefined).length
  const views = Object.keys(team?.views ?? {}).length
  return questions + approvals + secrets + holds + views
}

// ---- Memory summary ------------------------------------------------------

// `memory-view` on the computer returns `summary` as `{ text, at } | null`.
export function memorySummaryText(summary: unknown): string | null {
  if (typeof summary === 'string') return summary.trim() === '' ? null : summary
  if (summary !== null && typeof summary === 'object') {
    const text = (summary as { text?: unknown }).text
    if (typeof text === 'string' && text.trim() !== '') return text
  }
  return null
}
