import { fileIo as fs } from '@kit.CoreFileKit'
import { socket } from '@kit.NetworkKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { util } from '@kit.ArkTS'

const DOMAIN = 0x0000

// QGA JSON-RPC 请求接口
interface QGARequest {
  execute: string
  arguments?: QGAArguments
  id: number
}

// QGA 参数类型
interface QGAArguments {
  mode?: string
}

// QGA JSON-RPC 响应接口  
interface QGAResponse {
  return?: ESObject
  error?: QGAError
}

interface QGAError {
  class: string
  desc: string
}

/**
 * QEMU Guest Agent 客户端
 * 通过 LocalSocket 与虚拟机内的 qemu-guest-agent 通信
 */
export class QemuAgent {
  private socketPath: string
  private client: socket.LocalSocket | null = null
  private requestId: number = 0
  private pendingResponse: string = ''

  constructor(socketPath: string) {
    this.socketPath = socketPath
  }

  /**
   * 连接到 QGA LocalSocket
   */
  async connect(): Promise<boolean> {
    try {
      if (!fs.accessSync(this.socketPath, fs.AccessModeType.EXIST)) {
        hilog.error(DOMAIN, 'QemuAgent', 'Socket 文件不存在: %{public}s', this.socketPath)
        return false
      }

      this.client = socket.constructLocalSocketInstance()
      
      // LocalSocket connect 需要 LocalConnectOptions
      const connectOptions: socket.LocalConnectOptions = {
        address: {
          address: this.socketPath
        },
        timeout: 5000
      }
      
      await this.client.connect(connectOptions)
      
      // 设置消息接收监听器
      this.client.on('message', (value: socket.LocalSocketMessageInfo): void => {
        const decoder: util.TextDecoder = util.TextDecoder.create('utf-8')
        const message: string = decoder.decodeToString(new Uint8Array(value.message))
        this.pendingResponse += message
      })
      
      hilog.info(DOMAIN, 'QemuAgent', '已连接到 QGA: %{public}s', this.socketPath)
      return true
    } catch (e) {
      hilog.error(DOMAIN, 'QemuAgent', '连接 QGA 失败: %{public}s', JSON.stringify(e))
      return false
    }
  }

  /**
   * 断开连接
   */
  async disconnect(): Promise<void> {
    if (this.client) {
      await this.client.close()
      this.client = null
      hilog.info(DOMAIN, 'QemuAgent', 'QGA 连接已断开')
    }
  }

  /**
   * 向 QGA 发送 JSON-RPC 命令
   */
  private async sendCommand(command: string, args?: QGAArguments, waitForResponse: boolean = true): Promise<ESObject | null> {
    if (!this.client) {
      hilog.error(DOMAIN, 'QemuAgent', '未连接到 QGA')
      return null
    }

    try {
      const request: QGARequest = {
        execute: command,
        arguments: args,
        id: ++this.requestId
      }

      const requestJson = JSON.stringify(request) + '\n'
      const encoder = util.TextEncoder.create()
      const buffer = encoder.encodeInto(requestJson)

      // LocalSocket send 需要 LocalSendOptions
      const sendOptions: socket.LocalSendOptions = {
        data: buffer.buffer,
        encoding: 'utf-8'
      }
      
      await this.client.send(sendOptions)
      hilog.info(DOMAIN, 'QemuAgent', '发送命令: %{public}s', command)

      if (!waitForResponse) {
        return {}
      }

      // 等待响应（简单的轮询，实际应用中可以使用 Promise）
      const startTime: number = Date.now()
      const timeout: number = 5000
      this.pendingResponse = ''
      
      while (!this.pendingResponse.includes('\n') && (Date.now() - startTime < timeout)) {
        await new Promise<void>((resolve: () => void) => setTimeout(resolve, 10))
      }
      
      if (!this.pendingResponse) {
        hilog.error(DOMAIN, 'QemuAgent', '等待响应超时')
        return null
      }

      const result: QGAResponse = JSON.parse(this.pendingResponse.trim()) as QGAResponse
      this.pendingResponse = ''
      
      if (result.error) {
        hilog.error(DOMAIN, 'QemuAgent', 'QGA 错误: %{public}s', JSON.stringify(result.error))
        return null
      }

      return result.return || {}
    } catch (e) {
      hilog.error(DOMAIN, 'QemuAgent', '发送命令失败: %{public}s', JSON.stringify(e))
      return null
    }
  }

  /**
   * 关机
   */
  async shutdown(): Promise<boolean> {
    const args: QGAArguments = { mode: 'powerdown' }
    const result: Record<string, Object> | null = await this.sendCommand('guest-shutdown', args, false)
    return result !== null
  }

  /**
   * 重启
   */
  async reboot(): Promise<boolean> {
    const args: QGAArguments = { mode: 'reboot' }
    const result: Record<string, Object> | null = await this.sendCommand('guest-shutdown', args, false)
    return result !== null
  }

  /**
   * 暂停（挂起到 RAM）
   */
  async suspend(): Promise<boolean> {
    const result: ESObject | null = await this.sendCommand('guest-suspend-ram', undefined, false)
    return result !== null
  }

  /**
   * Ping 检查 QGA 是否响应
   */
  async ping(): Promise<boolean> {
    const result: ESObject | null = await this.sendCommand('guest-ping')
    return result !== null
  }

  /**
   * 获取虚拟机信息
   */
  async getInfo(): Promise<ESObject | null> {
    return await this.sendCommand('guest-info')
  }
}

export default QemuAgent
