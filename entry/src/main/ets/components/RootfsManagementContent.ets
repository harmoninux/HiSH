import preference from '@ohos.data.preferences';
import appOption from "../model/appOption"
import { picker } from '@kit.CoreFileKit';
import { defaultRootfs, RootFilesystem } from "../model/Emulator"
import { RepeatGrid } from "../components/RepeatGrid"
import { common } from "@kit.AbilityKit";
import { CustomContentDialog, LoadingDialog } from "@kit.ArkUI";
import { util } from "@kit.ArkTS";
import copyFile from "../lib/copyFile";
import { fileIo as fs } from '@kit.CoreFileKit'
import readQcow2VirtualSize from '../lib/readQcow2VirtualSize';
import { BackButton } from './BackButton';
import napi from 'libentry.so';
import { router } from '@kit.ArkUI';

import { deviceInfo } from '@kit.BasicServicesKit';
import ImageManagementContent from './ImageManagementContent';
import { Emulator } from '../model/Emulator';

interface RootfsItem {
  model: RootFilesystem
  fileSize: string
  virtualSize: string
}

interface DetailInfo {
  fileFormat: string
  virtualSize: number
  diskSize: number
  clusterSize?: number
  lazyRefcounts?: boolean
  extendedL2?: boolean
  compressionType?: string
  compat?: string
  refcountBits?: number
  corrupt?: boolean
}

@Component
export default struct RootfsManagementContent {
  @StorageLink(appOption.rootFilesystems) roots: RootFilesystem[] = []
  @State rootfsItems: RootfsItem[] = []
  @State tempRootfsName: string = ''
  @State tempSrcUri?: string = undefined
  @Prop specifiedBreak?: string = undefined
  @Prop toolBar: boolean = true
  onOpenDataDiskManagement?: () => void = undefined
  @State detailInfo?: DetailInfo = undefined
  filesDir: string = this.getUIContext().getHostContext()!!.getApplicationContext().filesDir
  actionAfterNameInput: () => Promise<void> = (): Promise<void> => this.createNewRootfs()

  rootfsNameController = new CustomDialogController({
    builder: CustomContentDialog({
      primaryTitle: $r('app.string.dialog_rootfs_name'),
      contentBuilder: () => {
        this.buildInputRootfsName()
      }
    })
  })
  importProgress: CustomDialogController = new CustomDialogController({
    builder: LoadingDialog({
      content: $r('app.string.dialog_import_shared'),
    }),
    autoCancel: false
  })
  exportProgress: CustomDialogController = new CustomDialogController({
    builder: LoadingDialog({
      content: $r('app.string.dialog_export_shared'),
    }),
    autoCancel: false
  })
  detailDialogController: CustomDialogController = new CustomDialogController({
    builder: CustomContentDialog({
      primaryTitle: $r('app.string.image_details'),
      contentBuilder: () => {
        this.buildDetailContent()
      },
      buttons: [{
        value: $r('app.string.btn_close'),
        action: () => {
          this.detailDialogController.close()
        }
      }]
    }),
    autoCancel: true
  })
  promptAction = this.getUIContext().getPromptAction()

  aboutToAppear(): void {
    this.syncRootfsViewItems()
  }

  @Builder
  buildRootfsListItem(value: RootfsItem) {
    RootFilesystemItem({
      value,
      onEdit: (item) => {
        this.editRootfsName(item);
      },
      onDelete: (item) => {
        this.deleteRootFilesystem(item)
      },
      onExport: (item) => {
        this.exportRootFilesystem(item)
      },
      onShowInfo: (item) => {
        this.showDiskInfo(item)
      }
    })
  }

  build() {
    Column() {
      if (this.toolBar) {
        Row() {
          BackButton()
            .padding({ left: 15 })

          Text($r('app.string.image_management_title'))
            .fontSize(18)

          // 数据盘管理入口
          Text($r('app.string.data_disk_management'))
            .fontSize(14)
            .fontColor('#007DFF')
            .margin({ left: 16 })
            .onClick(() => {
              router.pushUrl({ url: 'pages/DataDiskManagementPage' })
            })

          Blank().layoutWeight(1)

          Button($r('app.string.btn_import'), { buttonStyle: ButtonStyleMode.TEXTUAL })
            .onClick(() => {
              this.importRootFilesystem()
            })
        }
        .height(56)
      }

      Scroll() {
        RepeatGrid({
          items: this.rootfsItems as object[],
          contentBuilder: (item: object, index: number) => {
            this.buildRootfsListItem(item as RootfsItem)
          },
          getKey: (item: object, index: number) => (item as RootfsItem).model.id,
          specifiedBreak: this.specifiedBreak
        })
      }
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Auto)
      .scrollBarWidth(1)
      .layoutWeight(1)
      .align(Alignment.Top)

      if (!this.toolBar) {
        Row() {
          Button($r('app.string.data_disk_management'))
            .layoutWeight(1)
            .margin({ right: 12 })
            .onClick(() => {
              if (this.onOpenDataDiskManagement) {
                this.onOpenDataDiskManagement()
              } else {
                router.pushUrl({ url: 'pages/DataDiskManagementPage' })
              }
            })

          Button($r('app.string.btn_import'))
            .layoutWeight(1)
            .onClick(() => {
              this.importRootFilesystem()
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 24, top: 16 })
      }
    }
  }

  @Builder
  buildInputRootfsName() {
    Column() {
      TextInput({
        text: this.tempRootfsName,
        placeholder: $r('app.string.placeholder_rootfs_name')
      })
        .onChange((value) => {
          this.tempRootfsName = value;
        })
      Button($r('app.string.btn_finish'))
        .margin({ top: 10 })
        .width('100%')
        .enabled(this.validateRootfsName())
        .onClick(async () => {
          await this.actionAfterNameInput()
        })
    }
  }

  @Builder
  buildDetailContent() {
    if (this.detailInfo) {
      Scroll() {
        Column() {
          // 文件格式
          this.buildDetailRow($r('app.string.label_file_format'), this.detailInfo.fileFormat)
          Divider().color($r('sys.color.ohos_id_color_list_separator'))

          // 虚拟大小
          this.buildDetailRow($r('app.string.virtual_size'), this.formatSize(this.detailInfo.virtualSize))
          Divider().color($r('sys.color.ohos_id_color_list_separator'))

          // 实际占用
          this.buildDetailRow($r('app.string.disk_size'), this.formatSize(this.detailInfo.diskSize))
          Divider().color($r('sys.color.ohos_id_color_list_separator'))

          // 簇大小
          if (this.detailInfo.clusterSize) {
            this.buildDetailRow($r('app.string.label_cluster_size'), this.formatSize(this.detailInfo.clusterSize))
            Divider().color($r('sys.color.ohos_id_color_list_separator'))
          }

          // 兼容版本
          if (this.detailInfo.compat) {
            this.buildDetailRow($r('app.string.label_compat'), this.detailInfo.compat)
            Divider().color($r('sys.color.ohos_id_color_list_separator'))
          }

          // Lazy Refcounts
          if (this.detailInfo.lazyRefcounts !== undefined) {
            this.buildDetailRow($r('app.string.label_lazy_refcounts'), this.detailInfo.lazyRefcounts ? getContext(this).resourceManager.getStringSync($r('app.string.status_enabled').id) : getContext(this).resourceManager.getStringSync($r('app.string.status_disabled').id))
            Divider().color($r('sys.color.ohos_id_color_list_separator'))
          }

          // Extended L2
          if (this.detailInfo.extendedL2 !== undefined) {
            this.buildDetailRow($r('app.string.label_extended_l2'), this.detailInfo.extendedL2 ? getContext(this).resourceManager.getStringSync($r('app.string.status_enabled').id) : getContext(this).resourceManager.getStringSync($r('app.string.status_disabled').id))
            Divider().color($r('sys.color.ohos_id_color_list_separator'))
          }

          // Refcount Bits
          if (this.detailInfo.refcountBits) {
            this.buildDetailRow($r('app.string.label_refcount_bits'), this.detailInfo.refcountBits.toString())
            Divider().color($r('sys.color.ohos_id_color_list_separator'))
          }

          // 镜像状态
          if (this.detailInfo.corrupt !== undefined) {
            this.buildDetailRow($r('app.string.label_image_status'), this.detailInfo.corrupt ? getContext(this).resourceManager.getStringSync($r('app.string.status_corrupt').id) : getContext(this).resourceManager.getStringSync($r('app.string.status_normal').id))
          }
        }
        .width('100%')
        .padding(16)
      }
      .width('100%')
      .constraintSize({ maxHeight: 400 })
    } else {
      Text($r('app.string.msg_no_details'))
        .fontSize(12)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .padding(16)
    }
  }

  @Builder
  buildDetailRow(label: Resource | string, value: string) {
    Row() {
      Text(label)
        .fontSize(12)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .width(100)
      Text(value)
        .fontSize(12)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
  }

  validateRootfsName(): boolean {

    const name = this.tempRootfsName.trim();
    if (name.length <= 0) {
      return false
    }

    if (this.roots.findIndex(it => it.name === name) >= 0) {
      return false
    }

    return true
  }

  private editRootfsName(item: RootFilesystem) {
    if (item.id === defaultRootfs.id) {
      this.promptAction.showToast({
        message: $r('app.string.msg_default_rootfs_edit'),
        duration: 3000
      });
    } else {
      this.tempRootfsName = item.name
      this.actionAfterNameInput = (): Promise<void> => this.updateRootfsName(item);
      this.rootfsNameController.open();
    }
  }

  deleteRootFilesystem(item: RootFilesystem) {
    if (item.id === defaultRootfs.id) {
      this.promptAction.showToast({
        message: $r('app.string.msg_default_rootfs_delete'),
        duration: 3000
      });
    } else {
      this.getUIContext().showAlertDialog({
        title: $r('app.string.dialog_confirm_delete'),
        message: $r('app.string.dialog_delete_rootfs_msg'),
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
              this.deleteRootFilesystemItem(item)
            }
          }
        ],
      });
    }
  }

  async deleteRootFilesystemItem(item: RootFilesystem) {

    const path = item.path

    const i = this.roots.findIndex(it => it.id === item.id)
    this.roots.splice(i, 1)

    await this.saveRootFilesystems()
    await fs.unlinkSync(path)
  }

  async exportRootFilesystem(item: RootFilesystem) {

    let context = this.getUIContext().getHostContext() as common.UIAbilityContext;

    const options = new picker.DocumentSaveOptions()
    options.newFileNames = [item.name + '.qcow2'];

    const savePicker = new picker.DocumentViewPicker(context)
    const uris = await savePicker.save(options)

    if (uris.length == 0) {
      return
    }

    const src = item.path
    const destUri = uris[0]

    this.exportProgress.open()
    try {
      await copyFile(src, destUri)
    } finally {
      this.exportProgress.close()
    }
  }

  /**
   * 显示磁盘信息
   */
  private showDiskInfo(item: RootFilesystem): void {
    try {
      const result: string = napi.getImageInfo(item.path)
      const info: Record<string, ESObject> = JSON.parse(result) as Record<string, ESObject>

      if (info['error']) {
        this.promptAction.showDialog({
          title: $r('app.string.msg_get_disk_info_fail'),
          message: info['error'] as string,
          buttons: [{ text: $r('app.string.setting_generic_confirm'), color: '#007DFF' }]
        })
        return
      }

      // 提取详细信息
      const formatSpecific = info['format-specific'] as Record<string, Object> | undefined
      const qcow2Data = formatSpecific?.['data'] as Record<string, Object> | undefined

      this.detailInfo = {
        fileFormat: info['format'] as string || 'unknown',
        virtualSize: info['virtual-size'] as number || 0,
        diskSize: info['actual-size'] as number || 0,
        clusterSize: info['cluster-size'] as number,
        lazyRefcounts: qcow2Data?.['lazy-refcounts'] as boolean,
        extendedL2: qcow2Data?.['extended-l2'] as boolean,
        compressionType: qcow2Data?.['compression-type'] as string,
        compat: qcow2Data?.['compat'] as string,
        refcountBits: qcow2Data?.['refcount-bits'] as number,
        corrupt: qcow2Data?.['corrupt'] as boolean
      }

      // 打开详情对话框
      this.detailDialogController.open()
    } catch (e) {
      this.promptAction.showToast({
        message: $r('app.string.msg_get_disk_info_fail'),
        duration: 2000
      })
    }
  }

  private formatSize(bytes: number): string {
    if (bytes === 0) return '0 B'
    const k = 1024
    const units = ['B', 'KB', 'MB', 'GB', 'TB']
    const i = Math.floor(Math.log(bytes) / Math.log(k))
    const size = bytes / Math.pow(k, i)
    return `${size.toFixed(2)} ${units[i]}`
  }

  private async createNewRootfs() {

    const uri = this.tempSrcUri!!
    const name = this.tempRootfsName.trim()
    const id = util.generateRandomUUID()

    const rootfsBaseDir = AppStorage.get(appOption.rootfsBaseDir) as string
    const target = rootfsBaseDir + '/' + id + uri.substring(uri.lastIndexOf('.'))

    this.importProgress.open()
    try {
      await copyFile(uri, target)

      this.roots.push({ id, name, path: target })

      await this.saveRootFilesystems();
    } finally {
      this.importProgress.close()
    }

    this.rootfsNameController.close()
  }

  private async updateRootfsName(item: RootFilesystem) {

    const name = this.tempRootfsName.trim()

    const i = this.roots.findIndex(it => it.id === item.id)

    const updated: RootFilesystem = { id: item.id, name, path: item.path }
    this.roots[i] = updated

    await this.saveRootFilesystems()

    this.rootfsNameController.close()
  }

  private async saveRootFilesystems() {

    const roots = this.roots

    const appContext = this.getUIContext().getHostContext()!!.getApplicationContext();
    const appPref: preference.Preferences = await preference.getPreferences(appContext, appOption.preferenceName);
    await appPref.put(appOption.rootFilesystems, JSON.stringify(roots));
    await appPref.flush();

    this.syncRootfsViewItems()
  }

  async importRootFilesystem() {

    let context = this.getUIContext().getHostContext() as common.UIAbilityContext;

    let options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.fileSuffixFilters = ['qcow2']

    let documentPicker = new picker.DocumentViewPicker(context);
    let uris = await documentPicker.select(options);

    if (uris.length == 0) {
      return
    }

    this.tempSrcUri = uris[0]
    this.tempRootfsName = ''

    this.actionAfterNameInput = (): Promise<void> => this.createNewRootfs()
    this.rootfsNameController.open()
  }

  syncRootfsViewItems() {
    this.rootfsItems.splice(0, this.rootfsItems.length)

    setTimeout(() => {
      for (let i = 0; i < this.roots.length; i++) {
        const it = this.roots[i]
        const path = it.path
        const stat = fs.statSync(path)
        const sizeString = (stat.size / (1024 * 1024)).toFixed(1) + ' MB'
        const virtualSize = readQcow2VirtualSize(path)
        let virtualSizeString: string;
        if (virtualSize === undefined) {
          virtualSizeString = '-'
        } else {
          virtualSizeString = (virtualSize / (1024 * 1024 * 1024)).toFixed(1) + ' GB'
        }
        this.rootfsItems.push({ model: it, fileSize: sizeString, virtualSize: virtualSizeString })
      }
    }, 20)
  }
}

@Component
struct RootFilesystemItem {
  @State @Require value: RootfsItem
  @Require onEdit: (item: RootFilesystem) => void
  @Require onDelete: (item: RootFilesystem) => void
  @Require onExport: (item: RootFilesystem) => void
  @Require onShowInfo: (item: RootFilesystem) => void
  @State storageSize: number = 0

  aboutToAppear(): void {
    this.storageSize = 128
  }

  build() {
    Column() {
      Row() {
        Text(this.value.model.name)
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
          Text(this.value.fileSize)
            .fontSize($r('sys.float.Body_M'))
            .fontColor($r('sys.color.font_primary'))
          Text($r('app.string.label_file_size')).fontSize($r('sys.float.Body_S')).fontColor($r('sys.color.font_tertiary'))
            .margin({ top: 5 })
        }
        .layoutWeight(1)

        Column() {
          Text(this.value.virtualSize)
            .fontSize($r('sys.float.Body_M'))
            .fontColor($r('sys.color.font_primary'))
          Text($r('app.string.virtual_size')).fontSize($r('sys.float.Body_S')).fontColor($r('sys.color.font_tertiary'))
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
        Button($r('app.string.delete_this'), { buttonStyle: ButtonStyleMode.TEXTUAL, controlSize: ControlSize.SMALL })
          .fontSize($r('sys.float.Body_M'))
          .fontColor($r('sys.color.font_secondary'))
          .onClick(() => this.onDelete(this.value.model))
        Button($r('app.string.btn_rename'), { buttonStyle: ButtonStyleMode.TEXTUAL, controlSize: ControlSize.SMALL })
          .fontSize($r('sys.float.Body_M'))
          .fontColor($r('sys.color.font_secondary'))
          .onClick(() => this.onEdit(this.value.model))
        Button($r('app.string.btn_details'), { buttonStyle: ButtonStyleMode.TEXTUAL, controlSize: ControlSize.SMALL })
          .fontSize($r('sys.float.Body_M'))
          .fontColor($r('sys.color.font_secondary'))
          .onClick(() => this.onShowInfo(this.value.model))
        Button($r('app.string.btn_export'), { buttonStyle: ButtonStyleMode.TEXTUAL, controlSize: ControlSize.SMALL })
          .fontSize($r('sys.float.Body_M'))
          .fontColor($r('sys.color.font_secondary'))
          .onClick(() => this.onExport(this.value.model))
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
    .clickEffect({ level: ClickEffectLevel.LIGHT })
  }
}
