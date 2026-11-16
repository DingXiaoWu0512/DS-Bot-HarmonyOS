// The chat's scrolling list: the port of Chat.tsx's inverted FlatList. The ArkUI
// List has no inverted mode, so the whole list rotates 180° and each row sits in
// a counter-rotated wrapper: rows are stored newest-first (index 0 renders at
// the visual bottom), older pages append at the data end — the visual top —
// without ever moving the viewport, and new rows prepend at index 0 where the
// bottom-pinned offset keeps them in view. Chat owns the data and overlays;
// this file owns the scroll bookkeeping, the jump chip and the page spinner.

import { appStore, type, shadowOf, Palette } from '../../components/Theme'
import { t } from '../../common/ui/i18n'
import type { Bot, ChatItem, FileRef, ImageRef } from '../../common/team/types'
import { Item, PhotoOpenData } from './ChatRows'
import { Icon } from '../../components/Icon'

// One rendered row, precomputed by Chat: the item, its stable list key, the
// desktop's trailing time stamp, and everything the row needs from its chat.
export interface MessageRow {
  item: ChatItem
  key: string
  stamp: string
  stepsOpen: boolean
  maxWidth: number
  author: Bot | undefined
  admin: boolean
}

// LazyForEach only re-renders an item when its key changes, so the mutable
// bits ride along in the key: the steps fold state, the streaming bubble's
// growing text, and an author photo landing from the avatar cache.
function rowKeyOf(row: MessageRow): string {
  let key = row.key
  if (row.stepsOpen) key += '+open'
  if (row.key === 'streaming') key += `#${(row.item.text ?? '').length}`
  if (row.author?.avatar?.image !== undefined) key += '+img'
  return key
}

// The LazyForEach data source. Rows arrive as whole arrays from Chat; this
// class diffs them by key and issues the precise per-index notifications the
// lazy list needs, so unchanged rows keep their identity and are not rebuilt.
class RowsSource implements IDataSource {
  private rows: MessageRow[] = []
  private listeners: DataChangeListener[] = []

  totalCount(): number {
    return this.rows.length
  }

  getData(index: number): MessageRow {
    return this.rows[index]
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener)
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const at = this.listeners.indexOf(listener)
    if (at >= 0) {
      this.listeners.splice(at, 1)
    }
  }

  count(): number {
    return this.rows.length
  }

  private emit(notify: (listener: DataChangeListener) => void): void {
    for (let i = 0; i < this.listeners.length; i++) {
      notify(this.listeners[i])
    }
  }

  private keysOf(list: MessageRow[]): string[] {
    const keys: string[] = []
    for (let i = 0; i < list.length; i++) {
      keys.push(list[i].key)
    }
    return keys
  }

  // True when `next` begins with exactly the old keys (older rows were
  // appended at the data end, and old rows may have new content).
  private startsWithOld(oldKeys: string[], nextKeys: string[]): boolean {
    if (nextKeys.length < oldKeys.length) {
      return false
    }
    for (let i = 0; i < oldKeys.length; i++) {
      if (oldKeys[i] !== nextKeys[i]) {
        return false
      }
    }
    return true
  }

  // Swaps in the next rows, notifying the lazy list of exactly what changed.
  // Returns how many rows were prepended at index 0 (the newest side).
  setRows(next: MessageRow[]): number {
    const old = this.rows
    if (old.length === 0) {
      this.rows = next
      if (next.length > 0) {
        this.emit((listener: DataChangeListener): void => listener.onDataReloaded())
      }
      return next.length
    }
    if (next.length === 0) {
      this.rows = next
      this.emit((listener: DataChangeListener): void => listener.onDataReloaded())
      return 0
    }
    const oldKeys = this.keysOf(old)
    const nextKeys = this.keysOf(next)
    // Older pages landed below: the old block is a prefix of the new one.
    if (this.startsWithOld(oldKeys, nextKeys)) {
      this.rows = next
      for (let i = 0; i < old.length; i++) {
        if (old[i] !== next[i]) {
          this.emit((listener: DataChangeListener): void => listener.onDataChange(i))
        }
      }
      for (let i = old.length; i < next.length; i++) {
        this.emit((listener: DataChangeListener): void => listener.onDataAdd(i))
      }
      return 0
    }
    // New rows arrived above: the old block starts at `prepend` in the new one.
    const firstOldKey = oldKeys[0]
    let prepend = -1
    for (let i = 0; i < nextKeys.length; i++) {
      if (nextKeys[i] === firstOldKey) {
        prepend = i
        break
      }
    }
    if (prepend > 0 && this.startsWithOld(oldKeys, nextKeys.slice(prepend))) {
      // Insert one row at a time so the list hears the same insertion it sees.
      for (let i = prepend - 1; i >= 0; i--) {
        this.rows.unshift(next[i])
        this.emit((listener: DataChangeListener): void => listener.onDataAdd(0))
      }
      this.rows = next
      for (let j = 0; j < old.length; j++) {
        if (old[j] !== next[prepend + j]) {
          this.emit((listener: DataChangeListener): void => listener.onDataChange(prepend + j))
        }
      }
      for (let k = prepend + old.length; k < next.length; k++) {
        this.emit((listener: DataChangeListener): void => listener.onDataAdd(k))
      }
      return prepend
    }
    // Anything else (a pending row leaving, a chat reset): rebuild.
    this.rows = next
    this.emit((listener: DataChangeListener): void => listener.onDataReloaded())
    return 0
  }
}

@ComponentV2
export struct MessageList {
  @Require @Param rows: MessageRow[]
  @Require @Param sessionId: string
  @Param flat: boolean = false
  @Param inRoom: boolean = false
  @Param loadingOlder: boolean = false
  @Event onLoadOlder: () => void = (): void => {}
  @Event onLongPress: (text: string) => void = (_text: string): void => {}
  @Event onOpenPhoto: (open: PhotoOpenData) => void = (_open: PhotoOpenData): void => {}
  @Event onOpenFile: (file: FileRef) => void = (_file: FileRef): void => {}
  @Event onRetry: (localId: string, discard: boolean) => void = (_localId: string, _discard: boolean): void => {}
  @Event onToggleSteps: (rowKey: string) => void = (_rowKey: string): void => {}

  @Local away: boolean = false
  private scroller: Scroller = new Scroller()
  private source: RowsSource = new RowsSource()
  private firstVisible: number = 0
  private nearBottom: boolean = true
  private areaHeight: number = 0
  private lastLoadAt: number = 0

  aboutToAppear(): void {
    this.source.setRows(this.rows)
  }

  // The lazy list is fed here whenever Chat hands over a new rows array. A
  // prepend scrolls to the newest row when the list sits at (or near) the
  // bottom — or when the row is our own send — and re-anchors the previously
  // first visible row when the user is reading older messages, the way RN's
  // maintainVisibleContentPosition kept the content still.
  @Monitor('rows')
  onRowsChange(): void {
    const prevFirst = this.firstVisible
    const prepended = this.source.setRows(this.rows)
    if (prepended > 0 && this.source.count() > 0) {
      const head = this.rows[0]
      if (this.nearBottom || (head !== undefined && head.item.local !== undefined)) {
        this.scroller.scrollToIndex(0, true)
      } else {
        // Row list indexes start at 1 (the bottom spacer is index 0), so the
        // last row caps at the source count.
        const target = Math.min(prevFirst + prepended, this.source.count())
        this.scroller.scrollToIndex(target, false, ScrollAlign.START)
      }
    }
  }

  private maybeLoadOlder(): void {
    if (this.loadingOlder) {
      return
    }
    const now = Date.now()
    if (now - this.lastLoadAt < 900) {
      return
    }
    this.lastLoadAt = now
    this.onLoadOlder()
  }

  private openPhotoOf(row: MessageRow, index: number): void {
    const refs: ImageRef[] = row.item.imageRefs ?? []
    if (refs.length === 0) {
      return
    }
    const open: PhotoOpenData = { sessionId: this.sessionId, refs: refs, index: index }
    this.onOpenPhoto(open)
  }

  private p(): Palette {
    return appStore.theme.p
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      List({ scroller: this.scroller, initialIndex: 0 }) {
        // The resting zone below the newest row (RN's contentInset): empty at
        // rest so the newest message clears the floating composer, but rows
        // scroll through it and under the composer toward the screen edge.
        ListItem() {
          Column() {
          }
          .width('100%')
          .height(Math.max(appStore.safeBottom, 10) + 54 + 24.6)
        }
        LazyForEach(this.source, (row: MessageRow) => {
          ListItem() {
            Column() {
              Item({
                item: row.item,
                maxWidth: row.maxWidth,
                flat: this.flat,
                inRoom: this.inRoom,
                sessionId: this.sessionId,
                stepsOpen: row.stepsOpen,
                stamp: row.stamp,
                author: row.author,
                admin: row.admin,
                onLongPress: (text: string): void => this.onLongPress(text),
                onToggleSteps: (): void => this.onToggleSteps(row.key),
                onOpenFile: (file: FileRef) => this.onOpenFile(file),
                onOpenPhoto: (index: number): void => this.openPhotoOf(row, index),
                onRetry: (localId: string, discard: boolean) => this.onRetry(localId, discard),
              })
            }
            .width('100%')
            .rotate({ x: 0, y: 0, z: 1, angle: 180 })
          }
        }, (row: MessageRow): string => rowKeyOf(row))
        // The resting zone above the oldest row: the oldest line clears the
        // floating header pill at the top of the scroll, and everything in
        // between flows edge to edge behind the floating chrome.
        ListItem() {
          Column() {
          }
          .width('100%')
          .height(appStore.safeTop + 68)
        }
      }
      .cachedCount(8)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      // Only the horizontal chat margin insets the list; vertically the rows
      // run the full window height under the system bars and floating chrome.
      .padding({ left: 12, right: 12 })
      .width('100%')
      .height('100%')
      .rotate({ x: 0, y: 0, z: 1, angle: 180 })
      .onAreaChange((_oldValue: Area, newValue: Area): void => {
        // The viewport height changes late when the immersive safe insets
        // land; the bottom anchor was computed for the old height, so re-anchor
        // to the newest row once the box settles.
        const height = Number(newValue.height)
        if (this.areaHeight > 0 && Math.abs(height - this.areaHeight) > 1 && this.nearBottom) {
          this.scroller.scrollToIndex(0, false)
        }
        this.areaHeight = height
      })
      .onScrollIndex((start: number, end: number): void => {
        this.firstVisible = start
        this.nearBottom = start <= 2
        this.away = start >= 6
        // The two spacer ListItems sit outside the row source's count.
        const total = this.source.count() + 2
        if (total > 0 && end >= total - 6) {
          this.maybeLoadOlder()
        }
      })
      .onReachEnd((): void => this.maybeLoadOlder())

      if (this.loadingOlder) {
        Row() {
          LoadingProgress()
            .width(22)
            .height(22)
            .color(this.p().ink3)
        }
        .justifyContent(FlexAlign.Center)
        .width('100%')
        // Below the floating header pill, which spans the safe inset + 52.
        .margin({ top: appStore.safeTop + 60 })
      }

      if (this.away) {
        Column() {
          Icon({ name: 'arrowDown', iconSize: 18, color: this.p().ink2 })
        }
        .width(38)
        .height(38)
        .borderRadius(19)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(this.p().card)
        .border({ width: 0.5, color: this.p().line2 })
        .shadow(shadowOf(2))
        .position({ x: '100%', y: '100%' })
        // Anchored above the floating composer: its bottom inset + 44 pill +
        // gap, so the chip clears the bottom chrome instead of hiding under it.
        .markAnchor({ x: 52, y: Math.max(appStore.safeBottom, 10) + 96 })
        .accessibilityText(t('Latest messages'))
        .onClick((): void => this.scroller.scrollToIndex(0, true))
      }
    }
    .width('100%')
    .height('100%')
  }
}
