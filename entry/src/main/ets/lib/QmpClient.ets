import { fileIo as fs } from '@kit.CoreFileKit'
import { socket } from '@kit.NetworkKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { util } from '@kit.ArkTS'

const DOMAIN = 0x0000

// QMP JSON-RPC 请求接口
interface QmpRequest {
  execute: string
  arguments?: Record<string, Object>
  id?: number
}

// QMP JSON-RPC 响应接口
interface QmpResponse {
  return?: Record<string, Object>
  error?: Record<string, Object>
  QMP?: Record<string, Object> // 握手时的 Greeting
}

/**
 * QEMU Monitor Protocol (QMP) 客户端
 * 用于控制 QEMU 实例，例如唤醒挂起的虚拟机
 */
export class QmpClient {
  private socketPath: string
  private client: socket.LocalSocket | null = null
  private pendingResponse: string = ''

  constructor(socketPath: string) {
    this.socketPath = socketPath
  }

  /**
   * 连接到 QMP LocalSocket 并完成握手
   */
  async connect(): Promise<boolean> {
    try {
      // if (!fs.accessSync(this.socketPath, fs.AccessModeType.EXIST)) {
      //   hilog.error(DOMAIN, 'QmpClient', 'Socket 文件不存在: %{public}s', this.socketPath)
      //   return false
      // }

      this.client = socket.constructLocalSocketInstance()
      
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
      
      hilog.info(DOMAIN, 'QmpClient', '已连接到 QMP Socket: %{public}s', this.socketPath)

      // 1. 等待 Greeting
      const greeting = await this.waitForResponse()
      if (!greeting || !greeting.QMP) {
        hilog.error(DOMAIN, 'QmpClient', '未收到 QMP Greeting')
        return false
      }

      // 2. 发送 qmp_capabilities
      const capResult = await this.sendCommand('qmp_capabilities')
      if (!capResult) {
        hilog.error(DOMAIN, 'QmpClient', 'QMP 握手失败')
        return false
      }

      return true
    } catch (e) {
      hilog.error(DOMAIN, 'QmpClient', '连接 QMP 失败: %{public}s', JSON.stringify(e))
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
      hilog.info(DOMAIN, 'QmpClient', 'QMP 连接已断开')
    }
  }

  /**
   * 发送 system_wakeup 命令
   */
  async systemWakeup(): Promise<boolean> {
    const result = await this.sendCommand('system_wakeup')
    return result !== null
  }

  /**
   * 暂停虚拟机 (stop)
   */
  async stop(): Promise<boolean> {
    const result = await this.sendCommand('stop')
    return result !== null
  }

  /**
   * 恢复虚拟机 (cont)
   */
  async cont(): Promise<boolean> {
    const result = await this.sendCommand('cont')
    return result !== null
  }

  /**
   * 向 QMP 发送命令
   */
  private async sendCommand(command: string, args?: Record<string, Object>): Promise<Record<string, Object> | null> {
    if (!this.client) {
      hilog.error(DOMAIN, 'QmpClient', '未连接到 QMP')
      return null
    }

    try {
      const request: QmpRequest = {
        execute: command,
        arguments: args
      }

      const requestJson = JSON.stringify(request) + '\n'
      const encoder = util.TextEncoder.create()
      const buffer = encoder.encodeInto(requestJson)

      const sendOptions: socket.LocalSendOptions = {
        data: buffer.buffer,
        encoding: 'utf-8'
      }
      
      await this.client.send(sendOptions)
      hilog.info(DOMAIN, 'QmpClient', '发送命令: %{public}s', command)

      const response = await this.waitForResponse()
      if (!response) {
        return null
      }

      if (response.error) {
        hilog.error(DOMAIN, 'QmpClient', 'QMP 错误: %{public}s', JSON.stringify(response.error))
        return null
      }

      return response.return || {}
    } catch (e) {
      hilog.error(DOMAIN, 'QmpClient', '发送命令失败: %{public}s', JSON.stringify(e))
      return null
    }
  }

  /**
   * 等待响应
   */
  private async waitForResponse(): Promise<QmpResponse | null> {
    const startTime: number = Date.now()
    const timeout: number = 10000
    
    while (Date.now() - startTime < timeout) {
      // 检查缓冲区是否有完整行
      const lineEndIndex = this.pendingResponse.indexOf('\n')
      if (lineEndIndex !== -1) {
        const line = this.pendingResponse.substring(0, lineEndIndex).trim()
        this.pendingResponse = this.pendingResponse.substring(lineEndIndex + 1)
        
        if (line.length > 0) {
          try {
            return JSON.parse(line) as QmpResponse
          } catch (e) {
            hilog.warn(DOMAIN, 'QmpClient', 'JSON解析失败: %{public}s', line)
            // 继续处理下一行
            continue
          }
        } else {
            // 空行，继续
            continue
        }
      }
      
      // 没有完整行，等待更多数据
      await new Promise<void>((resolve: () => void) => setTimeout(resolve, 10))
    }
    
    hilog.error(DOMAIN, 'QmpClient', '等待响应超时')
    return null
  }
}

export default QmpClient
