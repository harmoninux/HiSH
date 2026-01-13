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

interface QmpError {
  class: string
  desc: string
}

// QMP JSON-RPC 响应接口
interface QmpResponse {
  return?: Record<string, Object>
  error?: QmpError
  QMP?: Record<string, Object> // 握手时的 Greeting
  event?: string               // 异步事件消息
  id?: number                  // 关联请求的 ID
}

/**
 * QEMU Monitor Protocol (QMP) 客户端
 * 用于控制 QEMU 实例，例如唤醒挂起的虚拟机
 */
export class QmpClient {
  private socketPath: string
  private client: socket.LocalSocket | null = null
  private pendingResponse: string = ''
  private idCounter: number = 0
  private responseCallbacks: Map<number, (res: QmpResponse) => void> = new Map()
  private isConnected: boolean = false

  constructor(socketPath: string) {
    this.socketPath = socketPath
  }

  private greetingResolver: ((success: boolean) => void) | null = null

  /**
   * 建立连接并完成握手
   * 支持长连接：如果已连且正常，直接返回 true
   */
  async connect(greetingTimeout: number = 3000): Promise<boolean> {
    if (this.client && this.isConnected) {
      return true
    }

    // 先清理旧状态
    await this.disconnect()

    try {
      this.client = socket.constructLocalSocketInstance()
      this.pendingResponse = ''
      this.greetingResolver = null

      // 核心监听逻辑：必须在 connect 之前注册，防止丢失首包 Greeting
      this.client.on('message', (value: socket.LocalSocketMessageInfo): void => {
        const decoder: util.TextDecoder = util.TextDecoder.create('utf-8')
        const message: string = decoder.decodeToString(new Uint8Array(value.message))
        this.pendingResponse += message

        // 1. 优先实时触发 Greeting 检测
        if (this.greetingResolver && (this.pendingResponse.includes('"QMP":') || this.pendingResponse.includes('"QMP" :'))) {
          const resolver = this.greetingResolver
          this.greetingResolver = null
          resolver(true)
        }

        this.processBuffer()
      })

      this.client.on('error', (err: ESObject): void => {
        hilog.error(DOMAIN, 'QmpClient', 'Socket Error: %{public}s', JSON.stringify(err))
        if (this.greetingResolver) {
          this.greetingResolver(false)
          this.greetingResolver = null
        }
        this.handleSocketClose()
      })

      this.client.on('close', (): void => {
        hilog.debug(DOMAIN, 'QmpClient', 'Socket Closed')
        if (this.greetingResolver) {
          this.greetingResolver(false)
          this.greetingResolver = null
        }
        this.handleSocketClose()
      })

      const connectOptions: socket.LocalConnectOptions = {
        address: { address: this.socketPath },
        timeout: 1500 // 连接建立超时设为 1.5s
      }

      await this.client.connect(connectOptions)

      // 1. 等待握手问候 (Greeting)
      const handshakeStart = Date.now()
      const greeting = await new Promise<boolean>((resolve) => {
        this.greetingResolver = resolve
        // 检查是否已经收到了（因为 message 回调可能在 await connect 之前就触发了）
        if (this.pendingResponse.includes('QMP')) {
          this.greetingResolver(true)
          this.greetingResolver = null
        }
        // 指令级硬超时
        setTimeout(() => {
          if (this.greetingResolver) {
            this.greetingResolver(false)
            this.greetingResolver = null
          }
        }, greetingTimeout)
      })

      if (!greeting) {
        hilog.error(DOMAIN, 'QmpClient', 'Handshake Failed: No Greeting after %{public}dms', Date.now() - handshakeStart)
        await this.disconnect()
        return false
      }

      // 2. 发送 Capabilities 启用 QMP 模式
      const capResult = await this.sendCommand('qmp_capabilities')
      if (!capResult) {
        hilog.error(DOMAIN, 'QmpClient', 'Capabilities negotiation failed')
        await this.disconnect()
        return false
      }

      this.isConnected = true
      hilog.info(DOMAIN, 'QmpClient', 'Connected and ready: %{public}s', this.socketPath)
      return true
    } catch (e) {
      hilog.error(DOMAIN, 'QmpClient', 'Connection Exception: %{public}s', JSON.stringify(e))
      await this.disconnect()
      return false
    }
  }

  private handleSocketClose() {
    this.isConnected = false
    this.client = null
    // 唤醒所有挂起的 Promise 并告知失败
    const errorResponse: QmpResponse = {
      error: {
        class: 'GenericError',
        desc: 'Connection lost'
      } as QmpError
    }
    this.responseCallbacks.forEach((callback) => {
      callback(errorResponse)
    })
    this.responseCallbacks.clear()
  }

  async disconnect(): Promise<void> {
    this.isConnected = false
    if (this.client) {
      const socket = this.client
      this.client = null // 提前断开引用
      try {
        socket.off('message')
        socket.off('error')
        socket.off('close')
        await socket.close()
      } catch (e) {
        hilog.warn(DOMAIN, 'QmpClient', 'Disconnect exception: %{public}s', JSON.stringify(e))
      }
    }
    this.pendingResponse = ''
  }

  /**
   * 发送命令并等待指定回执 (核心 API)
   */
  public async sendCommand(command: string, args?: Record<string, Object>): Promise<Record<string, Object> | null> {
    if (!this.client) {
      hilog.error(DOMAIN, 'QmpClient', 'No connection for %{public}s', command)
      return null
    }

    const requestId = ++this.idCounter
    const request: QmpRequest = {
      execute: command,
      arguments: args,
      id: requestId
    }

    return new Promise<Record<string, Object> | null>((resolve) => {
      // 1. 注册响应监听
      const timeoutTimer = setTimeout(() => {
        if (this.responseCallbacks.has(requestId)) {
          this.responseCallbacks.delete(requestId)
          hilog.warn(DOMAIN, 'QmpClient', 'Command Timeout: %{public}s (ID: %{public}d)', command, requestId)
          resolve(null)
        }
      }, 8000) // 8秒硬超时

      this.responseCallbacks.set(requestId, (response: QmpResponse) => {
        clearTimeout(timeoutTimer)
        if (response.error) {
          hilog.error(DOMAIN, 'QmpClient', 'QMP Error for %{public}s: %{public}s', command, JSON.stringify(response.error))
          resolve(null)
        } else {
          resolve(response.return || {})
        }
      })

      // 2. 实际发送
      try {
        const json = JSON.stringify(request) + '\n'
        const buffer = util.TextEncoder.create().encodeInto(json)
        const sendOptions: socket.LocalSendOptions = {
          data: buffer.buffer,
          encoding: 'utf-8'
        }
        this.client!.send(sendOptions).catch((err: ESObject) => {
          hilog.error(DOMAIN, 'QmpClient', 'Send Failed: %{public}s', JSON.stringify(err))
          if (this.responseCallbacks.has(requestId)) {
            this.responseCallbacks.delete(requestId)
            clearTimeout(timeoutTimer)
            resolve(null)
          }
        })
      } catch (e) {
        this.responseCallbacks.delete(requestId)
        clearTimeout(timeoutTimer)
        resolve(null)
      }
    })
  }

  /**
   * 缓冲区解析与响应路由
   */
  private processBuffer() {
    let lineEndIndex: number
    while ((lineEndIndex = this.pendingResponse.indexOf('\n')) !== -1) {
      const line = this.pendingResponse.substring(0, lineEndIndex).trim()
      this.pendingResponse = this.pendingResponse.substring(lineEndIndex + 1)

      if (line.length === 0) continue

      try {
        const parsed = JSON.parse(line) as QmpResponse

        // 分发逻辑
        if (parsed.id !== undefined && typeof parsed.id === 'number') {
          const callback = this.responseCallbacks.get(parsed.id)
          if (callback) {
            this.responseCallbacks.delete(parsed.id)
            callback(parsed)
          }
        } else if (parsed.event) {
          hilog.debug(DOMAIN, 'QmpClient', 'Async Event: %{public}s', parsed.event)
        } else if (parsed.QMP) {
          // 2. 在解析循环中补充触发 Greeting
          if (this.greetingResolver) {
            const resolver = this.greetingResolver
            this.greetingResolver = null
            resolver(true)
          }
          hilog.info(DOMAIN, 'QmpClient', 'Greeting received in parse loop')
        }
      } catch (e) {
        hilog.warn(DOMAIN, 'QmpClient', 'Malformed JSON: %{public}s', line)
      }
    }
  }


  async getStatus(): Promise<QmpStatusResult | null> {
    const result = await this.sendCommand('query-status')
    if (result) {
      return {
        status: result['status'] as 'debug' | 'inmigrate' | 'internal-error' | 'io-error' | 'paused' | 'postmigrate' | 'prelaunch' | 'finish-migrate' | 'restore-vm' | 'running' | 'save-vm' | 'shutdown' | 'suspended' | 'watchdog' | 'guest-panicked' | 'colo',
        running: result['running'] as boolean,
        singlestep: result['singlestep'] as boolean
      } as QmpStatusResult
    }
    return null
  }

  // 快捷业务指令
  async systemWakeup(): Promise<boolean> { return (await this.sendCommand('system_wakeup')) !== null }
  async stop(): Promise<boolean> { return (await this.sendCommand('stop')) !== null }
  async cont(): Promise<boolean> { return (await this.sendCommand('cont')) !== null }
  async systemReset(): Promise<boolean> { return (await this.sendCommand('system_reset')) !== null }
  async quit(): Promise<boolean> { return (await this.sendCommand('quit')) !== null }
}

export default QmpClient

// 导出状态接口
export interface QmpStatusResult {
  status: 'debug' | 'inmigrate' | 'internal-error' | 'io-error' | 'paused' | 'postmigrate' | 'prelaunch' | 'finish-migrate' | 'restore-vm' | 'running' | 'save-vm' | 'shutdown' | 'suspended' | 'watchdog' | 'guest-panicked' | 'colo'
  running: boolean
  singlestep: boolean
}
