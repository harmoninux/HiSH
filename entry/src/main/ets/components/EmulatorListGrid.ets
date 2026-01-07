import { fileIo as fs } from '@kit.CoreFileKit'
import { Emulator, RootFilesystem, PortMapping } from '../model/Emulator';
import { RepeatGrid } from './RepeatGrid';
import { util } from '@kit.ArkTS';
import appOption, { savePreference } from '../model/appOption';
import { CustomContentDialog, LoadingDialog } from '@kit.ArkUI';
import copyFile, { copyFileWithProgress } from '../lib/copyFile';
import napi from 'libentry.so';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Want, bundleManager } from '@kit.AbilityKit';
import EmulatorItem from './EmulatorItem';
import PowerManagementContent from './PowerManagementContent';
import ImageManagementContent from './ImageManagementContent';
import deviceInfo from '@ohos.deviceInfo';
import preference from '@ohos.data.preferences';
import { startVm } from '../lib/startVm';
import { VmController } from '../lib/VmController';


const DOMAIN = 0x0000;

@Component
export default struct EmulatorListGrid {
  @State selectedId?: string = undefined
  @State tempEmulatorName: string = ''
  @State tempRootfsName: string = ''
  @State copyProgressValue: number = 0  // 复制进度 (0-100)
  @Watch('onEmulatorsChange') @StorageLink(appOption.emulators) emulators: Emulator[] = []
  @StorageLink(appOption.rootFilesystems) rootFilesystems: RootFilesystem[] = []
  @State displayEmulators: Emulator[] = []
  @StorageLink(appOption.defaultStartEmulator) defaultStart?: string = undefined
  @StorageProp(appOption.currentRunningEmulator) currentRunning?: string = undefined
  @StorageProp(appOption.bundleInfo) bundleInfo?: bundleManager.BundleInfo = undefined
  @Require onEditEmulator: (item: Emulator, edit: boolean) => void
  @Prop specifiedBreak?: string = undefined
  emulatorNameController = new CustomDialogController({
    builder: CustomContentDialog({
      primaryTitle: $r('app.string.dialog_copy'),
      secondaryTitle: $r('app.string.dialog_copy_subtitle'),
      contentBuilder: () => {
        this.buildInputEmulatorName()
      }
    })
  })
  rootfsNameController = new CustomDialogController({
    builder: CustomContentDialog({
      primaryTitle: $r('app.string.dialog_export_rootfs'),
      secondaryTitle: $r('app.string.dialog_export_subtitle'),
      contentBuilder: () => {
        this.buildInputRootfsName()
      }
    })
  })
  copyProgress: CustomDialogController = new CustomDialogController({
    builder: LoadingDialog({
      content: $r('app.string.progress_copying'),
    }),
    autoCancel: false
  })
  exportProgress: CustomDialogController = new CustomDialogController({
    builder: LoadingDialog({
      content: $r('app.string.progress_exporting'),
    }),
    autoCancel: false
  })
  powerManagementController: CustomDialogController = new CustomDialogController({
    builder: CustomContentDialog({
      primaryTitle: $r('app.string.dialog_power_management'),
      contentBuilder: () => {
        this.buildPowerManagement();
      }
    })
  })
  imageManagementController: CustomDialogController | null = null
  @State selectedEmulatorForImage: Emulator | null = null
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
        placeholder: $r('app.string.placeholder_emulator_name')
      })
        .onChange((value) => {
          this.tempEmulatorName = value;
        })
      Button($r('app.string.btn_done'))
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
        placeholder: $r('app.string.placeholder_export_name')
      })
        .onChange((value) => {
          this.tempRootfsName = value;
        })
      Button($r('app.string.btn_done'))
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
      message: $r('app.string.msg_export_complete'),
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
        this.onEditEmulator(item, true)
      },
      onDelete: (item) => {
        if (item.id === this.currentRunning) {
          this.promptAction.showToast({ message: $r('app.string.msg_cannot_delete_running') })
        } else if (item.id === this.defaultStart) {
          this.promptAction.showToast({ message: $r('app.string.msg_cannot_delete_default') })
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
      onExport: async (item: Emulator): Promise<void> => {
        // 检查是否有快照
        try {
          const result: string = napi.getSnapshots(item.rootFilesystem)
          const response: Record<string, ESObject> = JSON.parse(result) as Record<string, ESObject>
          const snapshots: Array<ESObject> = response['snapshots'] as Array<ESObject>
          
          if (snapshots && snapshots.length > 0) {
            this.promptAction.showDialog({
              title: $r('app.string.dialog_cannot_export'),
              message: $r('app.string.msg_export_has_snapshots'),
              buttons: [
                { text: $r('app.string.btn_got_it'), color: '#007DFF' }
              ]
            })
            return
          }
        } catch (e) {
          hilog.error(0x0000, 'EmulatorListGrid', '检查快照失败: %{public}s', JSON.stringify(e))
          // 检查失败时仍允许导出，但给出警告
        }
        
        this.selectedId = item.id
        this.rootfsNameController.open()
      },
      onPowerManage: (item) => {
        this.openPowerManageDialog()
      },
      onImageManage: (item) => {
        this.openImageManageDialog(item)
      }
    }).onClick(() => {
      this.onEditEmulator(emulator, false)
    })
  }

  askForStartEmulator(item: Emulator) {
    const isPcOrTablet = deviceInfo.deviceType === '2in1' || deviceInfo.deviceType === 'tablet';
    
    this.getUIContext().showAlertDialog({
      title: item.name,
      message: isPcOrTablet ? $r('app.string.msg_start_vm_confirm') : $r('app.string.msg_restart_confirm'),
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
          value: $r('app.string.btn_run'),
          action: async () => {
            this.startEmulator(item);
          }
        }
      ],
    });
  }

  // 统一启动入口
  async startEmulator(item: Emulator) {
    await VmController.getInstance().startVM(item, this.getUIContext());
  }

  private askForDeleteEmulator(item: Emulator) {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.dialog_confirm_delete'),
      message: $r('app.string.msg_delete_emulator_confirm'),
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

    this.copyProgressValue = 0
    this.copyProgress.open()
    try {
      await copyFileWithProgress(srcRootfs, target, (progress: number) => {
        this.copyProgressValue = progress
      })

      const emulator: Emulator = {
        id,
        name: this.tempEmulatorName.trim(),
        cpu: src.cpu,
        memory: src.memory,
        init: src.init,
        portMapping: src.portMapping,
        rootVda: src.rootVda,
        rootFilesystem: target,
        sharedFolderReadonly: src.sharedFolderReadonly,
        mountDataDisk: src.mountDataDisk,
        dataDiskId: src.dataDiskId
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

  openPowerManageDialog() {
    this.powerManagementController.open()
  }

  openImageManageDialog(emulator: Emulator) {
    this.selectedEmulatorForImage = emulator
    this.imageManagementController = new CustomDialogController({
      builder: CustomContentDialog({
        primaryTitle: $r('app.string.dialog_image_management'),
        contentBuilder: () => {
          this.buildImageManagement()
        }
      })
    })
    this.imageManagementController.open()
  }

  @Builder
  buildPowerManagement() {
    PowerManagementContent()
  }

  @Builder
  buildImageManagement() {
    if (this.selectedEmulatorForImage) {
      ImageManagementContent({ 
        emulator: this.selectedEmulatorForImage,
        isVmRunning: this.selectedEmulatorForImage.id === this.currentRunning
      })
    }
  }

  onEmulatorsChange() {
    hilog.info(1, "EmulatorManagement", "onEmulatorsChange: %{public}s", JSON.stringify(this.emulators))
    this.displayEmulators.splice(0, this.displayEmulators.length)
    setTimeout(() => {
      this.emulators.forEach(it => this.displayEmulators.push(it))
    }, 20)
  }
}
