import { fileIo as fs } from '@kit.CoreFileKit'
import { Emulator, RootFilesystem } from '../model/Emulator';
import { RepeatGrid } from './RepeatGrid';
import { util } from '@kit.ArkTS';
import appOption, { savePreference } from '../model/appOption';
import { CustomContentDialog, LoadingDialog } from '@kit.ArkUI';
import copyFile from '../lib/copyFile';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Want } from '@kit.AbilityKit';
import { bundleManager } from '@kit.MDMKit';
import EmulatorItem from './EmulatorItem';

@Component
export default struct EmulatorListGrid {
  @State selectedId?: string = undefined
  @State tempEmulatorName: string = ''
  @State tempRootfsName: string = ''
  @Watch('onEmulatorsChange') @StorageLink(appOption.emulators) emulators: Emulator[] = []
  @StorageLink(appOption.rootFilesystems) rootFilesystems: RootFilesystem[] = []
  @State displayEmulators: Emulator[] = []
  @StorageLink(appOption.defaultStartEmulator) defaultStart?: string = undefined
  @StorageProp(appOption.currentRunningEmulator) currentRunning?: string = undefined
  @StorageProp('bundleInfo') bundleInfo?: bundleManager.BundleInfo = undefined
  @Require onEditEmulator: (item: Emulator) => void
  @Prop specifiedBreak?: string = undefined
  emulatorNameController = new CustomDialogController({
    builder: CustomContentDialog({
      primaryTitle: '复制',
      secondaryTitle: '输入新的模拟器名称，请注意不要与已有模拟器重复',
      contentBuilder: () => {
        this.buildInputEmulatorName()
      }
    })
  })
  rootfsNameController = new CustomDialogController({
    builder: CustomContentDialog({
      primaryTitle: '导出为镜像',
      secondaryTitle: '输入新的镜像名称，请注意不要与已有镜像重复',
      contentBuilder: () => {
        this.buildInputRootfsName()
      }
    })
  })
  copyProgress: CustomDialogController = new CustomDialogController({
    builder: LoadingDialog({
      content: '正在复制',
    }),
  })
  exportProgress: CustomDialogController = new CustomDialogController({
    builder: LoadingDialog({
      content: '正在导出',
    }),
  })
  filesDir = this.getUIContext().getHostContext()!!.getApplicationContext().filesDir
  promptAction = this.getUIContext().getPromptAction()

  aboutToAppear(): void {
    this.onEmulatorsChange()
  }

  @Builder
  buildInputEmulatorName() {
    Column() {
      TextInput({
        text: this.tempEmulatorName,
        placeholder: '输入新的模拟器名称'
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

  @Builder
  buildInputRootfsName() {
    Column() {
      TextInput({
        text: this.tempRootfsName,
        placeholder: '输入导出的镜像名称'
      })
        .onChange((value) => {
          this.tempRootfsName = value;
        })
      Button('完成')
        .margin({ top: 10 })
        .width('100%')
        .enabled(this.validateRootfsName())
        .onClick(async () => {
          this.rootfsNameController.close()
          await this.exportToRootfs()
        })
    }
  }

  async exportToRootfs() {
    const src = this.emulators.find(it => it.id === this.selectedId)!!

    const id = util.generateRandomUUID()

    const base = AppStorage.get(appOption.rootfsBaseDir) as string;
    const target = base + '/' + id + src.rootFilesystem.substring(src.rootFilesystem.lastIndexOf('.'))

    const srcRootfs = src.rootFilesystem

    this.exportProgress.open()
    try {
      await copyFile(srcRootfs, target)

      const rootfs: RootFilesystem = {
        id,
        name: this.tempRootfsName.trim(),
        path: target
      }
      this.rootFilesystems.push(rootfs)

      await savePreference(appOption.rootFilesystems, this.rootFilesystems, this.getUIContext())
    } finally {
      this.exportProgress.close()
    }
    this.promptAction.showToast({
      message: '导出镜像完成，您可以前往“镜像管理”进行查看',
      duration: 3000
    })
  }

  validateRootfsName(): boolean {
    const name = this.tempRootfsName.trim();
    if (name.length <= 0) {
      return false
    }
    const used = this.rootFilesystems.findIndex(it => it.name === name) >= 0
    if (used) {
      return false
    }
    return true
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
  buildEmulatorListItem(emulator: Emulator) {
    EmulatorItem({
      emulator: emulator,
      isRunning: emulator.id === this.currentRunning,
      isDefault: emulator.id === this.defaultStart,
      onEdit: (item) => {
        this.onEditEmulator(item)
      },
      onDelete: (item) => {
        if (item.id === this.currentRunning) {
          this.promptAction.showToast({ message: '不支持删除运行中的模拟器' })
        } else if (item.id === this.defaultStart) {
          this.promptAction.showToast({ message: '不支持删除默认启动的模拟器' })
        } else {
          this.askForDeleteEmulator(item);
        }
      },
      onCopy: (item) => {
        this.selectedId = item.id
        this.emulatorNameController.open()
      },
      onSetDefault: (item) => {
        this.onSetDefault(item);
      },
      onStart: (item) => {
        this.askForStartEmulator(item)
      },
      onExport: (item) => {
        this.selectedId = item.id
        this.rootfsNameController.open()
      }
    })
  }

  askForStartEmulator(item: Emulator) {
    this.getUIContext().showAlertDialog({
      title: item.name,
      message: '将重启HiSH并启动“' + item.name + "”，建议保存好当前模拟器中的数据再操作。是否现在启动？",
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
          value: '运行',
          action: async () => {
            this.startEmulator(item);
          }
        }
      ],
    });
  }

  async startEmulator(item: Emulator) {
    await savePreference(appOption.temporaryStartEmulator, item.id, this.getUIContext())
    await this.restartApp()
  }

  private async restartApp() {
    let applicationContext = this.getUIContext().getHostContext()!!.getApplicationContext();
    let want: Want = {
      bundleName: this.bundleInfo?.name,
      abilityName: 'EntryAbility'
    };
    applicationContext.restartApp(want);
  }

  private askForDeleteEmulator(item: Emulator) {
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
            this.deleteEmulatorItem(item);
          }
        }
      ],
    });
  }

  private async onSetDefault(item: Emulator) {
    this.defaultStart = item.id;
    await savePreference(appOption.defaultStartEmulator, this.defaultStart, this.getUIContext())
  }

  async deleteEmulatorItem(item: Emulator) {

    const i = this.emulators.findIndex(it => it.id === item.id)

    const rootfs = item.rootFilesystem
    try {
      fs.unlinkSync(rootfs)
    } catch (e) {
      hilog.info(1, "EmulatorManagement", "failed to delete %{public}s", rootfs)
    }

    this.emulators.splice(i, 1)
    await savePreference(appOption.emulators, this.emulators, this.getUIContext())
  }

  async copyEmulatorItem() {

    const src = this.emulators.find(it => it.id === this.selectedId)!!

    const id = util.generateRandomUUID()

    const base = AppStorage.get(appOption.vmBaseDir) as string;
    const target = base + '/' + id + src.rootFilesystem.substring(src.rootFilesystem.lastIndexOf('.'))

    const srcRootfs = src.rootFilesystem

    this.copyProgress.open()
    try {
      await copyFile(srcRootfs, target)

      const emulator: Emulator = {
        id,
        name: this.tempEmulatorName.trim(),
        cpu: src.cpu,
        memory: src.memory,
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
    Scroll() {
      RepeatGrid({
        items: this.displayEmulators as object[],
        contentBuilder: (item: object, index: number) => {
          this.buildEmulatorListItem(item as Emulator)
        },
        getKey: (item: object, index: number) => (item as Emulator).id,
        specifiedBreak: this.specifiedBreak
      })
    }
    .scrollable(ScrollDirection.Vertical)
    .scrollBar(BarState.Auto)
    .scrollBarWidth(1)
    .layoutWeight(1)
    .align(Alignment.Top)
  }

  onEmulatorsChange() {
    hilog.info(1, "EmulatorManagement", "onEmulatorsChange: %{public}s", JSON.stringify(this.emulators))
    this.displayEmulators.splice(0, this.displayEmulators.length)
    setTimeout(() => {
      this.emulators.forEach(it => this.displayEmulators.push(it))
    }, 20)
  }
}
