import { common } from "@kit.AbilityKit"
import { hash, picker } from "@kit.CoreFileKit"
import { uri } from "@kit.ArkTS"

const algorithms: SelectOption[] = [{
  value: 'MD5'
}, {
  value: 'SHA1'
}, {
  value: 'SHA256'
}]

@Component
export struct HashVerifyContent {
  @State algo: string = 'MD5'
  @State expected: string = ''
  @State fileName?: string = undefined
  @State fileHash?: string = undefined
  @State result?: boolean = undefined

  build() {
    Column() {
      Row() {
        Text('选择算法：')
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

      if (this.fileName !== undefined) {
        Text(this.fileName)
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .ellipsisMode(EllipsisMode.START)
          .textAlign(TextAlign.Center)
          .margin({ bottom: 5 })
      }
      Button(this.fileName ? '重新选择文件' : '选择文件', { buttonStyle: ButtonStyleMode.TEXTUAL })
        .width('100%')
        .margin({ bottom: 15 })
        .onClick(() => this.selectFileToVerify())

      if (this.fileHash !== undefined) {
        if (this.expected.toLowerCase() === this.fileHash.toLowerCase()) {
          Row() {
            Text('验证通过')
              .fontColor('#388E3C')
            Text(this.fileHash)
              .fontColor('#388E3C')
          }
        } else if (this.expected.length > 0) {
          Column() {
            Text('验证不通过')
              .fontColor('#E57373')
            Text(this.fileHash)
              .fontColor('#E57373')
          }
        } else {
          Column() {
            Text('文件哈希值')
            Text(this.fileHash)
          }
        }
      }
    }
    .padding(10)
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

      this.fileName = srcUri.path
      this.fileHash = await hash.hash(srcUri.path, this.algo.toLowerCase())
    } catch (e) {
      this.fileName = undefined
      this.fileHash = undefined
    }
  }
}