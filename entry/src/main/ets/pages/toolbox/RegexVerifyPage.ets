import { ComposeTitleBar } from '@kit.ArkUI'
import { RegexVerifyContent } from '../../components/toolbox/RegexVerifyContent'

@Entry
@Component
struct RegexVerifyPage {
  @Builder
  build() {
    Column() {
      ComposeTitleBar({
        title: '正则验证',
        subtitle: '验证正则表达式'
      })
      RegexVerifyContent()
        .layoutWeight(1)
        .margin({ left: 15, right: 15 })
    }
  }
}