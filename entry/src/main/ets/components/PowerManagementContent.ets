import { CustomContentDialog } from '@kit.ArkUI'
import appOption from '../model/appOption'
import QemuAgent from '../lib/QemuAgent'
import { QemuAgentManager, AgentPriority } from '../lib/QemuAgentManager'
import QmpClient from '../lib/QmpClient'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { startVm } from '../lib/startVm'
import { Emulator, PortMapping } from '../model/Emulator'
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
  private isComponentActive: boolean = false  // [2.2] 生命周期标志

  aboutToAppear() {
    AppStorage.setOrCreate(appOption.isPowerManagementOpen, true)
    this.isComponentActive = true
    this.connectToQGA()
  }

  aboutToDisappear() {
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
    if (this.currentEmulatorStatus === 'SHUTDOWN' || this.currentEmulatorStatus === '') {
      this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_shutdown').id)
      this.isConnected = false
      this.isConnecting = false
      return
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
   * 强制重连 Agent
   * 清除所有历史阻塞，强制断开并重新建立干净的通信接口
   * @param silent 静默模式，不显示提示消息（用于自动重连）
   */
  async forceReconnectAgent(silent: boolean = false) {
    if (!silent) {
      this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_connecting_short').id)
    }
    
    // 1. 强制重置所有状态
    this.isConnecting = false
    this.isConnected = false
    
    // 2. 释放连接管理器中的连接
    await QemuAgentManager.release('PowerManagement')
    this.qgaAgent = null
    
    // 3. 等待一小段时间让资源释放
    await new Promise<void>((resolve: () => void) => setTimeout(resolve, 500))
    
    // 4. 重新连接（更多重试，更长等待）
    await this.connectToQGA(5, 3000)
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
    const uiSocket = appTempDir + '/qmp_socket_ui'
    
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
    this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_resuming').id)
    try {
      const qmpClient = await this.connectToQmp()
      
      if (qmpClient) {
        try {
          this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_sending_resume').id)
          const result = await qmpClient.cont()
          
          if (result) {
            this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_resumed').id)
            AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'RUNNING')
            // 使用强制重连（清除历史阻塞）
            setTimeout((): void => {
              if (this.isComponentActive) {
                this.forceReconnectAgent(true)
              }
            }, 2000)
          } else {
            this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_resume_failed_cmd').id)
          }
        } finally {
          await qmpClient.disconnect()
        }
      } else {
        this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_qmp_connect_failed').id)
      }
    } catch (e) {
      this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_resume_failed').id) + JSON.stringify(e)
      hilog.error(DOMAIN, 'PowerManagement', '恢复失败: %{public}s', JSON.stringify(e))
    } finally {
      this.isOperating = false
    }
  }

  async performPause() {
    if (this.isOperating) return
    this.isOperating = true
    this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_pausing').id)
    // 主动断开 Guest Agent
    if (this.qgaAgent) {
      try { await this.qgaAgent.disconnect() } catch (e) {}
    }
    this.isConnected = false
    this.isConnecting = false  // 确保不阻塞其他按钮

    try {
      const qmpClient = await this.connectToQmp()
      
      if (qmpClient) {
        try {
          const result = await qmpClient.stop()
          
          if (result) {
            this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_paused').id)
            AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'PAUSED')
          } else {
            this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_pause_failed').id)
          }
        } finally {
          await qmpClient.disconnect()
        }
      } else {
        this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_qmp_connect_failed').id)
      }
    } catch (e) {
      this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_pause_failed').id) + JSON.stringify(e)
      hilog.error(DOMAIN, 'PowerManagement', '暂停失败: %{public}s', JSON.stringify(e))
    } finally {
      this.isOperating = false
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
          const pid = await this.qgaAgent.exec('/sbin/poweroff', [])
          if (pid !== null) {
            this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_shutdown').id)
            this.isConnected = false
            AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'SHUTDOWN')
            await this.qgaAgent.disconnect()
            return
          }
        } catch (e) {
          hilog.warn(DOMAIN, 'PowerManagement', 'poweroff 命令失败: %{public}s', JSON.stringify(e))
        }
        
        // Fallback: 尝试 guest-shutdown
        try {
          this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_try_guest_shutdown').id)
          const result = await this.qgaAgent.shutdown()
          if (result) {
            this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_shutdown').id)
            this.isConnected = false
            AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'SHUTDOWN')
            await this.qgaAgent.disconnect()
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
          AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'SHUTDOWN')
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
    if (!this.qgaAgent || !this.isConnected) {
      this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_not_connected').id)
      this.isOperating = false
      return
    }
    this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_rebooting').id)
    try {
      // 优先尝试执行 reboot 命令（最兼容）
      let rebootSuccess = false
      try {
        this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_exec_reboot').id)
        const pid = await this.qgaAgent.exec('/sbin/reboot', [])
        if (pid !== null) {
          rebootSuccess = true
        }
      } catch (e) {
        hilog.warn(DOMAIN, 'PowerManagement', 'reboot 命令失败: %{public}s', JSON.stringify(e))
      }
      
      // Fallback: 尝试 guest-shutdown (mode: reboot)
      if (!rebootSuccess) {
        try {
          this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_try_guest_shutdown').id)
          const result = await this.qgaAgent.reboot()
          if (result) {
            rebootSuccess = true
          }
        } catch (e) {
          hilog.warn(DOMAIN, 'PowerManagement', 'guest-shutdown reboot 失败: %{public}s', JSON.stringify(e))
        }
      }
      
      if (rebootSuccess) {
        this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_reboot_sent').id)
        this.isConnected = false
        AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'REBOOTING')
        await this.qgaAgent.disconnect()
        
        // 状态验证定时器（不依赖组件生命周期）
        // 15秒后验证虚拟机状态，如果仍为 REBOOTING 则尝试验证或标记异常
        this.scheduleStatusVerification(15000)
        
        // 如果组件仍活跃，5秒后尝试重连（供 UI 使用）
        setTimeout((): void => {
          if (this.isComponentActive) {
            this.forceReconnectAgent(true)
          }
        }, 5000)
      } else {
        this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_reboot_failed').id)
      }
    } catch (e) {
      this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_reboot_failed_detail').id, JSON.stringify(e))
      hilog.error(DOMAIN, 'PowerManagement', '重启失败: %{public}s', JSON.stringify(e))
    } finally {
      this.isOperating = false
    }
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
        this.forceReconnectAgent(true)
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
    
    // 1. 断开 Agent
    this.isConnected = false
    if (this.qgaAgent) {
      try { await this.qgaAgent.disconnect() } catch (e) {}
      this.qgaAgent = null
    }
    
    try {
      // 2. 断电
      this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_powering_off').id)
      const qmpClient = await this.connectToQmp()
      if (qmpClient) {
        try {
          await qmpClient.quit()
        } finally {
          await qmpClient.disconnect()
        }
      }
      
      AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'SHUTDOWN')
      
      // 3. 等待 1 秒让资源释放
      await new Promise<void>((resolve: () => void) => setTimeout(resolve, 1000))
      
      // 4. 重新开机
      this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_powering_on').id)
      const vmBaseDir = AppStorage.get(appOption.vmBaseDir) as string
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
      const appContext = getContext(this).getApplicationContext();
      const appPref: preference.Preferences = await preference.getPreferences(appContext, appOption.preferenceName);
      const vncEnabledPref = await appPref.get(appOption.vncEnabled, true);
      const vncEnabled = typeof vncEnabledPref === 'boolean' ? vncEnabledPref : true;
      
      // 获取 VNC 端口
      const vncPort = vncEnabled ? getFreeVncPort(60000, 65000) : undefined;
      if (vncPort) {
        AppStorage.setOrCreate('vncWebSocketPort', vncPort);
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
        vncWebSocketPort: vncPort
      })
      
      this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_running').id)
      AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'RUNNING')
      // 延迟后连接 Agent
      setTimeout((): void => { 
        if (this.isComponentActive) this.forceReconnectAgent(true) 
      }, 3000)
    } catch (e) {
      this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_reset_failed').id, JSON.stringify(e))
      hilog.error(DOMAIN, 'PowerManagement', '重置失败: %{public}s', JSON.stringify(e))
    } finally {
      this.isOperating = false
    }
  }

  async performForceShutdown() {
    if (this.isOperating) return
    this.isOperating = true
    this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_force_shutdown').id)
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
    this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_shutdown').id)
    this.isOperating = false
  }

  async performPowerOn() {
    if (this.isOperating) return  // 添加操作锁
    this.isOperating = true
    this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_starting').id)
    try {
      const appTempDir = AppStorage.get(appOption.appTempDir) as string
      const vmBaseDir = AppStorage.get(appOption.vmBaseDir) as string
      const kernelFile = AppStorage.get(appOption.kernel) as string
      const sharedFolder = AppStorage.get(appOption.sharedHost) as string
      const emulators = AppStorage.get(appOption.emulators) as Emulator[]
      const currentEmulatorId = AppStorage.get(appOption.currentRunningEmulator) as string
      const emulator = emulators.find((e: Emulator) => e.id === currentEmulatorId)
      
      if (!emulator) {
        this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_poweron_failed_no_config').id)
        return
      }
      
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
        vncWebSocketPort: vncPort
      })
      
      this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_running').id)
      AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'RUNNING')
      // 使用强制重连
      setTimeout((): void => { 
        if (this.isComponentActive) this.forceReconnectAgent(true) 
      }, 3000)
    } catch (e) {
      this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_poweron_failed').id, JSON.stringify(e))
      hilog.error(DOMAIN, 'PowerManagement', '开机失败: %{public}s', JSON.stringify(e))
    } finally {
      this.isOperating = false
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

        // 强制重连按钮（只要 VM 在运行就显示）
        if (this.currentEmulatorStatus === 'RUNNING' && !this.isConnecting) {
          Button($r('app.string.pm_btn_force_reconnect'))
            .width('100%')
            .margin({ bottom: 16 })
            .onClick(() => {
              this.forceReconnectAgent()
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
