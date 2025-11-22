import { HashVerifyContent } from '../../components/toolbox/HashVerifyContent'
import { ComposeTitleBar } from '@kit.ArkUI'

@Entry
@Component
struct HashVerifyPage {
  @Builder
  build() {
    Column() {
      ComposeTitleBar({
        title: '哈希校验',
        subtitle: '通过哈希值验证文件的完整性'
      })
      HashVerifyContent()
        .layoutWeight(1)
        .margin({ left: 15, right: 15 })
    }
  }
}