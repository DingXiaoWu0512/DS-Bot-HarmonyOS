// Markdown in Bot text: a CommonMark-subset lexer with the same token kinds the
// RN build takes from `marked` — headings, paragraphs, fenced code, nested lists,
// blockquotes, tables, rules — and the inline tokens strong/em/codespan/link/del/
// br/image. Tables and fenced code scroll horizontally in the bubble view.
export interface MdToken {
  type: 'heading' | 'paragraph' | 'code' | 'list' | 'blockquote' | 'table' | 'hr' | 'space' | 'text' | 'html'
  depth?: number
  text?: string
  raw?: string
  lang?: string
  ordered?: boolean
  start?: number
  items?: MdListItem[]
  tokens?: MdToken[]
  inline?: InlineToken[]
  header?: MdToken[]
  rows?: MdToken[][]
}

/** One list item: its block tokens and, for task items, the checkbox state. */
export interface MdListItem {
  tokens: MdToken[]
  task?: boolean
  checked?: boolean
}

export interface InlineToken {
  type: 'text' | 'strong' | 'em' | 'codespan' | 'link' | 'del' | 'br' | 'image' | 'escape'
  text?: string
  href?: string
  tokens?: InlineToken[]
  raw?: string
}

// Any non-whitespace char can anchor an emphasis run — CJK included, matching
// marked (the RN reference parser): "**加粗**" must parse, not stay literal.
const ANCHOR = /\S/

// Block-level lexing, line by line, close to marked's block rules for the subset.
function lexBlocks(src: string, depth = 0): MdToken[] {
  const lines = src.replace(/\r\n?/g, '\n').split('\n')
  const tokens: MdToken[] = []
  let at = 0
  while (at < lines.length) {
    const line = lines[at]!
    const trimmedStart = line.trimStart()
    // Fenced code.
    const fence = /^ {0,3}(`{3,}|~{3,})\s*([^`]*)$/.exec(line)
    if (fence !== null) {
      const marker = fence[1]!.charAt(0).repeat(3)
      const lang = (fence[2] ?? '').trim()
      const body: string[] = []
      at += 1
      while (at < lines.length) {
        const closing = /^ {0,3}(`{3,}|~{3,})\s*$/.exec(lines[at] ?? '')
        if (closing !== null && (closing[1] ?? '').charAt(0) === marker.charAt(0)) {
          at += 1
          break
        }
        body.push(lines[at] ?? '')
        at += 1
      }
      tokens.push({ type: 'code', text: body.join('\n'), lang, raw: body.join('\n') })
      continue
    }
    // Horizontal rule.
    if (/^ {0,3}((?:\*[ \t]*){3,}|(?:-[ \t]*){3,}|(?:_[ \t]*){3,})$/.test(line)) {
      tokens.push({ type: 'hr' })
      at += 1
      continue
    }
    // Heading.
    const heading = /^(#{1,6})\s+(.*?)\s*#*\s*$/.exec(line)
    if (heading !== null) {
      tokens.push({ type: 'heading', depth: heading[1]!.length, text: heading[2] ?? '', inline: lexInline(heading[2] ?? '') })
      at += 1
      continue
    }
    // Blockquote: collect consecutive > lines, strip the markers, recurse.
    if (/^ {0,3}>/.test(line)) {
      const body: string[] = []
      while (at < lines.length && /^ {0,3}>/.test(lines[at] ?? '')) {
        body.push((lines[at] ?? '').replace(/^ {0,3}> ?/, ''))
        at += 1
      }
      tokens.push({ type: 'blockquote', tokens: lexBlocks(body.join('\n'), depth + 1) })
      continue
    }
    // Table: a header row with at least two cells and a |, then a delimiter row.
    const tableHeader = /^\s*\|?([^|]*\|.+)\|?\s*$/.exec(line)
    if (tableHeader !== null && at + 1 < lines.length && /^ {0,3}\|?[\s:|-]+\|[\s:|-]*$/.test(lines[at + 1] ?? '')) {
      const cells = (row: string): string[] =>
        row.replace(/^\s*\|/, '').replace(/\|\s*$/, '').split('|').map(cell => cell.trim())
      const header = cells(line).map(cell => ({ type: 'text' as const, text: cell, inline: lexInline(cell) }))
      const aligns = cells(lines[at + 1] ?? '')
      at += 2
      const rows: MdToken[][] = []
      while (at < lines.length && lines[at] !== undefined && lines[at]!.includes('|') && (lines[at] ?? '').trim() !== '') {
        rows.push(cells(lines[at] ?? '').map(cell => ({ type: 'text' as const, text: cell, inline: lexInline(cell) })))
        at += 1
      }
      void aligns
      tokens.push({ type: 'table', header, rows })
      continue
    }
    // List: items starting with - * + or digit.
    const bullet = /^([ \t]*)([-*+])\s+/
    const ordered = /^([ \t]*)(\d{1,9})[.)]\s+/
    const listMatch = bullet.exec(line) ?? ordered.exec(line)
    if (listMatch !== null && depth < 8) {
      const isOrdered = ordered.exec(line) !== null
      const indent = listMatch[1] ?? ''
      const itemIndent = indent.length
      const items: MdListItem[] = []
      let startNumber = isOrdered ? Number(ordered.exec(line)![2]) : 1
      while (at < lines.length) {
        const current = lines[at] ?? ''
        const m = bullet.exec(current) ?? ordered.exec(current)
        if (m === null || (m[1] ?? '').length !== itemIndent) break
        if (bullet.test(current) && isOrdered) break
        if (ordered.test(current) && !isOrdered) break
        const first = current.slice((m[1] ?? '').length + (m[2] ?? '').length + 1)
        const bodyLines = [first]
        // Task item: a "[ ] "/"[x] " prefix on the first line. The prefix is
        // stripped here so the body lexes clean and only the marker shows it.
        const taskPrefix = /^\[([ xX])\] /.exec(first)
        const task = taskPrefix !== null
        const checked = taskPrefix !== null && (taskPrefix[1] ?? ' ') !== ' '
        if (taskPrefix !== null) bodyLines[0] = first.slice(4)
        at += 1
        while (at < lines.length) {
          const next = lines[at] ?? ''
          const contentCol = itemIndent + (m[2] ?? '').length + 1
          if (next.trim() === '') {
            // A blank line ends the list unless the next line continues the
            // item: another list marker, or any non-blank line indented to
            // the item's content column (a loose item's paragraphs).
            const after = at + 1 < lines.length ? lines[at + 1] ?? '' : ''
            const afterList = bullet.exec(after) ?? ordered.exec(after)
            const afterIndent = (after.match(/^[ \t]*/) ?? [''])[0].length
            if (after.trim() !== '' && (afterList !== null || afterIndent >= contentCol)) {
              bodyLines.push('')
              at += 1
              continue
            }
            break
          }
          const nextList = bullet.exec(next) ?? ordered.exec(next)
          if (nextList !== null && (nextList[1] ?? '').length <= itemIndent) break
          if (nextList !== null && (nextList[1] ?? '').length >= contentCol) {
            // A nested list marker keeps its relative indent: strip only the
            // item's own indent so the marker line becomes a nested list in
            // the recursive lexBlocks, not a flattened sibling.
            bodyLines.push(next.slice(itemIndent))
            at += 1
            continue
          }
          // Continuation lines keep the item's text indent.
          const strip = Math.min(contentCol, next.length)
          bodyLines.push(next.length > strip && /^\s/.test(next) ? next.slice(strip) : next.replace(/^[ \t]+/, ''))
          at += 1
        }
        items.push({ tokens: lexBlocks(bodyLines.join('\n'), depth + 1).filter(token => token.type !== 'space'), task, checked })
      }
      tokens.push({ type: 'list', ordered: isOrdered, start: startNumber, items })
      void startNumber
      continue
    }
    // Blank lines group into space tokens.
    if (line.trim() === '') {
      while (at < lines.length && (lines[at] ?? '').trim() === '') at += 1
      tokens.push({ type: 'space' })
      continue
    }
    // HTML-ish block: pass through as text.
    if (/^ {0,3}</.test(line)) {
      const body: string[] = []
      while (at < lines.length && (lines[at] ?? '').trim() !== '') {
        body.push(lines[at] ?? '')
        at += 1
      }
      tokens.push({ type: 'html', text: body.join('\n'), raw: body.join('\n') })
      continue
    }
    // Paragraph: until a blank line or a block start.
    const body: string[] = []
    let setextDepth = 0
    while (at < lines.length) {
      const current = lines[at] ?? ''
      // A Setext underline (= or -) turns the collected lines into a heading;
      // it must be checked before the hr rule so "Foo\n---" is a heading,
      // not a paragraph plus a rule (marked's behavior).
      if (body.length > 0) {
        if (/^ {0,3}=+\s*$/.test(current)) {
          setextDepth = 1
          at += 1
          break
        }
        if (/^ {0,3}-{2,}\s*$/.test(current)) {
          setextDepth = 2
          at += 1
          break
        }
      }
      if (current.trim() === '') break
      if (/^(#{1,6})\s+/.test(current)) break
      if (/^ {0,3}(`{3,}|~{3,})/.test(current)) break
      if (/^ {0,3}>/.test(current)) break
      if (/^ {0,3}((?:\*[ \t]*){3,}|(?:-[ \t]*){3,}|(?:_[ \t]*){3,})$/.test(current)) break
      // A list marker line interrupts the paragraph (marked's behavior):
      // a bullet marker always, an ordered marker only when it starts at 1.
      const orderedBreak = /^[ \t]*(\d{1,9})[.)]\s+\S/.exec(current)
      if (/^[ \t]*[-*+]\s+\S/.test(current) || (orderedBreak !== null && Number(orderedBreak[1]) === 1)) break
      // A table header glued to the paragraph (no blank line before it) starts
      // a table when the next line is its delimiter row: stop so the table
      // branch consumes the header instead of stranding the delimiter row.
      if (current.includes('|') && at + 1 < lines.length
        && /^ {0,3}\|?[\s:|-]+\|[\s:|-]*$/.test(lines[at + 1] ?? '')) break
      if (at > 0 || body.length > 0) {
        if (/^ {0,3}\|?[\s:|-]+\|[\s:|-]*$/.test(current)) break
      }
      body.push(current)
      at += 1
    }
    if (setextDepth > 0) {
      const text = body.join('\n')
      tokens.push({ type: 'heading', depth: setextDepth, text, inline: lexInline(text) })
      continue
    }
    if (body.length > 0) {
      const text = body.join('\n')
      tokens.push({ type: 'paragraph', text, inline: lexInline(text) })
    } else {
      // Safety net: a line no block rule consumed must not strand the lexer
      // in a zero-progress loop. Emit it as a plain paragraph and move on.
      tokens.push({ type: 'paragraph', text: line, inline: lexInline(line) })
      at += 1
    }
  }
  return tokens
}

// Inline lexing: code spans first, then emphasis, links, images, del, br.
function lexInline(src: string): InlineToken[] {
  const tokens: InlineToken[] = []
  let text = ''
  let at = 0
  const flush = (): void => {
    if (text !== '') {
      tokens.push({ type: 'text', text })
      text = ''
    }
  }
  while (at < src.length) {
    const char = src.charAt(at)
    if (char === '`') {
      // A code span runs to the next backtick run of the same length.
      const opening = /^`+/.exec(src.slice(at))!
      const tick = opening[0]
      const closeAt = src.indexOf(tick, at + tick.length)
      if (closeAt !== -1) {
        flush()
        const code = src.slice(at + tick.length, closeAt)
        tokens.push({ type: 'codespan', text: code.replace(/^ | $/g, '') })
        at = closeAt + tick.length
        continue
      }
    }
    if (char === '!' && src.charAt(at + 1) === '[') {
      const image = /^!\[([^\]]*)\]\(([^)\s]+)(?:\s+"([^"]*)")?\)/.exec(src.slice(at))
      if (image !== null) {
        flush()
        tokens.push({ type: 'image', text: image[1] ?? '', href: image[2] })
        at += image[0].length
        continue
      }
    }
    if (char === '[') {
      const link = /^\[([^\]]*)\]\(([^)\s]+)(?:\s+"([^"]*)")?\)/.exec(src.slice(at))
      if (link !== null) {
        flush()
        tokens.push({ type: 'link', text: link[1] ?? '', href: link[2], tokens: lexInline(link[1] ?? '') })
        at += link[0].length
        continue
      }
    }
    if (char === '*' || char === '_') {
      // A `_` emphasis run never opens right after a word character, so
      // my_var_name stays literal; `*` keeps allowing intraword runs.
      const intraword = char === '_'
      const before = at > 0 ? src.charAt(at - 1) : ''
      if (!intraword || !/[0-9A-Za-z]/.test(before)) {
        const marker = char.repeat(2)
        const closeAt = src.indexOf(marker, at + 2)
        // Both ends must anchor on non-whitespace and the content must be
        // non-empty; a `_` run also never closes right before a word char.
        if (closeAt > at + 2 && ANCHOR.test(src.charAt(at + 2) || ' ') && ANCHOR.test(src.charAt(closeAt - 1) || ' ')
          && (!intraword || !/[0-9A-Za-z]/.test(src.charAt(closeAt + 2)))) {
          flush()
          const inner = src.slice(at + 2, closeAt)
          tokens.push({ type: 'strong', text: inner, tokens: lexInline(inner) })
          at = closeAt + 2
          continue
        }
        const closeSingle = src.indexOf(char, at + 1)
        if (closeSingle > at + 1 && ANCHOR.test(src.charAt(at + 1) || ' ') && ANCHOR.test(src.charAt(closeSingle - 1) || ' ')
          && (!intraword || !/[0-9A-Za-z]/.test(src.charAt(closeSingle + 1)))) {
          flush()
          const inner = src.slice(at + 1, closeSingle)
          tokens.push({ type: 'em', text: inner, tokens: lexInline(inner) })
          at = closeSingle + 1
          continue
        }
      }
    }
    if (char === '~' && src.charAt(at + 1) === '~') {
      const closeAt = src.indexOf('~~', at + 2)
      if (closeAt !== -1) {
        flush()
        const inner = src.slice(at + 2, closeAt)
        tokens.push({ type: 'del', text: inner, tokens: lexInline(inner) })
        at = closeAt + 2
        continue
      }
    }
    if (char === '\\' && src.charAt(at + 1) === '\n') {
      flush()
      tokens.push({ type: 'br' })
      at += 2
      continue
    }
    if (char === '\\' && /[!`[\]()_*~\\]/.test(src.charAt(at + 1) || '')) {
      text += src.charAt(at + 1)
      at += 2
      continue
    }
    if (char === '\n') {
      // Two or more trailing spaces make a hard break; a lone newline inside
      // a paragraph stays in the text token and renders as a real line break
      // on the phone (normalizeSoftBreaks keeps it).
      if (/ {2,}$/.test(text)) {
        text = text.replace(/ +$/, '')
        flush()
        tokens.push({ type: 'br' })
      } else {
        text += '\n'
      }
      at += 1
      continue
    }
    text += char
    at += 1
  }
  flush()
  return tokens
}

/** The block tokens of one markdown text. */
export function lexer(text: string): MdToken[] {
  return lexBlocks(text)
}
