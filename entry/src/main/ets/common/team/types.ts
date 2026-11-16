// Team state types the host answers with, ported from src/connection.ts.
export interface BotAvatar {
  shape?: string
  image?: string
  imageRef?: string
}

export interface Bot {
  id: string
  name: string
  role?: string
  /** The DSH permission preset the Bot runs with; unset runs on the default one. */
  permission?: string
  /** A credential or balance failure that stops the Bot until the user fixes it. */
  blocked?: { code: string; status?: number; provider?: string; at?: number }
  color?: string
  avatar?: BotAvatar
  model?: string
  appliedModel?: string
  capabilities?: string[]
  browser?: boolean
  effort?: string
  workDir?: string
  main?: boolean
  private?: boolean
  instructions?: string
  sessionId?: string
  parts?: string[]
  waiting?: boolean
  pinned?: boolean
  hidden?: boolean
  createdAt?: number
  lastAt?: number
  preview?: string
}

export interface Room {
  id: string
  name: string
  preview?: string
  lastAt?: number
  members?: string[]
  admin?: string
  mode?: string
  notice?: string
  named?: boolean
  sessionId?: string
  pinned?: boolean
  hidden?: boolean
  createdAt?: number
  /** The group's goal island, as the desktop's goal.js shows it. */
  goal?: RoomGoal
}

export interface RoomGoalTask {
  status?: string
}

export interface RoomGoalStage {
  title?: string
  status?: string
  tasks?: RoomGoalTask[]
}

export interface RoomGoal {
  status?: string
  idle?: boolean
  title?: string
  current?: number
  stages?: RoomGoalStage[]
}

export interface Question {
  id: string
  question: string
  detail?: string
  options?: { label: string }[]
  multiSelect?: boolean
}

export interface Approval {
  id: string
  sessionId: string
  botId: string
  roomId?: string
  at?: number
  tool: string
  reason: string
  detail?: { text?: string; code?: string }
  answerable?: boolean
}

export interface SecretRequest {
  id: string
  name?: string
  scope?: string | string[]
  status?: string
  kind?: string
}

export interface ShownView {
  id?: string
  title?: string
  view?: unknown
}

export interface ModelInfo {
  ref: string
  name: string
  provider?: string
  providerName?: string
  reasoning?: Reasoning
}

export interface Reasoning {
  efforts?: { id: string; name: string }[]
  defaultEffort?: string
}

export interface CapabilityInfo {
  name: string
  description?: string
  kind?: string
  transport?: string
  command?: string
  url?: string
  content?: string
  items?: string[]
  status?: string
}

// Computer use (computer.js): what the computer reports while a Bot holds it.
export interface ComputerControl {
  state?: string
  app?: string
}

export interface ComputerAsk {
  id: string
  botId: string
  appName?: string
}

export interface ComputerLive {
  bots?: Record<string, ComputerControl>
  asks?: Record<string, ComputerAsk>
}

export interface TeamState {
  revision: number
  unchanged?: boolean
  liveKey?: string
  bots: Bot[]
  rooms?: Room[]
  mainBotId?: string | null
  mainBotIds?: string[]
  models?: ModelInfo[]
  defaultModel?: string
  memory?: boolean
  questions?: Record<string, Question>
  views?: Record<string, ShownView>
  secretRequests?: Record<string, SecretRequest[]>
  connectors?: { id: string; name: string; state?: string; account?: string; error?: string }[]
  capabilities?: CapabilityInfo[]
  browserHolds?: Record<string, { by?: string; reason?: string; note?: string; callId?: string }>
  computerLive?: ComputerLive
  btwCards?: Record<string, { id: string; partId?: string; question?: string; answer?: string; failure?: string; status?: string }[]>
  sideChats?: Record<string, { chatId: string; entries?: { id: string; question?: string; answer?: string; status?: string; failure?: string }[] }[]>
  capabilityStatuses?: Record<string, Record<string, { state?: string; error?: string }> | { state?: string; error?: string }>
  workspace?: string
  dataPath?: string
  version?: string
  /** The DSH permission presets the host offers (details-drawer). */
  permissions?: { options?: { value: string; name: string }[]; defaultPreset?: string }
  /** Whether the host allows Bot browser takeovers at all. */
  browser?: boolean
  work?: {
    bots?: Record<string, { tool?: string; said?: string; note?: string; target?: string; switching?: boolean; folder?: boolean }>
    rooms?: Record<string, { botId: string; tool?: string; said?: string; note?: string; target?: string }[]>
    approvals?: Approval[]
    waiting?: Record<string, { bots?: string[]; rooms?: string[] }>
    turns?: Record<string, number>
  }
  activity?: Record<string, { tool?: string; said?: string; note?: string; target?: string; switching?: boolean }>
  exchangeTurns?: Record<string, number[]>
  prefs?: { theme?: string; accent?: string; layout?: string; width?: number; flatWidth?: number }
  secrets?: { name: string; description?: string; scope?: string | string[] }[]
}

// Chat items, ported from src/screens/chat/items.tsx.
export interface ImageRef {
  attachmentId: string
  mime?: string
  name?: string
}

export interface FileRef {
  name: string
  bytes?: number
  attachmentId?: string
}

export interface ChatItem {
  kind: 'bot' | 'user' | 'event' | 'answer' | 'view' | 'divider' | 'steps' | 'closed' | 'post' | 'relay'
  text?: string
  time?: number
  seq?: number
  turn?: number
  role?: string
  event?: string
  code?: string
  name?: string
  botId?: string
  images?: number
  via?: string
  imageRefs?: ImageRef[]
  files?: FileRef[]
  file?: FileRef
  whole?: { file?: FileRef; length?: number }
  length?: number
  title?: string
  view?: unknown
  views?: { id: string; title: string; view: unknown }[]
  closed?: string
  question?: SettledQuestionData
  questions?: SettledQuestionData[]
  handoff?: { reason?: string; note?: string; outcome?: string }
  reply?: RelayReplyData
  answers?: { id?: string; action?: string; values?: { selected?: string[]; inputs?: Record<string, unknown>; fields?: Record<string, string>; confirmed?: boolean }; selected?: string[]; custom?: string }[]
  tools?: { name: string; label?: string | null; ok?: boolean; detail?: string | null }[]
  ms?: number
  live?: boolean
  texts?: string[]
  /** Photos picked on this phone, shown from the device until the computer has them. */
  localImages?: string[]
  /** A message the phone sent that the computer has not shown back yet. */
  local?: 'sending' | 'failed'
  localId?: string
}

export interface SettledQuestionData {
  id?: string
  question: string
  detail?: string
  options?: (string | { label: string })[]
}

export interface RelayReplyData {
  kind?: string
  event?: string
  botId?: string
  name?: string
  color?: string
  text?: string
  code?: string
  idle?: boolean
  count?: number
  names?: string[]
}

export interface Hello {
  api: number | null
  capabilities: string[]
  boot: string
  seq: number
}
