import { fileIo as fs } from '@kit.CoreFileKit'
import { defaultEmulator, Emulator } from '../model/Emulator';
import { RepeatGrid } from './RepeatGrid';
import { util } from '@kit.ArkTS';
import appOption, { savePreference } from '../model/appOption';
import readQcow2VirtualSize from '../lib/readQcow2VirtualSize';
import { CustomContentDialog, LoadingDialog } from '@kit.ArkUI';
import copyFile from '../lib/copyFile';

@Component
export default struct EmulatorManagement {
  @State selectedIdToCopy?: string = undefined
  @State tempEmulatorName: string = ''
  @StorageLink(appOption.emulators) emulators: Emulator[] = []
  emulatorNameController = new CustomDialogController({
    builder: CustomContentDialog({
      primaryTitle: '复制',
      secondaryTitle: '输入新的模拟器名称，请注意不要重复',
      contentBuilder: () => {
        this.buildInputEmulatorName()
      }
    })
  })
  copyProgress: CustomDialogController = new CustomDialogController({
    builder: LoadingDialog({
      content: '正在复制',
    }),
  })
  filesDir = this.getUIContext().getHostContext()!!.getApplicationContext().filesDir

  @Builder
  buildInputEmulatorName() {
    Column() {
      TextInput({
        text: this.tempEmulatorName,
        placeholder: '输入镜像名称'
      })
        .onChange((value) => {
          this.tempEmulatorName = value;
        })
      Button('完成')
        .margin({ top: 10 })
        .width('100%')
        .enabled(this.validateEmulatorName())
        .onClick(async () => {
          this.emulatorNameController.close()
          await this.copyEmulatorItem()
        })
    }
  }

  validateEmulatorName(): boolean {
    const name = this.tempEmulatorName.trim();
    if (name.length <= 0) {
      return false
    }
    const used = this.emulators.findIndex(it => it.name === name) >= 0
    if (used) {
      return false
    }
    return true
  }

  @Builder
  buildEmulatorList(emulator: Emulator) {
    EmulatorItem({
      emulator: emulator,
      isRunning: true,
      isDefault: true,
      onEdit: (item) => {
        this.getUIContext().getRouter().pushUrl({
          url: 'pages/EditEmulator',
          params: { id: item.id }
        })
      },
      onDelete: (item) => {
        this.getUIContext().showAlertDialog({
          title: '确定删除',
          message: '您正在操作删除模拟器，删除后不可恢复，确定操作？',
          autoCancel: true,
          alignment: DialogAlignment.Center,
          buttons: [
            {
              value: $r('app.string.setting_generic_cancel'),
              action: () => {
              }
            },
            {
              enabled: true,
              style: DialogButtonStyle.HIGHLIGHT,
              backgroundColor: $r('sys.color.warning'),
              value: $r('app.string.confirm_remove'),
              action: async () => {
                this.deleteEmulatorItem(item)
              }
            }
          ],
        });
      },
      onCopy: (item) => {
        this.selectedIdToCopy = item.id
        this.emulatorNameController.open()
      }
    })
  }

  deleteEmulatorItem(item: Emulator) {

    const i = this.emulators.findIndex(it => it.id === item.id)

    const rootfs = item.rootFilesystem
    fs.unlinkSync(rootfs)

    this.emulators.splice(i, 1)
  }

  async copyEmulatorItem() {

    const src = this.emulators.find(it => it.id === this.selectedIdToCopy)!!

    const id = util.generateRandomUUID()

    const rootfsBase = AppStorage.get(appOption.vmBaseDir) as string;
    const target = rootfsBase + '/' + id + src.rootFilesystem.substring(src.rootFilesystem.lastIndexOf('.'))

    const srcRootfs =
      src.rootFilesystem.startsWith('/') ? src.rootFilesystem : (this.filesDir + '/' + src.rootFilesystem)

    this.copyProgress.open()
    try {
      await copyFile(srcRootfs, target)

      const emulator: Emulator = {
        id,
        name: this.tempEmulatorName,
        cpu: src.cpu,
        memory: src.memory,
        networking: src.networking,
        init: src.init,
        portMapping: src.portMapping,
        rootFilesystem: target,
        sharedFolderReadonly: src.sharedFolderReadonly
      }
      this.emulators.push(emulator)

      await savePreference(appOption.emulators, this.emulators, this.getUIContext())
    } finally {
      this.copyProgress.close()
    }
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

      ForEach(this.emulators, (item: Emulator, i: number) => {
        Text(item.name)
      }, (item: Emulator) => item.id)

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
  filesDir = this.getUIContext().getHostContext()!!.getApplicationContext().filesDir
  promptAction = this.getUIContext().getPromptAction()

  aboutToAppear(): void {
    const rootfsPath = this.emulator.rootFilesystem.startsWith('/')
      ? this.emulator.rootFilesystem
      : this.filesDir + '/' + this.emulator.rootFilesystem
    const virtualSize = readQcow2VirtualSize(rootfsPath)
    this.storageSize = virtualSize / (1024 * 1024 * 1024)
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
          Text(this.storageSize.toFixed(1) + 'GB')
            .fontSize($r('sys.float.Body_M'))
            .fontColor($r('sys.color.font_primary'))
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
          .onClick(() => {
            if (this.emulator.id === defaultEmulator.id) {
              this.promptAction.showToast({ message: '不支持删除默认模拟器' })
            } else {
              this.onDelete(this.emulator)
            }
          })
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
