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

interface RootfsItem {
  model: RootFilesystem
  fileSize: string
  virtualSize: string
}

@Component
export default struct RootfsManagementContent {
  @StorageLink(appOption.rootFilesystems) roots: RootFilesystem[] = []
  @State rootfsItems: RootfsItem[] = []
  @State tempRootfsName: string = ''
  @State tempSrcUri?: string = undefined
  @Prop specifiedBreak?: string = undefined
  @Prop toolBar: boolean = true
  filesDir: string = this.getUIContext().getHostContext()!!.getApplicationContext().filesDir
  actionAfterNameInput: () => Promise<void> = (): Promise<void> => this.createNewRootfs()
  rootfsNameController = new CustomDialogController({
    builder: CustomContentDialog({
      primaryTitle: '镜像名称',
      contentBuilder: () => {
        this.buildInputRootfsName()
      }
    })
  })
  importProgress: CustomDialogController = new CustomDialogController({
    builder: LoadingDialog({
      content: '正在导入文件',
    }),
    autoCancel: false
  })
  exportProgress: CustomDialogController = new CustomDialogController({
    builder: LoadingDialog({
      content: '正在导出文件',
    }),
    autoCancel: false
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
      }
    })
  }

  build() {
    Column() {
      if (this.toolBar) {
        Row() {
          BackButton()
            .padding({ left: 15 })

          Text('镜像管理')
            .fontSize(18)

          Blank().layoutWeight(1)

          Button('导入', { buttonStyle: ButtonStyleMode.TEXTUAL })
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
        Button('导入')
          .width('100%')
          .onClick(() => {
            this.importRootFilesystem()
          })
      }
    }
  }

  @Builder
  buildInputRootfsName() {
    Column() {
      TextInput({
        text: this.tempRootfsName,
        placeholder: '输入镜像名称'
      })
        .onChange((value) => {
          this.tempRootfsName = value;
        })
      Button('完成')
        .margin({ top: 10 })
        .width('100%')
        .enabled(this.validateRootfsName())
        .onClick(async () => {
          await this.actionAfterNameInput()
        })
    }
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
        message: '不支持修改默认镜像',
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
        message: '不支持删除默认镜像',
        duration: 3000
      });
    } else {
      this.getUIContext().showAlertDialog({
        title: '确定删除',
        message: '您正在操作删除镜像，删除后不可恢复，确定操作？',
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
          Text('文件大小').fontSize($r('sys.float.Body_S')).fontColor($r('sys.color.font_tertiary'))
            .margin({ top: 5 })
        }
        .layoutWeight(1)

        Column() {
          Text(this.value.virtualSize)
            .fontSize($r('sys.float.Body_M'))
            .fontColor($r('sys.color.font_primary'))
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
          .fontColor($r('sys.color.font_secondary'))
          .onClick(() => this.onDelete(this.value.model))
        Button('重命名', { buttonStyle: ButtonStyleMode.TEXTUAL, controlSize: ControlSize.SMALL })
          .fontSize($r('sys.float.Body_M'))
          .fontColor($r('sys.color.font_secondary'))
          .onClick(() => this.onEdit(this.value.model))
        Button('导出', { buttonStyle: ButtonStyleMode.TEXTUAL, controlSize: ControlSize.SMALL })
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