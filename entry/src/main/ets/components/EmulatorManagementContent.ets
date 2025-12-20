import { util } from '@kit.ArkTS';
import { Emulator } from '../model/Emulator';
import EditEmulatorContent from './EditEmulatorContent';
import EmulatorListGrid from './EmulatorListGrid';
import { CustomContentDialog } from '@kit.ArkUI';

@Component
export default struct EmulatorManagementContent {
  build() {
    Column() {
      Row() {
        Text('模拟器管理')
          .fontSize(18)
          .padding({ left: 15 })

        Blank().layoutWeight(1)

        Button('添加', { buttonStyle: ButtonStyleMode.TEXTUAL })
          .onClick(() => {
            const id = util.generateRandomUUID()
            this.getUIContext().getRouter().pushUrl({
              url: 'pages/EditEmulator',
              params: { id }
            })
          })

        SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
          .fontSize(24)
          .fontColor([$r('sys.color.icon_secondary')])
          .padding(4)
          .borderRadius(4)
          .hoverEffect(HoverEffect.Highlight)
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.8 })
          .margin({ right: 5 })
          .bindMenu([{
            value: '镜像管理',
            action: () => {
              this.getUIContext().getRouter().pushUrl({
                url: 'pages/RootfsManagement'
              })
            }
          }])
      }
      .height(56)

      EmulatorListGrid({
        onEditEmulator: (item, edit) => {
          if (edit) {
            this.getUIContext().getRouter().pushUrl({
              url: 'pages/EditEmulator',
              params: { id: item.id }
            })
          } else {
            this.openEditEmulatorDialog(item)
          }
        }
      })
    }
  }

  private openEditEmulatorDialog(item: Emulator) {
    const emulatorToEdit: Emulator = {
      id: item.id,
      name: item.name,
      init: item.init,
      cpu: item.cpu,
      memory: item.memory,
      portMapping: item.portMapping,
      rootVda: item.rootVda,
      rootFilesystem: item.rootFilesystem,
      sharedFolderReadonly: item.sharedFolderReadonly
    };
    const controller = new CustomDialogController({
      builder: CustomContentDialog({
        primaryTitle: item.name,
        contentBuilder: () => {
          this.buildEditEmulator(emulatorToEdit, (): void => controller.close());
        }
      })
    });
    controller.open();
  }

  @Builder
  buildEditEmulator(emulator: Emulator, onFinished: (item: Emulator) => void) {
    EditEmulatorContent({
      emulator: emulator,
      onFinished: onFinished,
      specifiedBreak: 'xs',
      titleBar: false,
      editing: false
    })
  }
}
