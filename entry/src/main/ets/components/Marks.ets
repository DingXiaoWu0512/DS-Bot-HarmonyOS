// Character marks ported from mobile/src/ui/marks.tsx, drawn with the same
// generator output as the desktop (common/ui/characters.ts): body, fixed paints,
// shade, then the eye capsules punched out of the finished mark with
// destination-out (the upstream SVG masks the same holes over every layer).
// ArkUI's Path2D accepts SVG path data directly, so the layer strings from
// characters.ts render as-is; image looks (data: URIs) render as rounded photos.
// Status badges follow ui-standard 8.2: working green dot, waiting accent "?",
// Main Bot star at 36% of the avatar, ringed in the list's background color.

import { shapeOf, shapeLayerPath, shapePaintPaths, shapeEyePaths, shapeBodyPaint, lookOf, GRADIENTS } from '../common/ui/characters'
import { MAIN_LOOK } from '../common/ui/characters-table'
import { Bot, Room } from '../common/team/types'
import { Icon } from './Icon'

// Parsed Path2D per layer string, reused across every mark and redraw.
const path2dCache = new Map<string, Path2D>()

function cachedPath2D(d: string): Path2D {
  const hit = path2dCache.get(d)
  if (hit !== undefined) {
    return hit
  }
  const p = new Path2D(d)
  path2dCache.set(d, p)
  return p
}

// Shape families for a working mark's motion (mark.js styles.js): the squircle
// family squashes, the angular family wiggles, everything else (and uploaded
// images) bobs; waiting marks sway in place.
const SQUASH_SHAPES: string[] = ['gumdrop', 'peanut', 'cushion', 'squircle', 'moon', 'wave']
const WIGGLE_SHAPES: string[] = ['star', 'hex', 'plus', 'gem', 'magnet', 'ring']

@ComponentV2
export struct Mark {
  @Param shape: string = ''
  @Param color: string = ''
  @Param image: string = ''
  @Param dark: boolean = false
  @Param markSize: number = 24
  @Param motion: string = 'idle' // idle | working | waiting
  @Local ready: boolean = false
  @Local phase: number = 0 // 0..1, the motion loop's position
  private settings: RenderingContextSettings = new RenderingContextSettings(true)
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings)

  private isImage(): boolean {
    return this.image.startsWith('data:')
  }

  private onCanvasReady(): void {
    this.ready = true
    this.draw()
    this.setMotion()
  }

  @Monitor('shape', 'color', 'dark', 'markSize', 'image')
  onLookChange(monitor: IMonitor): void {
    this.draw()
  }

  @Monitor('motion')
  onMotionChange(monitor: IMonitor): void {
    this.setMotion()
  }

  // The motion kind of a working mark; waiting always sways.
  private motionKind(): string {
    if (this.motion === 'waiting') return 'sway'
    if (this.isImage()) return 'bob'
    if (SQUASH_SHAPES.includes(this.shape)) return 'squash'
    if (WIGGLE_SHAPES.includes(this.shape)) return 'wiggle'
    return 'bob'
  }

  private motionDuration(): number {
    if (this.motion === 'waiting') return 2600
    if (this.motionKind() === 'squash') return 1200
    if (this.motionKind() === 'wiggle') return 1400
    return 1600
  }

  // The loop is an alternate infinite animation of phase between 0 and 1;
  // going idle animates the phase back to rest.
  private setMotion(): void {
    if (!this.ready) return
    if (this.motion === 'idle') {
      if (this.phase !== 0) {
        this.getUIContext().animateTo({ duration: 240, curve: Curve.EaseOut }, (): void => {
          this.phase = 0
        })
      }
      return
    }
    this.getUIContext().animateTo({
      duration: this.motionDuration() / 2,
      curve: Curve.EaseInOut,
      iterations: -1,
      playMode: PlayMode.Alternate,
    }, (): void => {
      this.phase = 1
    })
  }

  private offsetY(): number {
    if (this.motion === 'idle') return 0
    if (this.motionKind() === 'squash') return -0.03 * this.markSize * this.phase
    return -0.04 * this.markSize * this.phase
  }

  private angle(): number {
    if (this.motion === 'waiting') return -10 + 20 * this.phase
    if (this.motionKind() === 'wiggle') return -12 + 24 * this.phase
    if (this.motionKind() === 'bob') return -5 * this.phase
    return 0
  }

  private scaleX(): number {
    if (this.motion !== 'idle' && this.motionKind() === 'squash') return 1 + 0.08 * this.phase
    return 1
  }

  private scaleY(): number {
    if (this.motion !== 'idle' && this.motionKind() === 'squash') return 1 - 0.1 * this.phase
    return 1
  }

  private bodyPaint(): string | CanvasGradient {
    const stops = GRADIENTS[this.color]
    if (stops !== undefined) {
      const grad = this.ctx.createLinearGradient(18, 10, 78, 92)
      for (const stop of stops) {
        grad.addColorStop(stop[0], stop[1])
      }
      return grad
    }
    return shapeBodyPaint(this.color, this.dark)
  }

  private draw(): void {
    if (!this.ready) {
      return
    }
    const ctx = this.ctx
    // The canvas surface is sized in pixels; ctx.width does not reliably
    // report it, so scale from the laid-out vp size instead.
    const surface = Math.max(1, this.getUIContext().vp2px(this.markSize))
    ctx.clearRect(0, 0, surface * 2, surface * 2)
    const scale = surface / shapeOf(this.shape).size
    ctx.save()
    ctx.scale(scale, scale)
    ctx.fillStyle = this.bodyPaint()
    ctx.fill(cachedPath2D(shapeLayerPath(this.shape, 'body')), 'evenodd')
    const paints = shapePaintPaths(this.shape)
    for (const paint of paints) {
      ctx.globalAlpha = paint.opacity
      ctx.fillStyle = paint.fill
      ctx.fill(cachedPath2D(paint.d), 'evenodd')
    }
    ctx.globalAlpha = 1
    const shade = shapeLayerPath(this.shape, 'shade')
    if (shade !== '') {
      ctx.globalAlpha = 0.07
      ctx.fillStyle = '#000000'
      ctx.fill(cachedPath2D(shade), 'evenodd')
      ctx.globalAlpha = 1
    }
    // Punch the eye capsules out of the finished mark, as the upstream mask does.
    const eyePaths = shapeEyePaths(this.shape)
    if (eyePaths.length > 0) {
      ctx.globalCompositeOperation = 'destination-out'
      ctx.fillStyle = '#000000'
      for (const eye of eyePaths) {
        ctx.fill(cachedPath2D(eye), 'evenodd')
      }
      ctx.globalCompositeOperation = 'source-over'
    }
    ctx.restore()
  }

  build() {
    if (this.isImage()) {
      Image(this.image)
        .width(this.markSize)
        .height(this.markSize)
        .borderRadius(this.markSize / 2)
        .objectFit(ImageFit.Cover)
        .translate({ y: this.offsetY() })
        .rotate({ angle: this.angle() })
        .scale({ x: this.scaleX(), y: this.scaleY() })
    } else {
      Canvas(this.ctx)
        .width(this.markSize)
        .height(this.markSize)
        .onReady(() => this.onCanvasReady())
        .translate({ y: this.offsetY() })
        .rotate({ angle: this.angle() })
        .scale({ x: this.scaleX(), y: this.scaleY() })
    }
  }
}

@ComponentV2
export struct BotMark {
  @Param bot: Bot | undefined = undefined
  @Param dark: boolean = false
  @Param markSize: number = 36
  @Param motion: string = 'idle'

  private lookShape(): string {
    return lookOf(this.bot).shape
  }

  private lookColor(): string {
    return lookOf(this.bot).color
  }

  private lookImage(): string {
    const image = lookOf(this.bot).image
    if (image !== undefined) {
      return image
    }
    return ''
  }

  build() {
    Mark({
      shape: this.lookShape(),
      color: this.lookColor(),
      image: this.lookImage(),
      dark: this.dark,
      markSize: this.markSize,
      motion: this.motion
    })
  }
}

// The "You" avatar of the desktop sidebar's footer: the whale mark.
@ComponentV2
export struct YouMark {
  @Param dark: boolean = false
  @Param markSize: number = 24

  build() {
    Mark({
      shape: MAIN_LOOK.shape,
      color: MAIN_LOOK.color,
      image: MAIN_LOOK.image ?? '',
      dark: this.dark,
      markSize: this.markSize
    })
  }
}

// Status badges per ui-standard 8.2, scaled to the row's 44px avatar: a working
// green dot (27%), a waiting accent "?" (27%), the Main Bot star at 36%, each
// ringed in the list's background color.
@ComponentV2
export struct Avatar {
  @Param bot: Bot | undefined = undefined
  @Param dark: boolean = false
  @Param markSize: number = 44
  @Param ring: string = ''
  @Param working: boolean = false
  @Param waiting: boolean = false
  @Param main: boolean = false

  private dotSize(): number {
    return Math.round(this.markSize * 0.27)
  }

  private starSize(): number {
    return Math.round(this.markSize * 0.36)
  }

  @Builder
  waitingBadge() {
    Column() {
      Column() {
        Text('?')
          .fontSize(this.dotSize() * 0.66)
          .lineHeight(this.dotSize())
          .fontWeight('600')
          .fontColor('#ffffff')
          .textAlign(TextAlign.Center)
      }
      .width(this.dotSize())
      .height(this.dotSize())
      .borderRadius(this.dotSize() / 2)
      .backgroundColor('#4d6bfe')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width(this.dotSize() + 4)
    .height(this.dotSize() + 4)
    .borderRadius((this.dotSize() + 4) / 2)
    .backgroundColor(this.ring)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .position({ x: this.markSize - this.dotSize() - 2, y: this.markSize - this.dotSize() - 2 })
  }

  @Builder
  workingBadge() {
    Column() {
      Column()
        .width(this.dotSize() * 0.67)
        .height(this.dotSize() * 0.67)
        .borderRadius(this.dotSize())
        .backgroundColor('#00c972')
        .margin({ top: this.dotSize() * 0.165 })
    }
    .width(this.dotSize() + 4)
    .height(this.dotSize() + 4)
    .borderRadius((this.dotSize() + 4) / 2)
    .backgroundColor(this.ring)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .position({ x: this.markSize - this.dotSize() - 4, y: this.markSize - this.dotSize() - 4 })
  }

  @Builder
  mainBadge() {
    Column() {
      Icon({ name: 'mainStar', iconSize: this.starSize() })
    }
    .width(this.starSize() + 3)
    .height(this.starSize() + 3)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .position({ x: this.markSize - this.starSize() - 1, y: this.markSize - this.starSize() - 1 })
  }

  private motionOf(): string {
    if (this.working) return 'working'
    if (this.waiting) return 'waiting'
    return 'idle'
  }

  build() {
    Stack() {
      BotMark({ bot: this.bot, dark: this.dark, markSize: this.markSize, motion: this.motionOf() })
      if (this.waiting) {
        this.waitingBadge()
      } else if (this.working) {
        this.workingBadge()
      }
      if (this.main) {
        this.mainBadge()
      }
    }
    .width(this.markSize)
    .height(this.markSize)
  }
}

// A group avatar seats its members' characters like the desktop's RoomAvatar
// clusterSeats; below ~32px the members line up overlapped instead, and the
// gaps between seats are faked with a ring in the background color.
export interface Seat {
  x: number
  y: number
  seatSize: number
}

@ComponentV2
export struct RoomAvatar {
  @Param room: Room | undefined = undefined
  @Param bots: Bot[] = []
  @Param dark: boolean = false
  @Param markSize: number = 44
  @Param ring: string = ''

  private members(): Bot[] {
    const ids = this.room?.members ?? []
    const out: Bot[] = []
    for (const id of ids) {
      for (const bot of this.bots) {
        if (bot.id === id) {
          out.push(bot)
          break
        }
      }
    }
    return out
  }

  private memberAt(index: number): Bot | undefined {
    return this.members()[index]
  }

  private overlapMembers(): Bot[] {
    return this.members().slice(0, 3)
  }

  private overlap(): number {
    return this.markSize * 0.35
  }

  private overlapLeft(index: number): number {
    if (index === 0) {
      return 0
    }
    return -this.overlap()
  }

  private moreText(): string {
    return `+${this.members().length - 3}`
  }

  private gap(): number {
    return this.markSize / 14
  }

  private overflow(): number {
    const count = this.members().length
    if (count > 4) {
      return count - 3
    }
    return 0
  }

  private seats(): Seat[] {
    const frame = this.markSize
    const count = Math.min(this.members().length, 4)
    const seats: Seat[] = []
    if (count === 1) {
      seats.push({ x: 0, y: 0, seatSize: frame })
    } else if (count === 2) {
      seats.push({ x: 0, y: 0, seatSize: frame * 2 / 3 })
      seats.push({ x: frame / 3, y: frame / 3, seatSize: frame * 2 / 3 })
    } else if (count === 3) {
      const s = frame * 5 / 9
      const rest = frame - s
      seats.push({ x: rest / 2, y: 0, seatSize: s })
      seats.push({ x: 0, y: rest, seatSize: s })
      seats.push({ x: rest, y: rest, seatSize: s })
    } else if (count === 4) {
      const half = frame / 2
      seats.push({ x: 0, y: 0, seatSize: half })
      seats.push({ x: half, y: 0, seatSize: half })
      seats.push({ x: 0, y: half, seatSize: half })
      seats.push({ x: half, y: half, seatSize: half })
    }
    return seats
  }

  @Builder
  overlapRow() {
    Row() {
      ForEach(this.overlapMembers(), (bot: Bot, index: number) => {
        Column() {
          BotMark({ bot: bot, dark: this.dark, markSize: this.markSize })
        }
        .margin({ left: this.overlapLeft(index) })
        .zIndex(this.overlapMembers().length - index)
      }, (bot: Bot) => bot.id)
      if (this.members().length > 3) {
        Text(this.moreText())
          .fontSize(Math.max(9, Math.round(this.markSize * 0.4)))
          .fontColor('#888888')
          .margin({ left: -this.overlap() * 0.4 })
          .zIndex(0)
      }
    }
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  seatView(seat: Seat, index: number) {
    if (this.overflow() > 0 && index === 3) {
      Column() {
        Text(`+${this.overflow()}`)
          .fontSize(Math.max(8, Math.round(seat.seatSize * 0.36)))
          .fontColor('#888888')
      }
      .width(seat.seatSize)
      .height(seat.seatSize)
      .borderRadius(seat.seatSize / 2)
      .backgroundColor(this.ring)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .position({ x: seat.x, y: seat.y })
    } else {
      Column() {
        BotMark({ bot: this.memberAt(index), dark: this.dark, markSize: seat.seatSize })
      }
      .width(seat.seatSize + this.gap())
      .height(seat.seatSize + this.gap())
      .borderRadius((seat.seatSize + this.gap()) / 2)
      .backgroundColor(this.ring)
      .padding(this.gap() / 2)
      .position({ x: seat.x - this.gap() / 2, y: seat.y - this.gap() / 2 })
    }
  }

  @Builder
  cluster() {
    Stack() {
      ForEach(this.seats(), (seat: Seat, index: number) => {
        this.seatView(seat, index)
      }, (seat: Seat, index: number) => `${index}`)
    }
    .width(this.markSize)
    .height(this.markSize)
  }

  build() {
    if (this.members().length === 0) {
      Column()
        .width(this.markSize)
        .height(this.markSize)
        .borderRadius(this.markSize / 2)
        .backgroundColor(this.ring)
    } else if (this.markSize <= 32 && this.members().length > 1) {
      this.overlapRow()
    } else {
      this.cluster()
    }
  }
}
