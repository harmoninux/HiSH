import { hash } from "@kit.CoreFileKit"
import { pasteboard } from "@kit.BasicServicesKit"
import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN = 0x0000

const algorithms: SelectOption[] = [{
  value: 'MD5'
}, {
  value: 'SHA1'
}, {
  value: 'SHA256'
}]

@Component
export struct HashGenerateContent {
  @Watch('computeHash') @State algo: string = 'MD5'
  @Watch('computeHash') @State data: string = ''
  @State hashValue?: string = undefined

  build() {
    Column() {
      Row() {
        Text('选择算法')
          .fontSize($r('sys.float.Body_L'))
          .fontColor($r('sys.color.font_secondary'))
        Blank().layoutWeight(1)
        Select(algorithms)
          .width(140)
          .value(this.algo)
          .onSelect((i, value) => this.algo = value)
      }
      .width('100%')
      .margin({ bottom: 15 })

      TextArea({text: this.data, placeholder: '输入数据'})
        .width('100%')
        .height(300)
        .margin({ bottom: 15 })
        .onChange((value) => this.data = value)

      if (this.hashValue !== undefined) {
        Text('哈希值')
          .fontColor($r('sys.color.font_secondary'))
        Text(this.hashValue)
          .fontColor($r('sys.color.font_secondary'))
        Button('复制', { buttonStyle: ButtonStyleMode.TEXTUAL })
          .onClick(() => {
            this.copyHashValue()
          })
      }
    }
  }

  async copyHashValue() {
    try {
      const pasteboardData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.hashValue!!);
      const systemPasteboard = pasteboard.getSystemPasteboard();
      await systemPasteboard.setData(pasteboardData);

      this.getUIContext().getPromptAction().showToast({
        message: '已复制到剪贴板',
        duration: 2000
      })
    } catch (e) {
      hilog.error(DOMAIN, 'HashGenerateContent', '复制到剪贴板失败: %{public}s', JSON.stringify(e))
    }
  }

  async computeHash() {
    const h = hash.createHash(this.algo.toLowerCase())
    h.write(this.data)
    this.hashValue = h.digest()
  }
}