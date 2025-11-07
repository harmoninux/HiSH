import { Emulator } from '../model/Emulator';
import { RepeatGrid } from './RepeatGrid';
import { util } from '@kit.ArkTS';

@Preview
@Component
export default struct EmulatorManagement {
  @StorageProp('emulators') private emulators: Emulator[] = []

  @Builder
  buildEmulatorList(emulator: Emulator) {
    EmulatorItem({
      emulator,
      isRunning: true,
      isDefault: true,
      onEdit: (item) => {
        this.getUIContext().getRouter().pushUrl({
          url: 'pages/EditEmulator',
          params: { id: item.id }
        })
      },
      onDelete: (item) => {
      },
      onCopy: (item) => {
      }
    })
  }

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
  @Require emulator: Emulator
  @Require isRunning: boolean
  @Require isDefault: boolean
  @Require onEdit: (item: Emulator) => void
  @Require onDelete: (item: Emulator) => void
  @Require onCopy: (item: Emulator) => void
  @State storageSize: number = 0

  aboutToAppear(): void {
    this.storageSize = 128
  }

  build() {
    Column() {
      Row() {
        Text(this.emulator.name)
          .fontSize($r('sys.float.Body_L'))
          .fontColor($r('sys.color.font_primary'))
          .ellipsisMode(EllipsisMode.END)
          .maxLines(1)
          .layoutWeight(1)
        if (this.isRunning) {
          Text('运行中')
            .fontSize($r('sys.float.Body_S'))
            .fontColor('#FF5291FF')
        }
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
          Text(this.emulator.cpu + '核').fontSize($r('sys.float.Body_M')).fontColor($r('sys.color.font_primary'))
          Text('CPU').fontSize($r('sys.float.Body_S')).fontColor($r('sys.color.font_tertiary'))
            .margin({ top: 5 })
        }
        .layoutWeight(1)

        Column() {
          Text(this.emulator.memory + 'MB').fontSize($r('sys.float.Body_M')).fontColor($r('sys.color.font_primary'))
          Text('内存').fontSize($r('sys.float.Body_S')).fontColor($r('sys.color.font_tertiary'))
            .margin({ top: 5 })
        }
        .layoutWeight(1)

        Column() {
          Text(this.storageSize + 'GB').fontSize($r('sys.float.Body_M')).fontColor($r('sys.color.font_primary'))
          Text('虚拟盘').fontSize($r('sys.float.Body_S')).fontColor($r('sys.color.font_tertiary'))
            .margin({ top: 5 })
        }
        .layoutWeight(1)

        Column() {
          Text(this.emulator.networking ? '开启' : '关闭')
            .fontSize($r('sys.float.Body_M'))
            .fontColor($r('sys.color.font_primary'))
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
          Checkbox()
            .select(this.isDefault)
            .size({ width: $r('sys.float.Body_L'), height: $r('sys.float.Body_L') })
            .enabled(!this.isDefault)
          Text('设为默认').fontSize($r('sys.float.Body_M')).fontColor($r('sys.color.font_tertiary'))
        }
        .clickEffect({ level: ClickEffectLevel.LIGHT })

        Blank().layoutWeight(1)
        Button('删除', { buttonStyle: ButtonStyleMode.TEXTUAL, controlSize: ControlSize.SMALL })
          .fontSize($r('sys.float.Body_M'))
          .onClick(() => this.onDelete(this.emulator))
        Button('修改', { buttonStyle: ButtonStyleMode.TEXTUAL, controlSize: ControlSize.SMALL })
          .fontSize($r('sys.float.Body_M'))
          .onClick(() => this.onEdit(this.emulator))
        Button('复制', { buttonStyle: ButtonStyleMode.TEXTUAL, controlSize: ControlSize.SMALL })
          .fontSize($r('sys.float.Body_M'))
          .onClick(() => this.onCopy(this.emulator))
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
