// Markdown in Bot text: the ported lexer (common/markdown) walks the block
// tokens; each block maps to ArkUI nodes — headings, paragraphs with lifted
// images, fenced code, nested task/ordered/bullet lists, blockquotes, aligned
// tables with Copy/Expand, rules — and the inline token tree flattens into
// styled runs (common/markdown/markdown-run) that render as one Span
// sequence, so nested emphasis stays inline-continuous like the RN build's
// nested <Text>. Workspace images load through the markdown-image RPC
// (common/markdown/markdown-image) and cache by content revision. Line/code
// tints derive from the text color, so the same Markdown reads on the Bot's
// light bubble and the user's dark one.

import { Want, common } from '@kit.AbilityKit'

import { lexer, type InlineToken, type MdListItem, type MdToken } from '../../common/markdown/markdown'
import {
  computeTableWidths,
  listItemInfo,
  normalizeSoftBreaks,
  splitParagraphImages,
  tableToTsv,
  type ListItemInfo,
  type ParagraphSegment,
  type TableWidthOpts,
} from '../../common/markdown/markdown-model'
import {
  cachedMdImage,
  loadMarkdownImage,
  MD_IMAGE_TTL_MS,
  onMdImageEpoch,
  type MdImageOutcome,
} from '../../common/markdown/markdown-image'
import { flattenInlineRuns, type StyledRun } from '../../common/markdown/markdown-run'
import { copyToClipboard } from '../../platform/Platform'
import { t } from '../../common/ui/i18n'
import { appStore, MONO, radius, type } from '../../components/Theme'

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

// True when the text has a block that lays out wider than its text (list,
// code, table, heading, rule, quote): the bubble needs its full width to
// wrap inside it. Matches the RN rule (markdown.tsx hasBlockContent).
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

// One inline run inside a Text: the inline token tree is flattened (pure
// data, common/markdown/markdown-run) into styled runs that render as one
// Span sequence, so nested emphasis stays inline-continuous like the RN
// build's nested <Text>. Shared by every block that lays out inline tokens.
@ComponentV2
struct MarkdownInlines {
  @Require @Param tokens: InlineToken[]
  @Require @Param color: string
  @Param fs: number = 16
  @Param lh: number = 25
  @Param bold: boolean = false

  runs(): StyledRun[] {
    return flattenInlineRuns(this.tokens)
  }

  isLink(run: StyledRun): boolean {
    const href: string = run.href ?? ''
    return run.href !== undefined && (/^https?:/i.test(href) || /^mailto:/i.test(href))
  }

  openHref(run: StyledRun): void {
    const href: string = run.href ?? ''
    if (href === '') return
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    openExternalUrl(context, href)
  }

  // A heading/table-header block is bold all through, so a plain run there
  // inherits the block's weight instead of overriding it back to 400.
  runWeight(run: StyledRun): number {
    return run.bold === true || this.bold ? 600 : 400
  }

  runFontStyle(run: StyledRun): FontStyle {
    return run.italic === true ? FontStyle.Italic : FontStyle.Normal
  }

  runDecoration(run: StyledRun): TextDecorationType {
    if (run.strike === true) return TextDecorationType.LineThrough
    if (this.isLink(run)) return TextDecorationType.Underline
    return TextDecorationType.None
  }

  build() {
    Text() {
      ForEach(this.runs(), (run: StyledRun) => {
        if (run.muted === true) {
          // An image inside a run that cannot be lifted (a heading, a table
          // cell) keeps its readable alt text.
          Span(run.text !== '' ? run.text : t('Image'))
            .fontColor(tint(this.color, 0.45))
            .fontSize(this.fs)
        } else if (run.mono === true) {
          Span(run.text)
            .fontFamily(MONO)
            .fontSize(Math.max(12.5, this.fs - 2.5))
            .fontColor(this.isLink(run) ? appStore.theme.p.accent : this.color)
            .fontWeight(this.runWeight(run))
            .fontStyle(this.runFontStyle(run))
            .decoration({ type: this.runDecoration(run) })
            .onClick(() => {
              this.openHref(run)
            })
        } else if (this.isLink(run)) {
          Span(run.text)
            .fontColor(appStore.theme.p.accent)
            .fontSize(this.fs)
            .fontWeight(this.runWeight(run))
            .fontStyle(this.runFontStyle(run))
            .decoration({ type: this.runDecoration(run) })
            .onClick(() => {
              this.openHref(run)
            })
        } else {
          Span(run.text)
            .fontColor(this.color)
            .fontSize(this.fs)
            .fontWeight(this.runWeight(run))
            .fontStyle(this.runFontStyle(run))
            .decoration({ type: this.runDecoration(run) })
        }
      }, (run: StyledRun, index: number): string => `r-${index}-${run.text.length}`)
    }
    .fontSize(this.fs)
    .lineHeight(this.lh)
    .fontWeight(this.bold ? 600 : 400)
    .fontColor(this.color)
    .copyOption(CopyOptions.LocalDevice)
  }
}

@ComponentV2
export struct MarkdownText {
  @Require @Param text: string
  @Require @Param textColor: string
  @Param fontSize: number = 16
  @Param lineHeight: number = 25
  @Param bg: string = ''
  @Param sessionId: string = ''
  @Param botId: string = ''

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
          sessionId: this.sessionId,
          botId: this.botId,
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
  @Param sessionId: string = ''
  @Param botId: string = ''
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

  /** Marker/body info for one list item at this nesting depth. */
  listInfo(item: MdListItem, index: number): ListItemInfo {
    return listItemInfo(this.token, item, index, this.depth)
  }

  headingSize(): number {
    const depth: number = this.token.depth ?? 1
    if (depth === 1) return this.fontSize + 4
    if (depth === 2) return this.fontSize + 2
    return this.fontSize + 1
  }

  build() {
    if (this.token.type === 'heading') {
      MarkdownInlines({
        tokens: this.token.inline ?? [],
        color: this.textColor,
        fs: this.headingSize(),
        lh: Math.round(this.headingSize() * 1.4),
        bold: true,
      })
        .margin({ top: this.topGap(12), bottom: this.bottomGap(4) })
    } else if (this.token.type === 'paragraph') {
      // Images lift out of the inline run into their own blocks, so no image
      // ever mounts inside a Text subtree.
      Column({ space: 6 }) {
        ForEach(splitParagraphImages(this.token.inline ?? []), (seg: ParagraphSegment, si: number) => {
          if (seg.kind === 'inlines') {
            MarkdownInlines({
              tokens: seg.tokens,
              color: this.textColor,
              fs: this.fontSize,
              lh: this.lineHeight,
            })
          } else {
            MarkdownImage({
              href: seg.href,
              alt: seg.alt,
              linkHref: seg.linkHref ?? '',
              ink: this.ink,
              sessionId: this.sessionId,
              botId: this.botId,
            })
          }
        }, (seg: ParagraphSegment, si: number): string => `s-${si}`)
      }
      .margin({ top: this.topGap(8), bottom: this.bottomGap(2) })
      .alignItems(HorizontalAlign.Start)
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
        ForEach(this.token.items ?? [], (item: MdListItem, index: number) => {
          Row() {
            Text(this.listInfo(item, index).marker)
              .fontSize(this.fontSize)
              .lineHeight(this.lineHeight)
              .fontColor(this.listInfo(item, index).checked ? appStore.theme.p.accent : this.ink.muted)
              .constraintSize({ minWidth: this.token.ordered === true ? 26 : 18 })
              .padding({ right: this.token.ordered === true ? 6 : 4 })
            Column() {
              ForEach(this.listInfo(item, index).tokens, (inner: MdToken, bi: number) => {
                MarkdownBlock({
                  token: inner,
                  ink: this.ink,
                  textColor: this.textColor,
                  fontSize: this.fontSize,
                  lineHeight: this.lineHeight,
                  sessionId: this.sessionId,
                  botId: this.botId,
                  first: bi === 0,
                  last: bi === this.listInfo(item, index).tokens.length - 1,
                  depth: this.depth + 1,
                })
              }, (inner: MdToken, bi: number): string => `i-${bi}`)
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .alignItems(VerticalAlign.Top)
        }, (item: MdListItem, index: number): string => `l-${index}`)
      }
      .margin({ left: this.depth > 0 ? 12 : 0, top: this.topGap(6), bottom: this.bottomGap(4) })
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
            sessionId: this.sessionId,
            botId: this.botId,
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
      MarkdownTable({
        token: this.token,
        ink: this.ink,
        textColor: this.textColor,
        fontSize: this.fontSize,
        lineHeight: this.lineHeight,
        first: this.first,
        last: this.last,
      })
    } else if (this.token.type === 'hr') {
      Column() {
      }
      .height(1)
      .backgroundColor(this.ink.line)
      .margin({ top: this.topGap(10), bottom: this.bottomGap(10) })
    } else if (this.token.type === 'text') {
      if ((this.token.inline ?? []).length > 0) {
        Column({ space: 4 }) {
          ForEach(splitParagraphImages(this.token.inline ?? []), (seg: ParagraphSegment, si: number) => {
            if (seg.kind === 'inlines') {
              MarkdownInlines({
                tokens: seg.tokens,
                color: this.textColor,
                fs: this.fontSize,
                lh: this.lineHeight,
              })
            } else {
              MarkdownImage({
                href: seg.href,
                alt: seg.alt,
                linkHref: seg.linkHref ?? '',
                ink: this.ink,
                sessionId: this.sessionId,
                botId: this.botId,
              })
            }
          }, (seg: ParagraphSegment, si: number): string => `s-${si}`)
        }
        .alignItems(HorizontalAlign.Start)
      } else {
        Text(normalizeSoftBreaks(this.token.text ?? ''))
          .fontSize(this.fontSize)
          .lineHeight(this.lineHeight)
          .fontColor(this.textColor)
          .copyOption(CopyOptions.LocalDevice)
      }
    } else if (this.token.type === 'html') {
      Text(normalizeSoftBreaks(this.token.text ?? ''))
        .fontSize(this.fontSize)
        .lineHeight(this.lineHeight)
        .fontColor(this.textColor)
        .copyOption(CopyOptions.LocalDevice)
    }
  }
}

// Aligned table: column widths computed across header and all rows, a Copy
// bar (TSV to the clipboard) and an Expand cover with the full-screen grid.
@ComponentV2
struct MarkdownTable {
  @Require @Param token: MdToken
  @Require @Param ink: MarkdownInk
  @Require @Param textColor: string
  @Require @Param fontSize: number
  @Require @Param lineHeight: number
  @Param first: boolean = false
  @Param last: boolean = false
  @Local boxWidth: number = 0
  @Local copied: boolean = false
  @Local expanded: boolean = false

  headerCells(): MdToken[] {
    return this.token.header ?? []
  }

  rowCells(): MdToken[][] {
    return this.token.rows ?? []
  }

  headerTexts(): string[] {
    return this.headerCells().map((cell: MdToken): string => cell.text ?? '')
  }

  rowTexts(): string[][] {
    return this.rowCells().map((row: MdToken[]): string[] =>
      row.map((cell: MdToken): string => cell.text ?? ''))
  }

  colWidths(): number[] {
    const opts: TableWidthOpts = { containerWidth: Math.max(0, this.boxWidth - 2) }
    return computeTableWidths(this.headerTexts(), this.rowTexts(), opts)
  }

  cellOf(row: MdToken[], ci: number): MdToken {
    return row[ci] ?? { type: 'text', text: '', inline: [] }
  }

  copyTable(): void {
    void copyToClipboard(tableToTsv(this.headerTexts(), this.rowTexts())).then((): void => {
      this.copied = true
      setTimeout((): void => {
        this.copied = false
      }, 1500)
    })
  }

  @Builder
  bubbleGrid() {
    Column() {
      Row() {
        ForEach(this.headerCells(), (cell: MdToken, ci: number) => {
          Column() {
            MarkdownInlines({
              tokens: cell.inline ?? [],
              color: this.textColor,
              fs: this.fontSize - 1,
              lh: this.lineHeight - 4,
              bold: true,
            })
          }
          .width(this.colWidths()[ci] ?? 100)
          .padding({ left: 10, right: 10, top: 8, bottom: 8 })
          .alignItems(HorizontalAlign.Start)
          .border({ width: { left: ci > 0 ? 1 : 0 }, color: this.ink.line })
        }, (cell: MdToken, ci: number): string => `h-${ci}`)
      }
      .backgroundColor(this.ink.fill)
      ForEach(this.rowCells(), (row: MdToken[], ri: number) => {
        Row() {
          ForEach(this.headerCells(), (_cell: MdToken, ci: number) => {
            Column() {
              MarkdownInlines({
                tokens: this.cellOf(row, ci).inline ?? [],
                color: this.textColor,
                fs: this.fontSize - 1,
                lh: this.lineHeight - 4,
              })
            }
            .width(this.colWidths()[ci] ?? 100)
            .padding({ left: 10, right: 10, top: 7, bottom: 7 })
            .alignItems(HorizontalAlign.Start)
            .border({ width: { left: ci > 0 ? 1 : 0 }, color: this.ink.line })
          }, (_cell: MdToken, ci: number): string => `c-${ci}`)
        }
        .border({ width: { top: 1 }, color: this.ink.line })
      }, (row: MdToken[], ri: number): string => `r-${ri}`)
    }
    .border({ width: 1, color: this.ink.line })
    .borderRadius(radius.input)
    .clip(true)
  }

  @Builder
  modalGrid() {
    Column() {
      Row() {
        ForEach(this.headerCells(), (cell: MdToken, ci: number) => {
          Column() {
            MarkdownInlines({
              tokens: cell.inline ?? [],
              color: appStore.theme.p.ink,
              fs: this.fontSize - 1,
              lh: this.lineHeight - 4,
              bold: true,
            })
          }
          .width(this.colWidths()[ci] ?? 110)
          .padding({ left: 10, right: 10, top: 8, bottom: 8 })
          .alignItems(HorizontalAlign.Start)
          .border({ width: { left: ci > 0 ? 1 : 0 }, color: appStore.theme.p.line2 })
        }, (cell: MdToken, ci: number): string => `h-${ci}`)
      }
      .backgroundColor(appStore.theme.p.hover)
      ForEach(this.rowCells(), (row: MdToken[], ri: number) => {
        Row() {
          ForEach(this.headerCells(), (_cell: MdToken, ci: number) => {
            Column() {
              MarkdownInlines({
                tokens: this.cellOf(row, ci).inline ?? [],
                color: appStore.theme.p.ink,
                fs: this.fontSize - 1,
                lh: this.lineHeight - 4,
              })
            }
            .width(this.colWidths()[ci] ?? 110)
            .padding({ left: 10, right: 10, top: 8, bottom: 8 })
            .alignItems(HorizontalAlign.Start)
            .border({ width: { left: ci > 0 ? 1 : 0 }, color: appStore.theme.p.line2 })
          }, (_cell: MdToken, ci: number): string => `c-${ci}`)
        }
        .border({ width: { top: 1 }, color: appStore.theme.p.line })
      }, (row: MdToken[], ri: number): string => `r-${ri}`)
    }
    .border({ width: 1, color: appStore.theme.p.line2 })
    .borderRadius(radius.input)
    .backgroundColor(appStore.theme.p.card)
    .clip(true)
  }

  @Builder
  tableCover() {
    Column() {
      Row() {
        Text(t('Table'))
          .fontSize(type.headerTitle.fontSize)
          .lineHeight(type.headerTitle.lineHeight)
          .fontWeight(600)
          .fontColor(appStore.theme.p.ink)
        Blank()
        Text(this.copied ? t('Copied') : t('Copy'))
          .fontSize(type.small.fontSize)
          .lineHeight(type.small.lineHeight)
          .fontColor(this.copied ? appStore.theme.p.accent : appStore.theme.p.ink2)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .borderRadius(radius.item)
          .border({ width: 1, color: appStore.theme.p.line })
          .backgroundColor(appStore.theme.p.hover)
          .onClick((): void => {
            this.copyTable()
          })
        Text(t('Done'))
          .fontSize(type.small.fontSize)
          .lineHeight(type.small.lineHeight)
          .fontWeight(600)
          .fontColor(appStore.theme.p.accentInk)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .borderRadius(radius.item)
          .backgroundColor(appStore.theme.p.accent)
          .margin({ left: 10 })
          .onClick((): void => {
            this.expanded = false
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 10 })
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Scroll() {
          this.modalGrid()
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Auto)
        .align(Alignment.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Start)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(appStore.theme.p.main)
    .padding({ top: appStore.safeTop + 8, bottom: appStore.safeBottom + 12, left: 14, right: 14 })
  }

  build() {
    Column() {
      Scroll() {
        this.bubbleGrid()
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Auto)
      .align(Alignment.Start)
      Row({ space: 8 }) {
        Text(this.copied ? t('Copied') : t('Copy'))
          .fontSize(type.caption.fontSize)
          .lineHeight(type.caption.lineHeight)
          .fontColor(this.copied ? appStore.theme.p.accent : this.ink.muted)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .borderRadius(radius.item)
          .border({ width: 1, color: this.ink.line })
          .backgroundColor(this.ink.fill)
          .onClick((): void => {
            this.copyTable()
          })
        Text(t('Expand'))
          .fontSize(type.caption.fontSize)
          .lineHeight(type.caption.lineHeight)
          .fontColor(this.ink.muted)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .borderRadius(radius.item)
          .border({ width: 1, color: this.ink.line })
          .backgroundColor(this.ink.fill)
          .onClick((): void => {
            this.expanded = true
          })
      }
      .justifyContent(FlexAlign.End)
      .width('100%')
      .margin({ top: 6 })
    }
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      const width: Length = newArea.width
      const measured: number = typeof width === 'number' ? width : Number(width)
      if (Number.isFinite(measured)) this.boxWidth = measured
    })
    .margin({ top: this.first ? 0 : 6, bottom: this.last ? 0 : 6 })
    .alignItems(HorizontalAlign.Start)
    .bindContentCover(this.expanded, this.tableCover, {
      modalTransition: ModalTransition.DEFAULT,
      onDisappear: (): void => {
        this.expanded = false
      },
    })
  }
}

// One image in Bot text. An absolute https or data: URI renders directly; a
// workspace path loads through the markdown-image RPC with a TTL/LRU cache;
// everything else keeps its readable alt text. A link-wrapped image opens the
// link, a plain one opens the full-screen viewer.
@ComponentV2
struct MarkdownImage {
  @Require @Param href: string
  @Require @Param alt: string
  @Param linkHref: string = ''
  @Require @Param ink: MarkdownInk
  @Param sessionId: string = ''
  @Param botId: string = ''
  @Local uri: string = ''
  @Local failed: boolean = false
  @Local open: boolean = false
  private offEpoch: (() => void) | null = null

  remote(): boolean {
    return /^https:\/\//i.test(this.href) || /^data:image\//i.test(this.href)
  }

  load(): void {
    this.failed = false
    if (this.remote()) {
      this.uri = this.href
      return
    }
    if (this.sessionId === '' || this.href === '') {
      this.failed = true
      return
    }
    const key: string = `${this.sessionId}:${this.botId}:${this.href}`
    const cached = cachedMdImage(key)
    if (cached !== undefined && cached.uri !== undefined) this.uri = cached.uri
    if (cached !== undefined && Date.now() - cached.at < MD_IMAGE_TTL_MS) return
    const controller = appStore.link.controller
    if (controller === null) {
      if (cached === undefined) this.failed = true
      return
    }
    const call = controller.call
    void loadMarkdownImage(call, key, this.sessionId, this.href, this.botId)
      .then((outcome: MdImageOutcome): void => {
        if (outcome.state === 'failed') {
          this.uri = ''
          this.failed = true
          return
        }
        if (outcome.state === 'stale') {
          // A transient error: a cached image keeps showing; without one the
          // alt box shows.
          if (this.uri === '') this.failed = true
          return
        }
        if (outcome.uri !== undefined) this.uri = outcome.uri
      })
  }

  aboutToAppear(): void {
    this.offEpoch = onMdImageEpoch((): void => {
      this.load()
    })
    this.load()
  }

  aboutToDisappear(): void {
    if (this.offEpoch !== null) this.offEpoch()
  }

  press(): void {
    if (/^https:\/\//i.test(this.linkHref)) {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      openExternalUrl(context, this.linkHref)
      return
    }
    if (this.uri !== '') this.open = true
  }

  @Builder
  imageCover() {
    Stack() {
      Image(this.uri)
        .objectFit(ImageFit.Contain)
        .width('100%')
        .height('82%')
      Text(t('Done'))
        .fontSize(type.settingsRow.fontSize)
        .lineHeight(type.settingsRow.lineHeight)
        .fontColor('#ffffff')
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .position({ top: appStore.safeTop + 10, right: 16 })
        .onClick((): void => {
          this.open = false
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
    .alignContent(Alignment.Center)
    .onClick((): void => {
      this.open = false
    })
  }

  build() {
    Column() {
      if (this.failed || this.href === '') {
        Text(this.alt !== '' ? this.alt : t('Image'))
          .fontSize(type.caption.fontSize)
          .lineHeight(type.caption.lineHeight)
          .fontColor(this.ink.muted)
          .padding({ left: 10, right: 10, top: 8, bottom: 8 })
          .borderRadius(radius.input)
          .border({ width: 1, color: this.ink.line })
          .backgroundColor(this.ink.fill)
      } else {
        Column() {
          if (this.uri !== '') {
            Image(this.uri)
              .width('100%')
              .objectFit(ImageFit.Contain)
              .constraintSize({ maxHeight: 280, minHeight: 72 })
              .onError((): void => {
                this.failed = true
              })
          } else {
            Text(this.alt !== '' ? this.alt : t('Image'))
              .fontSize(type.caption.fontSize)
              .lineHeight(type.caption.lineHeight)
              .fontColor(this.ink.muted)
          }
        }
        .borderRadius(radius.input)
        .border({ width: 1, color: this.ink.line })
        .backgroundColor(this.ink.fill)
        .clip(true)
        .onClick((): void => {
          this.press()
        })
        .bindContentCover(this.open, this.imageCover, { modalTransition: ModalTransition.NONE })
      }
    }
    .margin({ top: 4, bottom: 4 })
    .alignItems(HorizontalAlign.Start)
  }
}
