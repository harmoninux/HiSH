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
  @State scanning: boolean = false
  @State timeout: number = 1000

  @Builder
  build() {
    Column() {
      TextInput({ placeholder: '输入主机地址，例如：192.168.1.1' })
        .margin({ bottom: 15 })
        .onChange((value) => this.address = value)

      TextInput({ placeholder: '输入端口范围，例如：10-20' })
        .margin({ bottom: 15 })
        .onChange((value) => this.range = value)

      Row() {
        Text('超时时间（毫秒）')
          .fontSize($r('sys.float.Body_L'))
          .fontColor($r('sys.color.font_secondary'))
        Blank().layoutWeight(1)
        TextInput({ text: this.timeout.toString() })
          .width(120)
          .type(InputType.Number)
          .onChange((value) => this.timeout = parseInt(value))
      }
      .width('100%')
      .margin({ bottom: 15 })

      Column() {
        if (this.scanning) {
          Button('扫描中：' + this.scanningProgress())
            .width('100%')
            .enabled(false)
        } else {
          Button('开始扫描')
            .width('100%')
            .enabled(this.address.trim().length > 0
              && this.parseRange() !== undefined
              && !isNaN(this.timeout) && this.timeout > 0)
            .onClick(() => {
              this.startPortScan()
            })
        }
      }
      .margin({ bottom: 15 })

      Column() {
        Text('扫描结果')
          .width('100%')
          .padding(10)
          .fontSize($r('sys.float.Body_L'))
          .fontColor($r('sys.color.font_primary'))
        Scroll() {
          Column() {
            ForEach(this.results, (a: PortStatus, i: number) => {
              Row() {
                Text(a.port.toString())
                  .fontSize($r('sys.float.Body_M'))
                  .fontColor($r('sys.color.font_secondary'))
                Blank().layoutWeight(1)
                Text(a.status === 'open' ? '开放' : '关闭')
                  .fontSize($r('sys.float.Body_M'))
                  .fontColor(a.status === 'open' ? '#388E3C' : '#E57373')
              }
              .padding({ left: 5, right: 5 })
            }, (a: PortStatus, i: number) => a.port.toString())
          }
        }
        .scrollable(ScrollDirection.Vertical)
        .scrollBar(BarState.Auto)
        .scrollBarWidth(1)
        .layoutWeight(1)
        .align(Alignment.Top)
      }
      .layoutWeight(1)
      .borderRadius(10)
      .backgroundColor($r('app.color.setting_block_background'))
    }
    .padding(10)
  }

  scanningProgress() {
    const progress = this.results.length / this.getPorts().length
    return (progress * 100.0).toFixed(0) + '%'
  }

  parseRange(): Range | undefined {
    try {
      const parts = this.range.split('-')
      if (parts.length === 1) {
        const start = parseInt(parts[0])
        return { start, end: start }
      }
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

    this.scanning = true

    try {
      this.results = []

      const ports: number[] = this.getPorts()
      for (let i = 0; i < ports.length && this.scanning; i++) {
        const port = ports[i]
        const open = await this.checkPortOpen(this.address, port)
        this.results.push({ port, status: open ? 'open' : 'closed' })
      }
    } finally {
      this.scanning = false
    }
  }

  aboutToDisappear(): void {
    this.scanning = false
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
      await tcp.connect({ address: { address: address, port: port, family: 1 }, timeout: this.timeout })
      return true
    } catch (e) {
      return false
    } finally {
      await tcp.close()
    }
  }
}