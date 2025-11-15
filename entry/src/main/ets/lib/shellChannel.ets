import { fileIo as fs } from '@kit.CoreFileKit'
import { buffer, util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { socket } from '@kit.NetworkKit';

const sleep = (ms: number): Promise<void> => {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function stringToArrayBuffer(str: string, encoding: buffer.BufferEncoding = 'utf-8'): ArrayBuffer {
  const buf = buffer.from(str, encoding);
  return buf.buffer;
}

interface RunResult {
  code: number
  content: string
}

class ShellChannel {
  private decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { ignoreBOM: true })
  private buffer: string = ''
  private resolves: ((s: string) => void)[] = []
  private contents: string[] = []
  private socket?: socket.LocalSocket

  async connect(us: string) {
    this.socket = socket.constructLocalSocketInstance()
    while (true) {
      const exist = await fs.access(us, fs.AccessModeType.EXIST)
      if (!exist) {
        await sleep(10)
      } else {
        break
      }
    }
    await this.socket.connect({ address: { address: us } })
    this.socket.on('message', (info) => {
      const buf = info.message
      const chunk = this.decoder.decodeToString(new Uint8Array(buf), { stream: true })
      for (let i = 0; i < chunk.length; i++) {
        const c = chunk.charAt(i)
        this.processChar(c)
      }
    })
  }

  async send(s: string) {
    hilog.info(1, "ShellChannel", "content sent: '%{public}s'", s)
    const buf = stringToArrayBuffer(s)
    await this.socket?.send({ data: buf })
  }

  async wait(): Promise<string> {
    return new Promise<string>((resolve) => {
      this.resolves.push(resolve)
      this.notify()
    })
  }

  async run(cmd: string): Promise<RunResult> {
    await this.send(cmd + '\n')
    const content = await this.wait()
    await this.send('echo $?\n')
    const code = await this.wait()
    return {
      code: parseInt(code),
      content
    }
  }

  private processChar(c: string) {
    this.buffer = this.buffer + c
    if (this.buffer.endsWith('\x1b[6n')) {

      const end = this.buffer.lastIndexOf('\x0d\x0a')
      const start = this.buffer.indexOf('\x0d\x0a')
      const content = this.buffer.substring(Math.max(0, start), end).trim()
      this.buffer = ''
      this.send('\x1b[1;9R')

      hilog.info(1, "ShellChannel", "content received: '%{public}s'", content)
      this.contents.push(content)

      this.notify()
    }
  }

  private notify() {
    while (this.resolves.length > 0 && this.contents.length > 0) {
      const resolve = this.resolves.shift()!!
      const content = this.contents.shift()!!
      resolve(content)
    }
  }
}

export { ShellChannel }
