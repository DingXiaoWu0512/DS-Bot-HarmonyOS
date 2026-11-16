// What a Bot is doing, worded like the desktop's workPhrase. Port of phrases.ts.
import { t } from './i18n.ts'

export interface DoingState {
  tool?: string
  said?: string
  note?: string
  target?: string
  switching?: boolean
  folder?: boolean
}

const TOOL_PHRASES: [RegExp, string][] = [
  [/web_?search|search_?web/i, 'Searching online'],
  [/fetch|browse|browser|web/i, 'Reading a page'],
  [/shell|bash|pwsh|powershell|exec|command|terminal/i, 'Running shell commands'],
  [/^(read|view|cat)\b|read_/i, 'Opening a file'],
  [/write|edit|patch|create_file/i, 'Writing a file'],
  [/recall|memory|remember/i, 'Checking memory'],
]

export function workPhrase(doing: DoingState | string | undefined): string {
  const parts: DoingState = typeof doing === 'string' ? { tool: doing } : (doing ?? {})
  const { tool, said, note, target, switching, folder } = parts
  if (switching === true) return folder === true ? t('Switching working folder') : t('Moving to a fresh conversation')
  const own = (said || note || '').replace(/[\s.。…]+$/u, '')
  if (own !== '') return own
  if (tool === undefined || tool === '') return t('Thinking about it')
  const matched = TOOL_PHRASES.find(([pattern]) => pattern.test(tool))
  const label = matched !== undefined ? t(matched[1]) : t('On it')
  return target !== undefined && target !== '' ? `${label} · ${target}` : label
}
