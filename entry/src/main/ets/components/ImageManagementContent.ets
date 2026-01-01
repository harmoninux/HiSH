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
  @State optimizeTaskMessage: string = '正在执行...'
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
      primaryTitle: '镜像详情',
      contentBuilder: () => {
        this.buildDetailContent()
      },
      buttons: [{
        value: '关闭',
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
      primaryTitle: '创建快照',
      contentBuilder: () => {
        this.buildCreateSnapshotContent()
      },
      buttons: [
        {
          value: '取消',
          action: () => {
            this.createSnapshotDialogController.close()
          }
        },
        {
          value: '创建',
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
      primaryTitle: '选择优化模式',
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
        message: '该功能仅适用于 PC/2in1 设备',
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
      this.errorMessage = '无法读取镜像信息'
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
      this.errorMessage = '获取详情失败: ' + (e as Error).message
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
        message: '文件路径已复制到剪贴板',
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
        message: `后台任务处理中: ${this.globalTaskDescription}`,
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
      this.snapshotError = '加载快照失败'
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
        message: '此操作需要虚拟机关机后执行',
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
        message: '请重启应用后重试',
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
    if (!this.checkAndLockTask('创建快照...')) return
    
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
          message: '快照创建成功',
          duration: 2000
        })
        await this.loadSnapshots()
      }
    } catch (e) {
      hilog.error(DOMAIN, 'ImageManagement', '创建快照失败: %{public}s', JSON.stringify(e))
      this.errorMessage = '创建快照失败: ' + (e as Error).message
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
    if (!this.checkAndLockTask('恢复快照...')) return
    
    this.promptAction.showDialog({
      title: '确认恢复',
      message: `确定要恢复到快照 "${name}" 吗？当前状态将会丢失。`,
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '恢复', color: '#E74C3C' }
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
              message: '快照恢复成功',
              duration: 2000
            })
          }
        } catch (e) {
          hilog.error(DOMAIN, 'ImageManagement', '恢复快照失败: %{public}s', JSON.stringify(e))
          this.errorMessage = '恢复快照失败: ' + (e as Error).message
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
    if (!this.checkAndLockTask('删除快照...')) return
    
    this.promptAction.showDialog({
      title: '确认删除',
      message: `确定要删除快照 "${name}" 吗？`,
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '删除', color: '#E74C3C' }
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
              message: '快照删除成功',
              duration: 2000
            })
            await this.loadSnapshots()
          }
        } catch (e) {
          hilog.error(DOMAIN, 'ImageManagement', '删除快照失败: %{public}s', JSON.stringify(e))
          this.errorMessage = '删除快照失败: ' + (e as Error).message
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
    if (!this.checkAndLockTask('批量删除快照...')) return

    this.promptAction.showDialog({
      title: '确认批量删除',
      message: `确定要删除选中的 ${this.selectedSnapshots.size} 个快照吗？`,
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '删除', color: '#E74C3C' }
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
            message: `批量删除完成: 成功 ${successCount}, 失败 ${failCount}`,
            duration: 3000
          })
          
          this.selectedSnapshots.clear()
          await this.loadSnapshots()
          
        } catch (e) {
          this.errorMessage = '批量删除失败: ' + (e as Error).message
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
    
    const modeNames: Record<string, string> = {
      'sparse': '整理碎片',
      'prealloc': '预分配',
      'optimize': '格式优化'
    }
    const tempPath = `${basicInfo.path}.tmp`
    
    // 检查全局任务状态
    if (this.globalTaskRunning) {
      this.promptAction.showDialog({
        title: '有任务正在执行',
        message: `当前正在执行: ${this.globalTaskDescription}\n\n请等待任务完成后再进行新操作。\n\n如果任务已异常中断，可强制清理状态。`,
        buttons: [
          { text: '继续等待', color: '#007DFF' },
          { text: '强制清理', color: '#E74C3C' }
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
            message: '已强制清理任务状态，请重新执行操作',
            duration: 2000
          })
        }
      })
      return
    }

    
    // 防止重复操作
    if (this.isLoading) {
      this.promptAction.showToast({
        message: '有操作正在进行中，请稍候',
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
        title: '发现残留临时文件',
        message: `存在临时文件 (${tmpSize})，最后修改于 ${elapsed} 分钟前。\n\n如果任务仍在运行，文件会持续更新。\n如果文件长时间未更新，说明任务可能已异常中断。\n\n选择"强制清理"将删除临时文件。`,
        buttons: [
          { text: '取消', color: '#666666' },
          { text: '强制清理', color: '#E74C3C' }
        ]
      }).then(async (result) => {
        if (result.index === 1) {
          try {
            await fs.unlink(tempPath)
            this.globalTaskRunning = false
            this.globalTaskDescription = ''
            this.promptAction.showToast({
              message: '临时文件已清理，请重新执行操作',
              duration: 2000
            })
          } catch (e) {
            this.errorMessage = '清理临时文件失败: ' + (e as Error).message
          }
        }
      })
      return
    } catch (e) {
      // 临时文件不存在，可以继续
    }
    
    // 设置任务状态
    this.isLoading = true
    this.checkAndLockTask(`${modeNames[mode]} (${new Date().toLocaleTimeString()})`)
    
    // 显示进度对话框（不可关闭）
    this.optimizeTaskMessage = `正在执行${modeNames[mode]}...\n此操作可能需要几分钟，请勿关闭应用`
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
        this.errorMessage = '替换文件失败: ' + (e as Error).message
        return
      }
      
      // 计算节省空间
      const savedBytes = oldSize - newSize
      const savedStr = savedBytes > 0 ? `节省 ${this.formatSize(savedBytes)}` : `增加 ${this.formatSize(-savedBytes)}`
      
      this.promptAction.showToast({
        message: `优化完成，${savedStr}`,
        duration: 3000
      })
      
      // 刷新基础信息
      this.loadBasicInfo()
    } catch (e) {
      hilog.error(DOMAIN, 'ImageManagement', '优化镜像失败: %{public}s', JSON.stringify(e))
      this.errorMessage = '优化失败: ' + (e as Error).message
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
      title: '确认强制清理',
      message: '这将清理任务状态和临时文件。\n\n仅在确认任务已异常中断时使用，否则可能导致数据丢失。',
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '强制清理', color: '#E74C3C' }
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
          message: '已强制清理任务状态',
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
            Text('格式优化')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
            Text('启用 lazy_refcounts 和 extended_l2 特性')
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
        this.confirmAndOptimize('optimize', '格式优化', '此操作将启用 lazy_refcounts 和 extended_l2 特性，提升镜像写入性能和空间效率。这会重写整个镜像文件。')
      })
      
      // 整理碎片按钮 - 蓝色
      Button({ type: ButtonType.Normal, stateEffect: true }) {
        Row({ space: 8 }) {
          Text('🧹')
            .fontSize(18)
          Column() {
            Text('整理碎片')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
            Text('释放未使用空间，转换为稀疏格式')
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
            Text('预分配格式')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
            Text('最高性能，会占用完整虚拟磁盘空间')
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
        this.confirmAndOptimize('prealloc', '预分配格式', '预分配格式会占用完整的虚拟磁盘空间，确定继续？')
      })
    }
    .padding(8)
    .width('100%')
  }
  
  /**
   * 确认后执行优化
   */
  private confirmAndOptimize(mode: 'sparse' | 'prealloc' | 'cleanup' | 'optimize', title: string, message: string): void {
    this.promptAction.showDialog({
      title: title,
      message: message,
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '开始', color: '#007DFF' }
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
            Text('基础信息')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .margin({ bottom: 12 })
              .alignSelf(ItemAlign.Start)

            // 镜像名称
            Row() {
              Text('镜像名称')
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
              Text('系统路径')
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
              Text('文件路径')
                .fontSize(12)
                .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                .width(80)
              Text(this.basicInfo.userPath)
                .fontSize(9)
                .fontColor($r('sys.color.ohos_id_color_text_primary'))
                .layoutWeight(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .maxLines(2)
              Button('复制', { buttonStyle: ButtonStyleMode.TEXTUAL, controlSize: ControlSize.SMALL })
                .fontSize(10)
                .onClick(() => this.copyPath())
            }
            .width('100%')
            .padding({ top: 8, bottom: 8 })

            Divider().color($r('sys.color.ohos_id_color_list_separator'))

            // 虚拟大小
            Row() {
              Text('虚拟大小')
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
              Text('实际占用')
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
              Text('空间利用率')
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
            Button('查看详情', { buttonStyle: ButtonStyleMode.TEXTUAL })
              .layoutWeight(1)
              .height(36)
              .enabled(!this.isLoading && !this.globalTaskRunning)
              .onClick(() => this.loadDetailInfo())

            // 优化镜像按钮
            Button('优化镜像')
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
              Text('虚拟机正在运行，优化镜像功能需要先关闭虚拟机')
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
              Text('镜像文件已被修改，需要重启应用后才能继续操作')
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
              Text(`后台任务: ${this.globalTaskDescription}`)
                .fontSize(12)
                .fontColor('#007DFF')
                .margin({ left: 8 })
                .layoutWeight(1)
              Button('强制清理', { buttonStyle: ButtonStyleMode.TEXTUAL })
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
              Text('正在获取详细信息...')
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
            Text('正在加载镜像信息...')
              .fontSize(12)
              .margin({ left: 8 })
          }
          .padding(16)
        }

        // 说明文字
        Text('提示：虚拟大小是镜像的最大容量，实际占用是当前磁盘使用量。QCOW2 格式支持动态分配空间。')
          .fontSize(11)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .margin({ top: 16 })
          .width('100%')

        // ================== 快照管理区域 ==================
        Column() {
          // 标题行
          Row() {
            Text('快照管理')
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
              Text('加载快照中...')
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
            Text('暂无快照')
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
                
                Text('全选')
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
                  Button('恢复', { buttonStyle: ButtonStyleMode.TEXTUAL, controlSize: ControlSize.SMALL })
                    .fontSize(10)
                    .onClick(() => this.applySnapshot(snapshot.name))
                    .enabled(!this.isVmRunning && !this.needRestart && !this.globalTaskRunning)
                  
                  // 删除按钮
                  Button('删除', { buttonStyle: ButtonStyleMode.TEXTUAL, controlSize: ControlSize.SMALL })
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
            Button('创建快照')
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

            Button(`批量删除 (${this.selectedSnapshots.size})`)
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
              Text('虚拟机正在运行，快照操作需要先关闭虚拟机')
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
  buildDetailRow(label: string, value: string) {
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
        placeholder: '请输入快照名称',
        text: $$this.snapshotNameInput
      })
        .width('100%')
        .height(40)
        .margin({ bottom: 8 })
      
      Text('快照名称不能与现有快照重复')
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
          this.buildDetailRow('文件格式', this.detailInfo.fileFormat)
          Divider().color($r('sys.color.ohos_id_color_list_separator'))

          // 虚拟大小
          this.buildDetailRow('虚拟大小', this.formatSize(this.detailInfo.virtualSize))
          Divider().color($r('sys.color.ohos_id_color_list_separator'))

          // 实际占用
          this.buildDetailRow('实际占用', this.formatSize(this.detailInfo.diskSize))
          Divider().color($r('sys.color.ohos_id_color_list_separator'))

          // 簇大小
          if (this.detailInfo.clusterSize) {
            this.buildDetailRow('簇大小', this.formatSize(this.detailInfo.clusterSize))
            Divider().color($r('sys.color.ohos_id_color_list_separator'))
          }

          // 兼容版本
          if (this.detailInfo.compat) {
            this.buildDetailRow('兼容版本', this.detailInfo.compat)
            Divider().color($r('sys.color.ohos_id_color_list_separator'))
          }

          // Lazy Refcounts
          if (this.detailInfo.lazyRefcounts !== undefined) {
            this.buildDetailRow('延迟引用计数', this.detailInfo.lazyRefcounts ? '启用' : '禁用')
            Divider().color($r('sys.color.ohos_id_color_list_separator'))
          }

          // Extended L2
          if (this.detailInfo.extendedL2 !== undefined) {
            this.buildDetailRow('扩展L2表', this.detailInfo.extendedL2 ? '启用' : '禁用')
            Divider().color($r('sys.color.ohos_id_color_list_separator'))
          }

          // Refcount Bits
          if (this.detailInfo.refcountBits) {
            this.buildDetailRow('引用计数位数', this.detailInfo.refcountBits.toString())
            Divider().color($r('sys.color.ohos_id_color_list_separator'))
          }

          // 镜像状态
          if (this.detailInfo.corrupt !== undefined) {
            this.buildDetailRow('镜像状态', this.detailInfo.corrupt ? '已损坏' : '正常')
          }
        }
        .width('100%')
        .padding(16)
      }
      .width('100%')
      .constraintSize({ maxHeight: 400 })
    } else {
      Text('无详细信息')
        .fontSize(12)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .padding(16)
    }
  }

}
