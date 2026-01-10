import { CustomContentDialog, LoadingDialog } from '@kit.ArkUI'
import appOption from '../model/appOption'
import QemuAgent from '../lib/QemuAgent'
import { QemuAgentManager, AgentPriority } from '../lib/QemuAgentManager'
import QmpClient from '../lib/QmpClient'
import { getQmpEventListener } from '../lib/QmpEventListener'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { startVm } from '../lib/startVm'
import { VmController } from '../lib/VmController'
import { Emulator, PortMapping, DataDisk } from '../model/Emulator'
import napi from 'libentry.so'
import preference from '@ohos.data.preferences'

const DOMAIN = 0x0000

/**
 * 获取一个未被占用的随机端口 (用于 VNC WebSocket)
 */
function getFreeVncPort(min: number, max: number): number | undefined {
  const range = max - min + 1;
  for (let i = 0; i < 100; i++) {
    const port = min + Math.floor(Math.random() * range);
    if (!napi.checkPortUsed(port)) {
      return port;
    }
  }
  return undefined;
}

/**
 * 电源管理组件
 * 提供关机、重启、暂停虚拟机的功能
 */
@Component
export default struct PowerManagementContent {
  @State isConnecting: boolean = false
  @State isConnected: boolean = false
  @State isOperating: boolean = false  // 防止连续点击
  @State statusMessage: string = ''
  @StorageProp(appOption.currentEmulatorStatus) currentEmulatorStatus: string = ''
  private qgaAgent: QemuAgent | null = null
  @State processingMessage: string = ''
  private processingDialog: CustomDialogController = new CustomDialogController({
    builder: LoadingDialog({
      content: this.processingMessage
    }),
    autoCancel: false,
    alignment: DialogAlignment.Center
  })
  private isComponentActive: boolean = false  // [2.2] 生命周期标志
  private autoReconnectTimer: number = -1

  aboutToAppear() {
    AppStorage.setOrCreate(appOption.isPowerManagementOpen, true)
    this.isComponentActive = true
    this.connectToQGA()

    // 启动自动重连定时器 (每 5 秒检查一次)
    this.autoReconnectTimer = setInterval(() => {
      // 只有在组件活跃、VM 应该运行、未连接且未在进行敏感操作时才尝试重连
      if (this.isComponentActive && !this.isConnecting && !this.isConnected && !this.isOperating) {
        if (this.currentEmulatorStatus === 'RUNNING' || this.currentEmulatorStatus === 'ABNORMAL') {
           hilog.info(DOMAIN, 'PowerManagement', '自动重连定时器触发')
           this.connectToQGA(1, 0) // 尝试一次，无延迟
        } else if (this.currentEmulatorStatus === '') {
           // 状态丢失恢复机制
           this.connectToQGA(1, 0)
        }
      }
    }, 5000)
  }

  aboutToDisappear() {
    if (this.autoReconnectTimer !== -1) {
      clearInterval(this.autoReconnectTimer)
      this.autoReconnectTimer = -1
    }
    AppStorage.setOrCreate(appOption.isPowerManagementOpen, false)
    this.isComponentActive = false  // 标记组件已销毁
    this.isConnecting = false       // 重置连接状态
    this.isConnected = false        // 重置连接状态
    this.isOperating = false        // 重置操作状态
    // 释放连接管理器中的连接
    QemuAgentManager.release('PowerManagement')
    this.qgaAgent = null
  }

  /**
   * 连接到 Guest Agent，支持重试
   * @param maxRetries 最大重试次数，默认 5 次
   * @param retryDelay 重试间隔（毫秒），默认 3000
   */
  async connectToQGA(maxRetries: number = 5, retryDelay: number = 3000) {
    // 如果已关机或暂停，不尝试连接
    if (this.currentEmulatorStatus === 'SHUTDOWN') {
      this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_shutdown').id)
      this.isConnected = false
      this.isConnecting = false
      return
    }

    // 状态恢复：如果状态为空，但在运行，则恢复为 RUNNING
    if (this.currentEmulatorStatus === '') {
       // 检查 PID 文件
       const vmBaseDir = AppStorage.get(appOption.vmBaseDir) as string
       const pidFile = vmBaseDir + '/qemu.pid'
       if (napi.checkQemuAlive(pidFile)) {
         hilog.info(DOMAIN, 'PowerManagement', '检测到 VM 进程存活，恢复状态为 RUNNING')
         AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'RUNNING')
         // 继续连接
       } else {
         this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_shutdown').id)
         this.isConnected = false
         this.isConnecting = false
         return
       }
    }
    if (this.currentEmulatorStatus === 'PAUSED') {
      this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_paused').id)
      this.isConnected = false
      this.isConnecting = false
      return
    }

    // 防止重复连接
    if (this.isConnecting) {
      return
    }

    this.isConnecting = true
    this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_connecting').id)
    
    // 重试循环
    for (let attempt = 0; attempt <= maxRetries; attempt++) {
      // 检查组件是否仍然活跃
      if (!this.isComponentActive) {
        hilog.info(DOMAIN, 'PowerManagement', '组件已销毁，取消连接')
        this.isConnecting = false
        return
      }
      
      // 检查状态是否变化（允许 ABNORMAL 状态尝试连接以便恢复）
      if (this.currentEmulatorStatus !== 'RUNNING' && 
          this.currentEmulatorStatus !== 'REBOOTING' &&
          this.currentEmulatorStatus !== 'ABNORMAL') {
        this.isConnecting = false
        return
      }
      
      if (attempt > 0) {
        this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_retrying').id, attempt, maxRetries)
        // 重试前等待
        await new Promise<void>((resolve: () => void) => setTimeout(resolve, retryDelay))
        
        // 等待后再次检查
        if (!this.isComponentActive) {
          this.isConnecting = false
          return
        }
      }
      
      try {
        // 使用连接管理器获取连接（高优先级）
        this.qgaAgent = await QemuAgentManager.acquire('PowerManagement', AgentPriority.HIGH)
        
        if (this.qgaAgent) {
          // 测试 ping
          const pingResult = await this.qgaAgent.ping()
          if (pingResult) {
            this.isConnected = true
            this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_connected').id)
            this.isConnecting = false
            
            // 如果当前状态是异常或重启中，连接成功后自动恢复为 RUNNING
            const currentStatus = AppStorage.get(appOption.currentEmulatorStatus) as string
            if (currentStatus === 'ABNORMAL' || currentStatus === 'REBOOTING') {
              AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'RUNNING')
              hilog.info(DOMAIN, 'PowerManagement', '状态已从 %{public}s 恢复为 RUNNING', currentStatus)
            }
            
            return  // 成功，退出
          }
        }
        
        hilog.warn(DOMAIN, 'PowerManagement', 'Agent 连接尝试 %{public}d 失败', attempt + 1)
        // 释放连接以备重试
        await QemuAgentManager.release('PowerManagement')
        this.qgaAgent = null
      } catch (e) {
        hilog.error(DOMAIN, 'PowerManagement', '连接 QGA 失败: %{public}s', JSON.stringify(e))
        await QemuAgentManager.release('PowerManagement')
        this.qgaAgent = null
      }
    }
    
    // 所有重试都失败
    this.isConnected = false
    this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_connect_failed_final').id)
    this.isConnecting = false
  }

  /**
   * 执行全局重置
   * 重置 QGA/QMP 连接，清空队列，并等待状态恢复
   */
  async performGlobalReset() {
    if (this.isOperating) return
    this.isOperating = true
    
    this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_resetting_connections').id)
    this.processingMessage = this.statusMessage
    this.processingDialog.open()
    
    try {
      // 1. 重置 QGA 管理器 (清空队列，断开连接，恢复状态)
      await QemuAgentManager.reset()
      
      // 2. 重置 QMP 监听器
      const qmpListener = getQmpEventListener()
      if (qmpListener) {
        await qmpListener.reset()
      }
      
      // 3. 等待一小段时间让底层释放资源
      await new Promise<void>((resolve: () => void) => setTimeout(resolve, 1000))
      
      // 4. 尝试重新连接 QGA (带重试)
      // 注意：QemuAgentManager.reset() 内部已经尝试恢复了 RUNNING 状态(如果进程存活)
      // 这里调用 connectToQGA 会根据恢复后的状态决定是否连接
      await this.connectToQGA(5, 2000)
      
      if (this.isConnected) {
        this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_reset_connections_success').id)
      }
      
    } catch (e) {
      hilog.error(DOMAIN, 'PowerManagement', '全局重置失败: %{public}s', JSON.stringify(e))
      this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_reset_failed').id, JSON.stringify(e))
    } finally {
      this.isOperating = false
      this.processingDialog.close()
    }
  }

  async performAction(action: string, actionFn: () => Promise<boolean>) {
    if (!this.qgaAgent || !this.isConnected) {
      this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_not_connected').id)
      return
    }

    this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_executing').id, action)
    try {
      const result = await actionFn()
      this.statusMessage = result ? getContext(this).resourceManager.getStringSync($r('app.string.pm_status_command_sent').id, action) : getContext(this).resourceManager.getStringSync($r('app.string.pm_status_action_failed').id, action)
    } catch (e) {
      this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_action_failed_detail').id, action, JSON.stringify(e))
      hilog.error(DOMAIN, 'PowerManagement', '%{public}s失败: %{public}s', action, JSON.stringify(e))
    }
  }

  private async connectToQmp(): Promise<QmpClient | null> {
    const appTempDir = AppStorage.get(appOption.appTempDir) as string
    const uiSocket = appTempDir + '/qmp_socket'  // Use Monitor Socket instead of UI Event Socket
    
    // 快速重试 3 次，间隔 500ms
    for (let attempt = 0; attempt < 3; attempt++) {
      const client = new QmpClient(uiSocket)
      try {
        const connected = await client.connect()
        if (connected) {
          return client
        }
        await client.disconnect()
      } catch (e) {
        await client.disconnect()
      }
      
      // 短暂等待后重试
      if (attempt < 2) {
        await new Promise<void>((resolve: () => void) => setTimeout(resolve, 500))
      }
    }
    
    hilog.error(DOMAIN, 'PowerManagement', 'QMP 连接失败（已重试 3 次）')
    return null
  }

  async performResume() {
    if (this.isOperating) return
    this.isOperating = true
    this.statusMessage = this.getUIContext().getHostContext()!!.resourceManager.getStringSync($r('app.string.pm_status_resuming').id)
    this.processingMessage = this.statusMessage
    this.processingDialog.open()

    try {
      // 使用 VmController 统一的恢复逻辑
      await VmController.getInstance().resumeVM()
      
      this.statusMessage = this.getUIContext().getHostContext()!!.resourceManager.getStringSync($r('app.string.pm_status_resumed').id)
      // 2. 尝试连接 Agent
      this.connectToQGA()

    } catch (e) {
      const errorMsg = (e as Error).message || JSON.stringify(e);
      this.statusMessage = this.getUIContext().getHostContext()!!.resourceManager.getStringSync($r('app.string.pm_status_resume_failed_cmd').id) + `: ${errorMsg}`
      hilog.error(DOMAIN, 'PowerManagement', '恢复失败: %{public}s', errorMsg)
    } finally {
      this.isOperating = false
      this.processingDialog.close()
    }
  }
  async performPause() {
    if (this.isOperating) return
    this.isOperating = true
    this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_pausing').id)
    this.processingMessage = this.statusMessage
    this.processingMessage = this.statusMessage
    this.processingDialog.open()
    
    let qmpClient: QmpClient | null = null

    try {
      // 1. 断开 Agent (必须彻底释放，否则 Resume 时会获取到断开的实例)
      this.isConnected = false
      await QemuAgentManager.release('PowerManagement')
      this.qgaAgent = null
      
      qmpClient = await this.connectToQmp()
      
      if (qmpClient) {
        // 2. 发送 stop 命令
        await qmpClient.stop()
        
        // 3. 更新状态
        AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'PAUSED')
        this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_paused').id)
      } else {
        this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_pause_failed').id)
      }
    } catch (e) {
      this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_pause_failed').id)
      hilog.error(DOMAIN, 'PowerManagement', '暂停失败: %{public}s', JSON.stringify(e))
    } finally {
      this.isOperating = false
      this.processingDialog.close()
      if (qmpClient) {
        try { await qmpClient.disconnect() } catch (e) {}
      }
    }
  }

  async performShutdown() {
    if (this.isOperating) return  // [4.1] 添加操作锁
    this.isOperating = true
    this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_shutting_down').id)
    
    try {
      // 优先尝试执行 poweroff 命令（最兼容）
      if (this.qgaAgent && this.isConnected) {
        try {
          this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_exec_poweroff').id)
          
          // 广播关机消息
          await this.qgaAgent.exec('wall', ['System is shutting down by HiSH Manager...'])
          
          const pid = await this.qgaAgent.exec('/sbin/poweroff', [])
          if (pid !== null) {
            this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_shutdown').id)
            this.isConnected = false
            
            // 显式保存 Last ID
            const currentRunning = AppStorage.get(appOption.currentRunningEmulator) as string;
            if (currentRunning) {
               AppStorage.setOrCreate('lastRunningEmulatorId', currentRunning);
            }
            // 移除过早的状态设置，等待 QMP SHUTDOWN 事件
            // AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'SHUTDOWN')
            
            // 正确释放 Agent
            await QemuAgentManager.release('PowerManagement')
            this.qgaAgent = null
            return
          }
        } catch (e) {
          hilog.warn(DOMAIN, 'PowerManagement', 'poweroff 命令失败: %{public}s', JSON.stringify(e))
        }
        
        // Fallback: 尝试 guest-shutdown
        try {
          this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_try_guest_shutdown').id)
          const result = await this.qgaAgent!.shutdown()
          if (result) {
            this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_shutdown').id)
            this.isConnected = false
            
            // 显式保存 Last ID
            const currentRunning = AppStorage.get(appOption.currentRunningEmulator) as string;
            if (currentRunning) {
               AppStorage.setOrCreate('lastRunningEmulatorId', currentRunning);
            }
            // 移除过早的状态设置，等待 QMP SHUTDOWN 事件
            // AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'SHUTDOWN')
            
            // 正确释放 Agent
            await QemuAgentManager.release('PowerManagement')
            this.qgaAgent = null
            return
          }
        } catch (e) {
          hilog.warn(DOMAIN, 'PowerManagement', 'guest-shutdown 失败: %{public}s', JSON.stringify(e))
        }
      }
      
      // Fallback: 尝试 ACPI 关机
      this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_try_acpi').id)
      const qmpClient = await this.connectToQmp()
      if (qmpClient) {
        try {
          await qmpClient.sendCommand('system_powerdown')
          this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_shutdown').id)
          
           // 显式保存 Last ID
           const currentRunning = AppStorage.get(appOption.currentRunningEmulator) as string;
           if (currentRunning) {
              AppStorage.setOrCreate('lastRunningEmulatorId', currentRunning);
           }
           // 移除过早的状态设置，等待 QMP SHUTDOWN 事件
           // AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'SHUTDOWN')
        } finally {
          await qmpClient.disconnect()
        }
      } else {
        this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_shutdown_failed_qmp').id)
      }
    } catch (e) {
      hilog.error(DOMAIN, 'PowerManagement', 'ACPI 关机失败: %{public}s', JSON.stringify(e))
      this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_shutdown_failed').id, JSON.stringify(e))
    } finally {
      this.isOperating = false
    }
  }

  async performReboot() {
    if (this.isOperating) return  // [4.2] 添加操作锁
    this.isOperating = true
    
    // 如果没有连接 QGA，尝试 QMP
    if (!this.qgaAgent || !this.isConnected) {
       hilog.warn(DOMAIN, 'PowerManagement', 'QGA 未连接，尝试 QMP system_reset')
       // Fallback to QMP logic below (or implement direct QMP system_reset here)
       // Since QMP logic is not shared easily, we can just try QMP fallback directly
    }

    this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_rebooting').id)
    
    let rebootSuccess = false
    
    // 1. 尝试 QGA
    if (this.qgaAgent && this.isConnected) {
        try {
          // reboot command
          this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_exec_reboot').id)
          const pid = await this.qgaAgent.exec('/sbin/reboot', [])
          if (pid !== null) rebootSuccess = true
        } catch (e) {
          hilog.warn(DOMAIN, 'PowerManagement', 'reboot 命令失败: %{public}s', JSON.stringify(e))
        }
        
        if (!rebootSuccess) {
            try {
              const result = await this.qgaAgent.reboot()
              if (result) rebootSuccess = true
            } catch(e) {}
        }
    }
    
    // 2. Fallback: QMP system_reset
    if (!rebootSuccess) {
         this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_try_acpi').id) // Use Generic message or add specific
         const qmpClient = await this.connectToQmp()
         if (qmpClient) {
            try {
               await qmpClient.sendCommand('system_reset')
               rebootSuccess = true
            } catch (e) {
               hilog.error(DOMAIN, 'PowerManagement', 'QMP system_reset 失败: %{public}s', JSON.stringify(e))
            } finally {
               await qmpClient.disconnect()
            }
         }
    }
      
    if (rebootSuccess) {
        this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_reboot_sent').id)
        this.isConnected = false
        AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'REBOOTING')
        if (this.qgaAgent) await this.qgaAgent.disconnect()
        
        // 延迟连接
        setTimeout((): void => { 
        setTimeout((): void => { 
          if (this.isComponentActive) this.connectToQGA(5, 2000) 
        }, 10000) // 重启稍微久一点
        }, 10000) // 重启稍微久一点
    } else {
        this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_reboot_failed').id)
    }
    
    this.isOperating = false
  }

  /**
   * 状态验证定时器
   * 在指定时间后验证虚拟机状态，确保 UI 状态与实际状态一致
   * @param timeout 超时时间（毫秒）
   */
  private scheduleStatusVerification(timeout: number) {
    setTimeout(async (): Promise<void> => {
      const currentStatus = AppStorage.get(appOption.currentEmulatorStatus) as string
      
      // 只在状态仍为 REBOOTING 时进行验证
      if (currentStatus !== 'REBOOTING') {
        return
      }
      
      hilog.info(DOMAIN, 'PowerManagement', '开始验证虚拟机状态...')
      
      // 尝试连接 Agent 验证实际状态
      const verified = await this.verifyVmStatus()
      
      if (verified) {
        hilog.info(DOMAIN, 'PowerManagement', '验证成功，状态更新为 RUNNING')
        AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'RUNNING')
      } else {
        hilog.warn(DOMAIN, 'PowerManagement', '验证失败，状态更新为 ABNORMAL')
        AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'ABNORMAL')
      }
      
      // 如果组件仍活跃，尝试重连
      if (this.isComponentActive) {
        this.connectToQGA(3, 2000)
      }
    }, timeout)
  }

  /**
   * 验证虚拟机状态
   * 尝试通过 Agent ping 验证虚拟机是否正常运行
   * @returns true 表示虚拟机正常运行，false 表示无法验证
   */
  private async verifyVmStatus(): Promise<boolean> {
    try {
      const agent = await QemuAgentManager.acquire('PowerManagement', AgentPriority.HIGH, 5000)
      if (agent) {
        const ping = await agent.ping()
        await QemuAgentManager.release('PowerManagement')
        return ping
      }
    } catch (e) {
      hilog.error(DOMAIN, 'PowerManagement', '验证虚拟机状态失败: %{public}s', JSON.stringify(e))
    }
    return false
  }

  async performHardReset() {
    if (this.isOperating) return
    this.isOperating = true
    this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_resetting').id)
    
    // 设置重置标志
    AppStorage.setOrCreate(appOption.isVmSwitching, true)
    
    // 1. 断开 Agent
    this.isConnected = false
    if (this.qgaAgent) {
      try { await this.qgaAgent.disconnect() } catch (e) {}
      this.qgaAgent = null
    }
    
    try {
      // 2. 断电 (优先 QMP, 备选强制杀进程)
      this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_powering_off').id)
      const vmBaseDir = AppStorage.get(appOption.vmBaseDir) as string
      const pidFile = vmBaseDir + '/qemu.pid'
      
      const qmpClient = await this.connectToQmp()
      if (qmpClient) {
        try {
          await qmpClient.quit()
        } finally {
          await qmpClient.disconnect()
        }
        hilog.info(DOMAIN, 'PowerManagement', 'QMP quit 命令已发送')
      } else {
        hilog.warn(DOMAIN, 'PowerManagement', 'QMP 连接失败，尝试强制杀进程')
        napi.killQemuProcess(pidFile)
      }
      
      // 3. 轮询等待进程退出 (最多 30 秒)
      const startTime = Date.now()
      const timeout = 30000
      
      while (Date.now() - startTime < timeout) {
        if (!napi.checkQemuAlive(pidFile)) {
          break
        }
        await new Promise<void>((resolve: () => void) => setTimeout(resolve, 500))
      }
      
      if (napi.checkQemuAlive(pidFile)) {
        throw new Error('虚拟机进程未能在超时时间内退出')
      }
      
      // 4. 重新开机
      this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_powering_on').id)
      const appTempDir = AppStorage.get(appOption.appTempDir) as string
      const kernelFile = AppStorage.get(appOption.kernel) as string
      const sharedFolder = AppStorage.get(appOption.sharedHost) as string
      const emulators = AppStorage.get(appOption.emulators) as Emulator[]
      const currentEmulatorId = AppStorage.get(appOption.currentRunningEmulator) as string
      const emulator = emulators.find((e: Emulator) => e.id === currentEmulatorId)
      
      if (!emulator) {
        this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_reset_failed_no_config').id)
        return
      }
      
      // 读取 VNC 启用配置
      const appContext = this.getUIContext().getHostContext()!!.getApplicationContext();
      const appPref: preference.Preferences = await preference.getPreferences(appContext, appOption.preferenceName);
      const vncEnabledPref = await appPref.get(appOption.vncEnabled, true);
      const vncEnabled = typeof vncEnabledPref === 'boolean' ? vncEnabledPref : true;
      
      // 获取 VNC 端口
      const vncPort = vncEnabled ? getFreeVncPort(60000, 65000) : undefined;
      if (vncPort) {
        AppStorage.setOrCreate('vncWebSocketPort', vncPort);
      }

      // 获取数据盘路径（如果开启了挂载）
      let dataDiskPath: string | undefined = undefined;
      if (emulator.dataDiskId && emulator.mountDataDisk) {
        const dataDisks = (AppStorage.get(appOption.dataDisks) as DataDisk[]) || [];
        const selectedDisk = dataDisks.find(d => d.id === emulator.dataDiskId);
        if (selectedDisk) {
          dataDiskPath = selectedDisk.path;
        }
      }

      startVm({
        baseDir: vmBaseDir,
        cpu: emulator.cpu,
        memory: emulator.memory,
        portMapping: emulator.portMapping.filter((pm: PortMapping) => pm.host),
        kernel: kernelFile,
        rootVda: emulator.rootVda,
        rootFilesystem: emulator.rootFilesystem,
        sharedFolder: sharedFolder,
        serialUnixSocket: appTempDir + '/serial_socket',
        sharedFolderReadonly: emulator.sharedFolderReadonly,
        init: emulator.init,
        qmpUnixSocket: appTempDir + '/qmp_socket',
        qmpUnixSocketUI: appTempDir + '/qmp_socket_ui',
        qgaUnixSocket: appTempDir + '/qga_socket',
        vncWebSocketPort: vncPort,
        dataDiskPath: dataDiskPath
      })
      
      this.statusMessage = this.getUIContext().getHostContext()!!.resourceManager.getStringSync($r('app.string.pm_status_running').id)
      AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'RUNNING')
      // 延迟后连接 Agent
      setTimeout((): void => { 
        if (this.isComponentActive) this.connectToQGA(5, 2000) 
      }, 3000)
    } catch (e) {
      this.statusMessage = this.getUIContext().getHostContext()!!.resourceManager.getStringSync($r('app.string.pm_status_reset_failed').id, JSON.stringify(e))
      hilog.error(DOMAIN, 'PowerManagement', '重置失败: %{public}s', JSON.stringify(e))
    } finally {
      this.isOperating = false
      // 延迟重置 VM 切换标志
      setTimeout(() => {
        AppStorage.setOrCreate(appOption.isVmSwitching, false)
      }, 1500)
    }
  }

  async performForceShutdown() {
    if (this.isOperating) return
    this.isOperating = true
    this.statusMessage = this.getUIContext().getHostContext()!!.resourceManager.getStringSync($r('app.string.pm_status_force_shutdown').id)
    this.isConnected = false
    
    if (this.qgaAgent) {
      try { await this.qgaAgent.disconnect() } catch (e) {}
      this.qgaAgent = null
    }
    
    try {
      const qmpClient = await this.connectToQmp()
      if (qmpClient) {
        try {
          await qmpClient.quit()
        } catch (e) {}
        try { await qmpClient.disconnect() } catch (e) {}
      }
    } catch (e) {}
    
    AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'SHUTDOWN')
    this.statusMessage = this.getUIContext().getHostContext()!!.resourceManager.getStringSync($r('app.string.pm_status_shutdown').id)
    this.isOperating = false
  }

  async performPowerOn() {
    if (this.isOperating) return  // 添加操作锁
    this.isOperating = true
    
    // 设置 VM 切换标志
    AppStorage.setOrCreate(appOption.isVmSwitching, true)
    
    this.statusMessage = this.getUIContext().getHostContext()!!.resourceManager.getStringSync($r('app.string.pm_status_starting').id)
    try {
      const appTempDir = AppStorage.get(appOption.appTempDir) as string
      const vmBaseDir = AppStorage.get(appOption.vmBaseDir) as string
      const kernelFile = AppStorage.get(appOption.kernel) as string
      const sharedFolder = AppStorage.get(appOption.sharedHost) as string
      const emulators = AppStorage.get(appOption.emulators) as Emulator[]
      let currentEmulatorId = AppStorage.get(appOption.currentRunningEmulator) as string
      
      // 如果 currentRunningEmulator 为空，使用 defaultStartEmulator 作为备选
      if (!currentEmulatorId) {
        currentEmulatorId = AppStorage.get(appOption.defaultStartEmulator) as string
        hilog.info(DOMAIN, 'PowerManagement', '使用默认模拟器: %{public}s', currentEmulatorId)
      }
      
      const emulator = emulators.find((e: Emulator) => e.id === currentEmulatorId)
      
      if (!emulator) {
        this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_poweron_failed_no_config').id)
        return
      }
      
      // 更新 currentRunningEmulator
      AppStorage.setOrCreate(appOption.currentRunningEmulator, emulator.id)
      
      // 读取 VNC 启用配置
      const appContext = getContext(this).getApplicationContext();
      const appPref: preference.Preferences = await preference.getPreferences(appContext, appOption.preferenceName);
      const vncEnabledPref = await appPref.get(appOption.vncEnabled, true);
      const vncEnabled = typeof vncEnabledPref === 'boolean' ? vncEnabledPref : true;
      
      // 获取 VNC 端口
      const vncPort = vncEnabled ? getFreeVncPort(60000, 65000) : undefined;
      if (vncPort) {
        AppStorage.setOrCreate('vncWebSocketPort', vncPort);
      }

      // 使用 VmController 启动虚拟机 (确保状态同步和事件监听)
      await VmController.getInstance().startVM(emulator, this.getUIContext());
      
      this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_running').id)
      // VmController 会设置 currentEmulatorStatus 为 RUNNING

      // 使用强制重连
      setTimeout((): void => { 
        if (this.isComponentActive) this.connectToQGA(5, 2000) 
      }, 3000)
    } catch (e) {
      this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_poweron_failed').id, JSON.stringify(e))
      hilog.error(DOMAIN, 'PowerManagement', '开机失败: %{public}s', JSON.stringify(e))
    } finally {
      this.isOperating = false
      // 延迟释放 switch 标志
      setTimeout(() => {
        AppStorage.setOrCreate(appOption.isVmSwitching, false)
      }, 1500)
    }
  }

  build() {
    Scroll() {
      Column() {
        // 状态显示
        Row() {
          Text($r('app.string.pm_label_ga_status'))
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
          Blank()
          if (this.isConnecting) {
            LoadingProgress()
              .width(12)
              .height(12)
              .margin({ right: 8 })
          }
          Text(this.statusMessage)
            .fontSize(10)
            .fontColor(this.isConnected ? '#00AA00' : '#AA0000')
        }
        .width('100%')
        .padding(12)
        .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
        .borderRadius(8)
        .margin({ bottom: 12 })

        // 强制重连按钮（只要 VM 未关机就显示，总是可用以便打断）
        if (this.currentEmulatorStatus !== 'SHUTDOWN' && this.currentEmulatorStatus !== '') {
          Button($r('app.string.pm_btn_force_reconnect'))
            .width('100%')
            .margin({ bottom: 16 })
            .enabled(!this.isOperating) // 操作中禁用
            .onClick(() => {
              this.performGlobalReset()
            })
        }

        // 电源管理按钮
        Text($r('app.string.pm_title'))
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .margin({ bottom: 8 })
          .alignSelf(ItemAlign.Start)

        Column({ space: 8 }) {
          // 强制断电按钮
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            Row({ space: 4 }) {
              SymbolGlyph($r('sys.symbol.bolt_fill'))
                .fontSize(16)
                .fontColor(['#FFFFFF'])
              Text($r('app.string.pm_btn_force_shutdown'))
                .fontSize(14)
                .fontColor('#FFFFFF')
            }
          }
          .width('100%')
          .height(36)
          .backgroundColor('#8B0000')
          .borderRadius(8)
          .enabled(!this.isOperating && this.currentEmulatorStatus !== 'SHUTDOWN' && this.currentEmulatorStatus !== '')
          .onClick(() => this.performForceShutdown())

          // 强制重置按钮
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            Row({ space: 4 }) {
              SymbolGlyph($r('sys.symbol.arrow_counterclockwise'))
                .fontSize(16)
                .fontColor(['#FFFFFF'])
              Text($r('app.string.pm_btn_reset'))
                .fontSize(14)
                .fontColor('#FFFFFF')
            }
          }
          .width('100%')
          .height(36)
          .backgroundColor('#C0392B')
          .borderRadius(8)
          .enabled(!this.isOperating && (this.currentEmulatorStatus === 'RUNNING' || this.currentEmulatorStatus === 'PAUSED' || this.currentEmulatorStatus === 'ABNORMAL' || this.currentEmulatorStatus === 'REBOOTING'))
          .onClick(() => this.performHardReset())

          // 关机按钮
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            Row({ space: 4 }) {
              SymbolGlyph($r('sys.symbol.power'))
                .fontSize(16)
                .fontColor(['#FFFFFF'])
              Text($r('app.string.pm_btn_shutdown'))
                .fontSize(14)
                .fontColor('#FFFFFF')
            }
          }
          .width('100%')
          .height(36)
          .backgroundColor('#E74C3C')
          .borderRadius(8)
          .enabled(!this.isOperating && this.isConnected && !this.isConnecting)
          .onClick(() => this.performShutdown())

          // 重启按钮
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            Row({ space: 4 }) {
              SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                .fontSize(16)
                .fontColor(['#FFFFFF'])
              Text($r('app.string.pm_btn_reboot'))
                .fontSize(14)
                .fontColor('#FFFFFF')
            }
          }
          .width('100%')
          .height(36)
          .backgroundColor('#F39C12')
          .borderRadius(8)
          .enabled(!this.isOperating && this.isConnected && !this.isConnecting)
          .onClick(() => this.performReboot())

          // 暂停按钮
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            Row({ space: 4 }) {
              SymbolGlyph($r('sys.symbol.pause'))
                .fontSize(16)
                .fontColor(['#FFFFFF'])
              Text($r('app.string.pm_btn_pause'))
                .fontSize(14)
                .fontColor('#FFFFFF')
            }
          }
          .width('100%')
          .height(36)
          .backgroundColor('#3498DB')
          .borderRadius(8)
          .enabled(!this.isOperating && this.currentEmulatorStatus === 'RUNNING' && !this.isConnecting)
          .onClick(() => this.performPause())

          // 恢复按钮
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            Row({ space: 4 }) {
              SymbolGlyph($r('sys.symbol.play'))
                .fontSize(16)
                .fontColor(['#FFFFFF'])
              Text($r('app.string.pm_btn_resume'))
                .fontSize(14)
                .fontColor('#FFFFFF')
            }
          }
          .width('100%')
          .height(36)
          .backgroundColor('#2ECC71')
          .borderRadius(8)
          .enabled(!this.isOperating && this.currentEmulatorStatus === 'PAUSED' && !this.isConnecting)
          .onClick(() => this.performResume())

          // 开机按钮
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            Row({ space: 4 }) {
              SymbolGlyph($r('sys.symbol.power'))
                .fontSize(16)
                .fontColor(['#FFFFFF'])
              Text($r('app.string.pm_btn_poweron'))
                .fontSize(14)
                .fontColor('#FFFFFF')
            }
          }
          .width('100%')
          .height(36)
          .backgroundColor('#27AE60')
          .borderRadius(8)
          .enabled((this.currentEmulatorStatus === 'SHUTDOWN' || this.currentEmulatorStatus === '') && !this.isConnecting)
          .onClick(() => this.performPowerOn())
        }
        .width('100%')

        // 说明文字
        Text($r('app.string.pm_note_qga'))
          .fontSize(12)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .margin({ top: 24 })
          .width('100%')
      }
      .width('100%')
      .padding(16)
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Auto)
  }
}
