import appOption, { savePreference } from "../model/appOption"
import { picker } from '@kit.CoreFileKit';
import { DataDisk, Emulator } from "../model/Emulator"
import { RepeatGrid } from "./RepeatGrid"
import { common } from "@kit.AbilityKit";
import { CustomContentDialog, LoadingDialog, promptAction, router } from "@kit.ArkUI";
import { util } from "@kit.ArkTS";
import copyFile from "../lib/copyFile";
import { fileIo as fs } from '@kit.CoreFileKit'
import readQcow2VirtualSize from '../lib/readQcow2VirtualSize';
import { BackButton } from './BackButton';
import napi from 'libentry.so';
import { taskpool } from '@kit.ArkTS';
import { executeQemuImgTask } from '../utils/ImageTasks';
import { deviceInfo } from '@kit.BasicServicesKit';
import ImageManagementContent from './ImageManagementContent';

// 数据盘列表项模型
interface DataDiskItem {
  model: DataDisk
  fileSize: string
  virtualSize: string
}

@Component
export default struct DataDiskManagementContent {
  @StorageLink(appOption.dataDisks) dataDisks: DataDisk[] = []
  @StorageLink(appOption.rootfsBaseDir) dataDiskBaseDir: string = ''
  @State dataDiskItems: DataDiskItem[] = []
  @State specifiedBreak?: string = undefined
  titleBar: boolean = true
  @State isLoading: boolean = false

  // 新建数据盘对话框状态
  @State tempDiskName: string = ''
  @State tempDiskSize: string = '1024'

  // 名称输入对话框状态
  @State tempName: string = ''
  private actionAfterNameInput: (() => Promise<void>) | null = null

  // 详情对话框状态
  @State selectedDisk: DataDisk | null = null

  // 事务锁机制
  @State globalTaskRunning: boolean = false
  @State globalTaskName: string = ''

  // 新建数据盘对话框
  newDiskDialogController: CustomDialogController = new CustomDialogController({
    builder: CustomContentDialog({
      primaryTitle: $r('app.string.dialog_new_data_disk_title'),
      contentBuilder: () => {
        this.buildNewDataDiskDialog()
      },
      buttons: [
        {
          value: $r('app.string.setting_generic_cancel'),
          action: () => {
            this.newDiskDialogController.close()
          }
        },
        {
          value: $r('app.string.btn_create'),
          action: () => {
            this.executeCreateDataDisk()
          }
        }
      ]
    }),
    autoCancel: true
  })

  // 名称输入对话框
  nameInputController: CustomDialogController = new CustomDialogController({
    builder: CustomContentDialog({
      primaryTitle: $r('app.string.label_data_disk_name'),
      contentBuilder: () => {
        this.buildInputName()
      },
      buttons: [
        {
          value: $r('app.string.setting_generic_cancel'),
          action: () => {
            this.nameInputController.close()
          }
        },
        {
          value: $r('app.string.setting_generic_confirm'),
          action: () => {
            if (this.actionAfterNameInput) {
              this.actionAfterNameInput()
            }
          }
        }
      ]
    }),
    autoCancel: true
  })

  // 加载进度对话框
  loadingDialogController: CustomDialogController = new CustomDialogController({
    builder: LoadingDialog({
      content: this.globalTaskName || $r('app.string.msg_creating_data_disk'),
    }),
    autoCancel: false
  })

  // 详情对话框
  detailDialogController: CustomDialogController = new CustomDialogController({
    builder: CustomContentDialog({
      primaryTitle: $r('app.string.data_disk_image_management_title'),
      contentBuilder: () => {
        this.buildDetailDialog()
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

  aboutToAppear(): void {
    this.loadDataDisks()
    this.cleanupTempFiles()
  }

  // 清理临时文件
  private async cleanupTempFiles(): Promise<void> {
    try {
      const filenames: string[] = await fs.listFile(this.dataDiskBaseDir)
      for (const name of filenames) {
        if (name.endsWith('.tmp') || name.endsWith('.bak')) {
          const path = this.dataDiskBaseDir + '/' + name
          await fs.unlink(path)
          console.log('清理临时文件:', path)
        }
      }
    } catch (e) {
      console.error('清理临时文件失败:', e)
    }
  }

  // 检测是否为 PC/平板
  private checkPC(): boolean {
    const deviceType = deviceInfo.deviceType
    return deviceType === '2in1' || deviceType === 'tablet'
  }

  // 事务锁：检查并锁定
  private checkAndLockTask(taskName: string): boolean {
    if (this.globalTaskRunning) {
      promptAction.showToast({
        message: `任务正在运行: ${this.globalTaskName}`,
        duration: 2000
      })
      return false
    }
    this.globalTaskRunning = true
    this.globalTaskName = taskName
    return true
  }

  // 事务锁：解锁
  private unlockTask(): void {
    this.globalTaskRunning = false
    this.globalTaskName = ''
  }

  // 加载数据盘列表
  private async loadDataDisks(): Promise<void> {
    this.isLoading = true
    const items: DataDiskItem[] = []

    for (const disk of this.dataDisks) {
      try {
        const stat = await fs.stat(disk.path)
        const virtualSize = await readQcow2VirtualSize(disk.path)
        items.push({
          model: disk,
          fileSize: this.formatSize(stat.size),
          virtualSize: this.formatSize(virtualSize)
        })
      } catch (e) {
        // 文件不存在，跳过
        console.error('加载数据盘失败:', disk.path, e)
      }
    }

    this.dataDiskItems = items
    this.isLoading = false
  }

  // 格式化文件大小
  private formatSize(bytes: number): string {
    if (bytes < 1024) return bytes + ' B'
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB'
    if (bytes < 1024 * 1024 * 1024) return (bytes / 1024 / 1024).toFixed(1) + ' MB'
    return (bytes / 1024 / 1024 / 1024).toFixed(1) + ' GB'
  }

  // 导入数据盘
  private async importDataDisk(): Promise<void> {
    let context = this.getUIContext().getHostContext() as common.UIAbilityContext
    const options = new picker.DocumentSelectOptions()
    options.fileSuffixFilters = ['.qcow2']
    options.maxSelectNumber = 1

    const picker_inst = new picker.DocumentViewPicker(context)
    const uris = await picker_inst.select(options)

    if (uris.length == 0) return

    // 弹出名称输入对话框
    this.tempName = ''
    this.actionAfterNameInput = async () => {
      await this.executeImport(uris[0])
    }
    this.nameInputController.open()
  }

  // 执行导入
  private async executeImport(sourceUri: string): Promise<void> {
    const name = this.tempName.trim()
    if (!name) {
      promptAction.showToast({ message: $r('app.string.msg_data_disk_name_empty') })
      return
    }

    // 检查名称重复
    if (this.dataDisks.some(d => d.name === name)) {
      promptAction.showToast({ message: $r('app.string.msg_data_disk_name_exists') })
      return
    }

    // 事务锁检查
    if (!this.checkAndLockTask(`导入数据盘: ${name}`)) {
      return
    }

    this.nameInputController.close()
    this.loadingDialogController.open()

    let tempPath = ''
    try {
      if (!this.dataDiskBaseDir) {
        throw new Error('存储路径未初始化')
      }
      const id = util.generateRandomUUID()
      const destPath = this.dataDiskBaseDir + '/' + id + sourceUri.substring(sourceUri.lastIndexOf('.'))
      tempPath = destPath + '.tmp'
      
      // Step 1: 复制到临时文件
      await copyFile(sourceUri, tempPath)

      // Step 2: 重命名为正式文件（原子操作）
      await fs.rename(tempPath, destPath)

      const disk: DataDisk = { id, name, path: destPath }
      this.dataDisks.push(disk)
      await savePreference(appOption.dataDisks, this.dataDisks, this.getUIContext())
      await this.loadDataDisks()

      promptAction.showToast({ message: $r('app.string.msg_create_data_disk_success') })
    } catch (e) {
      console.error('导入数据盘失败:', e)
      promptAction.showToast({ message: $r('app.string.msg_create_data_disk_fail') })
      // 失败时清理临时文件
      if (tempPath) {
        try { await fs.unlink(tempPath) } catch (err) {}
      }
    } finally {
      this.loadingDialogController.close()
      this.unlockTask()
    }
  }

  // 新建数据盘
  private createNewDataDisk(): void {
    if (!this.checkPC()) {
      promptAction.showToast({
        message: $r('app.string.msg_pc_only_feature'),
        duration: 2000
      })
      return
    }
    this.tempDiskName = ''
    this.tempDiskSize = '1024'
    this.newDiskDialogController.open()
  }

  // 执行创建数据盘
  private async executeCreateDataDisk(): Promise<void> {
    const name = this.tempDiskName.trim()
    if (!name) {
      promptAction.showToast({ message: $r('app.string.msg_data_disk_name_empty') })
      return
    }

    // 检查名称重复
    if (this.dataDisks.some(d => d.name === name)) {
      promptAction.showToast({ message: $r('app.string.msg_data_disk_name_exists') })
      return
    }

    const size = parseInt(this.tempDiskSize)
    if (isNaN(size) || size <= 0) {
      promptAction.showToast({ message: $r('app.string.msg_data_disk_size_invalid') })
      return
    }

    // 事务锁检查
    if (!this.checkAndLockTask(`创建数据盘: ${name}`)) {
      return
    }

    this.newDiskDialogController.close()
    this.loadingDialogController.open()

    let tempPath = ''
    try {
      if (!this.dataDiskBaseDir) {
        throw new Error('存储路径未初始化')
      }
      const id = util.generateRandomUUID()
      const destPath = this.dataDiskBaseDir + '/' + id + '.qcow2'
      tempPath = destPath + '.tmp'
      const sizeM = size.toString() + 'M'

      // Step 1: 调用 NAPI 创建临时数据盘
      const args = ['create', '-f', 'qcow2', '-o', 'lazy_refcounts=on,extended_l2=on', tempPath, sizeM]
      const result = await taskpool.execute(executeQemuImgTask, args) as string
      
      let response: Record<string, Object> = {}
      try {
        response = JSON.parse(result) as Record<string, Object>
      } catch (e) {
        // 如果返回的不是 JSON，可能是 qemu-img 的原始输出
        // 检查是否包含错误关键字
        if (result && (result.toLowerCase().includes('error') || result.toLowerCase().includes('fail'))) {
          response = { 'error': result }
        } else {
          // 假设非错误信息的原始输出为成功
          response = { 'success': true }
        }
      }

      if (response['error']) {
        throw new Error(response['error'] as string)
      }

      // Step 2: 重命名为正式文件
      await fs.rename(tempPath, destPath)

      // 加入列表
      const disk: DataDisk = { id, name, path: destPath }
      this.dataDisks.push(disk)
      await savePreference(appOption.dataDisks, this.dataDisks, this.getUIContext())
      await this.loadDataDisks()

      promptAction.showToast({ message: $r('app.string.msg_create_data_disk_success') })
    } catch (e) {
      console.error('创建数据盘失败:', e)
      promptAction.showToast({ message: `创建失败: ${(e as Error).message}` })
      // 失败时清理临时文件
      if (tempPath) {
        try { await fs.unlink(tempPath) } catch (err) {}
      }
    } finally {
      this.loadingDialogController.close()
      this.unlockTask()
    }
  }

  // 删除数据盘（修复：先删文件后更新配置）
  private async deleteDataDisk(item: DataDisk): Promise<void> {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.dialog_confirm_delete'),
      message: $r('app.string.dialog_delete_disk_msg'),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      buttons: [
        {
          value: $r('app.string.setting_generic_cancel'),
          action: () => {}
        },
        {
          enabled: true,
          style: DialogButtonStyle.HIGHLIGHT,
          backgroundColor: $r('sys.color.warning'),
          value: $r('app.string.confirm_remove'),
          action: async () => {
            if (!this.checkAndLockTask(`删除数据盘: ${item.name}`)) {
              return
            }
            try {
              // 修复：先删除文件
              await fs.unlink(item.path)
              
              // 文件删除成功后再更新配置
              const i = this.dataDisks.findIndex(it => it.id === item.id)
              if (i >= 0) {
                this.dataDisks.splice(i, 1)
                await savePreference(appOption.dataDisks, this.dataDisks, this.getUIContext())
                await this.loadDataDisks()
              }
            } catch (e) {
              console.error('删除数据盘失败:', e)
              promptAction.showToast({ message: '删除失败' })
            } finally {
              this.unlockTask()
            }
          }
        }
      ],
    })
  }

  // 重命名数据盘
  private editDiskName(item: DataDisk): void {
    this.tempName = item.name
    this.actionAfterNameInput = async () => {
      const name = this.tempName.trim()
      if (!name) return

      // 检查名称重复（排除自身）
      if (this.dataDisks.some(d => d.name === name && d.id !== item.id)) {
        promptAction.showToast({ message: $r('app.string.msg_data_disk_name_exists') })
        return
      }

      if (!this.checkAndLockTask(`重命名数据盘: ${item.name}`)) {
        return
      }

      try {
        const i = this.dataDisks.findIndex(it => it.id === item.id)
        if (i >= 0) {
          this.dataDisks[i] = { id: item.id, name, path: item.path }
          await savePreference(appOption.dataDisks, this.dataDisks, this.getUIContext())
          await this.loadDataDisks()
        }
        this.nameInputController.close()
      } finally {
        this.unlockTask()
      }
    }
    this.nameInputController.open()
  }

  // 导出数据盘（检查快照）
  private async exportDataDisk(item: DataDisk): Promise<void> {
    // 检查是否有快照
    try {
      const result: string = napi.getSnapshots(item.path)
      const response: Record<string, Object> = JSON.parse(result)
      const snapshots: Array<Object> = response['snapshots'] as Array<Object>

      if (snapshots && snapshots.length > 0) {
        promptAction.showDialog({
          title: $r('app.string.dialog_cannot_export'),
          message: $r('app.string.msg_export_has_snapshots'),
          buttons: [{ text: $r('app.string.btn_got_it'), color: '#007DFF' }]
        })
        return
      }
    } catch (e) {
      // 检查失败时仍允许导出
    }

    // 继续导出
    let context = this.getUIContext().getHostContext() as common.UIAbilityContext
    const options = new picker.DocumentSaveOptions()
    options.newFileNames = [item.name + '.qcow2']

    const savePicker = new picker.DocumentViewPicker(context)
    const uris = await savePicker.save(options)

    if (uris.length == 0) return

    if (!this.checkAndLockTask(`导出数据盘: ${item.name}`)) {
      return
    }

    this.loadingDialogController.open()
    try {
      await copyFile(item.path, uris[0])
      promptAction.showToast({ message: $r('app.string.msg_export_success') })
    } catch (e) {
      console.error('导出失败:', e)
    } finally {
      this.loadingDialogController.close()
      this.unlockTask()
    }
  }

  // 显示详情
  private showDiskInfo(item: DataDisk): void {
    if (!this.checkPC()) {
      promptAction.showToast({
        message: $r('app.string.msg_pc_only_feature'),
        duration: 2000
      })
      return
    }

    this.selectedDisk = item
    this.detailDialogController.open()
  }

  // 构建新建数据盘对话框内容
  @Builder
  buildNewDataDiskDialog() {
    Column({ space: 16 }) {
      // 名称输入
      Row() {
        Text($r('app.string.label_data_disk_name'))
          .width(60)
          .fontSize(14)
        TextInput({ text: this.tempDiskName, placeholder: $r('app.string.placeholder_data_disk_name') })
          .layoutWeight(1)
          .onChange((value) => this.tempDiskName = value)
      }
      .width('100%')

      // 大小输入（带 MB 单位）
      Row() {
        Text($r('app.string.label_data_disk_size'))
          .width(60)
          .fontSize(14)
        TextInput({ text: this.tempDiskSize })
          .type(InputType.Number)
          .layoutWeight(1)
          .onChange((value) => this.tempDiskSize = value)
        Text($r('app.string.label_data_disk_size_unit'))
          .fontColor('#666666')
          .margin({ left: 8 })
      }
      .width('100%')
    }
    .padding(16)
    .width('100%')
  }

  // 构建名称输入对话框内容
  @Builder
  buildInputName() {
    Column() {
      TextInput({ text: this.tempName, placeholder: $r('app.string.placeholder_data_disk_name') })
        .width('100%')
        .onChange((value) => this.tempName = value)
    }
    .padding(16)
    .width('100%')
  }

  // 构建详情对话框内容（复用 ImageManagementContent）
  @Builder
  buildDetailDialog() {
    if (this.selectedDisk) {
      ImageManagementContent({
        emulator: {
          id: this.selectedDisk.id,
          name: this.selectedDisk.name,
          cpu: 0,
          memory: 0,
          portMapping: [],
          rootVda: '',
          rootFilesystem: this.selectedDisk.path,
          sharedFolderReadonly: false,
          init: '',
          mountDataDisk: false
        } as Emulator,
        isVmRunning: false
      })
    }
  }

  @Builder
  buildDataDiskListItem(item: DataDiskItem) {
    Column() {
      // 名称行
      Row() {
        Text(item.model.name)
          .fontSize($r('sys.float.Body_L'))
          .fontColor($r('sys.color.font_primary'))
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .maxLines(1)
          .layoutWeight(1)
      }
      .padding({ left: 5, right: 5, top: 10, bottom: 10 })
      .width('100%')

      // 大小信息行
      Row() {
        Column() {
          Text(item.fileSize)
            .fontSize($r('sys.float.Body_M'))
            .fontColor($r('sys.color.font_primary'))
          Text($r('app.string.label_file_size'))
            .fontSize($r('sys.float.Body_S'))
            .fontColor($r('sys.color.font_tertiary'))
        }.layoutWeight(1)

        Column() {
          Text(item.virtualSize)
            .fontSize($r('sys.float.Body_M'))
            .fontColor($r('sys.color.font_primary'))
          Text($r('app.string.virtual_size'))
            .fontSize($r('sys.float.Body_S'))
            .fontColor($r('sys.color.font_tertiary'))
        }.layoutWeight(1)
      }
      .padding({ top: 10, bottom: 10 })
      .borderRadius(10)
      .backgroundColor($r('app.color.setting_block_background_2'))

      // 操作按钮行
      Row() {
        Blank().layoutWeight(1)
        Button($r('app.string.delete_this'), { buttonStyle: ButtonStyleMode.TEXTUAL, controlSize: ControlSize.SMALL })
          .onClick(() => this.deleteDataDisk(item.model))
        Button($r('app.string.btn_rename'), { buttonStyle: ButtonStyleMode.TEXTUAL, controlSize: ControlSize.SMALL })
          .onClick(() => this.editDiskName(item.model))
        Button($r('app.string.btn_details'), { buttonStyle: ButtonStyleMode.TEXTUAL, controlSize: ControlSize.SMALL })
          .onClick(() => this.showDiskInfo(item.model))
        Button($r('app.string.btn_export'), { buttonStyle: ButtonStyleMode.TEXTUAL, controlSize: ControlSize.SMALL })
          .onClick(() => this.exportDataDisk(item.model))
      }
      .padding({ top: 5, bottom: 5 })
    }
    .borderRadius(10)
    .padding({ left: 10, right: 10 })
    .backgroundColor($r('app.color.setting_block_background'))
    .clickEffect({ level: ClickEffectLevel.LIGHT })
    .enabled(!this.globalTaskRunning)
    .opacity(this.globalTaskRunning ? 0.6 : 1.0)
  }

  build() {
    Column() {
      // 标题栏
      if (this.titleBar) {
        Row() {
          BackButton()
            .padding({ left: 15 })

          Text($r('app.string.data_disk_management'))
            .fontSize(18)

          Blank().layoutWeight(1)
        }
        .height(56)
      }

      // 列表
      if (this.dataDiskItems.length === 0 && !this.isLoading) {
        Column() {
          Text($r('app.string.msg_no_data_disk'))
            .fontSize(16)
            .fontColor($r('sys.color.font_tertiary'))
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          RepeatGrid({
            items: this.dataDiskItems as object[],
            contentBuilder: (item: object, index: number) => {
              this.buildDataDiskListItem(item as DataDiskItem)
            },
            getKey: (item: object, index: number) => (item as DataDiskItem).model.id,
            specifiedBreak: this.specifiedBreak
          })
        }
        .scrollable(ScrollDirection.Vertical)
        .scrollBar(BarState.Auto)
        .scrollBarWidth(1)
        .layoutWeight(1)
        .align(Alignment.Top)
      }

      // 底部按钮
      Row({ space: 12 }) {
        Button($r('app.string.btn_import'))
          .layoutWeight(1)
          .onClick(() => this.importDataDisk())
        Button($r('app.string.btn_new_data_disk'))
          .layoutWeight(1)
          .onClick(() => this.createNewDataDisk())
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 24, top: 16 })
      .enabled(!this.globalTaskRunning)
    }
    .width('100%')
  }
}
