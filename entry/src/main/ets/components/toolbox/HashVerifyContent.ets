import { common } from "@kit.AbilityKit"
import { hash, picker } from "@kit.CoreFileKit"
import { uri } from "@kit.ArkTS"
import { pasteboard } from "@kit.BasicServicesKit"
import { LoadingDialog } from "@kit.ArkUI"

const algorithms: SelectOption[] = [{
  value: 'MD5'
}, {
  value: 'SHA1'
}, {
  value: 'SHA256'
}]

@Component
export struct HashVerifyContent {
  @Watch('computeHash') @State algo: string = 'MD5'
  @State expected: string = ''
  @Watch('computeHash') @State filePath?: string = undefined
  @State fileHash?: string = undefined
  @State result?: boolean = undefined

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

      TextInput({ text: this.expected, placeholder: '输入哈希值' })
        .width('100%')
        .margin({ bottom: 15 })
        .onChange((value) => this.expected = value)

      if (this.filePath !== undefined) {
        Text(this.filePath)
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .ellipsisMode(EllipsisMode.START)
          .textAlign(TextAlign.Center)
          .margin({ bottom: 5 })
      }
      Button(this.filePath ? '重新选择文件' : '选择文件', { buttonStyle: ButtonStyleMode.TEXTUAL })
        .width('100%')
        .margin({ bottom: 15 })
        .onClick(() => this.selectFileToVerify())

      if (this.fileHash !== undefined) {
        Column() {
          if (this.expected.toLowerCase() === this.fileHash.toLowerCase()) {
            Text('验证通过')
              .fontColor('#388E3C')
            Text(this.fileHash)
              .fontColor('#388E3C')
          } else if (this.expected.length > 0) {
            Text('验证不通过')
              .fontColor('#E57373')
            Text(this.fileHash)
              .fontColor('#E57373')
          } else {
            Text('文件哈希值')
              .fontColor($r('sys.color.font_secondary'))
            Text(this.fileHash)
              .fontColor($r('sys.color.font_secondary'))
          }
          Button('复制', { buttonStyle: ButtonStyleMode.TEXTUAL })
            .onClick(() => {
              this.copyHashValue()
            })
        }
      }
    }
    .padding(10)
  }

  async copyHashValue() {
    try {
      const pasteboardData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.fileHash!!);
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

  async selectFileToVerify() {

    try {
      let context = this.getUIContext().getHostContext() as common.UIAbilityContext;

      let options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;

      let documentPicker = new picker.DocumentViewPicker(context);
      let uris = await documentPicker.select(options);

      if (uris.length == 0) {
        return
      }

      const srcUri = new uri.URI(uris[0])

      this.filePath = srcUri.path
    } catch (e) {
      this.filePath = undefined
    }
  }

  async computeHash() {
    const progress = new CustomDialogController({
      builder: LoadingDialog({
        content: '正在计算哈希'
      })
    })
    progress.open()
    try {
      if (this.filePath) {
        this.fileHash = await hash.hash(this.filePath!!, this.algo.toLowerCase())
      } else {
        this.fileHash = undefined
      }
    } catch (e) {
      this.fileHash = undefined
    } finally {
      progress.close()
    }
  }
}