import { ComposeTitleBar } from '@kit.ArkUI'
import { PortScannerContent } from '../../components/toolbox/PortScannerContent'

@Entry
@Component
struct PortScannerPage {
  @Builder
  build() {
    Column() {
      ComposeTitleBar({
        title: '端口扫描'
      })
      PortScannerContent()
        .layoutWeight(1)
        .margin({ left: 15, right: 15 })
    }
  }
}