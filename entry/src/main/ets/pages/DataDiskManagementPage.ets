import { ComposeTitleBar } from '@kit.ArkUI'
import DataDiskManagementContent from '../components/DataDiskManagementContent'

@Entry
@Component
struct DataDiskManagementPage {
  build() {
    Column() {
      ComposeTitleBar({
        title: $r('app.string.data_disk_management')
      })
      Column() {
        DataDiskManagementContent({ titleBar: false })
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
  }
}
