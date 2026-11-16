// The character pickers from manage.tsx: square shape cells drawn with the
// Bot's mark (shape swapped per cell), color cells drawn with COLOR_PAINT.
// Both wrap in fixed 52px cells with a 2px accent border on the picked one.

import { appStore, inkColor } from './Theme'
import { COLOR_PAINT } from '../common/ui/characters'
import { Avatar } from './Marks'
import { PICKER_SHAPES, CHARACTER_COLORS } from '../common/ui/characters-table'
import type { Bot, BotAvatar } from '../common/team/types'

const CELL = 52
const PREVIEW = 37

@ComponentV2
export struct CharacterShapeGrid {
  @Require @Param bot: Bot
  @Param color: string = ''
  @Param picked: string = ''
  @Event onPick: (id: string) => void = (id: string) => {}

  private pickedBorder(id: string): number {
    return this.picked === id ? 2 : 1
  }

  private cellBorderColor(id: string): string {
    if (this.picked === id) {
      return appStore.theme.p.accent
    }
    return appStore.theme.p.line
  }

  // The Bot's look with one shape swapped in, at the current color.
  private previewBot(id: string): Bot {
    const shape: BotAvatar = { shape: id }
    const image = this.bot.avatar?.image
    if (image !== undefined) shape.image = image
    const colorId = this.color !== '' ? this.color : (this.bot.color ?? 'blue')
    return { id: this.bot.id, name: this.bot.name, color: colorId, avatar: shape }
  }

  build() {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(PICKER_SHAPES, (id: string) => {
        Column() {
          Avatar({
            bot: this.previewBot(id),
            dark: appStore.theme.dark,
            markSize: PREVIEW,
            ring: appStore.theme.p.card,
          })
        }
        .width(CELL)
        .height(CELL)
        .borderRadius(14)
        .border({ width: this.pickedBorder(id), color: this.cellBorderColor(id) })
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
        .accessibilityText(id)
        .onClick(() => this.onPick(id))
      }, (id: string) => id)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
  }
}

@ComponentV2
export struct CharacterColorGrid {
  @Param picked: string = ''
  @Param dark: boolean = false
  @Event onPick: (id: string) => void = (id: string) => {}

  private paintOf(id: string): string {
    const paint = COLOR_PAINT[id]
    if (paint !== undefined) return paint
    return inkColor(id, this.dark)
  }

  private pickedBorder(id: string): number {
    return this.picked === id ? 2 : 1
  }

  private cellBorderColor(id: string): string {
    if (this.picked === id) {
      return appStore.theme.p.accent
    }
    return appStore.theme.p.line
  }

  build() {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(CHARACTER_COLORS, (id: string) => {
        Column() {
          Column()
            .width(27)
            .height(27)
            .borderRadius(27)
            .backgroundColor(this.paintOf(id))
        }
        .width(CELL)
        .height(CELL)
        .borderRadius(14)
        .border({ width: this.pickedBorder(id), color: this.cellBorderColor(id) })
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
        .accessibilityText(id)
        .onClick(() => this.onPick(id))
      }, (id: string) => id)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
  }
}
