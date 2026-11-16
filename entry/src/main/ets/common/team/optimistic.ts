// Optimistic updates: the write's effect on the team state, guessed before the
// reply lands. Port of optimistic.ts.
import type { Bot, Room, TeamState } from './types.ts'

export const OPTIMISTIC = new Set<string>(['update-bot', 'set-main', 'bot-capability', 'update-room'])

function cloneBotPatch(bot: Bot, patch: Record<string, unknown>): Bot {
  const next: Bot = { ...bot }
  for (const [key, value] of Object.entries(patch)) {
    if (key === 'id') continue
    ;(next as unknown as Record<string, unknown>)[key] = value
  }
  // The computer reads `null`/`''` as "clear"; the state omits the key.
  if (patch.effort === null) delete (next as unknown as Record<string, unknown>).effort
  if (patch.workDir === '') delete (next as unknown as Record<string, unknown>).workDir
  return next
}

export function optimistic(team: TeamState | null, endpoint: string, payload: Record<string, unknown>): TeamState | null {
  if (team === null) return null
  switch (endpoint) {
    case 'update-bot': {
      const index = team.bots.findIndex(bot => bot.id === payload.id)
      if (index === -1) return team
      const bots = [...team.bots]
      bots[index] = cloneBotPatch(team.bots[index]!, payload)
      return { ...team, bots }
    }
    case 'set-main': {
      const id = String(payload.id ?? '')
      if (!team.bots.some(bot => bot.id === id)) return team
      const mains = new Set<string>(team.mainBotIds ?? [])
      if (payload.main === false) mains.delete(id)
      else mains.add(id)
      const mainBotIds = [...mains]
      return { ...team, mainBotIds, mainBotId: mainBotIds[0] ?? null }
    }
    case 'bot-capability': {
      const index = team.bots.findIndex(bot => bot.id === payload.botId)
      if (index === -1) return team
      const attached = new Set<string>(team.bots[index]!.capabilities ?? [])
      if (payload.attached === true) attached.add(String(payload.name))
      else attached.delete(String(payload.name))
      const bots = [...team.bots]
      bots[index] = { ...team.bots[index]!, capabilities: [...attached] }
      return { ...team, bots }
    }
    case 'update-room': {
      const rooms = team.rooms ?? []
      const index = rooms.findIndex(room => room.id === payload.id)
      if (index === -1) return team
      const next: Room[] = [...rooms]
      const room = { ...rooms[index]! }
      for (const [key, value] of Object.entries(payload)) {
        if (key === 'id') continue
        ;(room as unknown as Record<string, unknown>)[key] = value
      }
      next[index] = room
      return { ...team, rooms: next }
    }
    default:
      return team
  }
}

export interface Write {
  endpoint: string
  payload: Record<string, unknown>
}

// A state read that left before a write landed would undo the write's guess, so
// every write still in flight is laid over each state the phone takes in.
export function withWrites(team: TeamState, writes: Write[]): TeamState {
  let next = team
  for (const write of writes) {
    next = optimistic(next, write.endpoint, write.payload) ?? next
  }
  return next
}
