import { Emulator } from '../model/Emulator';
import { RepeatGrid } from './RepeatGrid';

@Preview
@Component
export default struct EmulatorManagement {
  @StorageProp('emulators') private emulators: Emulator[] = []

  aboutToAppear(): void {
    this.emulators = [{
      id: 'a',
      name: 'b',
      init: '',
      cpu: 1,
      memory: 512,
      portMapping: [],
      networking: true,
      rootFilesystem: '',
      sharedFolder: ''
    }]
  }

  @Builder
  buildEmulatorList(emulator: Emulator) {
    EmulatorItem()
  }

  build() {
    Column() {
      Row() {
        Text('模拟器管理')
          .fontSize(16)
          .padding({ left: 15 })

        Blank().layoutWeight(1)

        Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(24)
            .fontColor([$r('sys.color.icon_secondary')])
            .aspectRatio(1)
            .padding(4)
            .borderRadius(4)
        }
        .onClick(() => {
          this.getUIContext().getRouter().pushUrl({
            url: 'pages/EditEmulator'
          })
        })

        SymbolGlyph($r('sys.symbol.dot_grid_1x2'))
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
            }
          }, {
            value: '共享文件夹',
            action: () => {
            }
          }])
      }
      .height(56)

      Scroll() {
        RepeatGrid({
          items: this.emulators as object[],
          contentBuilder: (item: object, index: number) => {
            this.buildEmulatorList(item as Emulator)
          },
          getKey: (item: object, index: number) => (item as Emulator).id
        })
      }
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Auto)
      .scrollBarWidth(1)
      .layoutWeight(1)
      .align(Alignment.Top)
    }
  }
}

@Component
struct EmulatorItem {
  build() {
    Column() {
      Row() {
        Text('名称')
          .fontSize($r('sys.float.Body_L'))
          .fontColor($r('sys.color.font_primary'))
          .ellipsisMode(EllipsisMode.END)
          .maxLines(1)
          .layoutWeight(1)
        Text('运行中')
          .fontSize($r('sys.float.Body_S'))
          .fontColor('#FF5291FF')
      }
      .padding({
        left: 5,
        right: 5,
        top: 10,
        bottom: 10
      })
      .width('100%')

      Row() {
        Column() {
          Text('2核').fontSize($r('sys.float.Body_M')).fontColor($r('sys.color.font_primary'))
          Text('CPU').fontSize($r('sys.float.Body_S')).fontColor($r('sys.color.font_tertiary'))
            .margin({ top: 5 })
        }
        .layoutWeight(1)

        Column() {
          Text('2G').fontSize($r('sys.float.Body_M')).fontColor($r('sys.color.font_primary'))
          Text('内存').fontSize($r('sys.float.Body_S')).fontColor($r('sys.color.font_tertiary'))
            .margin({ top: 5 })
        }
        .layoutWeight(1)

        Column() {
          Text('128G').fontSize($r('sys.float.Body_M')).fontColor($r('sys.color.font_primary'))
          Text('虚拟盘').fontSize($r('sys.float.Body_S')).fontColor($r('sys.color.font_tertiary'))
            .margin({ top: 5 })
        }
        .layoutWeight(1)

        Column() {
          Text('开启').fontSize($r('sys.float.Body_M')).fontColor($r('sys.color.font_primary'))
          Text('网络').fontSize($r('sys.float.Body_S')).fontColor($r('sys.color.font_tertiary'))
            .margin({ top: 5 })
        }
        .layoutWeight(1)
      }
      .padding({ top: 10, bottom: 10 })
      .borderRadius(10)
      .backgroundColor($r('app.color.setting_block_background_2'))
      .width('100%')

      Row() {
        Row() {
          Checkbox().size({ width: $r('sys.float.Body_L'), height: $r('sys.float.Body_L') })
          Text('设为默认').fontSize($r('sys.float.Body_M')).fontColor($r('sys.color.font_tertiary'))
        }
        .clickEffect({ level: ClickEffectLevel.LIGHT })

        Blank().layoutWeight(1)
        Button('删除', { buttonStyle: ButtonStyleMode.TEXTUAL, controlSize: ControlSize.SMALL })
          .fontSize($r('sys.float.Body_M'))
        Button('修改', { buttonStyle: ButtonStyleMode.TEXTUAL, controlSize: ControlSize.SMALL })
          .fontSize($r('sys.float.Body_M'))
        Button('复制', { buttonStyle: ButtonStyleMode.TEXTUAL, controlSize: ControlSize.SMALL })
          .fontSize($r('sys.float.Body_M'))
      }
      .padding({ top: 5, bottom: 5 })
      .width('100%')
    }
    .borderRadius(10)
    .padding({
      left: 10,
      right: 10
    })
    .backgroundColor($r('app.color.setting_block_background'))
  }
}
