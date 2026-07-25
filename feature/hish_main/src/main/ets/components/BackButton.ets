@Component
export struct BackButton {
  build() {
    SymbolGlyph($r('sys.symbol.arrow_left'))
      .fontSize(24)
      .fontColor([$r('sys.color.icon_secondary')])
      .padding(4)
      .borderRadius(4)
      .hoverEffect(HoverEffect.Highlight)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.8 })
      .margin({ right: 5 })
      .onClick(() => {
        this.getUIContext().getRouter().back()
      })
  }
}