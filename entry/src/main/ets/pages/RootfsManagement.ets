import RootfsManagementContent from '../components/RootfsManagementContent'
import { CustomContentDialog } from '@kit.ArkUI'
import DataDiskManagementContent from '../components/DataDiskManagementContent'

@Entry
@Component
struct RootfsManagement {
  dataDiskManagementController: CustomDialogController = new CustomDialogController({
    builder: CustomContentDialog({
      primaryTitle: $r('app.string.data_disk_management'),
      contentBuilder: () => {
        this.buildDataDiskManagement();
      }
    })
  })

  build() {
    Column() {
      RootfsManagementContent({
        toolBar: true,
        onOpenDataDiskManagement: () => {
          this.dataDiskManagementController.open()
        }
      })
    }
  }

  @Builder
  buildDataDiskManagement() {
    Column() {
      DataDiskManagementContent({
        titleBar: false,
        specifiedBreak: 'xs'
      })
    }
  }
}