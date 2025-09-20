@Component
export struct LinkItem {
  @Prop icon: Resource
  @Prop title: string
  @Prop subTitle: string
  click?: () => void

  build() {
    Row() {
      SymbolGlyph(this.icon)
        .fontSize('24vp')
        .margin({ right: $r('sys.float.padding_level8') })
        .fontColor([$r('sys.color.icon_emphasize')])
      Column() {
        Text(this.title).fontSize($r('sys.float.Body_L')).fontColor($r('sys.color.font_primary'))
        Text(this.subTitle).fontSize($r('sys.float.Body_M')).fontColor($r('sys.color.font_tertiary'))
      }
      .width('70%')
      .alignItems(HorizontalAlign.Start)

      Blank()

      if (this.click) {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontColor([$r('sys.color.icon_secondary')])
          .fontSize('24vp')
      }
    }
    .onClick(() => {
      if (this.click) {
        this.click();
      }
    })
    .alignItems(VerticalAlign.Center)
    .width('100%')
    .height(56)
    .padding({ left: $r('sys.float.padding_level6'), right: $r('sys.float.padding_level6') })
  }
}