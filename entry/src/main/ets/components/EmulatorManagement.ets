import { util } from '@kit.ArkTS';
import EmulatorListGrid from './EmulatorListGrid';

@Component
export default struct EmulatorManagement {
  build() {
    Column() {
      Row() {
        Text('模拟器管理')
          .fontSize(16)
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
            value: '共享文件夹',
            action: () => {
              this.getUIContext().getRouter().pushUrl({
                url: 'pages/SharedFolder'
              })
            }
          }, {
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
        onEditEmulator: (item) => {
          this.getUIContext().getRouter().pushUrl({
            url: 'pages/EditEmulator',
            params: { id: item.id }
          })
        }
      })
    }
  }
}
