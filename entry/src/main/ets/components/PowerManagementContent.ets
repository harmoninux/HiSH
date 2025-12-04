import { CustomContentDialog } from '@kit.ArkUI'
import appOption from '../model/appOption'
import QemuAgent from '../lib/QemuAgent'
import { hilog } from '@kit.PerformanceAnalysisKit'

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

  async connectToQGA() {
    this.isConnecting = true
    this.statusMessage = '正在连接 QEMU Guest Agent...'
    
    try {
      const appTempDir = AppStorage.get(appOption.appTempDir) as string
      const qgaSocket = appTempDir + '/qga_socket'
      
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
          this.performAction('关机', () => this.qgaAgent!.shutdown())
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
          this.performAction('重启', () => this.qgaAgent!.reboot())
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
            Text('暂停 (挂起到 RAM)')
              .fontSize(16)
              .fontColor('#FFFFFF')
          }
        }
        .width('100%')
        .height(48)
        .backgroundColor('#3498DB')
        .borderRadius(8)
        .enabled(this.isConnected && !this.isConnecting)
        .onClick(() => {
          this.performAction('暂停', () => this.qgaAgent!.suspend())
        })
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
