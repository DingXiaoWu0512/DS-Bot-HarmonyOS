// Update and diagnostics views the Updates page reads, ported from
// settings-pages.tsx's inline shapes.

export interface UpdateState {
  current?: string
  phase?: string
  latest?: string
  installed?: string
  verified?: string
  available?: boolean
  checkedAt?: number
  source?: string
  enabled?: boolean
  error?: string
  notes?: string
}

export interface DshState {
  current?: string
  phase?: string
  latest?: string
  installed?: string
  verified?: string
  available?: boolean
  blockedBy?: string
  error?: string
}

export interface DiagnosticsEntry {
  time?: number
  level?: string
  source?: string
  text?: string
}

export interface DiagnosticsView {
  total?: number
  entries?: DiagnosticsEntry[]
}

export interface UpdateCheckReply {
  current?: string
  update?: UpdateState | null
  dsh?: DshState | null
}
