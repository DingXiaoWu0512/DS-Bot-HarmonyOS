// Markdown in Bot text: the ported lexer (common/markdown) walks the block
// tokens; each block maps to ArkUI nodes — headings, paragraphs, fenced code,
// nested lists, blockquotes, tables, rules — and the inline tokens render as
// Span/nested Text runs (strong/em/codespan/link/del/br/image). Tables and
// fenced code scroll horizontally. Line/code tints derive from the text color,
// so the same Markdown reads on the Bot's light bubble and the user's dark one.

import { Want, common } from '@kit.AbilityKit'

import { lexer, type InlineToken, type MdToken } from '../../common/markdown/markdown'
import { appStore, MONO, radius } from '../../components/Theme'

// A chat redraws its rows on every refresh and a streamed reply on every token,
// so each text is lexed once and the tokens are kept for the most recent texts.
const lexed: Map<string, MdToken[]> = new Map<string, MdToken[]>()
const LEXED_KEPT: number = 400

function tokensOf(text: string): MdToken[] {
  const kept: MdToken[] | undefined = lexed.get(text)
  if (kept !== undefined) return kept
  const tokens: MdToken[] = lexer(text)
  lexed.set(text, tokens)
  if (lexed.size > LEXED_KEPT) {
    for (const oldest of lexed.keys()) {
      lexed.delete(oldest)
      break
    }
  }
  return tokens
}

/** True when the text has a block that needs the bubble's full width to lay out. */
export function hasBlockContent(text: string): boolean {
  if (text === '') return false
  return tokensOf(text).some((token: MdToken): boolean =>
    token.type !== 'paragraph' && token.type !== 'text' && token.type !== 'space')
}

/** A translucent version of a color, for lines, fills and muted marks. */
export function tint(color: string, alpha: number): string {
  const hex: RegExpExecArray | null = /^#([0-9a-f]{6})$/i.exec(color)
  if (hex !== null) {
    const body: string = hex[1] ?? ''
    const r: number = parseInt(body.slice(0, 2), 16)
    const g: number = parseInt(body.slice(2, 4), 16)
    const b: number = parseInt(body.slice(4, 6), 16)
    return `rgba(${r},${g},${b},${alpha})`
  }
  const rgb: RegExpExecArray | null = /^rgba?\(([^)]+)\)$/i.exec(color)
  if (rgb !== null) {
    const parts: string[] = (rgb[1] ?? '').split(',').slice(0, 3)
    return `rgba(${parts.join(',')},${alpha})`
  }
  return color
}

/** Opens a web or mail link in the system; other schemes never fire. */
export function openExternalUrl(context: common.UIAbilityContext, href: string): void {
  if (!/^https?:/i.test(href) && !/^mailto:/i.test(href)) return
  void context.startAbility({
    action: 'ohos.want.action.viewData',
    uri: href,
  } as Want).catch((): void => {})
}

export interface MarkdownInk {
  text: string
  muted: string
  line: string
  fill: string
  bg: string
}

function endsHan(token: InlineToken | undefined): boolean {
  if (token === undefined) return false
  const text: string | undefined = token.text
  return text !== undefined && /[\u4e00-\u9fff]$/.test(text)
}

function startsHan(token: InlineToken | undefined): boolean {
  if (token === undefined) return false
  const text: string | undefined = token.text
  return text !== undefined && /^[\u4e00-\u9fff]/.test(text)
}

// Inline emphasis can nest; deeper than this renders as plain text.
const INLINE_DEPTH: number = 6

@ComponentV2
export struct MarkdownText {
  @Require @Param text: string
  @Require @Param textColor: string
  @Param fontSize: number = 16
  @Param lineHeight: number = 25
  @Param bg: string = ''

  blocks(): MdToken[] {
    return tokensOf(this.text).filter((token: MdToken): boolean => token.type !== 'space')
  }

  ink(): MarkdownInk {
    return {
      text: this.textColor,
      muted: tint(this.textColor, 0.48),
      line: tint(this.textColor, 0.14),
      fill: tint(this.textColor, 0.07),
      bg: this.bg !== '' ? this.bg : appStore.theme.p.bubble,
    }
  }

  build() {
    Column() {
      ForEach(this.blocks(), (token: MdToken, index: number) => {
        MarkdownBlock({
          token: token,
          ink: this.ink(),
          textColor: this.textColor,
          fontSize: this.fontSize,
          lineHeight: this.lineHeight,
          first: index === 0,
          last: index === this.blocks().length - 1,
          depth: 0,
        })
      }, (token: MdToken, index: number): string => `b-${index}`)
    }
    .alignItems(HorizontalAlign.Start)
  }
}

@ComponentV2
struct MarkdownBlock {
  @Require @Param token: MdToken
  @Require @Param ink: MarkdownInk
  @Require @Param textColor: string
  @Require @Param fontSize: number
  @Require @Param lineHeight: number
  @Param first: boolean = false
  @Param last: boolean = false
  @Param depth: number = 0

  topGap(gap: number): number {
    return this.first ? 0 : gap
  }

  bottomGap(gap: number): number {
    return this.last ? 0 : gap
  }

  innerTokens(): MdToken[] {
    const tokens: MdToken[] | undefined = this.token.tokens
    return (tokens ?? []).filter((token: MdToken): boolean => token.type !== 'space')
  }

  itemTokens(item: MdToken[]): MdToken[] {
    return item.filter((token: MdToken): boolean => token.type !== 'space')
  }

  headingSize(): number {
    const depth: number = this.token.depth ?? 1
    if (depth === 1) return this.fontSize + 4
    if (depth === 2) return this.fontSize + 2
    return this.fontSize + 1
  }

  safeHref(token: InlineToken): boolean {
    const href: string = token.href ?? ''
    return /^https?:/i.test(href) || /^mailto:/i.test(href)
  }

  openHref(token: InlineToken): void {
    const href: string = token.href ?? ''
    if (href === '') return
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    openExternalUrl(context, href)
  }

  inlineLead(tokens: InlineToken[], index: number): string {
    return endsHan(tokens[index - 1]) ? '\u2006' : ''
  }

  inlineTrail(tokens: InlineToken[], index: number): string {
    return startsHan(tokens[index + 1]) ? '\u2006' : ''
  }

  // One inline run: a Span for flat text, a nested Text for styled nesting.
  @Builder
  inlineRuns(tokens: InlineToken[], color: string, fs: number, depth: number) {
    ForEach(tokens, (token: InlineToken, index: number) => {
      if (token.type === 'strong') {
        Text() {
          if (depth < INLINE_DEPTH) {
            this.inlineRuns(token.tokens ?? [], color, fs, depth + 1)
          }
        }
        .fontWeight(600)
        .fontColor(color)
        .fontSize(fs)
      } else if (token.type === 'em') {
        Text() {
          if (depth < INLINE_DEPTH) {
            this.inlineRuns(token.tokens ?? [], color, fs, depth + 1)
          }
        }
        .fontStyle(FontStyle.Italic)
        .fontColor(color)
        .fontSize(fs)
      } else if (token.type === 'codespan') {
        Span(`${this.inlineLead(tokens, index)}${token.text ?? ''}${this.inlineTrail(tokens, index)}`)
          .fontFamily(MONO)
          .fontSize(Math.max(12.5, fs - 2.5))
          .fontColor(color)
      } else if (token.type === 'link') {
        if (this.safeHref(token)) {
          Text() {
            if (depth < INLINE_DEPTH) {
              this.inlineRuns(token.tokens ?? [], color, fs, depth + 1)
            }
          }
          .fontColor(appStore.theme.p.accent)
          .fontSize(fs)
          .decoration({ type: TextDecorationType.Underline })
          .onClick(() => {
            this.openHref(token)
          })
        } else {
          Text() {
            if (depth < INLINE_DEPTH) {
              this.inlineRuns(token.tokens ?? [], color, fs, depth + 1)
            }
          }
          .fontColor(color)
          .fontSize(fs)
        }
      } else if (token.type === 'del') {
        Text() {
          if (depth < INLINE_DEPTH) {
            this.inlineRuns(token.tokens ?? [], color, fs, depth + 1)
          }
        }
        .fontColor(color)
        .fontSize(fs)
        .decoration({ type: TextDecorationType.LineThrough })
      } else if (token.type === 'br') {
        Span('\n')
      } else if (token.type === 'image') {
        Span(token.text !== undefined && token.text !== '' ? token.text : 'image')
          .fontColor(tint(color, 0.45))
          .fontSize(fs)
      } else {
        Span(token.text ?? '')
          .fontColor(color)
          .fontSize(fs)
      }
    }, (token: InlineToken, index: number): string => `${depth}-${index}`)
  }

  build() {
    if (this.token.type === 'heading') {
      Text() {
        this.inlineRuns(this.token.inline ?? [], this.textColor, this.headingSize(), 0)
      }
      .fontSize(this.headingSize())
      .lineHeight(Math.round(this.headingSize() * 1.4))
      .fontWeight(600)
      .fontColor(this.textColor)
      .margin({ top: this.topGap(12), bottom: this.bottomGap(4) })
      .copyOption(CopyOptions.LocalDevice)
    } else if (this.token.type === 'paragraph') {
      Text() {
        this.inlineRuns(this.token.inline ?? [], this.textColor, this.fontSize, 0)
      }
      .fontSize(this.fontSize)
      .lineHeight(this.lineHeight)
      .fontColor(this.textColor)
      .margin({ top: this.topGap(8), bottom: this.bottomGap(2) })
      .copyOption(CopyOptions.LocalDevice)
    } else if (this.token.type === 'code') {
      Column() {
        Scroll() {
          Text(this.token.text ?? '')
            .fontFamily(MONO)
            .fontSize(13)
            .lineHeight(19)
            .fontColor(this.textColor)
            .padding({ left: 12, right: 12, top: 9, bottom: 9 })
            .copyOption(CopyOptions.LocalDevice)
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .align(Alignment.Start)
      }
      .backgroundColor(this.ink.fill)
      .borderRadius(radius.input)
      .margin({ top: this.topGap(6), bottom: this.bottomGap(6) })
      .border({ width: 1, color: this.ink.line })
      .clip(true)
    } else if (this.token.type === 'list') {
      Column({ space: 6 }) {
        ForEach(this.token.items ?? [], (item: MdToken[], index: number) => {
          Row() {
            Text(this.token.ordered === true ? `${(this.token.start ?? 1) + index}.` : '•')
              .fontSize(this.fontSize)
              .lineHeight(this.lineHeight)
              .fontColor(this.ink.muted)
              .constraintSize({ minWidth: this.token.ordered === true ? 24 : 16 })
              .padding({ right: this.token.ordered === true ? 6 : 4 })
            Column() {
              ForEach(this.itemTokens(item), (inner: MdToken, bi: number) => {
                MarkdownBlock({
                  token: inner,
                  ink: this.ink,
                  textColor: this.textColor,
                  fontSize: this.fontSize,
                  lineHeight: this.lineHeight,
                  first: bi === 0,
                  last: bi === this.itemTokens(item).length - 1,
                  depth: this.depth + 1,
                })
              }, (inner: MdToken, bi: number): string => `i-${bi}`)
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .alignItems(VerticalAlign.Top)
        }, (item: MdToken[], index: number): string => `l-${index}`)
      }
      .margin({ left: this.depth * 14, top: this.topGap(6), bottom: this.bottomGap(4) })
      .alignItems(HorizontalAlign.Start)
    } else if (this.token.type === 'blockquote') {
      Column() {
        ForEach(this.innerTokens(), (inner: MdToken, index: number) => {
          MarkdownBlock({
            token: inner,
            ink: this.ink,
            textColor: this.textColor,
            fontSize: this.fontSize,
            lineHeight: this.lineHeight,
            first: index === 0,
            last: index === this.innerTokens().length - 1,
            depth: this.depth,
          })
        }, (inner: MdToken, index: number): string => `q-${index}`)
      }
      .padding({ left: 10 })
      .border({ width: { left: 3 }, color: this.ink.line })
      .margin({ top: this.topGap(6), bottom: this.bottomGap(6) })
      .alignItems(HorizontalAlign.Start)
    } else if (this.token.type === 'table') {
      Column() {
        Scroll() {
          Column() {
            Row() {
              ForEach(this.token.header ?? [], (cell: MdToken, ci: number) => {
                Column() {
                  Text() {
                    this.inlineRuns(cell.inline ?? [], this.textColor, this.fontSize - 1, 0)
                  }
                  .fontSize(this.fontSize - 1)
                  .lineHeight(this.lineHeight - 4)
                  .fontWeight('600')
                  .fontColor(this.textColor)
                }
                .constraintSize({ minWidth: 92, maxWidth: 260 })
                .padding({ left: 10, right: 10, top: 7, bottom: 7 })
                .alignItems(HorizontalAlign.Start)
              }, (cell: MdToken, ci: number): string => `h-${ci}`)
            }
            .backgroundColor(this.ink.fill)
            ForEach(this.token.rows ?? [], (row: MdToken[], ri: number) => {
              Row() {
                ForEach(row, (cell: MdToken, ci: number) => {
                  Column() {
                    Text() {
                      this.inlineRuns(cell.inline ?? [], this.textColor, this.fontSize - 1, 0)
                    }
                    .fontSize(this.fontSize - 1)
                    .lineHeight(this.lineHeight - 4)
                    .fontColor(this.textColor)
                  }
                  .constraintSize({ minWidth: 92, maxWidth: 260 })
                  .padding({ left: 10, right: 10, top: 7, bottom: 7 })
                  .alignItems(HorizontalAlign.Start)
                }, (cell: MdToken, ci: number): string => `c-${ci}`)
              }
              .border({ width: { top: 1 }, color: this.ink.line })
            }, (row: MdToken[], ri: number): string => `r-${ri}`)
          }
          .border({ width: 1, color: this.ink.line })
          .borderRadius(radius.input)
          .clip(true)
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
      }
      .margin({ top: this.topGap(6), bottom: this.bottomGap(6) })
    } else if (this.token.type === 'hr') {
      Column() {
      }
      .height(1)
      .backgroundColor(this.ink.line)
      .margin({ top: this.topGap(10), bottom: this.bottomGap(10) })
    } else if (this.token.type === 'text') {
      if ((this.token.inline ?? []).length > 0) {
        Text() {
          this.inlineRuns(this.token.inline ?? [], this.textColor, this.fontSize, 0)
        }
        .fontSize(this.fontSize)
        .lineHeight(this.lineHeight)
        .fontColor(this.textColor)
        .copyOption(CopyOptions.LocalDevice)
      } else {
        Text(this.token.text ?? '')
          .fontSize(this.fontSize)
          .lineHeight(this.lineHeight)
          .fontColor(this.textColor)
          .copyOption(CopyOptions.LocalDevice)
      }
    } else if (this.token.type === 'html') {
      Text(this.token.text ?? '')
        .fontSize(this.fontSize)
        .lineHeight(this.lineHeight)
        .fontColor(this.textColor)
        .copyOption(CopyOptions.LocalDevice)
    }
  }
}
