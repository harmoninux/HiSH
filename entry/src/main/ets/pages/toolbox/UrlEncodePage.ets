import { ComposeTitleBar } from '@kit.ArkUI'
import { UrlEncodeContent } from '../../components/toolbox/UrlEncodeContent'

@Entry
@Component
struct UrlEncodePage {
  @Builder
  build() {
    Column() {
      ComposeTitleBar({
        title: 'URL Encoding',
        subtitle: 'URL Encoding 编解码'
      })
      UrlEncodeContent()
        .layoutWeight(1)
        .margin({ left: 15, right: 15 })
    }
  }
}