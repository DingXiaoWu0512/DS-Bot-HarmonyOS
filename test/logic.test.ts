// Ported unit tests: settled helpers, i18n, work phrases, optimistic updates,
// open-chat navigation model, markdown subset, deep-view formula engine.
import assert from 'node:assert/strict'
import { test } from 'node:test'

import { cleanPreview, handoffTitleOf, relayReplyText, roundEventText, settledQuestionPicks, stripLongNote, keysOf, keepSame, sameMessage } from '../entry/src/main/ets/common/team/chat-state.ts'
import { setLang, weekdayShort, t, clockLabel } from '../entry/src/main/ets/common/ui/i18n.ts'
import { workPhrase } from '../entry/src/main/ets/common/ui/phrases.ts'
import { optimistic, withWrites, OPTIMISTIC } from '../entry/src/main/ets/common/team/optimistic.ts'
import type { TeamState, ChatItem } from '../entry/src/main/ets/common/team/types.ts'
import { compileFormula, createScope, evaluate, show } from '../entry/src/main/ets/common/deepview/formula.ts'
import { validateViewAnswer, viewAnswerText, choiceValue } from '../entry/src/main/ets/common/deepview/views-core.ts'
import { lexer, type MdToken } from '../entry/src/main/ets/common/markdown/markdown.ts'

test('settledQuestionPicks preserves option letters and custom slot from host answer item', () => {
  // Exact shape emitted by ds-bot/src/host/parts.js displayItems for kind: 'answer' (ask_user)
  const answerItem: ChatItem = {
    kind: 'answer',
    at: 1794466440000,
    questions: [{
      id: 'q1',
      question: '从哪里开始?',
      options: [
        { label: '读 AGENTS.md, 公开仓 AGENTS.md, CONTRIBUTING.md' },
        { label: '先看线上 CI 状态' },
        { label: '直接检查发版脚本' },
      ],
      multiSelect: false,
    }],
    answers: [{ id: 'q1', selected: ['先看线上 CI 状态'], custom: '顺便看 release.yml' }],
  }
  const picks = settledQuestionPicks((answerItem.questions ?? [])[0], (answerItem.answers ?? [])[0])
  assert.deepEqual(picks, [
    { label: '先看线上 CI 状态', letter: 'B' },
    { label: '顺便看 release.yml', letter: 'D' },
  ])
})

test('handoffTitleOf decodes host browser_handoff answer reasons in both languages', () => {
  setLang('zh')
  assert.equal(handoffTitleOf('verification'), '需要验证')
  assert.equal(handoffTitleOf('confirmation'), '需要确认')
  assert.equal(handoffTitleOf('other'), '请接手浏览器')
  setLang('en')
  assert.equal(handoffTitleOf('verification'), 'Verification needed')
  assert.equal(handoffTitleOf('confirmation'), 'Confirmation needed')
  assert.equal(handoffTitleOf('other'), 'Your turn in the browser')
  setLang('system')
})

test('workPhrase and weekdayShort localize tool activity and schedule weekdays', () => {
  setLang('zh')
  assert.equal(workPhrase({ tool: 'run_shell_command', target: 'npm test' }), '运行命令 · npm test')
  assert.equal(weekdayShort(1), '一')
  assert.equal(weekdayShort(7), '日')

  setLang('en')
  assert.equal(workPhrase({ tool: 'run_shell_command', target: 'npm test' }), 'Running shell commands · npm test')
  assert.equal(weekdayShort(1), 'Mon')
  assert.equal(weekdayShort(7), 'Sun')
  setLang('system')
})

test('stripLongNote preserves leading indentation and relayReplyText decodes archived host relay items', () => {
  const raw = '[A long message: 24810 characters. The full text is attached in message.txt.]\n第一段正文'
  assert.equal(stripLongNote(raw), '第一段正文')
  const indented = '[A long message: 24810 characters. The full text is attached in message.txt.]\n    const x = 1'
  assert.equal(stripLongNote(indented), '    const x = 1')

  setLang('zh')
  assert.equal(roundEventText('Beacon', 'done'), 'Beacon 做完了')
  assert.equal(roundEventText('Beacon', 'stopped'), '你停下了 Beacon 的工作')
  assert.equal(relayReplyText({ kind: 'failed', name: 'Beacon', text: '额度用尽' }), 'Beacon 无法回答：额度用尽')
  assert.equal(relayReplyText({ kind: 'admin-passed', name: 'Beacon' }), 'Beacon 没有回答，也没有叫谁；用 @名字 叫一个成员来回答')
  assert.equal(relayReplyText({ kind: 'paused', idle: true, name: 'Beacon', names: ['Coder'], count: 6 }), 'Beacon、Coder 来回 6 次没有进展，先停下了。你发言后继续')
  assert.equal(cleanPreview('[Browser handoff] verification — 完成 GitHub 两步验证\nAnswer: done'), '需要验证 · 完成 GitHub 两步验证')
  assert.equal(cleanPreview('[Answer to question card] 从哪里开始?\nAnswer: 读 AGENTS.md'), '读 AGENTS.md')
  setLang('system')
})

test('mobile-only strings translate while the desktop dictionary backs the rest', () => {
  setLang('zh')
  assert.equal(t('Pair with your computer'), '与电脑配对')
  assert.equal(t('Needs you'), '等你处理')
  assert.equal(t('Main Bot'), '主 Bot')
  assert.equal(t('Today {time}', { time: '9:00' }), '今天 9:00')
  assert.equal(t('This string is missing everywhere'), 'This string is missing everywhere')
  // The desktop's sense of "New" does not leak into the phone's badge.
  assert.equal(t('New'), '新建')
  assert.equal(t('{count} entries', { count: 3 }), '3 条')
  setLang('en')
  assert.equal(t('Needs you'), 'Needs you')
  setLang('system')
})

test('clockLabel builds timestamps by hand in both languages', () => {
  const past = new Date(Date.now() - 3 * 86400000)
  const noon = new Date(past.getFullYear(), past.getMonth(), past.getDate(), 12, 5).getTime()
  setLang('zh')
  assert.match(clockLabel(noon), /^[0-9]+月[0-9]+日 周[一二三四五六日] 12:05$/)
  setLang('en')
  assert.match(clockLabel(noon), /^(Sun|Mon|Tue|Wed|Thu|Fri|Sat), (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) [0-9]+ 12:05$/)
  setLang('system')
})

// ---- chat rows ------------------------------------------------------------

test('keysOf stay stable across page loads and dedupe repeated rows', () => {
  const items: ChatItem[] = [
    { kind: 'user', text: 'a', seq: 1 },
    { kind: 'bot', text: 'b', seq: 2 },
    { kind: 'bot', text: 'b2', seq: 2 },
    { kind: 'divider', time: 100 },
  ]
  const keys = keysOf(items)
  assert.deepEqual(keys, ['user-1', 'bot-2', 'bot-2#1', 'divider-100'])
  const local: ChatItem[] = [{ kind: 'user', text: 'x', localId: 'abc' }]
  assert.deepEqual(keysOf(local), ['local-abc'])
})

test('keepSame reuses unchanged item objects across refreshes', () => {
  const a: ChatItem = { kind: 'user', text: 'a', seq: 1 }
  const b: ChatItem = { kind: 'bot', text: 'b', seq: 2 }
  const next: ChatItem = { kind: 'bot', text: 'b', seq: 2 }
  const merged = keepSame([a, b], [a, next])
  assert.equal(merged[0], a)
  assert.equal(merged[1], b) // reused, since deep-equal
  const changed = keepSame([a], [{ kind: 'user', text: 'changed', seq: 1 }])
  assert.notEqual(changed[0], a)
})

test('sameMessage matches a sent message by trimmed text and photo count', () => {
  const sent: ChatItem = { kind: 'user', text: ' hello ', localImages: ['a', 'b'] }
  assert.equal(sameMessage({ kind: 'user', text: 'hello', imageRefs: [{ attachmentId: '1' }, { attachmentId: '2' }] }, sent), true)
  assert.equal(sameMessage({ kind: 'user', text: 'hello', imageRefs: [{ attachmentId: '1' }] }, sent), false)
  assert.equal(sameMessage({ kind: 'bot', text: 'hello' }, sent), false)
})

// ---- optimistic updates ----------------------------------------------------

function teamFixture(): TeamState {
  return {
    revision: 5,
    bots: [
      { id: 'b1', name: 'Chief', effort: 'high', workDir: '/work' },
      { id: 'b2', name: 'Writer', capabilities: ['Read files'] },
    ],
    rooms: [{ id: 'r1', name: 'Launch', notice: '' }],
    mainBotIds: ['b1'],
    mainBotId: 'b1',
  }
}

test('optimistic update-bot applies the patch and clears null/empty fields', () => {
  const team = teamFixture()
  const next = optimistic(team, 'update-bot', { id: 'b1', effort: null, workDir: '', name: 'Boss' })
  assert.equal(next?.bots[0]?.name, 'Boss')
  assert.equal('effort' in (next?.bots[0] ?? {}), false)
  assert.equal('workDir' in (next?.bots[0] ?? {}), false)
  assert.equal(next?.bots[1]?.name, 'Writer')
})

test('optimistic set-main toggles the main list', () => {
  const team = teamFixture()
  const next = optimistic(team, 'set-main', { id: 'b2', main: true })
  assert.deepEqual(next?.mainBotIds, ['b1', 'b2'])
  const off = optimistic(next, 'set-main', { id: 'b1', main: false })
  assert.deepEqual(off?.mainBotIds, ['b2'])
  assert.equal(off?.mainBotId, 'b2')
})

test('optimistic bot-capability attaches and detaches', () => {
  const team = teamFixture()
  const on = optimistic(team, 'bot-capability', { botId: 'b2', name: 'Run shell commands', attached: true })
  assert.deepEqual(on?.bots[1]?.capabilities, ['Read files', 'Run shell commands'])
  const off = optimistic(on, 'bot-capability', { botId: 'b2', name: 'Read files', attached: false })
  assert.deepEqual(off?.bots[1]?.capabilities, ['Run shell commands'])
})

test('optimistic update-room patches a group; withWrites lays writes over reads', () => {
  const team = teamFixture()
  const next = optimistic(team, 'update-room', { id: 'r1', notice: 'Ship it' })
  assert.equal(next?.rooms?.[0]?.notice, 'Ship it')
  assert.ok(OPTIMISTIC.has('update-room'))
  const writes = [{ endpoint: 'update-bot', payload: { id: 'b2', name: 'Prose' } }]
  const after = withWrites(team, writes)
  assert.equal(after.bots[1]?.name, 'Prose')
})

// ---- formula engine --------------------------------------------------------

test('compileFormula matches deep-view on expressions and errors', () => {
  const compiled = compileFormula('min(3, 2) * 2')
  assert.ok('tree' in compiled)
  if ('tree' in compiled) assert.deepEqual(compiled.names, [])
  const names = compileFormula('price * qty + tax')
  assert.ok('tree' in names)
  if ('tree' in names) assert.deepEqual(names.names.sort(), ['price', 'qty', 'tax'].sort())
  assert.ok('error' in compileFormula('price +'))
  assert.ok('error' in compileFormula('unknownFn(1)'))
})

test('formula evaluation covers the function set, ternaries and strings', () => {
  const lookup = (name: string): unknown => ({ price: 10, qty: 3, title: 'Re' })[name]
  const run = (source: string): unknown => {
    const compiled = compileFormula(source)
    if (!('tree' in compiled)) throw new Error(compiled.error)
    const result = evaluate(compiled.tree, lookup)
    if ('error' in result) throw new Error(result.error)
    return result.value
  }
  assert.equal(run('price * qty'), 30)
  assert.equal(run('price > 5 ? "yes" : "no"'), 'yes')
  assert.equal(run('clamp(20, 0, 10)'), 10)
  assert.equal(run('format(1234567.5, 2)'), '1,234,567.50')
  assert.equal(run('percent(0.25)'), '25%')
  assert.equal(run('title + "lease"'), 'Release')
  assert.equal(run('round(2.345, 2)'), 2.35)
  assert.equal(show(0.1 + 0.2), '0.3')
  assert.throws(() => run('missing + 1'))
})

test('createScope resolves let names and detects cycles', () => {
  const inputs = new Map<string, unknown>([['base', 10]])
  const compiled = compileFormula('base * 2')
  if (!('tree' in compiled)) throw new Error('parse')
  const compiledB = compileFormula('a + 1')
  if (!('tree' in compiledB)) throw new Error('parse')
  const scope = createScope(inputs, new Map([['a', compiled.tree], ['b', compiledB.tree]]))
  const evalA = evaluate(compiledB.tree, scope)
  assert.equal('value' in evalA ? evalA.value : undefined, 21)
  const selfRef = compileFormula('c + 1')
  if ('tree' in selfRef) {
    const scope2 = createScope(new Map(), new Map([['c', selfRef.tree]]))
    const out = evaluate(selfRef.tree, scope2)
    assert.ok('error' in out)
  }
})

// ---- view validation --------------------------------------------------------

const view = {
  type: 'stack',
  children: [
    { type: 'metric', label: 'Reviews', value: 18 },
    { type: 'slider', id: 'days', label: 'Days', min: 1, max: 14, step: 1, value: 5 },
    { type: 'options', id: 'a-1', options: [{ label: 'Ship Friday' }, { label: 'Hold' }] },
    { type: 'confirm', id: 'c-1', confirmLabel: 'Go', cancelLabel: 'Stop' },
    { type: 'form', id: 'f-1', fields: [{ id: 'note', label: 'Note' }] },
    { type: 'submit', id: 's-1', label: 'Send' },
    { type: 'toggle', id: 't-1', label: 'On', value: false },
    { type: 'choice', id: 'ch-1', label: 'Pick', options: [{ label: 'One' }, { label: 'Two' }] },
  ],
}

test('validateViewAnswer matches deep-view for every interactive component', () => {
  assert.deepEqual(validateViewAnswer(view, 'a-1', { selected: ['Ship Friday'] }), { answer: { selected: ['Ship Friday'], inputs: { days: 5, 't-1': false, 'ch-1': 'One' } } })
  assert.deepEqual(validateViewAnswer(view, 'a-1', { selected: ['Ship Friday', 'Hold'] }), { answer: { selected: ['Ship Friday'], inputs: { days: 5, 't-1': false, 'ch-1': 'One' } } })
  assert.ok(validateViewAnswer(view, 'a-1', { selected: ['Nope'] }).error !== undefined)
  assert.deepEqual(validateViewAnswer(view, 'c-1', { confirmed: true }), { answer: { confirmed: true, inputs: { days: 5, 't-1': false, 'ch-1': 'One' } } })
  assert.ok(validateViewAnswer(view, 'c-1', {}).error !== undefined)
  assert.deepEqual(validateViewAnswer(view, 'f-1', { fields: { note: 'ok' } }), { answer: { fields: { note: 'ok' }, inputs: { days: 5, 't-1': false, 'ch-1': 'One' } } })
  assert.ok(validateViewAnswer(view, 'f-1', { fields: { nope: 'x' } }).error !== undefined)
  assert.deepEqual(validateViewAnswer(view, 's-1', {}), { answer: { inputs: { days: 5, 't-1': false, 'ch-1': 'One' } } })
  assert.ok(validateViewAnswer(view, 'nope', {}).error !== undefined)
  assert.ok(validateViewAnswer(view, '', {}).error !== undefined)
  // Inputs ride along and are validated.
  assert.ok(validateViewAnswer(view, 's-1', { inputs: { days: 3 } }).answer !== undefined)
  assert.ok(validateViewAnswer(view, 's-1', { inputs: { days: 40 } }).error !== undefined)
  assert.ok(validateViewAnswer(view, 's-1', { inputs: { 't-1': true } }).answer !== undefined)
  assert.ok(validateViewAnswer(view, 's-1', { inputs: { 'ch-1': 'One' } }).answer !== undefined)
  assert.ok(validateViewAnswer(view, 's-1', { inputs: { unknown: 1 } }).error !== undefined)
  // The demo fixture answers exactly this shape.
  assert.equal(typeof viewAnswerText(view, { action: 'c-1', values: { confirmed: true } }), 'string')
})

test('choiceValue resolves labels from string or object options', () => {
  assert.equal(choiceValue('One'), 'One')
  assert.equal(choiceValue({ label: 'One' }), 'One')
  assert.equal(choiceValue({ value: 1, label: 'One' }), 1)
})

// ---- markdown subset ---------------------------------------------------------

test('markdown lexer covers the blocks the chat renders', () => {
  const tokens = lexer('# Title\n\nPara with `code`.\n\n```ts\nconst a = 1\n```\n\n- item one\n- item two\n\n| A | B |\n|---|---|\n| 1 | 2 |\n')
  const kinds = tokens.filter(token => token.type !== 'space').map(token => token.type)
  assert.deepEqual(kinds, ['heading', 'paragraph', 'code', 'list', 'table'])
  const list = tokens.find(token => token.type === 'list') as Extract<MdToken, { type: 'list' }>
  assert.equal(list.items?.length, 2)
  const table = tokens.find(token => token.type === 'table') as Extract<MdToken, { type: 'table' }>
  assert.equal(table.header?.length, 2)
  assert.equal(table.rows?.length, 1)
})

test('markdown handles blockquotes, nested lists and rules', () => {
  const tokens = lexer('> quoted\n> more\n\n1. one\n2. two\n\n---\n')
  assert.deepEqual(tokens.filter(token => token.type !== 'space').map(token => token.type), ['blockquote', 'list', 'hr'])
  const quote = tokens[0] as Extract<MdToken, { type: 'blockquote' }>
  assert.equal(quote.tokens?.length, 1)
})

test('inline tokens cover strong, em, links and images', () => {
  const tokens = lexer('See **this** and *that* and [x](https://a.b) and ![y](https://i.j)')
  const paragraph = tokens[0] as Extract<MdToken, { type: 'paragraph' }>
  const kinds = (paragraph.tokens ?? []).map(token => token.type)
  assert.ok(kinds.includes('strong'))
  assert.ok(kinds.includes('em'))
  assert.ok(kinds.includes('link'))
  assert.ok(kinds.includes('image'))
})
