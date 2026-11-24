// Inline style flattening for Bot text: the RN build renders inline emphasis
// by nesting <Text> inside <Text>, while ArkUI's Text only takes Span/
// ImageSpan/ContainerSpan children. The inline token tree is flattened here,
// pure data, into a run list the renderer turns into one Span sequence.
// Subtrees nested past INLINE_DEPTH fall back to their literal text so no
// character is ever lost.

import { type InlineToken } from './markdown'

/** One flattened inline run: literal text plus the style flags of its ancestors. */
export interface StyledRun {
  text: string
  bold?: boolean
  italic?: boolean
  strike?: boolean
  mono?: boolean
  href?: string
  muted?: boolean
}

/** Inline emphasis can nest; deeper than this renders as plain text. */
export const INLINE_DEPTH: number = 6

/** The accumulated ancestor style while walking the inline token tree. */
interface RunStyle {
  bold: boolean
  italic: boolean
  strike: boolean
  href: string | undefined
}

function endsHan(token: InlineToken | undefined): boolean {
  const text: string | undefined = token?.text
  return text !== undefined && /[\u4e00-\u9fff]$/.test(text)
}

function startsHan(token: InlineToken | undefined): boolean {
  const text: string | undefined = token?.text
  return text !== undefined && /^[\u4e00-\u9fff]/.test(text)
}

class RunFlattener {
  readonly runs: StyledRun[] = []

  private sameStyle(a: StyledRun, b: StyledRun): boolean {
    return a.bold === b.bold && a.italic === b.italic && a.strike === b.strike
      && a.mono === b.mono && a.muted === b.muted && a.href === b.href
  }

  push(text: string, style: RunStyle, mono: boolean, muted: boolean): void {
    const run: StyledRun = { text, bold: style.bold, italic: style.italic, strike: style.strike, mono }
    if (muted) run.muted = true
    if (style.href !== undefined) run.href = style.href
    // Adjacent runs with identical flags merge into one Span; an empty run
    // (a muted image with no alt) stays separate so the renderer can fill
    // in its fallback label.
    if (text !== '') {
      const last: StyledRun | undefined = this.runs.length > 0 ? this.runs[this.runs.length - 1] : undefined
      if (last !== undefined && this.sameStyle(last, run)) {
        last.text += text
        return
      }
    }
    this.runs.push(run)
  }

  walk(tokens: InlineToken[], style: RunStyle, depth: number): void {
    for (let index = 0; index < tokens.length; index++) {
      const token: InlineToken = tokens[index] ?? { type: 'text', text: '' }
      if (token.type === 'strong' || token.type === 'em' || token.type === 'del' || token.type === 'link') {
        if (depth >= INLINE_DEPTH) {
          // Too deep to keep nesting: the subtree's literal text still shows.
          this.push(token.text ?? '', style, false, false)
          continue
        }
        const next: RunStyle = {
          bold: style.bold || token.type === 'strong',
          italic: style.italic || token.type === 'em',
          strike: style.strike || token.type === 'del',
          href: token.type === 'link' ? token.href : style.href,
        }
        this.walk(token.tokens ?? [], next, depth + 1)
        continue
      }
      if (token.type === 'codespan') {
        // A hair-space keeps CJK glyphs from touching the mono box.
        const lead: string = endsHan(tokens[index - 1]) ? '\u2006' : ''
        const trail: string = startsHan(tokens[index + 1]) ? '\u2006' : ''
        this.push(`${lead}${token.text ?? ''}${trail}`, style, true, false)
        continue
      }
      if (token.type === 'br') {
        this.push('\n', style, false, false)
        continue
      }
      if (token.type === 'image') {
        // An image that cannot be lifted (heading, table cell) shows its alt.
        this.push(token.text ?? '', style, false, true)
        continue
      }
      // text and escape tokens contribute their literal text.
      this.push(token.text ?? '', style, false, false)
    }
  }
}

/** Flatten an inline token tree (pre-order) into styled text runs. */
export function flattenInlineRuns(tokens: InlineToken[]): StyledRun[] {
  const flattener = new RunFlattener()
  flattener.walk(tokens, { bold: false, italic: false, strike: false, href: undefined }, 0)
  return flattener.runs
}
