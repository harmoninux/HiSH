import { util } from "@kit.ArkTS"
import { pasteboard } from "@kit.BasicServicesKit"

@Component
struct Base64Encoder {
  @Watch('onContentChanged') @State content: string = ''
  @State encoded: string = ''

  build() {
    Column() {
      TextArea({ placeholder: '输入内容', text: this.content })
        .height(200)
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
        .padding(10)

        Text(this.encoded)
          .padding(5)
      }
      .layoutWeight(1)
      .borderRadius(10)
      .backgroundColor($r('app.color.setting_block_background'))
    }
  }

  async onContentChanged() {
    const content = this.content
    const helper = new util.Base64Helper()
    const a = util.TextEncoder.create('utf-8').encodeInto(content)
    this.encoded = await helper.encodeToString(a)
  }

  private async copyEncoded() {
    try {
      const pasteboardData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.encoded!!);
      const systemPasteboard = pasteboard.getSystemPasteboard();
      await systemPasteboard.setData(pasteboardData);
      this.getUIContext().getPromptAction().showToast({
        message: '已复制到剪贴板',
        duration: 2000
      })
    } catch (e) {
      console.log(e)
    }
  }
}

@Component
struct Base64Decoder {
  @Watch('onContentChanged') @State content: string = ''
  @State decoded: string = ''

  build() {
    Column() {
      TextArea({ placeholder: '输入base64', text: this.content })
        .height(200)
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
        .padding(10)

        Text(this.decoded)
          .padding(5)
      }
      .layoutWeight(1)
      .borderRadius(10)
      .backgroundColor($r('app.color.setting_block_background'))
    }
  }

  async onContentChanged() {
    const content = this.content
    const helper = new util.Base64Helper()
    const a: Uint8Array = await helper.decode(content)
    this.decoded = util.TextDecoder.create('utf-8').decodeToString(a)
  }

  private async copyEncoded() {
    try {
      const pasteboardData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.decoded!!);
      const systemPasteboard = pasteboard.getSystemPasteboard();
      await systemPasteboard.setData(pasteboardData);
      this.getUIContext().getPromptAction().showToast({
        message: '已复制到剪贴板',
        duration: 2000
      })
    } catch (e) {
      console.log(e)
    }
  }
}

@Component
export struct Base64EncodeContent {
  build() {
    Column() {
      Tabs() {
        TabContent() {
          Base64Encoder()
        }.tabBar(SubTabBarStyle.of('编码'))

        TabContent() {
          Base64Decoder()
        }.tabBar(SubTabBarStyle.of('解码'))
      }
      .height('100%')
      .barMode(BarMode.Fixed)
    }
  }
}