import { socket } from "@kit.NetworkKit"

interface Range {
  start: number
  end: number
}

interface PortStatus {
  port: number
  status: 'open' | 'closed'
}

@Preview
@Component
export struct PortScannerContent {
  @State address: string = ''
  @State range: string = ''
  @State results: PortStatus[] = []

  @Builder
  build() {
    Column() {
      TextInput({ placeholder: '输入主机地址，例如：192.168.1.1' })
        .margin({ bottom: 15 })
        .onChange((value) => this.address = value)

      TextInput({ placeholder: '输入端口范围，例如：10-20' })
        .margin({ bottom: 15 })
        .onChange((value) => this.range = value)

      Button('开始扫描')
        .width('100%')
        .enabled(this.address.trim().length > 0 && this.parseRange() !== undefined)
        .onClick(() => {
          this.startPortScan()
        })

      if (this.results.length > 0) {
        Column() {
          Text('扫描结果：').width('100%')
          ForEach(this.results, (a: PortStatus, i: number) => {
            Row() {
              Text(a.port.toString())
              Blank().layoutWeight(1)
              Text(a.status === 'open' ? '开放' : '关闭')
            }
          }, (a: PortStatus, i: number) => a.port.toString())
        }
        .margin({ top: 15 })
        .padding(10)
        .borderRadius(10)
        .backgroundColor($r('app.color.setting_block_background'))
      }
    }
    .padding(10)
  }

  parseRange(): Range | undefined {
    try {
      const parts = this.range.split('-')
      if (parts.length !== 2) {
        return undefined
      }
      const start = parseInt(parts[0])
      const end = parseInt(parts[1])
      if (start > end || isNaN(end)) {
        return undefined
      }
      return { start, end }
    } catch (e) {
      return undefined
    }
  }

  async startPortScan() {

    this.results = []

    const ports: number[] = this.getPorts()
    for (let i = 0; i < ports.length; i++) {
      const port = ports[i]
      const open = await this.checkPortOpen(this.address, port)
      this.results.push({ port, status: open ? 'open' : 'closed' })
    }
  }

  private getPorts() {
    const range = this.parseRange()!!
    const ports: number[] = []
    for (let i = range?.start; i <= range?.end; i += 1) {
      ports.push(i)
    }
    return ports
  }

  private async checkPortOpen(address: string, port: number): Promise<boolean> {
    const tcp = socket.constructTCPSocketInstance()
    try {
      await tcp.bind({ address: '0.0.0.0', family: 1 })
      await tcp.connect({ address: { address: address, port: port, family: 1 } })
      return true
    } catch (e) {
      return false
    } finally {
      await tcp.close()
    }
  }
}