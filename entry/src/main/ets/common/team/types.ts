// Team state types the host answers with, ported from src/connection.ts.
import type { ConnectorsView } from './connectors.ts'
import type { LearningProposal } from './learning.ts'

export interface BotAvatar {
  shape?: string
  image?: string
  imageRef?: string
}

/** One background task a Bot runs outside its chat (bot-tasks.js): a DSH
 *  Agent turn, a scheduled run or any long job the computer tracks. */
export interface BotTask {
  id: string
  title: string
  status: 'running' | 'waiting_work' | 'waiting_approval' | 'completed' | 'failed' | 'interrupted' | 'stopped' | string
  sessionId: string
  roomId?: string
  origin?: string
  startedAt?: number
  updatedAt?: number
  endedAt?: number
  summary?: string
  error?: string
  running?: boolean
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
  /** The local-agent route, present only on Bots that run on a local agent. */
  engine?: string
  /** What the user allowed this Bot to do in the browser, from its grants page. */
  browserGrants?: BrowserGrant[]
  /** The Bot's computer-use block; an unset level runs in the background. */
  computer?: BotComputer
  main?: boolean
  private?: boolean
  instructions?: string
  sessionId?: string
  parts?: string[]
  /** The background tasks the Bot runs outside its chat, when it runs any. */
  tasks?: BotTask[]
  waiting?: boolean
  pinned?: boolean
  hidden?: boolean
  createdAt?: number
  lastAt?: number
  preview?: string
}

/** One browser grant: which site, which risky actions, until when. */
export interface BrowserGrant {
  site: string
  kinds: string[]
  until?: number
}

/** The Bot's own computer-use settings; only its level lives on the Bot. */
export interface BotComputer {
  level?: string
}

export interface Room {
  id: string
  name: string
  /** The group's shared working folder; unset means each member uses its own. */
  workDir?: string
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
  /** The background task this approval gates, when it gates one. */
  taskId?: string
  taskTitle?: string
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
  /** True when the model still needs an API key before it can answer. */
  needsKey?: boolean
}

export interface Reasoning {
  efforts?: { id: string; name: string }[]
  defaultEffort?: string
}

export interface ConnectorRequest {
  id: string
  connectorId: string
  name?: string
  purpose?: string
  callId?: string
  sessionId?: string
  status?: string
}

export interface CapabilityStatus { state?: string; error?: string }

export interface CapabilityItem {
  name: string
  description?: string
  kind?: string
  transport?: string
  command?: string
  args?: string[]
  env?: Record<string, string>
  url?: string
  headers?: Record<string, string>
  content?: string
  items?: string[]
  status?: string
  approved?: boolean
}

// The pre-0.3.8 name of CapabilityItem; the screens still import it.
export type CapabilityInfo = CapabilityItem

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

/** Where the computer-use provider stands: off, loading, ready, error, missing,
 *  occupied or unsupported, with what to install when it is missing. */
export interface ComputerProvider {
  state?: string
  name?: string
  message?: string
  install?: { command?: string }
}

/** The computer-use switch, its provider and whether this is a Mac, from the
 *  team view the host ships beside `computerLive`. */
export interface ComputerInfo {
  enabled?: boolean
  provider?: ComputerProvider
  macos?: boolean
}

// IM connections (host im/index.js imView): one IM bot account bound to a Bot;
// direct chats reach that Bot, platform group chats can be bound to a group.
export interface ImChatTarget {
  botId?: string
  roomId?: string
}

export interface ImChat {
  kind?: string
  title?: string
  target?: ImChatTarget
  at?: number
}

export interface ImPaired {
  id: string
  name?: string
}

export interface ImRequest {
  id: string
  name?: string
  chatKey?: string
  chatKind?: string
  at?: number
}

export interface ImConnection {
  id: string
  platform: string
  account: { id?: string; name?: string } | null
  botId?: string | null
  settings?: Record<string, string>
  secrets?: string[]
  enabled?: boolean
  paired?: ImPaired[]
  requests?: ImRequest[]
  chats?: Record<string, ImChat>
  createdAt?: number
}

export interface ImView {
  connections?: ImConnection[]
  platforms?: string[]
}

/** The live connection status of one IM connection (stateOf's five states). */
export interface ImStatusEntry {
  state?: string
  error?: string
  at?: number
}

// The team's DSH Agent (agents.js): plain DSH Sessions, newest last, not a Bot.
export interface Agent { id: string; name?: string; sessions: string[]; createdAt?: number }

export interface TeamState {
  revision: number
  unchanged?: boolean
  liveKey?: string
  bots: Bot[]
  rooms?: Room[]
  agents?: Agent[]
  mainBotId?: string | null
  mainBotIds?: string[]
  models?: ModelInfo[]
  defaultModel?: string
  memory?: boolean
  questions?: Record<string, Question>
  views?: Record<string, ShownView>
  secretRequests?: Record<string, SecretRequest[]>
  connectorRequests?: Record<string, ConnectorRequest[]>
  /** The Bots' open learning proposals, keyed by Bot id. */
  learning?: Record<string, LearningProposal[]>
  connectors?: ConnectorsView
  capabilities?: CapabilityItem[]
  browserHolds?: Record<string, { by?: string; reason?: string; note?: string; callId?: string }>
  computerLive?: ComputerLive
  computer?: ComputerInfo
  btwCards?: Record<string, { id: string; partId?: string; question?: string; answer?: string; failure?: string; status?: string }[]>
  sideChats?: Record<string, { chatId: string; entries?: { id: string; question?: string; answer?: string; status?: string; failure?: string }[] }[]>
  capabilityStatuses?: Record<string, Record<string, CapabilityStatus> | CapabilityStatus>
  /** Live per-connection IM status (connecting/retrying/ready/error), keyed by connection id. */
  imStatus?: Record<string, ImStatusEntry>
  workspace?: string
  dataPath?: string
  version?: string
  /** The DSH permission presets the host offers (details-drawer). */
  permissions?: { options?: { value: string; name: string }[]; defaultPreset?: string }
  /** Whether the host allows Bot browser takeovers at all. */
  browser?: boolean
  work?: {
    bots?: Record<string, { tool?: string; said?: string; note?: string; target?: string; switching?: boolean; folder?: boolean }>
    agents?: Record<string, { tool?: string; said?: string; note?: string; target?: string }>
    rooms?: Record<string, { botId: string; tool?: string; said?: string; note?: string; target?: string }[]>
    approvals?: Approval[]
    waiting?: Record<string, { bots?: string[]; rooms?: string[] }>
    turns?: Record<string, number>
  }
  activity?: Record<string, { tool?: string; said?: string; note?: string; target?: string; switching?: boolean }>
  exchangeTurns?: Record<string, number[]>
  im?: ImView
  prefs?: { theme?: string; accent?: string; motion?: string; effects?: string; layout?: string; width?: number; flatWidth?: number; thinking?: boolean; defaultBotModel?: string }
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
  sessionId?: string
  attachmentId?: string
  seq?: number
  index?: number
}

export interface ChatItem {
  id?: string
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
  sessionId?: string
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

// Plugins (host channel.js 'plugins'): one bundle the host reports, with the
// pages it adds. The host may leave any field but id and name out.
export interface PluginPage {
  id: string
  label: string
}

export interface PluginBundle {
  id: string
  name: string
  version?: string
  description?: string
  enabled?: boolean
  manageOnDesktop?: boolean
  pages?: PluginPage[]
}

// Plugins v2 (host channel.js 'plugins' with an inventory): the web-parity
// plugin inventory the host attaches beside the v1 bundles. The fiber phase
// passes the host's PluginFiberPhase through verbatim ('pending' | 'loading'
// | 'active' | 'failed' | 'unloading'); null and a missing field both mean
// "no live fiber", which the phone renders with the same "inactive" wording.

/** One globally loaded plugin module the host reports. */
export interface GlobalPluginEntry {
  id: string
  moduleName: string
  name: string
  description?: string
  enabled: boolean
  fiberPhase?: string | null
  /** Present only when the fiber failed to start. */
  diagnostic?: string
  /** The pages the plugin registers, when it reports any. */
  pages?: PluginPage[]
}

/** One row of an Agent preset's plugin composition. */
export interface PresetPluginRow {
  entryId?: string | null
  moduleName: string
  name: string
  enabled: boolean | 'conditional'
  condition?: string
  fiberPhase?: string | null
  description?: string
}

/** One Agent preset: the plugin set its sessions run with. A broken preset
 *  carries its reason and no rows. */
export interface PresetGroup {
  id: string
  name?: string
  isDefault: boolean
  broken?: string
  rows: PresetPluginRow[]
}

/** The v2 inventory snapshot: global entries, the Agent presets (absent when
 *  the deployment has no preset manifest), and whether the host can manage
 *  plugins. */
export interface PluginsInventory {
  entries: GlobalPluginEntry[]
  presets?: PresetGroup[]
  managementAvailable?: boolean
}

/** The 'plugins' endpoint's full reply: the v1 bundles plus, on a v2 host,
 *  the plugin inventory snapshot. */
export interface PluginsReply {
  plugins?: PluginBundle[]
  inventory?: PluginsInventory
}

/** The timing half of a schedule-create payload (host schedules.js selectorOf):
 *  once at an ISO time, daily or weekly at a time with the local zone, or a
 *  repeat every N minutes. */
export interface ScheduleWhen {
  kind: string
  at?: string
  minutes?: number
  time?: string
  timeZone?: string
  weekdays?: number[]
}

/** What schedule-create sends: the target Bot or group chat, the task itself,
 *  and its timing. */
export interface ScheduleCreatePayload {
  target: string
  title: string
  prompt: string
  when: ScheduleWhen
}
