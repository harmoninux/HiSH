import copyToClipboard from "../../lib/copyToClipboard"

@Component
struct UrlEncoder {
  @Watch('onContentChanged') @State content: string = ''
  @State encoded: string = ''

  build() {
    Column() {
      TextArea({ placeholder: '输入内容', text: this.content })
        .height(200)
        .margin({ bottom: 10 })
        .onChange((value) => this.content = value)
      Column() {
        Row() {
          Text('编码结果')
            .fontSize($r('sys.float.Body_L'))
            .fontColor($r('sys.color.font_primary'))
          Blank().layoutWeight(1)
          Button('复制', { buttonStyle: ButtonStyleMode.TEXTUAL })
            .onClick(() => this.copyEncoded())
        }
        .padding({ left: 10, right: 10 })

        Scroll() {
          Text(this.encoded)
            .padding(5)
        }
        .scrollable(ScrollDirection.Vertical)
        .scrollBar(BarState.Auto)
        .scrollBarWidth(1)
        .layoutWeight(1)
        .align(Alignment.Top)
      }
      .layoutWeight(1)
      .borderRadius(10)
      .backgroundColor($r('app.color.setting_block_background'))
    }
  }

  async onContentChanged() {
    const content = this.content
    this.encoded = encodeURIComponent(content)
  }

  private async copyEncoded() {
    await copyToClipboard(this.encoded!!, this.getUIContext())
  }
}

@Component
struct UrlDecoder {
  @Watch('onContentChanged') @State content: string = ''
  @State decoded: string = ''

  build() {
    Column() {
      TextArea({ placeholder: '输入URL Encoding', text: this.content })
        .height(200)
        .margin({ bottom: 10 })
        .onChange((value) => this.content = value)
      Column() {
        Row() {
          Text('解码结果')
            .fontSize($r('sys.float.Body_L'))
            .fontColor($r('sys.color.font_primary'))
          Blank().layoutWeight(1)
          Button('复制', { buttonStyle: ButtonStyleMode.TEXTUAL })
            .onClick(() => this.copyEncoded())
        }
        .padding({ left: 10, right: 10 })

        Scroll() {
          Text(this.decoded)
            .padding(5)
        }
        .scrollable(ScrollDirection.Vertical)
        .scrollBar(BarState.Auto)
        .scrollBarWidth(1)
        .layoutWeight(1)
        .align(Alignment.Top)
      }
      .layoutWeight(1)
      .borderRadius(10)
      .backgroundColor($r('app.color.setting_block_background'))
    }
  }

  async onContentChanged() {
    const content = this.content
    this.decoded = decodeURIComponent(content)
  }

  private async copyEncoded() {
    await copyToClipboard(this.decoded!!, this.getUIContext())
  }
}

@Component
export struct UrlEncodeContent {
  build() {
    Column() {
      Tabs() {
        TabContent() {
          UrlEncoder()
        }.tabBar(SubTabBarStyle.of('编码'))

        TabContent() {
          UrlDecoder()
        }.tabBar(SubTabBarStyle.of('解码'))
      }
      .height('100%')
      .barMode(BarMode.Fixed)
    }
  }
}