import appOption from "../model/appOption"
import { RootFilesystem } from "../model/Emulator"
import { util } from "@kit.ArkTS"
import { RepeatGrid } from "../components/RepeatGrid"

@Entry
@Component
struct RootfsManagement {
  @StorageProp(appOption.rootFilesystems) private roots: RootFilesystem[] = []

  @Builder
  buildEmulatorList(value: RootFilesystem) {
    RootFilesystemItem({
      value,
      onEdit: (item) => {
        this.getUIContext().getRouter().pushUrl({
          url: 'pages/EditEmulator',
          params: { id: item.id }
        })
      },
      onDelete: (item) => {
      }
    })
  }

  build() {
    Column() {
      Row() {
        Text('镜像管理')
          .fontSize(16)
          .padding({ left: 15 })

        Blank().layoutWeight(1)

        Button('添加', { buttonStyle: ButtonStyleMode.TEXTUAL })
          .onClick(() => {
            const id = util.generateRandomUUID()
            this.getUIContext().getRouter().pushUrl({
              url: 'pages/EditRootFilesystem',
              params: { id }
            })
          })
      }
      .height(56)

      Scroll() {
        RepeatGrid({
          items: this.roots as object[],
          contentBuilder: (item: object, index: number) => {
            this.buildEmulatorList(item as RootFilesystem)
          },
          getKey: (item: object, index: number) => (item as RootFilesystem).id
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
struct RootFilesystemItem {
  @Require value: RootFilesystem
  @Require onEdit: (item: RootFilesystem) => void
  @Require onDelete: (item: RootFilesystem) => void
  @State storageSize: number = 0

  aboutToAppear(): void {
    this.storageSize = 128
  }

  build() {
    Column() {
      Row() {
        Text(this.value.name)
          .fontSize($r('sys.float.Body_L'))
          .fontColor($r('sys.color.font_primary'))
          .ellipsisMode(EllipsisMode.END)
          .maxLines(1)
          .layoutWeight(1)
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
          Text('64MB').fontSize($r('sys.float.Body_M')).fontColor($r('sys.color.font_primary'))
          Text('文件大小').fontSize($r('sys.float.Body_S')).fontColor($r('sys.color.font_tertiary'))
            .margin({ top: 5 })
        }
        .layoutWeight(1)

        Column() {
          Text('128GB').fontSize($r('sys.float.Body_M')).fontColor($r('sys.color.font_primary'))
          Text('虚拟大小').fontSize($r('sys.float.Body_S')).fontColor($r('sys.color.font_tertiary'))
            .margin({ top: 5 })
        }
        .layoutWeight(1)
      }
      .padding({ top: 10, bottom: 10 })
      .borderRadius(10)
      .backgroundColor($r('app.color.setting_block_background_2'))
      .width('100%')

      Row() {
        Blank().layoutWeight(1)
        Button('删除', { buttonStyle: ButtonStyleMode.TEXTUAL, controlSize: ControlSize.SMALL })
          .fontSize($r('sys.float.Body_M'))
          .onClick(() => this.onDelete(this.value))
        Button('修改', { buttonStyle: ButtonStyleMode.TEXTUAL, controlSize: ControlSize.SMALL })
          .fontSize($r('sys.float.Body_M'))
          .onClick(() => this.onEdit(this.value))
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
