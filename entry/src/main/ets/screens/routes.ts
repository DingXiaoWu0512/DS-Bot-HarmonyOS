// Route params shared by the push side (pages/Index.ets, TeamList, screens)
// and the destination screens. The route table carries them as untyped objects,
// so every destination normalizes through the readers below before use.

export interface BotDetailsParam {
  botId: string
}

export interface BotEditParam {
  botId: string
}

export interface BotBrowserParam {
  botId: string
}

export interface GroupDetailsParam {
  roomId: string
}

export interface GroupSettingsParam {
  roomId: string
}

export interface MemoryParam {
  botId?: string
  roomId?: string
}

export interface SchedulesParam {
  botId: string
  sessionId?: string
}

export interface FolderParam {
  pick: string
  botId?: string
  roomId?: string
  /** Where to start browsing (the Bot's current workDir). */
  current?: string
}

export interface UsageParam {
  botId?: string
}

export interface SideParam {
  botId: string
  sessionId: string
}

/** A required string field; '' when the param is missing or malformed. */
export function readStringParam(raw: unknown, field: string): string {
  if (raw === null || raw === undefined) return ''
  if (typeof raw !== 'object') return ''
  const holder = raw as Record<string, Object>
  const value = holder[field]
  if (typeof value === 'string') return value
  return ''
}

/** An optional string field; undefined when absent or not a string. */
export function optionalStringParam(raw: unknown, field: string): string | undefined {
  if (raw === null || raw === undefined) return undefined
  if (typeof raw !== 'object') return undefined
  const holder = raw as Record<string, Object>
  const value = holder[field]
  if (typeof value === 'string') return value
  return undefined
}
