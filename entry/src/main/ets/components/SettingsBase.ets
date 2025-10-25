@Component
export struct BlockTitle {
  content?: string | Resource

  build() {
    Text(this.content)
      .margin({ bottom: 10, left: 20 })
      .width('100%')
  }
}

export class SettingBlockStyle implements AttributeModifier<ColumnAttribute> {
  applyNormalAttribute(instance: ColumnAttribute): void {
    instance.borderRadius(20)
      .backgroundColor($r('app.color.setting_block_background'))
      .margin({ bottom: 20 })
  }
}

@Component
export struct ItemTitle {
  @Prop title: string | Resource
  @Prop subTitle: string | Resource

  build() {
    Column() {
      Text(this.title).fontSize($r('sys.float.Body_L')).fontColor($r('sys.color.font_primary'))
      Text(this.subTitle).fontSize($r('sys.float.Body_M')).fontColor($r('sys.color.font_tertiary'))
    }
    .flexGrow(1)
    .alignItems(HorizontalAlign.Start)
  }
}

@Component
export struct SettingItem {
  @Prop title: string | Resource
  @Prop subTitle: string | Resource
  @Prop icon: Resource | undefined
  @BuilderParam content?: () => void

  build() {

    Row() {
      ItemTitle({
        title: this.title,
        subTitle: this.subTitle
      })

      if (this.content) {
        this.content()
      }
      if (this.icon) {
        SymbolGlyph(this.icon)
          .fontColor([$r('sys.color.icon_secondary')])
          .fontSize('24vp')
      }
    }
    .alignItems(VerticalAlign.Center)
    .width('100%')
    .height(56)
    .padding({ left: $r('sys.float.padding_level6'), right: $r('sys.float.padding_level6') })
  }
}

@Component
export struct LinkItem {
  @Prop icon: Resource
  @Prop title: string | Resource
  @Prop subTitle: string | Resource
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
      .flexGrow(1)
      .alignItems(HorizontalAlign.Start)

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