import { hilog } from '@kit.PerformanceAnalysisKit'
import { CustomContentDialog } from '@kit.ArkUI'
import QemuAgent, { CpuStats, SystemInfo } from '../lib/QemuAgent'
import { QemuAgentManager, AgentPriority } from '../lib/QemuAgentManager'
import appOption from '../model/appOption'
import { Emulator } from '../model/Emulator'
import { util } from '@kit.ArkTS'
import { pasteboard } from '@kit.BasicServicesKit'

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
  masterSwitch: true,
  showAgent: true,
  showHostname: false,
  showCpu: true,
  showMemory: true,
  showDisk: false,
  showSwap: false,
  showSsh: false,
  refreshInterval: 10000
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
struct ConnectingProgress {
  @State showPopup:boolean = false
  build() {
    LoadingProgress()
      .onClick(() => this.showPopup = true)
      .bindPopup(this.showPopup, {
        message: this.getUIContext().getHostContext()!.resourceManager.getStringByNameSync('agent_connecting_tips'),
        onStateChange: (e) => {
          this.showPopup = e.isVisible
        }
      })
  }
}

@Component
export struct VmStatusBar {
  @StorageProp(appOption.appTempDir) appTempDir: string = ''
  @Watch('onEmulatorStatusChange') @StorageProp(appOption.currentEmulatorStatus) currentEmulatorStatus: string = ''
  @Watch('onPowerManagementChange') @StorageProp(appOption.isPowerManagementOpen) isPowerManagementOpen: boolean = false
  @StorageProp('terminalFps') terminalFps: number = 0
  @StorageProp('terminalGpuEnabled') terminalGpuEnabled: boolean = false

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
    masterSwitch: true,
    showAgent: true,
    showHostname: false,
    showCpu: true,
    showMemory: true,
    showDisk: false,
    showSwap: false,
    showSsh: false,
    refreshInterval: 5000
  }

  @State isRefreshing: boolean = false
  @State isForceReconnecting: boolean = false
  @Prop reactive?: boolean = undefined
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
    // [修复] 通过 Manager 释放连接，否则 currentUser 残留会导致其他组件无法 acquire
    QemuAgentManager.release('VmStatusBar')
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

  private showSshInfo() {
    try {
      const emulatorsJson = AppStorage.get<string>(appOption.emulators)
      const emulators = JSON.parse(emulatorsJson ?? '[]') as Emulator[]
      const runningId = AppStorage.get<string>(appOption.currentRunningEmulator)
      const emu = emulators.find((e: Emulator) => e.id === runningId)
      // Default SSH port is 2222
      let sshPort = 2222
      if (emu?.portMapping) {
        const sshMap = emu.portMapping.find((p) => p.guest === 22)
        if (sshMap?.host) sshPort = sshMap.host
      }
      const cmd = `ssh -p ${sshPort} root@127.0.0.1`
      const board = pasteboard.getSystemPasteboard()
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, cmd)
      board.setData(pasteData)
      this.getUIContext().getPromptAction().showToast({
        message: `已复制: ${cmd}`,
        duration: 2000
      })
    } catch (e) {
      hilog.error(DOMAIN, 'VmStatusBar', 'SSH copy failed: %{public}s', JSON.stringify(e))
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
    // 即使电源管理打开，监控条也继续探测，作为 Truth Source
    // 但为了避免抢占，如果在 reset 操作期间，逻辑通常会由全局状态控制暂停
    // 目前保持常开即可，因为 acquire 锁机制会处理竞争
    if (this.isPowerManagementOpen) {
      hilog.info(DOMAIN, 'VmStatusBar', '电源管理已打开，监控条继续维持状态同步')
    }
  }

  private async initAgent() {
    if (!this.appTempDir) {
      return
    }

    // 首次初始化：尝试获取一次数据
    await this.refreshStatus()

    // 始终启动定时刷新，保持 Agent 连接状态同步
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
   * 使用 QemuAgentManager 进行高优先级重连，保持全局管理统一
   */
  private async forceReconnectAgent() {
    // 防止重复点击
    if (this.isForceReconnecting) return
    this.isForceReconnecting = true

    hilog.info(DOMAIN, 'VmStatusBar', '开始强制重连 Agent (通过 Manager)...')

    try {
      // 1. 停止定时器，避免冲突
      this.stopRefreshTimer()

      // 2. 释放可能存在的旧占用
      await QemuAgentManager.release('VmStatusBar')

      // 3. 重置状态
      this.status.agentConnected = false
      this.lastCpuStats = null

      // 4. 尝试连接（使用 NORMAL 优先级，最多 3 次重试，间隔 2 秒）
      for (let attempt = 0; attempt < 3; attempt++) {
        if (!this.isComponentActive) return

        try {
          // 使用 NORMAL 优先级请求连接 (高于自动刷新的 LOW，但低于电源管理的 HIGH)
          const agent = await QemuAgentManager.acquire('VmStatusBar', AgentPriority.NORMAL, 3000)

          if (agent) {
            const ping = await agent.ping()
            if (ping) {
              this.status.agentConnected = true
              hilog.info(DOMAIN, 'VmStatusBar', 'Agent 强制重连成功')

              // 获取数据 (传入 agent 避免重复 acquire)
              await this.refreshStatus(agent)

              // 关键修复：refreshStatus 不会释放外部传入的 agent，必须手动释放
              await QemuAgentManager.release('VmStatusBar')

              // 如果启用了监控，重新启动定时器
              if (this.settings.masterSwitch) {
                this.startRefreshTimer()
              }
              return
            } else {
              // Ping 失败，释放连接
              await QemuAgentManager.release('VmStatusBar')
            }
          }
        } catch (e) {
          hilog.warn(DOMAIN, 'VmStatusBar', '重连尝试 %{public}d 失败: %{public}s', attempt + 1, JSON.stringify(e))
          // 确保释放
          await QemuAgentManager.release('VmStatusBar')
        }

        // 等待后重试
        if (attempt < 2) {
          await new Promise<void>((resolve: () => void) => setTimeout(resolve, 2000))
        }
      }

      hilog.error(DOMAIN, 'VmStatusBar', 'Agent 强制重连失败')
    } finally {
      this.isForceReconnecting = false
    }
  }

  async refreshStatus(externalAgent: QemuAgent | null = null) {
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
      // 如果没有传入外部 agent，则尝试 acquire
      const agent = externalAgent || await QemuAgentManager.acquire('VmStatusBar', AgentPriority.LOW, 3000)
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
      AppStorage.setOrCreate(appOption.isQgaConnected, pingResult)

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

      // [优化] 一次 shell exec 获取 meminfo + cpu stats + ssh 状态，替代原来三次独立调用
      const sysInfo: SystemInfo | null = await agent.getSystemInfo()
      if (sysInfo) {
        // 内存信息 (始终处理)
        const memInfo = sysInfo.memory
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

        // 如果启用监控，处理 CPU 和 SSH
        if (this.settings.masterSwitch) {
          // CPU 统计
          const cpuStats = sysInfo.cpuStats
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

          // SSH 状态
          this.status.sshRunning = sysInfo.sshRunning
        }
      }

      // 只有在非外部传入 agent 时才释放
      if (!externalAgent) {
        await QemuAgentManager.release('VmStatusBar')
      }
    } catch (e) {
      hilog.error(DOMAIN, 'VmStatusBar', '刷新状态失败: %{public}s', JSON.stringify(e))
      this.status.agentConnected = false
      // 确保释放连接
      try {
        if (!externalAgent) {
          await QemuAgentManager.release('VmStatusBar')
        }
      } catch (e2) { }
    } finally {
      this.isRefreshing = false
    }
  }

  build() {
    Row({ space: 4 }) {
      // Agent 状态
      if (this.settings.showAgent) {
        if (!this.status.agentConnected) {
          ConnectingProgress().height(18).width(18)
            .margin({ right: 5 })
        } else {
          Text('🟢').fontSize(11)
            .margin({ right: 5 })
        }
      }

      // 监控项始终显示（Agent 未连接时显示 '-'）
      Scroll() {
        Row() {
          if (this.settings.masterSwitch) {
            // 主机名
            if (this.settings.showHostname) {
              Text(`🖥️ ${this.status.agentConnected ? this.status.hostname : '-'}`)
                .fontSize(12)
                .fontColor('#FFFFFF')
                .margin({ right: 10 })
            }

            // CPU
            if (this.settings.showCpu) {
              Text(`🔲 ${this.status.agentConnected ?
                this.status.cpuCount + getContext(this).resourceManager.getStringSync($r('app.string.label_cores').id) +
                  ' ' + this.status.cpuUsage + '%' : '-'}`)
                .fontSize(12)
                .fontColor('#FFFFFF')
                .margin({ right: 10 })
            }

            // 内存
            if (this.settings.showMemory) {
              Text(`🔷 ${this.status.agentConnected ?
                formatBytes(this.status.memoryTotal, true) + ' ' + this.status.memoryUsage + '%' : '-'}`)
                .fontSize(12)
                .fontColor('#FFFFFF')
                .margin({ right: 10 })
            }

            // 硬盘
            if (this.settings.showDisk) {
              Text(`📦 ${this.status.agentConnected ?
                formatBytesToGB(this.status.diskUsed) + '/' + formatBytesToGB(this.status.diskTotal) + ' ' +
                this.status.diskUsage + '%' : '-'}`)
                .fontSize(12)
                .fontColor('#FFFFFF')
                .margin({ right: 10 })
            }

            // SWAP (仅在有数据时显示)
            if (this.settings.showSwap) {
              if (this.status.agentConnected && this.status.swapTotal > 0) {
                Text(`💫 ${formatBytes(this.status.swapTotal, true)} ${this.status.swapUsage}%`)
                  .fontSize(12)
                  .fontColor('#FFFFFF')
                  .margin({ right: 10 })
              } else if (!this.status.agentConnected) {
                Text(`💫 -`)
                  .fontSize(12)
                  .fontColor('#FFFFFF')
                  .margin({ right: 10 })
              }
            }

            // SSH
            if (this.settings.showSsh) {
              if (this.status.agentConnected && this.status.sshRunning) {
                Text('🔐 SSH')
                  .fontSize(12)
                  .fontColor('#4FC3F7')
                  .onClick(() => {
                    this.showSshInfo()
                  })
              } else if (this.status.agentConnected) {
                Text('🔒 -')
                  .fontSize(12)
                  .fontColor('#FFFFFF')
              } else {
                Text('🔒 -')
                  .fontSize(12)
                  .fontColor('#FFFFFF')
              }
            }
          }
        }
      }
      .layoutWeight(this.reactive ? 1: 0)
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .align(Alignment.Start)
      .margin({ right: 5 })

      // 帮助按钮
      SymbolGlyph($r('sys.symbol.slider_horizontal_2'))
        .fontSize(18)
        .fontColor([$r('sys.color.white')])
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
  }

  @Builder
  dialogBuilder() {
    Scroll() {
      Column({ space: 12 }) {
        // 状态列表
        Column({ space: 8 }) {
          // // 总开关
          // Row() {
          //   Toggle({ type: ToggleType.Checkbox, isOn: this.settings.masterSwitch })
          //     .onChange((isOn: boolean) => {
          //       this.settings.masterSwitch = isOn
          //     })
          //   Text($r('app.string.label_enable_monitor'))
          //     .fontSize(16)
          //     .fontWeight(FontWeight.Bold)
          //     .margin({ left: 8 })
          // }
          // .width('100%')
          // .padding({ bottom: 8 })
          //
          // Divider()

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
              { value: $r('app.string.option_5s') },
              { value: $r('app.string.option_10s') },
              { value: $r('app.string.option_15s') },
              { value: $r('app.string.option_30s') },
              { value: $r('app.string.option_45s') },
              { value: $r('app.string.option_60s') }
            ])
              .value(this.getIntervalLabel())
              .onSelect((index: number) => {
                const intervals = [5000, 10000, 15000, 30000, 45000, 60000]
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
      5000: getContext(this).resourceManager.getStringSync($r('app.string.option_5s').id),
      10000: getContext(this).resourceManager.getStringSync($r('app.string.option_10s').id),
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
