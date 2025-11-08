import { socket } from "@kit.NetworkKit"
import { hilog } from "@kit.PerformanceAnalysisKit"
import { util } from "@kit.ArkTS"

@Component
export default struct QemuMonitor {
  tempDir = this.getUIContext().getHostContext()!!.getApplicationContext().tempDir
  localSocket?: socket.LocalSocket = undefined
  utf8Decoder = util.TextDecoder.create('utf-8', { ignoreBOM: true })

  async aboutToAppear(): Promise<void> {
    const socketPath = this.tempDir + '/qmp_socket'
    const local = socket.constructLocalSocketInstance()
    try {
      await local.connect({ address: { address: socketPath }, timeout: 2000 })
      this.localSocket = local
      local.on('message', (info) => {
        const trunk = this.utf8Decoder.decodeToString(new Uint8Array(info.message))
        hilog.info(1, "QemuMonitor", 'info from qmp socket, %{public}s', trunk)
      })
      await local.send({ data: '{ "execute": "qmp_capabilities" }\n' })
      await local.send({ data: '{ "execute": "query-status" }\n' })
      await local.send({ data: '{ "execute": "query-commands" }\n' })
      setInterval(async () => {
        await local.send({ data: '{ "execute": "query-cpus-fast" }\n' })
        await local.send({ data: '{ "execute": "query-memory-size-summary" }\n' })
      }, 2000)
    } catch (e) {
      hilog.error(1, "QemuMonitor", "qmp socket failed, %{public}s", e)
    }
  }

  async aboutToDisappear(): Promise<void> {
    try {
      await this.localSocket?.close()
    } catch (e) {
      hilog.error(1, "QemuMonitor", "close qmp socket failed, %{public}s", e)
    }
  }

  build() {
    Column() {
    }
  }
}