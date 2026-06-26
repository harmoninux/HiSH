import { hilog } from '@kit.PerformanceAnalysisKit'
import { router } from '@kit.ArkUI'
import { Emulator, defaultEmulator } from '../model/Emulator'
import appOption from '../model/appOption'
import napi from 'libentry.so'
import { startVm } from '../lib/startVm'
import { getCpuCount, getMemSize } from '../lib/systemProfile'

const DOMAIN = 0x0000

interface StartResult {
  vmStarted: boolean
  portsSkipped: number[]
}

/**
 * 启动固件选择页
 * 用户选择要启动的 VM，支持倒计时自动启动上次使用的固件
 */
@Entry
@Component
struct LauncherPage {
  @StorageLink(appOption.emulators) emulators: Emulator[] = []
  @StorageLink(appOption.lastEmulatorId) lastEmulatorId: string = ''
  @StorageLink(appOption.showLauncher) showLauncher: boolean = true
  @State countdown: number = 3
  @State countdownTimer: number = -1
  @State isStarting: boolean = false

  aboutToAppear(): void {
    // 如果只有一个 emulator 或者用户关了 launcher，直接启动
    if (!this.showLauncher || this.emulators.length <= 1) {
      this.startEmulator(this.getDefaultEmulatorId())
      return
    }
    // 开始倒计时
    this.startCountdown()
  }

  aboutToDisappear(): void {
    if (this.countdownTimer >= 0) {
      clearInterval(this.countdownTimer)
    }
  }

  getDefaultEmulatorId(): string {
    if (this.lastEmulatorId && this.emulators.some(e => e.id === this.lastEmulatorId)) {
      return this.lastEmulatorId
    }
    const defaultId = AppStorage.get<string>(appOption.defaultStartEmulator)
    if (defaultId && this.emulators.some(e => e.id === defaultId)) {
      return defaultId
    }
    return this.emulators.length > 0 ? this.emulators[0].id : defaultEmulator.id
  }

  startCountdown(): void {
    this.countdown = 3
    this.countdownTimer = setInterval(() => {
      this.countdown--
      if (this.countdown <= 0) {
        clearInterval(this.countdownTimer)
        this.startEmulator(this.getDefaultEmulatorId())
      }
    }, 1000)
  }

  cancelCountdown(): void {
    if (this.countdownTimer >= 0) {
      clearInterval(this.countdownTimer)
      this.countdownTimer = -1
    }
    this.countdown = 0
  }

  startEmulator(emulatorId: string): void {
    if (this.isStarting) return
    this.isStarting = true
    this.cancelCountdown()

    // 记录上次启动的 emulator
    AppStorage.setOrCreate(appOption.lastEmulatorId, emulatorId)

    hilog.info(DOMAIN, 'LauncherPage', 'Starting emulator: %{public}s', emulatorId)

    // 查找要启动的 emulator
    const emulatorToStart = this.emulators.find(e => e.id === emulatorId) || defaultEmulator

    // 启动 VM（复用 EntryAbility 的逻辑）
    const result = this.doStartVm(emulatorToStart)

    // 跳转到终端页
    router.replaceUrl({ url: 'pages/Index' })
  }

  private doStartVm(emulatorToStart: Emulator): StartResult {
    const appTempDir = AppStorage.get(appOption.appTempDir) as string
    const cpuCount = emulatorToStart.cpu
    const memSize = emulatorToStart.memory

    // Apply performance profile
    const profile = AppStorage.get<string>(appOption.performanceProfile) ?? 'balanced'
    let adjustedCpu = cpuCount
    let adjustedMem = memSize
    if (profile === 'powersave') {
      adjustedCpu = Math.min(cpuCount, 2)
      adjustedMem = Math.min(memSize, 512)
    } else if (profile === 'performance') {
      adjustedCpu = getCpuCount()
      adjustedMem = Math.max(1024, getMemSize() - 1024)
    }

    const rootVda = emulatorToStart.rootVda
    const rootFilesystem = emulatorToStart.rootFilesystem
    const sharedFolderReadonly = emulatorToStart.sharedFolderReadonly
    const portMappingRaw = emulatorToStart.portMapping
    const init = emulatorToStart.init

    const sharedFolder = AppStorage.get(appOption.sharedHost) as string
    const vmBaseDir = AppStorage.get(appOption.vmBaseDir) as string
    const kernelFile = AppStorage.get(appOption.kernel) as string

    // 跳过特权端口
    const portUsed = portMappingRaw.map((it): number => it.host!!)
      .filter((p): boolean => {
        if (p < 1024) {
          hilog.warn(DOMAIN, 'LauncherPage', 'host port %{public}d is privileged (<1024), skipped', p)
          return true
        }
        return napi.checkPortUsed(p)
      })
    const portMapping = portMappingRaw.filter((it): boolean => portUsed.indexOf(it.host!!) < 0)

    AppStorage.setOrCreate(appOption.portUsedByOthers, portUsed)
    AppStorage.setOrCreate(appOption.currentRunningEmulator, emulatorToStart.id)

    // VNC 配置
    let vncEnabled = AppStorage.get<boolean>(appOption.vncEnabled) ?? true
    const vncPortMode = AppStorage.get<string>(appOption.vncPortMode) ?? 'local'
    let vncPort = AppStorage.get<number>(appOption.vncPort) ?? 5900

    // VNC 端口预检查
    if (vncEnabled && napi.checkPortUsed(vncPort)) {
      hilog.warn(DOMAIN, 'LauncherPage', 'VNC port %{public}d is in use, searching for free port', vncPort)
      const freePort = this.getFreeVncPort(5900, 5999)
      if (freePort !== undefined) {
        vncPort = freePort
        AppStorage.setOrCreate(appOption.vncPort, vncPort)
      } else {
        vncEnabled = false
        hilog.warn(DOMAIN, 'LauncherPage', 'No free VNC port found, disabling VNC')
      }
    }

    const serialUnixSocket = appTempDir + '/serial_socket'
    const qmpUnixSocket = appTempDir + '/qmp_socket'
    const qgaUnixSocket = appTempDir + '/qga_socket'

    const vmStarted = startVm({
      baseDir: vmBaseDir,
      cpu: adjustedCpu,
      memory: adjustedMem,
      portMapping: portMapping,
      kernel: kernelFile,
      rootVda,
      rootFilesystem,
      sharedFolder,
      serialUnixSocket,
      sharedFolderReadonly,
      init,
      qmpUnixSocket,
      qgaUnixSocket,
      vncEnabled,
      vncPortMode,
      vncPort
    })

    if (vmStarted) {
      AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'RUNNING')
    }

    return { vmStarted, portsSkipped: portUsed }
  }

  private getFreeVncPort(min: number, max: number): number | undefined {
    for (let port = min; port <= max; port++) {
      if (!napi.checkPortUsed(port)) {
        return port
      }
    }
    return undefined
  }

  build() {
    Column() {
      // 顶部标题
      Row() {
        Text('HiSH')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor('#ffffff')
        Blank()
        // 设置入口
        Text('⚙')
          .fontSize(20)
          .fontColor('#888888')
          .onClick(() => {
            router.pushUrl({ url: 'pages/SettingsPage' })
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 16, bottom: 8 })

      // 提示文字
      Text('选择要启动的虚拟机')
        .fontSize(14)
        .fontColor('#888888')
        .width('100%')
        .padding({ left: 20, bottom: 16 })

      // 模拟器列表
      List() {
        ForEach(this.emulators, (emulator: Emulator) => {
          ListItem() {
            this.buildEmulatorCard(emulator)
          }
        }, (emulator: Emulator) => emulator.id)
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 16, right: 16 })

      // 底部工具栏
      Row() {
        Text('+ 新建模拟器')
          .fontSize(14)
          .fontColor('#4FC3F7')
          .onClick(() => {
            router.pushUrl({ url: 'pages/EditEmulator' })
          })
        Blank()
        Text('📁 镜像管理')
          .fontSize(14)
          .fontColor('#888888')
          .onClick(() => {
            router.pushUrl({ url: 'pages/RootfsManagement' })
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 12, bottom: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#0d0d1a')
  }

  @Builder
  buildEmulatorCard(emulator: Emulator) {
    Column() {
      Row() {
        // 图标
        Text(emulator.name.startsWith('AI') ? '🤖' :
          emulator.name.includes('Arch') ? '🧪' : '🐧')
          .fontSize(32)
          .margin({ right: 12 })

        // 名称和配置
        Column() {
          Text(emulator.name)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#ffffff')
          Text(`${emulator.cpu} CPU / ${emulator.memory} MB`)
            .fontSize(12)
            .fontColor('#888888')
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        // 倒计时或启动按钮
        if (emulator.id === this.getDefaultEmulatorId() && this.countdown > 0) {
          Column() {
            Text(`${this.countdown}s`)
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor('#4FC3F7')
            Text('自动启动')
              .fontSize(10)
              .fontColor('#888888')
          }
          .alignItems(HorizontalAlign.Center)
        } else {
          Button('启动')
            .fontSize(14)
            .fontColor('#ffffff')
            .backgroundColor('#4FC3F7')
            .height(36)
            .onClick(() => {
              this.startEmulator(emulator.id)
            })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 取消自动启动按钮（只在倒计时中的默认 emulator 显示）
      if (emulator.id === this.getDefaultEmulatorId() && this.countdown > 0) {
        Button('取消自动启动')
          .fontSize(12)
          .fontColor('#888888')
          .backgroundColor('#333333')
          .height(28)
          .margin({ top: 8 })
          .width('100%')
          .onClick(() => {
            this.cancelCountdown()
          })
      }
    }
    .width('100%')
    .padding(16)
    .margin({ top: 8, bottom: 8 })
    .backgroundColor(emulator.id === this.getDefaultEmulatorId() ? '#1a1a3a' : '#1a1a2e')
    .borderRadius(12)
    .border({
      width: emulator.id === this.getDefaultEmulatorId() ? 1 : 0,
      color: '#4FC3F7'
    })
    .onClick(() => {
      if (emulator.id !== this.getDefaultEmulatorId() || this.countdown <= 0) {
        this.startEmulator(emulator.id)
      }
    })
  }
}
