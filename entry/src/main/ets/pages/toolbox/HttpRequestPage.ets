import { ComposeTitleBar } from '@kit.ArkUI'
import { HttpRequestContent } from '../../components/toolbox/HttpRequestContent'

@Entry
@Component
struct HttpRequestPage {
  build() {
    Column() {
      ComposeTitleBar({
        title: 'HTTP',
        subtitle: '调试HTTP接口'
      })
      HttpRequestContent()
        .layoutWeight(1)
        .margin({ left: 15, right: 15 })
    }
  }
}