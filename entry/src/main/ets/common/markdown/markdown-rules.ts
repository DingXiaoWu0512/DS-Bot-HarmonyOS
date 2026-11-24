// The Markdown rules around images the phone keeps from the RN build: only
// an absolute https image can load inline — anything else keeps its readable
// alt text. Workspace paths render through the markdown-image RPC instead,
// which the MarkdownText layer decides, not this predicate. (The phone
// renders soft breaks as real line breaks; softBreakText below is the legacy
// collapse helper, kept without callers for reference.)

import { type InlineToken } from './markdown'
import { rewrapInline } from './markdown-model'

/** Legacy soft-break collapse; unused — the phone keeps line breaks. */
export function softBreakText(text: string): string {
  return text.replace(/\r\n?/g, '\n').replace(/\n/g, ' ')
}

/** An inline image that can load directly. */
export interface InlineImageShown {
  kind: 'image'
  src: string
  alt: string
}

/** The alt text to show when the image cannot load inline. */
export interface InlineImageAlt {
  kind: 'alt'
  text: string
}

export type InlineImage = InlineImageShown | InlineImageAlt

// Only an absolute https image can load on the phone. A workspace-relative
// path has no file service behind it here, and http would be blocked as
// cleartext, so both keep the readable alt text they had before.
export function inlineImage(href: string | undefined, alt: string | undefined): InlineImage {
  const src: string = typeof href === 'string' ? href.trim() : ''
  const text: string = typeof alt === 'string' && alt.trim() !== '' ? alt.trim() : 'image'
  if (/^https:\/\/[^\s]+$/i.test(src)) return { kind: 'image', src, alt: text }
  return { kind: 'alt', text }
}

export function hasInlineImage(tokens: InlineToken[]): boolean {
  for (const token of tokens) {
    if (token.type === 'image') {
      const shown: InlineImage = inlineImage(token.href, token.text)
      if (shown.kind === 'image') return true
      continue
    }
    const inner: InlineToken[] | undefined = token.tokens
    if (inner !== undefined && hasInlineImage(inner)) return true
  }
  return false
}

/** A loadable image lifted out of a token run, with its optional link target. */
export interface ImageFlowImage {
  kind: 'image'
  src: string
  alt: string
  href?: string
}

/** A run of inline tokens between two lifted images. */
export interface ImageFlowText {
  kind: 'text'
  tokens: InlineToken[]
}

export type ImageFlowPart = ImageFlowImage | ImageFlowText

class ImageFlowWalker {
  readonly parts: ImageFlowPart[] = []

  walk(token: InlineToken, wrappers: InlineToken[], href: string | undefined): void {
    if (token.type === 'image') {
      const shown: InlineImage = inlineImage(token.href, token.text)
      if (shown.kind === 'image') {
        const part: ImageFlowImage = { kind: 'image', src: shown.src, alt: shown.alt }
        if (href !== undefined) part.href = href
        this.parts.push(part)
        return
      }
    }
    const inner: InlineToken[] | undefined = token.tokens
    if (inner !== undefined && hasInlineImage(inner)) {
      const linkHref: string | undefined = token.type === 'link' && /^(https?:|mailto:)/i.test(token.href ?? '')
        ? token.href
        : href
      const nextWrappers: InlineToken[] = wrappers.concat([token])
      for (const child of inner) this.walk(child, nextWrappers, linkHref)
      return
    }
    let wrapped: InlineToken = token
    for (let i = wrappers.length - 1; i >= 0; i--) {
      wrapped = rewrapInline(wrappers[i]!, [wrapped])
    }
    const last: ImageFlowPart | undefined = this.parts.length > 0 ? this.parts[this.parts.length - 1] : undefined
    if (last !== undefined && last.kind === 'text') {
      last.tokens.push(wrapped)
    } else {
      const part: ImageFlowText = { kind: 'text', tokens: [wrapped] }
      this.parts.push(part)
    }
  }
}

export function imageFlow(tokens: InlineToken[]): ImageFlowPart[] {
  const walker = new ImageFlowWalker()
  for (const token of tokens) walker.walk(token, [], undefined)
  return walker.parts
}
