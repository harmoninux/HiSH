import { fileIo as fs } from '@kit.CoreFileKit'
import { socket } from '@kit.NetworkKit'

const sleep = (ms: number): Promise<void> => {
  return new Promise(resolve => setTimeout(resolve, ms));
}

class SerialChannel {
  private buffer: ArrayBuffer[]
  private socket?: socket.LocalSocket
  private receiver: ((buf: ArrayBuffer) => void)[]

  constructor() {
    this.buffer = []
    this.receiver = []
  }

  async connect(socketPath: string) {
    this.socket = socket.constructLocalSocketInstance()
    while (true) {
      const exist = await fs.access(socketPath, fs.AccessModeType.EXIST)
      if (!exist) {
        await sleep(10)
      } else {
        break
      }
    }
    await this.socket.connect({ address: { address: socketPath } })
    this.socket.on('message', info => {
      if (this.receiver?.length > 0) {
        this.receiver.forEach(c => c(info.message))
      } else {
        this.buffer.push(info.message)
      }
    })
  }

  onMessage(receiver: (buf: ArrayBuffer) => void) {
    this.receiver.push(receiver)
    if (this.buffer.length > 0 && this.receiver.length === 1) {
      this.buffer.forEach(it => receiver(it))
      this.buffer.splice(0, this.buffer.length)
    }
  }

  async sendMessage(buf: ArrayBuffer) {
    return await this.socket!!.send({ data: buf })
  }
}

export default SerialChannel