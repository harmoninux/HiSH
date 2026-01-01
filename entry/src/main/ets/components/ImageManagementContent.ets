import { CustomContentDialog, LoadingDialog } from '@kit.ArkUI'
import { Emulator } from '../model/Emulator'
import { fileIo as fs } from '@kit.CoreFileKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { pasteboard, deviceInfo } from '@kit.BasicServicesKit'
import napi from 'libentry.so'
import { taskpool } from '@kit.ArkTS';
import { getSnapshotsTask, createSnapshotTask, applySnapshotTask, deleteSnapshotTask, optimizeImageTask, getImageInfoTask, needRestartTask } from '../utils/ImageTasks';
import appOption from '../model/appOption'

const DOMAIN = 0x0000

// 初始化任务状态
AppStorage.setOrCreate(appOption.qemuImgTaskRunning, false)
AppStorage.setOrCreate(appOption.qemuImgTaskDescription, '')

/**
 * 镜像信息接口
 */
interface ImageBasicInfo {
  name: string        // 镜像文件名
  path: string        // 系统路径（程序使用）
  userPath: string    // 用户侧文件路径（用户查看用）
  virtualSize: number // 虚拟大小 (bytes)
  diskSize: number    // 实际占用 (bytes)
}

/**
 * 镜像详细信息接口（来自 qemu-img info）
 */
interface ImageDetailInfo {
  image: string
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

/**
 * 快照信息接口
 */
interface SnapshotInfo {
  id: number
  name: string
  vm_size: number
  date: string
  vm_clock: string
}

/**
 * 镜像管理内容组件
 * 显示虚拟机磁盘镜像的基础信息和详细信息
 */
@Component
export default struct ImageManagementContent {
  @Prop emulator: Emulator
  @Prop isVmRunning: boolean = false  // VM 是否运行中
  @State basicInfo: ImageBasicInfo | null = null
  @State detailInfo: ImageDetailInfo | null = null
  @State isLoading: boolean = false
  @State errorMessage: string = ''
  @State showDetail: boolean = false
  
  // 快照管理相关状态
  @State snapshots: SnapshotInfo[] = []
  @State selectedSnapshots: Set<number> = new Set()
  @State isSnapshotLoading: boolean = false
  @State snapshotError: string = ''
  @State needRestart: boolean = false
  @State snapshotNameInput: string = ''  // 快照名称输入
  @State isPC: boolean = false // 是否为 PC/2in1 设备
  
  // 全局任务状态跟踪
  @StorageLink(appOption.qemuImgTaskRunning) globalTaskRunning: boolean = false
  @StorageLink(appOption.qemuImgTaskDescription) globalTaskDescription: string = ''
  
  private promptAction = this.getUIContext().getPromptAction()
  
  // 优化进度对话框控制器
  @State optimizeTaskMessage: string = ''
  private optimizeProgressDialog: CustomDialogController = new CustomDialogController({
    builder: LoadingDialog({
      content: this.optimizeTaskMessage
    }),
    autoCancel: false,  // 不可关闭
    alignment: DialogAlignment.Center
  })
  
  // 详情对话框控制器
  private detailDialogController: CustomDialogController = new CustomDialogController({
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
    autoCancel: true,
    alignment: DialogAlignment.Center
  })

  // 创建快照对话框控制器
  private createSnapshotDialogController: CustomDialogController = new CustomDialogController({
    builder: CustomContentDialog({
      primaryTitle: $r('app.string.create_snapshot'),
      contentBuilder: () => {
        this.buildCreateSnapshotContent()
      },
      buttons: [
        {
          value: $r('app.string.setting_generic_cancel'),
          action: () => {
            this.createSnapshotDialogController.close()
          }
        },
        {
          value: $r('app.string.btn_create'),
          role: ButtonRole.NORMAL,
          action: () => {
            if (this.snapshotNameInput.trim()) {
              this.createSnapshot(this.snapshotNameInput.trim())
              this.createSnapshotDialogController.close()
            }
          }
        }
      ]
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center
  })
  
  // 优化模式选择对话框控制器
  private optimizeModeDialogController: CustomDialogController = new CustomDialogController({
    builder: CustomContentDialog({
      primaryTitle: $r('app.string.dialog_optimize_mode'),
      contentBuilder: () => {
        this.buildOptimizeModeContent()
      }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center
  })

  aboutToAppear(): void {
    // 检查设备类型，仅 2in1 设备视为 PC
    this.isPC = deviceInfo.deviceType === '2in1' || deviceInfo.deviceType === 'tablet'
    
    // 异步加载，先加载基本信息，完成后再加载快照
    this.loadBasicInfoAsync().then(() => {
      this.loadSnapshotsAsync()
    })
  }

  /**
   * 检查是否为 PC 设备，如果不是则提示
   */
  private checkPC(): boolean {
    if (!this.isPC) {
      this.promptAction.showToast({
        message: $r('app.string.msg_pc_only'),
        duration: 2000
      })
      return false
    }
    return true
  }




  /**
   * 加载基础镜像信息（异步，不阻塞主线程）
   */
  private async loadBasicInfoAsync(): Promise<void> {
    const rootfsPath = this.emulator.rootFilesystem
    const context = this.getUIContext().getHostContext()?.getApplicationContext()
    const filesDir = context?.filesDir || ''
    const bundleName = context?.applicationInfo?.name || 'dev.hackeris.hish'
    const fullPath = rootfsPath.startsWith('/') ? rootfsPath : `${filesDir}/${rootfsPath}`
    
    try {
      // 获取文件名
      const pathParts = fullPath.split('/')
      const fileName = pathParts[pathParts.length - 1]
      
      // 生成用户侧文件路径
      let userPath = fullPath
      if (fullPath.includes('/data/storage/el2/base/')) {
        const relativePart = fullPath.replace('/data/storage/el2/base/', '')
        userPath = `/storage/Users/currentUser/appdata/el2/base/${bundleName}/${relativePart}`
      }
      
      // 异步读取文件信息
      const stat = await fs.stat(fullPath)
      const diskSize = stat.size
      
      // 异步读取 QCOW2 虚拟大小
      const virtualSize = await this.readQcow2VirtualSizeAsync(fullPath)
      
      this.basicInfo = {
        name: fileName,
        path: fullPath,
        userPath: userPath,
        virtualSize: virtualSize,
        diskSize: diskSize
      }
    } catch (e) {
      hilog.error(DOMAIN, 'ImageManagement', '读取镜像信息失败: %{public}s', JSON.stringify(e))
      this.errorMessage = getContext(this).resourceManager.getStringSync($r('app.string.msg_read_image_info_fail').id)
    }
  }

  /**
   * 同步版本（用于刷新时调用，保持向后兼容）
   */
  private loadBasicInfo(): void {
    this.loadBasicInfoAsync()
  }

  /**
   * 异步读取 QCOW2 文件的虚拟大小
   */
  private async readQcow2VirtualSizeAsync(filePath: string): Promise<number> {
    try {
      const f = await fs.open(filePath, fs.OpenMode.READ_ONLY)
      const HEADER_SIZE = 32
      const buffer = new ArrayBuffer(HEADER_SIZE)
      const readResult = await fs.read(f.fd, buffer, { offset: 0, length: HEADER_SIZE })
      await fs.close(f)
      
      if (readResult < HEADER_SIZE) {
        return 0
      }
      
      const dataView = new DataView(buffer)
      const size = dataView.getBigInt64(24, false)
      return Number(size)
    } catch (e) {
      return 0
    }
  }

  /**
   * 加载详细镜像信息（使用 taskpool 异步调用 NAPI）
   */
  private async loadDetailInfo(): Promise<void> {
    if (!this.checkPC()) return
    if (!this.basicInfo) return
    
    this.isLoading = true
    this.errorMessage = ''
    
    try {
      // 使用 taskpool 异步调用 NAPI 获取详细信息
      const jsonOutput = await taskpool.execute(getImageInfoTask, this.basicInfo.path) as string
      
      hilog.info(DOMAIN, 'ImageManagement', 'qemu-img info 输出: %{public}s', jsonOutput)
      
      // 解析 JSON 输出
      const info = JSON.parse(jsonOutput) as Record<string, Object>
      
      // 检查是否有错误
      if (info['error']) {
        this.errorMessage = info['error'] as string
        return
      }
      
      // 提取详细信息
      const formatSpecific = info['format-specific'] as Record<string, Object> | undefined
      const qcow2Data = formatSpecific?.['data'] as Record<string, Object> | undefined
      
      this.detailInfo = {
        image: info['filename'] as string || this.basicInfo.path,
        fileFormat: info['format'] as string || 'unknown',
        virtualSize: info['virtual-size'] as number || this.basicInfo.virtualSize,
        diskSize: info['actual-size'] as number || this.basicInfo.diskSize,
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
      hilog.error(DOMAIN, 'ImageManagement', '获取镜像详情失败: %{public}s', JSON.stringify(e))
      this.errorMessage = getContext(this).resourceManager.getStringSync($r('app.string.msg_get_detail_fail').id) + (e as Error).message
    } finally {
      this.isLoading = false
    }
  }


  /**
   * 格式化大小显示
   */
  private formatSize(bytes: number): string {
    if (bytes === 0) return '0 B'
    
    const units = ['B', 'KB', 'MB', 'GB', 'TB']
    const k = 1024
    const i = Math.floor(Math.log(bytes) / Math.log(k))
    const size = bytes / Math.pow(k, i)
    
    return `${size.toFixed(2)} ${units[i]}`
  }

  /**
   * 复制路径到剪贴板（复制用户侧路径）
   */
  private async copyPath(): Promise<void> {
    if (!this.basicInfo) return
    
    try {
      const board = pasteboard.getSystemPasteboard()
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.basicInfo.userPath)
      await board.setData(pasteData)
      
      this.promptAction.showToast({
        message: $r('app.string.msg_path_copied'),
        duration: 2000
      })
    } catch (e) {
      hilog.error(DOMAIN, 'ImageManagement', '复制路径失败: %{public}s', JSON.stringify(e))
    }
  }

  // ================== 任务锁辅助方法 ==================

  /**
   * 尝试获取任务锁
   * @param description 任务描述
   * @returns 是否成功获取锁
   */
  private checkAndLockTask(description: string): boolean {
    if (this.globalTaskRunning) {
      this.promptAction.showToast({
        message: getContext(this).resourceManager.getStringSync($r('app.string.msg_bg_task_running').id) + this.globalTaskDescription,
        duration: 2000
      })
      return false
    }
    this.globalTaskRunning = true
    this.globalTaskDescription = description
    return true
  }

  /**
   * 释放任务锁
   */
  private unlockTask(): void {
    this.globalTaskRunning = false
    this.globalTaskDescription = ''
  }

  // ================== 快照管理方法 ==================

  /**
   * 异步加载快照列表（不阻塞主线程）
   */
  private async loadSnapshotsAsync(): Promise<void> {
    if (!this.basicInfo) return
    
    this.isSnapshotLoading = true
    this.snapshotError = ''
    
    try {
      // 使用 taskpool 异步调用
      const jsonOutput = await taskpool.execute(getSnapshotsTask, this.basicInfo.path) as string
      hilog.info(DOMAIN, 'ImageManagement', '快照列表: %{public}s', jsonOutput)
      
      const result = JSON.parse(jsonOutput) as Record<string, Object>
      
      if (result['error']) {
        this.snapshotError = result['error'] as string
        return
      }
      
      this.snapshots = (result['snapshots'] as SnapshotInfo[]) || []
      this.needRestart = await taskpool.execute(needRestartTask) as boolean
    } catch (e) {
      hilog.error(DOMAIN, 'ImageManagement', '加载快照失败: %{public}s', JSON.stringify(e))
      this.snapshotError = getContext(this).resourceManager.getStringSync($r('app.string.msg_load_snapshot_failed').id)
    } finally {
      this.isSnapshotLoading = false
    }
  }

  /**
   * 同步版本（保持向后兼容）
   */
  private loadSnapshots(): void {
    this.loadSnapshotsAsync()
  }

  /**
   * 检查是否需要关机（操作前检查）
   * @returns true 如果需要关机但 VM 正在运行
   */
  private checkNeedShutdown(): boolean {
    if (this.isVmRunning) {
      this.promptAction.showToast({
        message: $r('app.string.vm_shutdown_required'),
        duration: 3000
      })
      return true
    }
    return false
  }

  /**
   * 检查是否需要重启应用
   */
  private checkNeedRestart(): boolean {
    if (this.needRestart) {
      this.promptAction.showToast({
        message: $r('app.string.restart_app_required'),
        duration: 3000
      })
      return true
    }
    return false
  }

  /**
   * 创建快照
   */
  private async createSnapshot(name: string): Promise<void> {
    const basicInfo = this.basicInfo
    if (!basicInfo) return
    if (!this.checkAndLockTask(getContext(this).resourceManager.getStringSync($r('app.string.task_creating_snapshot').id))) return
    
    this.isLoading = true
    try {
      hilog.info(DOMAIN, 'ImageManagement', 'createSnapshot: path=%{public}s, name=%{public}s', basicInfo.path, name)
      
      const result = await taskpool.execute(createSnapshotTask, basicInfo.path, name) as string
      const response = JSON.parse(result) as Record<string, Object>
      
      if (response['error']) {
        this.errorMessage = response['error'] as string
        if (response['need_restart']) {
          this.needRestart = true
        }
      } else {
        this.promptAction.showToast({
          message: $r('app.string.msg_snapshot_created'),
          duration: 2000
        })
        await this.loadSnapshots()
      }
    } catch (e) {
      hilog.error(DOMAIN, 'ImageManagement', '创建快照失败: %{public}s', JSON.stringify(e))
      this.errorMessage = getContext(this).resourceManager.getStringSync($r('app.string.msg_snapshot_create_fail').id) + (e as Error).message
    } finally {
      this.isLoading = false
    }
  }

  /**
   * 恢复快照
   */
  private async applySnapshot(name: string): Promise<void> {
    const basicInfo = this.basicInfo
    if (!basicInfo) return
    if (this.checkNeedShutdown()) return
    if (this.checkNeedRestart()) return
    if (!this.checkAndLockTask(getContext(this).resourceManager.getStringSync($r('app.string.task_restoring_snapshot').id))) return
    
    this.promptAction.showDialog({
      title: $r('app.string.dialog_confirm_restore'),
      message: getContext(this).resourceManager.getStringSync($r('app.string.msg_confirm_restore').id) + ` "${name}" ` + getContext(this).resourceManager.getStringSync($r('app.string.msg_confirm_restore_suffix').id),
      buttons: [
        { text: $r('app.string.setting_generic_cancel'), color: '#666666' },
        { text: $r('app.string.btn_restore'), color: '#E74C3C' }
      ]
    }).then(async (result) => {
      if (result.index === 1) {
        this.isLoading = true
        try {
          hilog.info(DOMAIN, 'ImageManagement', 'applySnapshot: path=%{public}s, name=%{public}s', basicInfo.path, name)
          
          const result = await taskpool.execute(applySnapshotTask, basicInfo.path, name) as string
          const response = JSON.parse(result) as Record<string, Object>
          
          if (response['error']) {
            this.errorMessage = response['error'] as string
            if (response['need_restart']) {
              this.needRestart = true
            }
          } else {
            this.promptAction.showToast({
              message: $r('app.string.msg_snapshot_restored'),
              duration: 2000
            })
          }
        } catch (e) {
          hilog.error(DOMAIN, 'ImageManagement', '恢复快照失败: %{public}s', JSON.stringify(e))
          this.errorMessage = getContext(this).resourceManager.getStringSync($r('app.string.msg_snapshot_restore_fail').id) + (e as Error).message
        } finally {
          this.isLoading = false
          this.unlockTask()
        }
      } else {
        this.unlockTask()
      }
    })
  }

  /**
   * 删除快照
   */
  private async deleteSnapshot(name: string): Promise<void> {
    const basicInfo = this.basicInfo
    if (!basicInfo) return
    if (this.checkNeedShutdown()) return
    if (this.checkNeedRestart()) return
    if (!this.checkAndLockTask(getContext(this).resourceManager.getStringSync($r('app.string.task_deleting_snapshot').id))) return
    
    this.promptAction.showDialog({
      title: $r('app.string.dialog_confirm_delete'),
      message: getContext(this).resourceManager.getStringSync($r('app.string.msg_confirm_delete_snapshot').id) + ` "${name}"?`,
      buttons: [
        { text: $r('app.string.setting_generic_cancel'), color: '#666666' },
        { text: $r('app.string.delete_this'), color: '#E74C3C' }
      ]
    }).then(async (result) => {
      if (result.index === 1) {
        this.isLoading = true
        try {
          hilog.info(DOMAIN, 'ImageManagement', 'deleteSnapshot: path=%{public}s, name=%{public}s', basicInfo.path, name)
          
          const result = await taskpool.execute(deleteSnapshotTask, basicInfo.path, name) as string
          const response = JSON.parse(result) as Record<string, Object>
          
          if (response['error']) {
            this.errorMessage = response['error'] as string
            if (response['need_restart']) {
              this.needRestart = true
            }
          } else {
            this.promptAction.showToast({
              message: $r('app.string.msg_snapshot_deleted'),
              duration: 2000
            })
            await this.loadSnapshots()
          }
        } catch (e) {
          hilog.error(DOMAIN, 'ImageManagement', '删除快照失败: %{public}s', JSON.stringify(e))
          this.errorMessage = getContext(this).resourceManager.getStringSync($r('app.string.msg_snapshot_delete_fail').id) + (e as Error).message
        } finally {
          this.isLoading = false
          this.unlockTask()
        }
      } else {
        this.unlockTask()
      }
    })
  }

  /**
   * 批量删除快照
   */
  private async batchDeleteSnapshots(): Promise<void> {
    const basicInfo = this.basicInfo
    if (!basicInfo || this.selectedSnapshots.size === 0) return
    if (this.checkNeedShutdown()) return
    if (this.checkNeedRestart()) return
    if (!this.checkAndLockTask(getContext(this).resourceManager.getStringSync($r('app.string.task_batch_deleting_snapshots').id))) return

    this.promptAction.showDialog({
      title: $r('app.string.dialog_confirm_batch_delete'),
      message: getContext(this).resourceManager.getStringSync($r('app.string.msg_confirm_batch_delete').id) + ` ${this.selectedSnapshots.size} ` + getContext(this).resourceManager.getStringSync($r('app.string.msg_confirm_batch_delete_suffix').id),
      buttons: [
        { text: $r('app.string.setting_generic_cancel'), color: '#666666' },
        { text: $r('app.string.delete_this'), color: '#E74C3C' }
      ]
    }).then(async (result) => {
      if (result.index === 1) {
        this.isLoading = true
        let successCount = 0
        let failCount = 0
        
        try {
          // 转换为数组以进行迭代
          const snapshotsToDelete = Array.from(this.selectedSnapshots)
          
          for (const id of snapshotsToDelete) {
            // 根据ID查找名称
            const snapshot = this.snapshots.find(s => s.id === id)
            if (!snapshot) continue
            
            try {
              const result = await taskpool.execute(deleteSnapshotTask, basicInfo.path, snapshot.name) as string
              const response = JSON.parse(result) as Record<string, Object>
              
              if (response['error']) {
                failCount++
                hilog.error(DOMAIN, 'ImageManagement', '删除快照 %{public}s 失败: %{public}s', snapshot.name, response['error'])
              } else {
                successCount++
              }
            } catch (e) {
              failCount++
              hilog.error(DOMAIN, 'ImageManagement', '删除快照 %{public}s 异常: %{public}s', snapshot.name, JSON.stringify(e))
            }
          }
          
          this.promptAction.showToast({
            message: getContext(this).resourceManager.getStringSync($r('app.string.msg_batch_delete_result').id) + ` ${successCount}, ` + getContext(this).resourceManager.getStringSync($r('app.string.msg_failed').id) + ` ${failCount}`,
            duration: 3000
          })
          
          this.selectedSnapshots.clear()
          await this.loadSnapshots()
          
        } catch (e) {
          this.errorMessage = getContext(this).resourceManager.getStringSync($r('app.string.msg_batch_delete_fail').id) + (e as Error).message
        } finally {
          this.isLoading = false
          this.unlockTask()
        }
      } else {
        this.unlockTask()
      }
    })
  }

  /**
   * 优化镜像
   * @param mode 'sparse' | 'prealloc' | 'cleanup' | 'optimize'
   */
  private async optimizeImage(mode: 'sparse' | 'prealloc' | 'cleanup' | 'optimize'): Promise<void> {
    const basicInfo = this.basicInfo
    if (!basicInfo) return
    if (this.checkNeedShutdown()) return
    if (this.checkNeedRestart()) return
    
    const modeNames: Record<string, Resource> = {
      'sparse': $r('app.string.optimize_mode_sparse'),
      'prealloc': $r('app.string.optimize_mode_prealloc'),
      'optimize': $r('app.string.optimize_mode_optimize')
    }
    const tempPath = `${basicInfo.path}.tmp`
    
    // 检查全局任务状态
    if (this.globalTaskRunning) {
      this.promptAction.showDialog({
        title: $r('app.string.dialog_task_running'),
        message: getContext(this).resourceManager.getStringSync($r('app.string.msg_task_running_prefix').id) + `${this.globalTaskDescription}\n\n` + getContext(this).resourceManager.getStringSync($r('app.string.msg_task_running_desc').id),
        buttons: [
          { text: $r('app.string.btn_wait'), color: '#007DFF' },
          { text: $r('app.string.btn_force_cleanup'), color: '#E74C3C' }
        ]
      }).then(async (result) => {
        if (result.index === 1) {
          // 强制清理
          this.unlockTask()
          try {
            await fs.unlink(tempPath)
          } catch (e) {
            // 忽略
          }
          this.promptAction.showToast({
            message: $r('app.string.msg_task_cleaned'),
            duration: 2000
          })
        }
      })
      return
    }

    
    // 防止重复操作
    if (this.isLoading) {
      this.promptAction.showToast({
        message: $r('app.string.msg_op_in_progress'),
        duration: 2000
      })
      return
    }
    
    // 检查是否存在临时文件（上次操作可能未完成或中断）
    try {
      await fs.access(tempPath)
      // 临时文件存在，询问用户如何处理
      const tmpStat = await fs.stat(tempPath)
      const tmpSize = this.formatSize(tmpStat.size)
      const modTime = new Date(tmpStat.mtime)
      const elapsed = Math.round((Date.now() - modTime.getTime()) / 1000 / 60)  // 分钟
      
      this.promptAction.showDialog({
        title: $r('app.string.dialog_temp_file_found'),
        message: getContext(this).resourceManager.getStringSync($r('app.string.msg_temp_file_found').id) + ` (${tmpSize})，` + getContext(this).resourceManager.getStringSync($r('app.string.msg_temp_file_time').id) + ` ${elapsed} ` + getContext(this).resourceManager.getStringSync($r('app.string.msg_temp_file_desc').id),
        buttons: [
          { text: $r('app.string.setting_generic_cancel'), color: '#666666' },
          { text: $r('app.string.btn_force_cleanup'), color: '#E74C3C' }
        ]
      }).then(async (result) => {
        if (result.index === 1) {
          try {
            await fs.unlink(tempPath)
            this.globalTaskRunning = false
            this.globalTaskDescription = ''
            this.promptAction.showToast({
              message: $r('app.string.msg_temp_file_cleaned'),
              duration: 2000
            })
          } catch (e) {
            this.errorMessage = getContext(this).resourceManager.getStringSync($r('app.string.msg_temp_file_clean_fail').id) + (e as Error).message
          }
        }
      })
      return
    } catch (e) {
      // 临时文件不存在，可以继续
    }
    
    // 设置任务状态
    this.isLoading = true
    const modeName = getContext(this).resourceManager.getStringSync(modeNames[mode].id)
    this.checkAndLockTask(`${modeName} (${new Date().toLocaleTimeString()})`)
    
    // 显示进度对话框（不可关闭）
    this.optimizeTaskMessage = getContext(this).resourceManager.getStringSync($r('app.string.msg_executing_prefix').id) + `${modeName}` + getContext(this).resourceManager.getStringSync($r('app.string.msg_executing_suffix').id)
    this.optimizeProgressDialog.open()
    
    try {
      hilog.info(DOMAIN, 'ImageManagement', '开始优化镜像: mode=%{public}s, output=%{public}s', mode, tempPath)
      
      // 使用 taskpool 执行耗时操作
      const result = await taskpool.execute(optimizeImageTask, basicInfo.path, tempPath, mode) as string
      const response = JSON.parse(result) as Record<string, Object>
      
      if (response['error']) {
        this.errorMessage = response['error'] as string
        if (response['need_restart']) {
          this.needRestart = true
        }
        // 删除临时文件
        try {
          await fs.unlink(tempPath)
        } catch (e) {
          // 忽略删除失败
        }
        return
      }
      
      // 获取优化前后大小
      const oldSize = basicInfo.diskSize
      const newStat = await fs.stat(tempPath)
      const newSize = newStat.size
      
      // 替换原文件
      try {
        await fs.unlink(basicInfo.path)
        await fs.rename(tempPath, basicInfo.path)
      } catch (e) {
        this.errorMessage = getContext(this).resourceManager.getStringSync($r('app.string.msg_replace_file_fail').id) + (e as Error).message
        return
      }
      
      // 计算节省空间
      const savedBytes = oldSize - newSize
      const savedStr = savedBytes > 0 ? getContext(this).resourceManager.getStringSync($r('app.string.msg_saved_space').id) + ` ${this.formatSize(savedBytes)}` : getContext(this).resourceManager.getStringSync($r('app.string.msg_increased_space').id) + ` ${this.formatSize(-savedBytes)}`
      
      this.promptAction.showToast({
        message: getContext(this).resourceManager.getStringSync($r('app.string.msg_optimize_finished').id) + `${savedStr}`,
        duration: 3000
      })
      
      // 刷新基础信息
      this.loadBasicInfo()
    } catch (e) {
      hilog.error(DOMAIN, 'ImageManagement', '优化镜像失败: %{public}s', JSON.stringify(e))
      this.errorMessage = getContext(this).resourceManager.getStringSync($r('app.string.msg_optimize_fail').id) + (e as Error).message
    } finally {
      this.optimizeProgressDialog.close()
      this.isLoading = false
      this.unlockTask()
    }
  }

  /**
   * 强制清理后台任务状态
   */
  private async forceCleanupTask(): Promise<void> {
    const basicInfo = this.basicInfo
    if (!basicInfo) return
    
    this.promptAction.showDialog({
      title: $r('app.string.dialog_confirm_force_cleanup'),
      message: $r('app.string.msg_confirm_force_cleanup'),
      buttons: [
        { text: $r('app.string.setting_generic_cancel'), color: '#666666' },
        { text: $r('app.string.btn_force_cleanup'), color: '#E74C3C' }
      ]
    }).then(async (result) => {
      if (result.index === 1) {
        const tempPath = `${basicInfo.path}.tmp`
        try {
          await fs.unlink(tempPath)
        } catch (e) {
          // 忽略
        }
        this.optimizeProgressDialog.close()
        this.isLoading = false
        this.unlockTask()
        this.promptAction.showToast({
          message: $r('app.string.msg_task_state_cleaned'),
          duration: 2000
        })
      }
    })
  }

  /**
   * 显示优化对话框
   */
  private showOptimizeDialog(): void {
    if (!this.checkPC()) return
    if (this.checkNeedShutdown()) return
    if (this.checkNeedRestart()) return
    
    this.optimizeModeDialogController.open()
  }
  
  @Builder
  buildOptimizeModeContent() {
    Column({ space: 8 }) {
      // 格式优化按钮 - 绿色推荐
      Button({ type: ButtonType.Normal, stateEffect: true }) {
        Row({ space: 8 }) {
          Text('🚀')
            .fontSize(18)
          Column() {
            Text($r('app.string.optimize_mode_optimize'))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
            Text($r('app.string.desc_optimize'))
              .fontSize(10)
              .fontColor('#FFFFFF')
              .opacity(0.8)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 12, right: 12 })
      }
      .width('100%')
      .height(52)
      .backgroundColor('#2ECC71')
      .borderRadius(8)
      .onClick(() => {
        this.optimizeModeDialogController.close()
        this.confirmAndOptimize('optimize', $r('app.string.optimize_mode_optimize'), $r('app.string.msg_optimize_confirm'))
      })
      
      // 整理碎片按钮 - 蓝色
      Button({ type: ButtonType.Normal, stateEffect: true }) {
        Row({ space: 8 }) {
          Text('🧹')
            .fontSize(18)
          Column() {
            Text($r('app.string.optimize_mode_sparse'))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
            Text($r('app.string.desc_sparse'))
              .fontSize(10)
              .fontColor('#FFFFFF')
              .opacity(0.8)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 12, right: 12 })
      }
      .width('100%')
      .height(52)
      .backgroundColor('#3498DB')
      .borderRadius(8)
      .onClick(() => {
        this.optimizeModeDialogController.close()
        this.optimizeImage('sparse')
      })
      
      // 预分配格式按钮 - 橙色警告
      Button({ type: ButtonType.Normal, stateEffect: true }) {
        Row({ space: 8 }) {
          Text('⚡')
            .fontSize(18)
          Column() {
            Text($r('app.string.title_prealloc'))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
            Text($r('app.string.desc_prealloc'))
              .fontSize(10)
              .fontColor('#FFFFFF')
              .opacity(0.8)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 12, right: 12 })
      }
      .width('100%')
      .height(52)
      .backgroundColor('#E67E22')
      .borderRadius(8)
      .onClick(() => {
        this.optimizeModeDialogController.close()
        this.confirmAndOptimize('prealloc', $r('app.string.title_prealloc'), $r('app.string.msg_prealloc_confirm'))
      })
    }
    .padding(8)
    .width('100%')
  }
  
  /**
   * 确认后执行优化
   */
  private confirmAndOptimize(mode: 'sparse' | 'prealloc' | 'cleanup' | 'optimize', title: Resource, message: Resource): void {
    this.promptAction.showDialog({
      title: title,
      message: message,
      buttons: [
        { text: $r('app.string.setting_generic_cancel'), color: '#666666' },
        { text: $r('app.string.btn_start'), color: '#007DFF' }
      ]
    }).then((result) => {
      if (result.index === 1) {
        this.optimizeImage(mode)
      }
    })
  }

  build() {
    Scroll() {
      Column() {
        if (this.errorMessage) {
          // 错误提示
          Row() {
            Text(this.errorMessage)
              .fontSize(14)
              .fontColor('#E74C3C')
          }
          .width('100%')
          .padding(16)
          .backgroundColor('#FFF0F0')
          .borderRadius(8)
          .margin({ bottom: 16 })
        }

        if (this.basicInfo) {
          // 基础信息区域
          Column() {
            Text($r('app.string.title_basic_info'))
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .margin({ bottom: 12 })
              .alignSelf(ItemAlign.Start)

            // 镜像名称
            Row() {
              Text($r('app.string.image_name'))
                .fontSize(12)
                .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                .width(80)
              Text(this.basicInfo.name)
                .fontSize(12)
                .fontColor($r('sys.color.ohos_id_color_text_primary'))
                .layoutWeight(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .maxLines(1)
            }
            .width('100%')
            .padding({ top: 8, bottom: 8 })

            Divider().color($r('sys.color.ohos_id_color_list_separator'))

            // 系统路径（程序使用）
            Row() {
              Text($r('app.string.label_system_path'))
                .fontSize(12)
                .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                .width(80)
              Text(this.basicInfo.path)
                .fontSize(9)
                .fontColor($r('sys.color.ohos_id_color_text_tertiary'))
                .layoutWeight(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .maxLines(2)
            }
            .width('100%')
            .padding({ top: 8, bottom: 8 })

            Divider().color($r('sys.color.ohos_id_color_list_separator'))

            // 用户路径（用户可访问）
            Row() {
              Text($r('app.string.label_file_path'))
                .fontSize(12)
                .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                .width(80)
              Text(this.basicInfo.userPath)
                .fontSize(9)
                .fontColor($r('sys.color.ohos_id_color_text_primary'))
                .layoutWeight(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .maxLines(2)
              Button($r('app.string.copy_this'), { buttonStyle: ButtonStyleMode.TEXTUAL, controlSize: ControlSize.SMALL })
                .fontSize(10)
                .onClick(() => this.copyPath())
            }
            .width('100%')
            .padding({ top: 8, bottom: 8 })

            Divider().color($r('sys.color.ohos_id_color_list_separator'))

            // 虚拟大小
            Row() {
              Text($r('app.string.virtual_size'))
                .fontSize(12)
                .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                .width(80)
              Text(this.formatSize(this.basicInfo.virtualSize))
                .fontSize(12)
                .fontColor($r('sys.color.ohos_id_color_text_primary'))
                .layoutWeight(1)
            }
            .width('100%')
            .padding({ top: 8, bottom: 8 })

            Divider().color($r('sys.color.ohos_id_color_list_separator'))

            // 实际占用
            Row() {
              Text($r('app.string.disk_size'))
                .fontSize(12)
                .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                .width(80)
              Text(this.formatSize(this.basicInfo.diskSize))
                .fontSize(12)
                .fontColor($r('sys.color.ohos_id_color_text_primary'))
                .layoutWeight(1)
            }
            .width('100%')
            .padding({ top: 8, bottom: 8 })

            // 空间利用率
            Row() {
              Text($r('app.string.space_usage'))
                .fontSize(12)
                .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                .width(80)
              Text(`${((this.basicInfo.diskSize / this.basicInfo.virtualSize) * 100).toFixed(1)}%`)
                .fontSize(12)
                .fontColor($r('sys.color.ohos_id_color_text_primary'))
                .layoutWeight(1)
            }
            .width('100%')
            .padding({ top: 8, bottom: 8 })
          }
          .width('100%')
          .padding(16)
          .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
          .borderRadius(8)
          .margin({ bottom: 16 })
          // 操作按钮行
          Row() {
            // 查看详情按钮
            Button($r('app.string.view_details'), { buttonStyle: ButtonStyleMode.TEXTUAL })
              .layoutWeight(1)
              .height(36)
              .enabled(!this.isLoading && !this.globalTaskRunning)
              .onClick(() => this.loadDetailInfo())

            // 优化镜像按钮
            Button($r('app.string.optimize_image'))
              .layoutWeight(1)
              .height(36)
              .backgroundColor('#007DFF')
              .fontColor(Color.White)
              .enabled(!this.isLoading && !this.isVmRunning && !this.needRestart && !this.globalTaskRunning)
              .onClick(() => this.showOptimizeDialog())
          }
          .width('100%')
          
          // VM 运行中提示
          if (this.isVmRunning) {
            Row() {
              SymbolGlyph($r('sys.symbol.info_circle'))
                .fontSize(14)
                .fontColor(['#E67E22'])
              Text($r('app.string.msg_vm_running_optimize'))
                .fontSize(11)
                .fontColor('#E67E22')
                .margin({ left: 6 })
            }
            .width('100%')
            .margin({ top: 8 })
            .padding(8)
            .backgroundColor('#FFF8E7')
            .borderRadius(6)
          }
          
          // 需要重启提示
          if (this.needRestart) {
            Row() {
              SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
                .fontSize(14)
                .fontColor(['#E74C3C'])
              Text($r('app.string.msg_image_modified'))
                .fontSize(11)
                .fontColor('#E74C3C')
                .margin({ left: 6 })
            }
            .width('100%')
            .margin({ top: 8 })
            .padding(8)
            .backgroundColor('#FFF0F0')
            .borderRadius(6)
          }
          
          // 后台任务状态提示和强制清理按钮
          if (this.globalTaskRunning) {
            Row() {
              LoadingProgress()
                .width(20)
                .height(20)
              Text(getContext(this).resourceManager.getStringSync($r('app.string.label_bg_task').id) + `${this.globalTaskDescription}`)
                .fontSize(12)
                .fontColor('#007DFF')
                .margin({ left: 8 })
                .layoutWeight(1)
              Button($r('app.string.btn_force_cleanup'), { buttonStyle: ButtonStyleMode.TEXTUAL })
                .fontSize(12)
                .fontColor('#E74C3C')
                .onClick(() => this.forceCleanupTask())
            }
            .width('100%')
            .margin({ top: 12 })
            .padding(8)
            .backgroundColor('#FFF3CD')
            .borderRadius(8)
          }

          if (this.isLoading && !this.globalTaskRunning) {
            Row() {
              LoadingProgress()
                .width(24)
                .height(24)
              Text($r('app.string.msg_getting_details'))
                .fontSize(12)
                .margin({ left: 8 })
            }
            .margin({ top: 16 })
          }
        } else {
          // 加载中状态
          Row() {
            LoadingProgress()
              .width(24)
              .height(24)
            Text($r('app.string.msg_loading_image_info'))
              .fontSize(12)
              .margin({ left: 8 })
          }
          .padding(16)
        }

        // 说明文字
        Text($r('app.string.msg_image_size_hint'))
          .fontSize(11)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .margin({ top: 16 })
          .width('100%')

        // ================== 快照管理区域 ==================
        Column() {
          // 标题行
          Row() {
            Text($r('app.string.snapshot_management'))
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .layoutWeight(1)
            
            // 刷新按钮
            Button({ type: ButtonType.Circle, stateEffect: true }) {
              SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                .fontSize(16)
                .fontColor([$r('sys.color.ohos_id_color_text_primary')])
            }
            .width(24)
            .height(24)
            .backgroundColor(Color.Transparent)
            .onClick(() => this.loadSnapshots())
          }
          .width('100%')
          .margin({ bottom: 8 })

          if (this.isSnapshotLoading) {
            Row() {
              LoadingProgress()
                .width(20)
                .height(20)
              Text($r('app.string.msg_loading_snapshots'))
                .fontSize(12)
                .margin({ left: 8 })
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .padding(16)
          } else if (this.snapshotError) {
            Text(this.snapshotError)
              .fontSize(12)
              .fontColor('#E74C3C')
              .padding(16)
          } else if (this.snapshots.length === 0) {
            Text($r('app.string.msg_no_snapshots'))
              .fontSize(12)
              .fontColor($r('sys.color.ohos_id_color_text_tertiary'))
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding(16)
              .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
              .borderRadius(8)
              .margin({ top: 8, bottom: 8 })
          } else {
            // 快照列表表格
            Column() {
              // 全选控制行
              Row() {
                Checkbox()
                  .select(this.snapshots.length > 0 && this.selectedSnapshots.size === this.snapshots.length)
                  .onChange((selected: boolean) => {
                    // 使用 setTimeout 避免在渲染过程中更新状态
                    setTimeout(() => {
                      if (selected) {
                        this.snapshots.forEach(s => this.selectedSnapshots.add(s.id))
                      } else {
                        this.selectedSnapshots.clear()
                      }
                      this.selectedSnapshots = new Set(this.selectedSnapshots)
                    }, 0)
                  })
                  .width(20)
                  .height(20)
                
                Text($r('app.string.btn_select_all'))
                  .fontSize(12)
                  .margin({ left: 8 })
                  .fontWeight(FontWeight.Bold)
              }
              .width('100%')
              .padding({ top: 4, bottom: 4 })
              
              Divider().color($r('sys.color.ohos_id_color_list_separator'))

              ForEach(this.snapshots, (snapshot: SnapshotInfo) => {
                Row() {
                  // 勾选框
                  Checkbox()
                    .select(this.selectedSnapshots.has(snapshot.id))
                    .onChange((selected: boolean) => {
                      // 使用 setTimeout 避免在渲染过程中更新状态
                      setTimeout(() => {
                        if (selected) {
                          this.selectedSnapshots.add(snapshot.id)
                        } else {
                          this.selectedSnapshots.delete(snapshot.id)
                        }
                        this.selectedSnapshots = new Set(this.selectedSnapshots)
                      }, 0)
                    })
                    .width(20)
                    .height(20)
                  
                  // 快照名称
                  Text(snapshot.name)
                    .fontSize(12)
                    .layoutWeight(1)
                    .margin({ left: 8 })
                  
                  // 创建日期
                  Text(snapshot.date.substring(5, 16))
                    .fontSize(10)
                    .fontColor($r('sys.color.ohos_id_color_text_tertiary'))
                    .width(80)
                  
                  // 恢复按钮
                  Button($r('app.string.btn_restore'), { buttonStyle: ButtonStyleMode.TEXTUAL, controlSize: ControlSize.SMALL })
                    .fontSize(10)
                    .onClick(() => this.applySnapshot(snapshot.name))
                    .enabled(!this.isVmRunning && !this.needRestart && !this.globalTaskRunning)
                  
                  // 删除按钮
                  Button($r('app.string.delete_this'), { buttonStyle: ButtonStyleMode.TEXTUAL, controlSize: ControlSize.SMALL })
                    .fontSize(10)
                    .fontColor('#E74C3C')
                    .onClick(() => this.deleteSnapshot(snapshot.name))
                    .enabled(!this.isVmRunning && !this.needRestart && !this.globalTaskRunning)
                }
                .width('100%')
                .padding({ top: 8, bottom: 8 })
                
                Divider().color($r('sys.color.ohos_id_color_list_separator'))
              })
            }
            .width('100%')
            .padding(12)
            .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
            .borderRadius(8)
            .margin({ top: 8, bottom: 8 })
          }

          // 底部操作栏
          Row() {
            Button($r('app.string.create_snapshot'))
              .layoutWeight(1)
              .height(40)
              .onClick(() => {
                if (!this.checkPC()) return
                if (this.checkNeedShutdown()) return
                if (this.checkNeedRestart()) return
                
                this.snapshotNameInput = ''
                this.createSnapshotDialogController.open()
              })
              .enabled(!this.isLoading && !this.isVmRunning && !this.needRestart && !this.globalTaskRunning)

            Blank().width(12)

            Button(getContext(this).resourceManager.getStringSync($r('app.string.btn_batch_delete').id) + ` (${this.selectedSnapshots.size})`)
              .layoutWeight(1)
              .height(40)
              .backgroundColor('#E74C3C')
              .fontColor(Color.White)
              .enabled(this.selectedSnapshots.size > 0 && !this.isLoading && !this.isVmRunning && !this.needRestart && !this.globalTaskRunning)
              .onClick(() => this.batchDeleteSnapshots())
          }
          .width('100%')
          .margin({ top: 16 })
          
          // VM 运行中提示（快照区域）
          if (this.isVmRunning) {
            Row() {
              SymbolGlyph($r('sys.symbol.info_circle'))
                .fontSize(14)
                .fontColor(['#E67E22'])
              Text($r('app.string.msg_vm_running_snapshot'))
                .fontSize(11)
                .fontColor('#E67E22')
                .margin({ left: 6 })
            }
            .width('100%')
            .margin({ top: 8 })
            .padding(8)
            .backgroundColor('#FFF8E7')
            .borderRadius(6)
          }
        }
        .width('100%')
        .margin({ top: 24 })
      }
      .padding(16)
    }
    .width('100%')
    .height('100%')
    .align(Alignment.TopStart)
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

  @Builder
  buildCreateSnapshotContent() {
    Column() {
      TextInput({
        placeholder: $r('app.string.placeholder_snapshot_name'),
        text: $$this.snapshotNameInput
      })
        .width('100%')
        .height(40)
        .margin({ bottom: 8 })
      
      Text($r('app.string.msg_snapshot_name_duplicate'))
        .fontSize(11)
        .fontColor($r('sys.color.ohos_id_color_text_tertiary'))
    }
    .width('100%')
    .padding(16)
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

}
