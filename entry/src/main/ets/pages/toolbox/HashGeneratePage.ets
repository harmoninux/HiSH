import { ComposeTitleBar } from '@kit.ArkUI'
import { HashGenerateContent } from '../../components/toolbox/HashGenerateContent'

@Entry
@Component
struct HashGeneratePage {
  @Builder
  build() {
    Column() {
      ComposeTitleBar({
        title: '哈希生成',
        subtitle: '生成数据的哈希值'
      })
      HashGenerateContent()
        .layoutWeight(1)
        .margin({ left: 15, right: 15 })
    }
  }
}