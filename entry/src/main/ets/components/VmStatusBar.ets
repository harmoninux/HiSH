import { hilog } from '@kit.PerformanceAnalysisKit'
import { CustomContentDialog } from '@kit.ArkUI'
import QemuAgent, { CpuStats } from '../lib/QemuAgent'
import { QemuAgentManager, AgentPriority } from '../lib/QemuAgentManager'
import appOption from '../model/appOption'
import { util } from '@kit.ArkTS'

const DOMAIN = 0x0000

// 虚拟机状态信息
interface VmStatus {
  agentConnected: boolean
  hostname: string
  cpuCount: number
  cpuUsage: number
  memoryTotal: number
  memoryUsage: number
  diskTotal: number
  diskUsed: number
  diskUsage: number
  swapTotal: number
  swapUsage: number
  sshRunning: boolean
}

// 文件系统信息
interface FilesystemInfo {
  mountpoint: string
  type: string
  'used-bytes'?: number
  'total-bytes'?: number
}

// 显示设置
interface DisplaySettings {
  masterSwitch: boolean
  showAgent: boolean
  showHostname: boolean
  showCpu: boolean
  showMemory: boolean
  showDisk: boolean
  showSwap: boolean
  showSsh: boolean
  refreshInterval: number
}

// 初始化持久化设置
PersistentStorage.persistProp('VmStatusBarSettings', {
  masterSwitch: false,
  showAgent: true,
  showHostname: true,
  showCpu: true,
  showMemory: true,
  showDisk: true,
  showSwap: true,
  showSsh: true,
  refreshInterval: 15000
})

// 格式化字节为可读格式
// 规则：小于1G用MB，大于等于1G用GB，GB保留2位小数
function formatBytes(bytes: number, useGB: boolean = false): string {
  if (bytes <= 0) return '-'
  const gb = bytes / (1024 * 1024 * 1024)
  const mb = bytes / (1024 * 1024)
  
  if (gb >= 1) {
    return `${gb.toFixed(2)}GB`
  } else if (mb >= 1) {
    return `${Math.round(mb)}MB`
  }
  return `${Math.round(bytes / 1024)}KB`
}

// 格式化字节为 GB，保留 2 位小数
function formatBytesToGB(bytes: number): string {
  if (bytes <= 0) return '-'
  const gb = bytes / (1024 * 1024 * 1024)
  return `${gb.toFixed(2)}GB`
}

@Component
export struct VmStatusBar {
  @StorageProp(appOption.appTempDir) appTempDir: string = ''
  @Watch('onEmulatorStatusChange') @StorageProp(appOption.currentEmulatorStatus) currentEmulatorStatus: string = ''
  @Watch('onPowerManagementChange') @StorageProp(appOption.isPowerManagementOpen) isPowerManagementOpen: boolean = false
  
  @State status: VmStatus = {
    agentConnected: false,
    hostname: '-',
    cpuCount: 0,
    cpuUsage: 0,
    memoryTotal: 0,
    memoryUsage: 0,
    diskTotal: 0,
    diskUsed: 0,
    diskUsage: 0,
    swapTotal: 0,
    swapUsage: 0,
    sshRunning: false
  }
  
  @StorageLink('VmStatusBarSettings') @Watch('onSettingsChange') settings: DisplaySettings = {
    masterSwitch: false,
    showAgent: true,
    showHostname: true,
    showCpu: true,
    showMemory: true,
    showDisk: true,
    showSwap: true,
    showSsh: true,
    refreshInterval: 15000
  }
  
  @State isRefreshing: boolean = false
  @State isForceReconnecting: boolean = false
  
  private qgaAgent: QemuAgent | null = null
  private refreshTimer: number = -1
  private isComponentActive: boolean = true
  
  private lastCpuStats: CpuStats | null = null
  
  aboutToAppear() {
    this.isComponentActive = true
    this.initAgent()
  }
  
  aboutToDisappear() {
    this.isComponentActive = false
    this.stopRefreshTimer()
    if (this.qgaAgent) {
      this.qgaAgent.disconnect()
    }
  }
  
  onSettingsChange() {
    // masterSwitch 控制显示和自动刷新
    if (this.settings.masterSwitch) {
      // 开启：重置统计状态，立即刷新一次，启动定时器
      this.lastCpuStats = null
      this.refreshStatus()
      this.startRefreshTimer()
    } else {
      // 关闭：停止定时器
      this.stopRefreshTimer()
    }
  }
  
  /**
   * 虚拟机状态变化时自动处理 Agent 连接
   * 当状态变为 RUNNING 或 REBOOTING 时，自动尝试连接 Agent
   */
  onEmulatorStatusChange() {
    hilog.info(DOMAIN, 'VmStatusBar', '虚拟机状态变化: %{public}s', this.currentEmulatorStatus)
    
    if (this.currentEmulatorStatus === 'RUNNING') {
      // 虚拟机开始运行，延迟后尝试首次连接（带重试机制）
      setTimeout((): void => {
        if (this.isComponentActive && this.currentEmulatorStatus === 'RUNNING' && !this.isPowerManagementOpen) {
          this.initialConnectWithRetry()
        }
      }, 5000)  // 统一等待 5 秒，等待 Guest Agent 服务启动
    } else if (this.currentEmulatorStatus === 'REBOOTING') {
      // 重启中状态，等待更长时间后尝试刷新
      this.status.agentConnected = false
      setTimeout((): void => {
        if (this.isComponentActive && !this.isPowerManagementOpen) {
          // 只要状态不是 SHUTDOWN/PAUSED 就尝试刷新
          const status = this.currentEmulatorStatus
          if (status === 'RUNNING' || status === 'REBOOTING' || status === 'ABNORMAL') {
            this.initialConnectWithRetry()  // 重启后也使用带重试的连接
          }
        }
      }, 8000) // 重启需要更长等待时间
    } else if (this.currentEmulatorStatus === 'ABNORMAL') {
      // 异常状态，允许刷新以便检测恢复
      this.status.agentConnected = false
      if (this.settings.masterSwitch) {
        this.startRefreshTimer()
      }
    } else {
      // 关机或暂停状态，标记 Agent 为断开
      this.status.agentConnected = false
      this.stopRefreshTimer()
    }
  }
  
  /**
   * 虚拟机启动后的首次连接（带重试机制）
   * 不受 masterSwitch 影响，确保首次连接成功
   */
  private async initialConnectWithRetry() {
    const maxAttempts = 10     // 最多 10 次
    const retryInterval = 2000 // 间隔 2 秒
    
    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
      // 检查组件状态
      if (!this.isComponentActive) return
      if (this.currentEmulatorStatus !== 'RUNNING' && this.currentEmulatorStatus !== 'REBOOTING') return
      if (this.isPowerManagementOpen) return
      
      hilog.info(DOMAIN, 'VmStatusBar', '首次连接尝试 %{public}d/%{public}d', attempt, maxAttempts)
      
      // 尝试刷新（内部会调用 acquire/ping/release）
      await this.refreshStatus()
      
      // 检查是否成功
      if (this.status.agentConnected) {
        hilog.info(DOMAIN, 'VmStatusBar', '首次连接成功，共尝试 %{public}d 次', attempt)
        break
      }
      
      // 失败，等待后重试
      if (attempt < maxAttempts) {
        await new Promise<void>((resolve: () => void) => setTimeout(resolve, retryInterval))
      }
    }
    
    // 如果开启了监控，启动定时刷新
    if (this.settings.masterSwitch) {
      this.startRefreshTimer()
    }
  }
  
  /**
   * 电源管理界面状态变化时的处理
   * 电源管理优先级最高，监控条必须让步
   */
  onPowerManagementChange() {
    if (this.isPowerManagementOpen) {
      // 电源管理打开：立即停止刷新并断开连接
      hilog.info(DOMAIN, 'VmStatusBar', '电源管理打开，监控条让步')
      this.stopRefreshTimer()
      if (this.qgaAgent) {
        this.qgaAgent.disconnect()
      }
      this.status.agentConnected = false
    } else {
      // 电源管理关闭：延迟 1 秒后恢复
      hilog.info(DOMAIN, 'VmStatusBar', '电源管理关闭，监控条恢复')
      setTimeout((): void => {
        if (this.isComponentActive && this.currentEmulatorStatus === 'RUNNING' && !this.isPowerManagementOpen) {
          this.refreshStatus()
          if (this.settings.masterSwitch) {
            this.startRefreshTimer()
          }
        }
      }, 1000)
    }
  }
  
  private async initAgent() {
    if (!this.appTempDir) return
    
    // 使用连接管理器获取连接
    this.qgaAgent = await QemuAgentManager.acquire('VmStatusBar', AgentPriority.LOW)
    
    if (this.qgaAgent) {
      // 立即获取一次数据
      await this.refreshStatus()
      
      // 释放连接供其他组件使用
      await QemuAgentManager.release('VmStatusBar')
      this.qgaAgent = null
    }
    
    // 始终启动定时刷新，保持 Agent 连接状态同步
    // 即使用户关闭了监控信息显示，也需要定期检查 Agent 状态
    this.startRefreshTimer()
  }
  
  private startRefreshTimer() {
    this.stopRefreshTimer()
    
    // 设置刷新间隔：启用监控时使用用户设置，否则使用较长的默认间隔（30秒）保持状态同步
    const interval = this.settings.masterSwitch ? this.settings.refreshInterval : 30000
    
    this.refreshTimer = setInterval((): void => {
      if (this.isComponentActive) {
        this.refreshStatus()
      }
    }, interval)
  }
  
  private stopRefreshTimer() {
    if (this.refreshTimer !== -1) {
      clearInterval(this.refreshTimer)
      this.refreshTimer = -1
    }
  }

  /**
   * 强制重连 Agent
   * 清除所有历史阻塞，强制断开并重新建立干净的通信接口
   */
  private async forceReconnectAgent() {
    // 防止重复点击
    if (this.isForceReconnecting) return
    this.isForceReconnecting = true
    
    hilog.info(DOMAIN, 'VmStatusBar', '开始强制重连 Agent...')
    
    try {
      // 1. 停止定时器，避免冲突
      this.stopRefreshTimer()
      
      // 2. 彻底销毁旧连接
      if (this.qgaAgent) {
        try {
          await this.qgaAgent.disconnect()
        } catch (e) {
          hilog.warn(DOMAIN, 'VmStatusBar', '断开旧连接时出错')
        }
        this.qgaAgent = null
      }
      
      // 3. 重置状态
      this.status.agentConnected = false
      this.lastCpuStats = null
      
      // 4. 等待资源释放
      await new Promise<void>((resolve: () => void) => setTimeout(resolve, 500))
      
      // 5. 重新创建 Agent 实例
      if (!this.appTempDir) return
      const qgaSocket = this.appTempDir + '/qga_socket'
      this.qgaAgent = new QemuAgent(qgaSocket)
      
      // 6. 尝试连接（最多 3 次重试，间隔 3 秒）
      for (let attempt = 0; attempt < 3; attempt++) {
        if (!this.isComponentActive) return
        
        try {
          const connected = await this.qgaAgent.connect()
          if (connected) {
            const ping = await this.qgaAgent.ping()
            if (ping) {
              this.status.agentConnected = true
              hilog.info(DOMAIN, 'VmStatusBar', 'Agent 强制重连成功')
              
              // 获取数据
              await this.refreshStatus()
              
              // 如果启用了监控，重新启动定时器
              if (this.settings.masterSwitch) {
                this.startRefreshTimer()
              }
              return
            }
          }
        } catch (e) {
          hilog.warn(DOMAIN, 'VmStatusBar', '重连尝试 %{public}d 失败', attempt + 1)
        }
        
        // 等待后重试
        if (attempt < 2) {
          await new Promise<void>((resolve: () => void) => setTimeout(resolve, 3000))
        }
      }
      
      hilog.error(DOMAIN, 'VmStatusBar', 'Agent 强制重连失败')
    } finally {
      this.isForceReconnecting = false
    }
  }

  async refreshStatus() {
    // 电源管理优先级最高，直接返回
    if (this.isPowerManagementOpen) return
    
    if (!this.isComponentActive || this.isRefreshing) return
    // 只有关机和暂停状态不刷新，其他状态（包括 REBOOTING、ABNORMAL）都尝试刷新
    if (this.currentEmulatorStatus === 'SHUTDOWN' || 
        this.currentEmulatorStatus === 'PAUSED' ||
        this.currentEmulatorStatus === '') {
      this.status.agentConnected = false
      return
    }
    
    this.isRefreshing = true
    
    try {
      // 使用连接管理器获取连接（低优先级，可被电源管理抢占）
      const agent = await QemuAgentManager.acquire('VmStatusBar', AgentPriority.LOW, 3000)
      if (!agent) {
        this.status.agentConnected = false
        return
      }
      
      // 再次检查电源管理状态（可能在等待期间打开了）
      if (this.isPowerManagementOpen) {
        await QemuAgentManager.release('VmStatusBar')
        return
      }
      
      // Ping 测试
      const pingResult = await agent.ping()
      this.status.agentConnected = pingResult
      
      if (!pingResult) {
        await QemuAgentManager.release('VmStatusBar')
        return
      }
      
      // 如果当前状态是异常或重启中，连接成功后自动恢复为 RUNNING
      const currentStatus = this.currentEmulatorStatus
      if (currentStatus === 'ABNORMAL' || currentStatus === 'REBOOTING') {
        AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'RUNNING')
        hilog.info(DOMAIN, 'VmStatusBar', '状态已从 %{public}s 恢复为 RUNNING', currentStatus)
      }
      
      // 获取主机名
      const hostname = await agent.getHostName()
      if (hostname) {
        this.status.hostname = hostname
      }
      
      // 获取 vCPU 数量
      const vcpus: ESObject[] | null = await agent.getVcpus()
      if (vcpus) {
        this.status.cpuCount = vcpus.length
      }
      
      // 获取文件系统信息
      const fsInfo: ESObject[] | null = await agent.getFilesystemInfo()
      if (fsInfo && fsInfo.length > 0) {
        // 找根文件系统
        for (let i = 0; i < fsInfo.length; i++) {
          const fsi = fsInfo[i] as Record<string, ESObject>
          if (fsi['mountpoint'] === '/') {
            const total = fsi['total-bytes'] as number
            const used = fsi['used-bytes'] as number
            this.status.diskTotal = total || 0
            this.status.diskUsed = used || 0
            if (this.status.diskTotal > 0) {
              this.status.diskUsage = Math.round((this.status.diskUsed / this.status.diskTotal) * 100)
            }
            break
          }
        }
      }
      
      // 获取内存信息 (始终获取，以满足核心数据要求)
      const memInfo: Record<string, number> | null = await agent.getMemoryInfo()
      if (memInfo) {
        this.status.memoryTotal = memInfo['MemTotal'] || 0
        const memAvailable = memInfo['MemAvailable'] || 0
        if (this.status.memoryTotal > 0) {
          const memUsed = this.status.memoryTotal - memAvailable
          this.status.memoryUsage = Math.round((memUsed / this.status.memoryTotal) * 100)
        }
        
        // SWAP
        this.status.swapTotal = memInfo['SwapTotal'] || 0
        const swapFree = memInfo['SwapFree'] || 0
        if (this.status.swapTotal > 0) {
          const swapUsed = this.status.swapTotal - swapFree
          this.status.swapUsage = Math.round((swapUsed / this.status.swapTotal) * 100)
        }
      }

      // 如果启用监控，获取动态数据
      if (this.settings.masterSwitch) {
        // 获取 CPU 统计信息并计算使用率
        const cpuStats: CpuStats | null = await agent.getCpuStats()
        if (cpuStats) {
          if (this.lastCpuStats) {
            const diffTotal = cpuStats.total - this.lastCpuStats.total
            const diffIdle = cpuStats.idle - this.lastCpuStats.idle
            if (diffTotal > 0) {
               this.status.cpuUsage = Math.round(((diffTotal - diffIdle) / diffTotal) * 100)
            }
          }
           const newCpuStats: CpuStats = { total: cpuStats.total, idle: cpuStats.idle }
           this.lastCpuStats = newCpuStats
        }
        
        // 检查 SSH
        this.status.sshRunning = await agent.isSshRunning()
      }
      
      // 释放连接
      await QemuAgentManager.release('VmStatusBar')
    } catch (e) {
      hilog.error(DOMAIN, 'VmStatusBar', '刷新状态失败: %{public}s', JSON.stringify(e))
      this.status.agentConnected = false
      // 确保释放连接
      try { await QemuAgentManager.release('VmStatusBar') } catch (e2) {}
    } finally {
      this.isRefreshing = false
    }
  }
  
  build() {
    Row({ space: 4 }) {
      // Agent 状态
      if (this.settings.showAgent) {
        Text(this.status.agentConnected ? '🟢' : '🔴')
          .fontSize(12)
      }
      
      // 监控项始终显示（Agent 未连接时显示 '-'）
      if (this.settings.masterSwitch) {
        // 主机名
        if (this.settings.showHostname) {
          Text(`🖥️ ${this.status.agentConnected ? this.status.hostname : '-'}`)
            .fontSize(12)
            .fontColor('#FFFFFF')
        }
        
        // CPU
        if (this.settings.showCpu) {
          Text(`🔲 ${this.status.agentConnected ? this.status.cpuCount + getContext(this).resourceManager.getStringSync($r('app.string.label_cores').id) + ' ' + this.status.cpuUsage + '%' : '-'}`)
            .fontSize(12)
            .fontColor('#FFFFFF')
        }
        
        // 内存
        if (this.settings.showMemory) {
          Text(`🔷 ${this.status.agentConnected ? formatBytes(this.status.memoryTotal, true) + ' ' + this.status.memoryUsage + '%' : '-'}`)
            .fontSize(12)
            .fontColor('#FFFFFF')
        }
        
        // 硬盘
        if (this.settings.showDisk) {
          Text(`📦 ${this.status.agentConnected ? formatBytesToGB(this.status.diskUsed) + '/' + formatBytesToGB(this.status.diskTotal) + ' ' + this.status.diskUsage + '%' : '-'}`)
            .fontSize(12)
            .fontColor('#FFFFFF')
        }
        
        // SWAP (仅在有数据时显示)
        if (this.settings.showSwap) {
          if (this.status.agentConnected && this.status.swapTotal > 0) {
            Text(`💫 ${formatBytes(this.status.swapTotal, true)} ${this.status.swapUsage}%`)
              .fontSize(12)
              .fontColor('#FFFFFF')
          } else if (!this.status.agentConnected) {
            Text(`💫 -`)
              .fontSize(12)
              .fontColor('#FFFFFF')
          }
        }
        
        // SSH
        if (this.settings.showSsh) {
          if (this.status.agentConnected) {
            Text(this.status.sshRunning ? '🔐' : '🔒')
              .fontSize(12)
          } else {
            Text('🔒 -')
              .fontSize(12)
              .fontColor('#FFFFFF')
          }
        }
      }
      
      // 帮助按钮
      Text('❓')
        .fontSize(12)
        .fontColor('#FFFFFF')
        .onClick(() => {
          new CustomDialogController({
            builder: CustomContentDialog({
              primaryTitle: $r('app.string.dialog_vm_status'),
              contentBuilder: () => {
                this.dialogBuilder()
              }
            })
          }).open()
        })
    }
    .padding({ left: 8, right: 8 })
  }
  
  @Builder
  dialogBuilder() {
    Scroll() {
      Column({ space: 12 }) {
      // 状态列表
      Column({ space: 8 }) {
        // 总开关
        Row() {
          Toggle({ type: ToggleType.Checkbox, isOn: this.settings.masterSwitch })
            .onChange((isOn: boolean) => {
              this.settings.masterSwitch = isOn
            })
          Text($r('app.string.label_enable_monitor'))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .margin({ left: 8 })
        }
        .width('100%')
        .padding({ bottom: 8 })
        
        Divider()
      
        // Agent (强制显示，图标根据状态变化)
        Row({ space: 8 }) {
          Toggle({ type: ToggleType.Checkbox, isOn: true })
            .enabled(false) // 禁用交互
          Text(this.status.agentConnected ? '🟢' : '🔴')
            .fontSize(16)
          Text(`${getContext(this).resourceManager.getStringSync($r('app.string.label_agent').id)}：${this.status.agentConnected ? getContext(this).resourceManager.getStringSync($r('app.string.status_connected').id) : getContext(this).resourceManager.getStringSync($r('app.string.status_disconnected').id)}`)
            .fontSize(14)
          
          // 未连接时显示重试链接
          if (!this.status.agentConnected) {
            Text(this.isForceReconnecting ? getContext(this).resourceManager.getStringSync($r('app.string.status_reconnecting').id) : getContext(this).resourceManager.getStringSync($r('app.string.btn_retry').id))
              .fontSize(14)
              .fontColor(this.isForceReconnecting ? '#999999' : '#007AFF')
              .enabled(!this.isForceReconnecting)
              .onClick(() => {
                this.forceReconnectAgent()
              })
          }
        }
        
        // 监控项始终显示
        if (this.settings.masterSwitch) {
          // 主机名
          this.statusRow(this.settings.showHostname, '🖥️', getContext(this).resourceManager.getStringSync($r('app.string.label_hostname').id),
            this.status.agentConnected ? this.status.hostname : '-',
            (checked: boolean) => { this.settings.showHostname = checked })
          
          // CPU
          this.statusRow(this.settings.showCpu, '🔲', 'CPU',
            this.status.agentConnected 
              ? `${this.status.cpuCount} ${getContext(this).resourceManager.getStringSync($r('app.string.label_cores2').id)} ${this.status.cpuUsage}%` 
              : '-',
            (checked: boolean) => { this.settings.showCpu = checked })
          
          // 内存
          this.statusRow(this.settings.showMemory, '🔷', getContext(this).resourceManager.getStringSync($r('app.string.label_memory2').id),
            this.status.agentConnected 
              ? `${formatBytes(this.status.memoryTotal, true)}${getContext(this).resourceManager.getStringSync($r('app.string.label_usage2').id)} ${this.status.memoryUsage}%` 
              : '-',
            (checked: boolean) => { this.settings.showMemory = checked })
          
          // 硬盘
          this.statusRow(this.settings.showDisk, '📦', getContext(this).resourceManager.getStringSync($r('app.string.label_disk').id),
            this.status.agentConnected 
              ? `${getContext(this).resourceManager.getStringSync($r('app.string.label_used2').id)} ${formatBytesToGB(this.status.diskUsed)} ${getContext(this).resourceManager.getStringSync($r('app.string.label_total2').id)} ${formatBytesToGB(this.status.diskTotal)} (${this.status.diskUsage}%)` 
              : '-',
            (checked: boolean) => { this.settings.showDisk = checked })
          
          // SWAP
          this.statusRow(this.settings.showSwap, '💫', 'SWAP',
            this.status.agentConnected && this.status.swapTotal > 0 
              ? `${getContext(this).resourceManager.getStringSync($r('app.string.label_total3').id)} ${formatBytes(this.status.swapTotal, true)}${getContext(this).resourceManager.getStringSync($r('app.string.label_usage2').id)} ${this.status.swapUsage}%` 
              : '-',
            (checked: boolean) => { this.settings.showSwap = checked })
          
          // SSH
          this.statusRow(this.settings.showSsh, this.status.sshRunning ? '🔐' : '🔒', 'SSH',
            this.status.agentConnected 
              ? (this.status.sshRunning ? getContext(this).resourceManager.getStringSync($r('app.string.status_ssh_on').id) : getContext(this).resourceManager.getStringSync($r('app.string.status_ssh_off').id)) 
              : '-',
            (checked: boolean) => { this.settings.showSsh = checked })
        } else {
           Text($r('app.string.msg_enable_monitor_hint'))
             .fontSize(14)
             .fontColor('#999999')
             .margin({ top: 8, bottom: 8 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      
      Divider()
      
      // 刷新间隔设置
      Column({ space: 8 }) {
        Text($r('app.string.label_refresh_settings'))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
        
        Row() {
          Text($r('app.string.label_refresh_interval'))
            .fontSize(14)
          Select([
            { value: $r('app.string.option_15s') },
            { value: $r('app.string.option_30s') },
            { value: $r('app.string.option_45s') },
            { value: $r('app.string.option_60s') }
          ])
            .value(this.getIntervalLabel())
            .onSelect((index: number) => {
              const intervals = [15000, 30000, 45000, 60000]
              this.settings.refreshInterval = intervals[index]
              if (this.settings.masterSwitch) {
                this.startRefreshTimer()
              }
            })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      }
      .padding(16)
      .width('100%')
    }
    .width('100%')
    .scrollBar(BarState.Auto)
    .align(Alignment.Top)
  }
  
  @Builder
  statusRow(checked: boolean, icon: string, label: string, value: string, onChange: (checked: boolean) => void) {
    Row({ space: 8 }) {
      Toggle({ type: ToggleType.Checkbox, isOn: checked })
        .onChange(onChange)
      Text(icon)
        .fontSize(16)
      Text(`${label}：${value}`)
        .fontSize(14)
    }
  }
  
  private getIntervalLabel(): string {
    const map: Record<number, string> = {
      15000: getContext(this).resourceManager.getStringSync($r('app.string.option_15s').id),
      30000: getContext(this).resourceManager.getStringSync($r('app.string.option_30s').id),
      45000: getContext(this).resourceManager.getStringSync($r('app.string.option_45s').id),
      60000: getContext(this).resourceManager.getStringSync($r('app.string.option_60s').id)
    }
    // 默认回退值改为15秒
    return map[this.settings.refreshInterval] || getContext(this).resourceManager.getStringSync($r('app.string.option_15s').id)
  }
}

export default VmStatusBar
