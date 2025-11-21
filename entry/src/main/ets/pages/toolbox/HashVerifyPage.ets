import { HashVerifyContent } from '../../components/toolbox/HashVerifyContent'
import { ComposeTitleBar } from '@kit.ArkUI'

@Entry
@Component
struct HashVerifyPage {
  @Builder
  build() {
    Column() {
      ComposeTitleBar({
        title: '哈希校验'
      })
      HashVerifyContent()
    }
  }
}