import { Base64EncodeContent } from '../../components/toolbox/Base64EncodeContent'
import { ComposeTitleBar } from '@kit.ArkUI'

@Entry
@Component
struct Base64EncodePage {
  @Builder
  build() {
    Column() {
      ComposeTitleBar({
        title: 'Base64',
        subtitle: 'Base64编解码'
      })
      Base64EncodeContent()
        .layoutWeight(1)
        .margin({ left: 15, right: 15 })
    }
  }
}