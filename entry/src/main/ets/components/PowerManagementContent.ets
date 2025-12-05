import { CustomContentDialog } from '@kit.ArkUI'
import appOption from '../model/appOption'
import QemuAgent from '../lib/QemuAgent'
import QmpClient from '../lib/QmpClient'
import { hilog } from '@kit.PerformanceAnalysisKit'
import common from '@ohos.app.ability.common'
import { startVm } from '../lib/startVm'
import { Emulator, PortMapping } from '../model/Emulator'

const DOMAIN = 0x0000

/**
 * 电源管理组件
 * 提供关机、重启、暂停虚拟机的功能
 */
@Component
export default struct PowerManagementContent {
  @State isConnecting: boolean = false
  @State isConnected: boolean = false
  @State statusMessage: string = ''
  private qgaAgent: QemuAgent | null = null

  aboutToAppear() {
    this.connectToQGA()
  }

  aboutToDisappear() {
    if (this.qgaAgent) {
      this.qgaAgent.disconnect()
      this.qgaAgent = null
    }
  }

  async connectToQGA() {
    this.isConnecting = true
    this.statusMessage = '正在连接 QEMU Guest Agent...'
    
    try {
      const appTempDir = AppStorage.get(appOption.appTempDir) as string
      const qgaSocket = appTempDir + '/qga_socket'
      
      if (this.qgaAgent) {
        await this.qgaAgent.disconnect()
      }
      this.qgaAgent = new QemuAgent(qgaSocket)
      const connected = await this.qgaAgent.connect()
      
      if (connected) {
        // 测试 ping
        const pingResult = await this.qgaAgent.ping()
        this.isConnected = pingResult
        this.statusMessage = pingResult ? '已连接到 Guest Agent' : '连接失败：Agent 无响应'
      } else {
        this.isConnected = false
        this.statusMessage = '连接失败：请确保虚拟机已安装 qemu-guest-agent'
      }
    } catch (e) {
      this.isConnected = false
      this.statusMessage = '连接失败：' + JSON.stringify(e)
      hilog.error(DOMAIN, 'PowerManagement', '连接 QGA 失败: %{public}s', JSON.stringify(e))
    } finally {
      this.isConnecting = false
    }
  }

  async performAction(action: string, actionFn: () => Promise<boolean>) {
    if (!this.qgaAgent || !this.isConnected) {
      this.statusMessage = '未连接到 Guest Agent'
      return
    }

    this.statusMessage = `正在执行${action}...`
    try {
      const result = await actionFn()
      this.statusMessage = result ? `${action}命令已发送` : `${action}失败`
    } catch (e) {
      this.statusMessage = `${action}失败: ` + JSON.stringify(e)
      hilog.error(DOMAIN, 'PowerManagement', '%{public}s失败: %{public}s', action, JSON.stringify(e))
    }
  }

  private async connectToQmp(): Promise<QmpClient | null> {
    const appTempDir = AppStorage.get(appOption.appTempDir) as string
    
    // 尝试连接新的 UI 专用 socket
    const uiSocket = appTempDir + '/qmp_socket_ui'
    let client = new QmpClient(uiSocket)
    try {
      await client.connect()
      return client
    } catch (e) {
      hilog.warn(DOMAIN, 'PowerManagement', '无法连接到 UI QMP socket: %{public}s', JSON.stringify(e))
    }

    // 回退尝试连接旧的 socket (兼容旧的 VM 实例)
    const legacySocket = appTempDir + '/qmp_socket'
    client = new QmpClient(legacySocket)
    try {
      await client.connect()
      hilog.info(DOMAIN, 'PowerManagement', '已连接到遗留 QMP socket')
      return client
    } catch (e) {
      hilog.error(DOMAIN, 'PowerManagement', '无法连接到遗留 QMP socket: %{public}s', JSON.stringify(e))
    }

    return null
  }

  async performResume() {
    this.statusMessage = '正在恢复虚拟机...'
    try {
      const qmpClient = await this.connectToQmp()
      
      if (qmpClient) {
        try {
          this.statusMessage = '正在发送恢复命令...'
          const result = await qmpClient.cont()
          
          if (result) {
            this.statusMessage = '恢复命令已发送，等待虚拟机响应...'
            AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'RUNNING')
            // 尝试重新连接 Guest Agent，增加等待时间
            setTimeout(() => {
              this.connectToQGA()
            }, 5000)
          } else {
            this.statusMessage = '恢复失败：QMP 命令执行错误'
          }
        } finally {
          await qmpClient.disconnect()
        }
      } else {
        this.statusMessage = '无法连接到 QMP (请尝试完全重启应用)'
      }
    } catch (e) {
      this.statusMessage = '恢复失败: ' + JSON.stringify(e)
      hilog.error(DOMAIN, 'PowerManagement', '恢复失败: %{public}s', JSON.stringify(e))
    }
  }

  async performPause() {
    this.statusMessage = '正在暂停虚拟机...'
    try {
      const qmpClient = await this.connectToQmp()
      
      if (qmpClient) {
        try {
          const result = await qmpClient.stop()
          
          if (result) {
            this.statusMessage = '暂停命令已发送'
            AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'PAUSED')
          } else {
            this.statusMessage = '暂停失败'
          }
        } finally {
          await qmpClient.disconnect()
        }
      } else {
        this.statusMessage = '无法连接到 QMP (请尝试完全重启应用)'
      }
    } catch (e) {
      this.statusMessage = '暂停失败: ' + JSON.stringify(e)
      hilog.error(DOMAIN, 'PowerManagement', '暂停失败: %{public}s', JSON.stringify(e))
    }
  }

  async performShutdown() {
    if (!this.qgaAgent || !this.isConnected) {
      this.statusMessage = '未连接到 Guest Agent'
      return
    }
    this.statusMessage = '正在执行关机...'
    try {
      const result = await this.qgaAgent.shutdown()
      if (result) {
        this.statusMessage = '关机命令已发送'
        this.isConnected = false
        AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'SHUTDOWN')
        await this.qgaAgent.disconnect()
      } else {
        this.statusMessage = '关机失败'
      }
    } catch (e) {
      this.statusMessage = '关机失败: ' + JSON.stringify(e)
      hilog.error(DOMAIN, 'PowerManagement', '关机失败: %{public}s', JSON.stringify(e))
    }
  }

  async performReboot() {
    if (!this.qgaAgent || !this.isConnected) {
      this.statusMessage = '未连接到 Guest Agent'
      return
    }
    this.statusMessage = '正在执行重启...'
    try {
      const result = await this.qgaAgent.reboot()
      if (result) {
        this.statusMessage = '重启命令已发送，正在重新连接...'
        this.isConnected = false
        AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'REBOOTING')
        await this.qgaAgent.disconnect()
        
        // 延迟后尝试重新连接
        setTimeout(() => {
          this.connectToQGA()
          AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'RUNNING')
        }, 5000)
      } else {
        this.statusMessage = '重启失败'
      }
    } catch (e) {
      this.statusMessage = '重启失败: ' + JSON.stringify(e)
      hilog.error(DOMAIN, 'PowerManagement', '重启失败: %{public}s', JSON.stringify(e))
    }
  }

/*  async performPowerOn() {
    this.statusMessage = '正在开机...'
    try {
      // 直接重启VM，不需要重启整个应用
      const appTempDir = AppStorage.get(appOption.appTempDir) as string
      const vmBaseDir = AppStorage.get(appOption.vmBaseDir) as string
      const kernelFile = AppStorage.get(appOption.kernel) as string
      const sharedFolder = AppStorage.get(appOption.sharedHost) as string
      const emulators = AppStorage.get(appOption.emulators) as Emulator[]
      const currentEmulatorId = AppStorage.get(appOption.currentRunningEmulator) as string
      const emulator = emulators.find((e: Emulator) => e.id === currentEmulatorId)
      
      if (!emulator) {
        this.statusMessage = '开机失败：未找到虚拟机配置'
        return
      }
      
      this.statusMessage = '正在启动虚拟机...'
      
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
        qgaUnixSocket: appTempDir + '/qga_socket'
      })
      
      this.statusMessage = '虚拟机启动成功'
      AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'RUNNING')
      
      // 延迟尝试连接Guest Agent
      setTimeout(() => {
        this.connectToQGA()
      }, 2000)
    } catch (e) {
      this.statusMessage = '开机失败: ' + JSON.stringify(e)
      hilog.error(DOMAIN, 'PowerManagement', '开机失败: %{public}s', JSON.stringify(e))
    }
  }*/

  build() {
    Column() {
      // 状态显示
      Row() {
        Text('Guest Agent 状态:')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
        Blank()
        if (this.isConnecting) {
          LoadingProgress()
            .width(16)
            .height(16)
            .margin({ right: 8 })
        }
        Text(this.statusMessage)
          .fontSize(12)
          .fontColor(this.isConnected ? '#00AA00' : '#AA0000')
      }
      .width('100%')
      .padding(16)
      .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
      .borderRadius(8)
      .margin({ bottom: 16 })

      // 重新连接按钮
      if (!this.isConnected && !this.isConnecting) {
        Button('重新连接')
          .width('100%')
          .margin({ bottom: 16 })
          .onClick(() => {
            this.connectToQGA()
          })
      }

      // 电源管理按钮
      Text('电源管理')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 12 })
        .alignSelf(ItemAlign.Start)

      Column({ space: 12 }) {
        // 关机按钮
        Button({
          type: ButtonType.Normal,
          stateEffect: true
        }) {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.power'))
              .fontSize(20)
              .fontColor(['#FFFFFF'])
            Text('关机')
              .fontSize(16)
              .fontColor('#FFFFFF')
          }
        }
        .width('100%')
        .height(48)
        .backgroundColor('#E74C3C')
        .borderRadius(8)
        .enabled(this.isConnected && !this.isConnecting)
        .onClick(() => {
          this.performShutdown()
        })

        // 重启按钮
        Button({
          type: ButtonType.Normal,
          stateEffect: true
        }) {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.arrow_clockwise'))
              .fontSize(20)
              .fontColor(['#FFFFFF'])
            Text('重启')
              .fontSize(16)
              .fontColor('#FFFFFF')
          }
        }
        .width('100%')
        .height(48)
        .backgroundColor('#F39C12')
        .borderRadius(8)
        .enabled(this.isConnected && !this.isConnecting)
        .onClick(() => {
          this.performReboot()
        })

        // 暂停按钮
        Button({
          type: ButtonType.Normal,
          stateEffect: true
        }) {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.pause'))
              .fontSize(20)
              .fontColor(['#FFFFFF'])
            Text('暂停')
              .fontSize(16)
              .fontColor('#FFFFFF')
          }
        }
        .width('100%')
        .height(48)
        .backgroundColor('#3498DB')
        .borderRadius(8)
        .onClick(() => {
          this.performPause()
        })

        // 恢复按钮
        Button({
          type: ButtonType.Normal,
          stateEffect: true
        }) {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.play'))
              .fontSize(20)
              .fontColor(['#FFFFFF'])
            Text('恢复')
              .fontSize(16)
              .fontColor('#FFFFFF')
          }
        }
        .width('100%')
        .height(48)
        .backgroundColor('#2ECC71')
        .borderRadius(8)
        .onClick(() => {
          this.performResume()
        })

        // 开机按钮
/*        Button({
          type: ButtonType.Normal,
          stateEffect: true
        }) {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.power'))
              .fontSize(20)
              .fontColor(['#FFFFFF'])
            Text('开机')
              .fontSize(16)
              .fontColor('#FFFFFF')
          }
        }
        .width('100%')
        .height(48)
        .backgroundColor('#27AE60')
        .borderRadius(8)
        .onClick(() => {
          this.performPowerOn()
        })*/
      }
      .width('100%')

      // 说明文字
      Text('注意：需要在虚拟机内安装 qemu-guest-agent 服务才能使用电源管理功能。')
        .fontSize(12)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .margin({ top: 24 })
        .width('100%')
    }
    .width('100%')
    .padding(16)
  }
}
