import { fileIo as fs } from '@kit.CoreFileKit'
import { socket } from '@kit.NetworkKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { util } from '@kit.ArkTS'

const DOMAIN = 0x0000
const TAG = 'QmpEventListener'

// QMP 事件类型
export type QmpEventType = 'SHUTDOWN' | 'RESET' | 'STOP' | 'RESUME' | 'POWERDOWN' | 'GUEST_PANICKED' | 'UNKNOWN'

// QMP 事件数据接口
export interface QmpEventData {
  guest?: boolean
  reason?: string
}

// QMP 时间戳接口
interface QmpTimestamp {
  seconds: number
  microseconds: number
}

// QMP 事件接口
interface QmpEvent {
  event: string
  data?: QmpEventData
  timestamp?: QmpTimestamp
}

// QMP 响应接口
interface QmpMessage {
  event?: string
  data?: QmpEventData
  return?: Record<string, Object>
  error?: Record<string, Object>
  QMP?: Record<string, Object>
  timestamp?: QmpTimestamp
}

// QMP 状态查询结果
interface QmpStatusResult {
  status: string
  running: boolean
  singlestep: boolean
}

// QMP 请求接口
interface QmpRequest {
  execute: string
}

// 事件回调类型
export type QmpEventCallback = (event: QmpEventType, data: QmpEventData | undefined) => void

/**
 * QMP 事件监听器
 * 用于监听 QEMU 虚拟机的状态事件（如关机、重启等）
 * 
 * 使用方式：
 * 1. 创建实例：const listener = new QmpEventListener(socketPath)
 * 2. 设置回调：listener.onEvent = (event, data) => { ... }
 * 3. 启动监听：await listener.start()
 * 4. 停止监听：await listener.stop()
 */
export class QmpEventListener {
  private socketPath: string
  private client: socket.LocalSocket | null = null
  private pendingData: string = ''
  private isRunning: boolean = false
  private isConnected: boolean = false
  private reconnectTimer: number = -1
  private statusCheckTimer: number = -1
  
  // 事件回调
  public onEvent: QmpEventCallback | null = null
  
  // 配置参数
  private reconnectInterval: number = 10000  // 重连间隔增加到 10 秒，减轻 PC 端压力
  private statusCheckInterval: number = 10000  // 状态检查间隔（毫秒）
  private maxReconnectAttempts: number = -1  // 最大重连次数，-1 表示无限
  private reconnectAttempts: number = 0
  
  constructor(socketPath: string) {
    this.socketPath = socketPath
  }
  
  /**
   * 启动事件监听
   */
  async start(): Promise<boolean> {
    if (this.isRunning) {
      hilog.warn(DOMAIN, TAG, '监听器已在运行')
      return true
    }
    
    this.isRunning = true
    this.reconnectAttempts = 0
    
    const connected = await this.connect()
    if (connected) {
      // 启动定期状态检查（作为事件监听的补充）
      this.startStatusCheck()
    }
    
    return connected
  }
  
  /**
   * 停止事件监听
   */
  async stop(): Promise<void> {
    this.isRunning = false
    this.stopReconnectTimer()
    this.stopStatusCheck()
    await this.disconnect()
    hilog.info(DOMAIN, TAG, '事件监听器已停止')
  }
  
  /**
   * 连接到 QMP Socket
   */
  private async connect(): Promise<boolean> {
    try {
      hilog.info(DOMAIN, TAG, '尝试连接 QMP Socket: %{public}s', this.socketPath)
      
      // 检查 socket 文件是否存在
      let socketExists = false
      try {
        socketExists = fs.accessSync(this.socketPath, fs.AccessModeType.EXIST)
      } catch (accessErr) {
        hilog.warn(DOMAIN, TAG, 'accessSync 异常: %{public}s', JSON.stringify(accessErr))
      }
      
      if (!socketExists) {
        hilog.warn(DOMAIN, TAG, 'QMP Socket 文件不存在: %{public}s，将尝试重连', this.socketPath)
        this.scheduleReconnect()
        return false
      }
      
      hilog.info(DOMAIN, TAG, 'QMP Socket 文件存在，开始连接...')
      
      this.client = socket.constructLocalSocketInstance()
      this.pendingData = ''
      
      const connectOptions: socket.LocalConnectOptions = {
        address: {
          address: this.socketPath
        },
        timeout: 3000
      }
      
      await this.client.connect(connectOptions)
      
      // 设置消息接收监听器
      this.client.on('message', (value: socket.LocalSocketMessageInfo): void => {
        this.onMessage(value)
      })
      
      // 设置错误监听器
      this.client.on('error', (err: Error): void => {
        hilog.error(DOMAIN, TAG, 'Socket 错误: %{public}s', err.message)
        this.handleDisconnect()
      })
      
      // 设置关闭监听器
      this.client.on('close', (): void => {
        hilog.info(DOMAIN, TAG, 'Socket 连接已关闭')
        this.handleDisconnect()
      })
      
      hilog.info(DOMAIN, TAG, '已连接到 QMP Socket: %{public}s', this.socketPath)
      
      // 等待 Greeting
      const greeting = await this.waitForGreeting()
      if (!greeting) {
        hilog.error(DOMAIN, TAG, '未收到 QMP Greeting')
        await this.disconnect()
        this.scheduleReconnect()
        return false
      }
      
      // 发送 qmp_capabilities 完成握手
      const capResult = await this.sendCommand('qmp_capabilities')
      if (!capResult) {
        hilog.error(DOMAIN, TAG, 'QMP 握手失败')
        await this.disconnect()
        this.scheduleReconnect()
        return false
      }
      
      this.isConnected = true
      this.reconnectAttempts = 0
      hilog.info(DOMAIN, TAG, 'QMP 事件监听器握手成功')
      
      return true
    } catch (e) {
      hilog.error(DOMAIN, TAG, '连接 QMP 失败: %{public}s', JSON.stringify(e))
      await this.disconnect()
      this.scheduleReconnect()
      return false
    }
  }
  
  /**
   * 断开连接
   */
  private async disconnect(): Promise<void> {
    this.isConnected = false
    if (this.client) {
      try {
        this.client.off('message')
        this.client.off('error')
        this.client.off('close')
        await this.client.close()
      } catch (e) {
        // 忽略关闭错误
      } finally {
        this.client = null
        this.pendingData = ''
      }
    }
  }
  
  /**
   * 处理断开连接
   */
  private handleDisconnect(): void {
    this.isConnected = false
    if (this.isRunning) {
      hilog.info(DOMAIN, TAG, '连接断开，准备重连...')
      this.scheduleReconnect()
    }
  }
  
  /**
   * 调度重连
   */
  private scheduleReconnect(): void {
    if (!this.isRunning) return
    
    if (this.maxReconnectAttempts !== -1 && this.reconnectAttempts >= this.maxReconnectAttempts) {
      hilog.warn(DOMAIN, TAG, '达到最大重连次数，停止重连')
      return
    }
    
    this.stopReconnectTimer()
    this.reconnectAttempts++
    
    hilog.info(DOMAIN, TAG, '将在 %{public}d 毫秒后尝试重连 (第 %{public}d 次)', 
               this.reconnectInterval, this.reconnectAttempts)
    
    this.reconnectTimer = setTimeout(async (): Promise<void> => {
      if (this.isRunning) {
        await this.connect()
      }
    }, this.reconnectInterval)
  }
  
  /**
   * 停止重连定时器
   */
  private stopReconnectTimer(): void {
    if (this.reconnectTimer !== -1) {
      clearTimeout(this.reconnectTimer)
      this.reconnectTimer = -1
    }
  }
  
  /**
   * 处理收到的消息
   */
  private onMessage(value: socket.LocalSocketMessageInfo): void {
    const decoder: util.TextDecoder = util.TextDecoder.create('utf-8')
    const message: string = decoder.decodeToString(new Uint8Array(value.message))
    this.pendingData += message
    
    // 只有在握手完成后才自动处理消息（事件）
    // 握手期间的消息由 waitForGreeting 和 sendCommand 手动从 pendingData 中提取
    if (this.isConnected) {
      this.processMessages()
    }
  }
  
  /**
   * 处理缓冲区中的消息
   */
  private processMessages(): void {
    while (true) {
      const lineEndIndex = this.pendingData.indexOf('\n')
      if (lineEndIndex === -1) break
      
      const line = this.pendingData.substring(0, lineEndIndex).trim()
      this.pendingData = this.pendingData.substring(lineEndIndex + 1)
      
      if (line.length > 0) {
        this.parseMessage(line)
      }
    }
  }
  
  /**
   * 解析单条消息
   */
  private parseMessage(line: string): void {
    try {
      const msg: QmpMessage = JSON.parse(line) as QmpMessage
      
      // 检查是否是事件
      if (msg.event) {
        this.handleEvent(msg.event, msg.data)
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'JSON 解析失败: %{public}s', line)
    }
  }
  
  /**
   * 处理 QMP 事件
   */
  private handleEvent(eventName: string, data?: QmpEventData): void {
    hilog.info(DOMAIN, TAG, '===== 收到 QMP 事件 =====')
    hilog.info(DOMAIN, TAG, '事件名称: %{public}s', eventName)
    hilog.info(DOMAIN, TAG, '事件数据: %{public}s', JSON.stringify(data))
    
    let eventType: QmpEventType
    
    switch (eventName) {
      case 'SHUTDOWN':
        eventType = 'SHUTDOWN'
        hilog.info(DOMAIN, TAG, '检测到 SHUTDOWN 事件！')
        break
      case 'RESET':
        eventType = 'RESET'
        break
      case 'STOP':
        eventType = 'STOP'
        break
      case 'RESUME':
        eventType = 'RESUME'
        break
      case 'POWERDOWN':
        eventType = 'POWERDOWN'
        hilog.info(DOMAIN, TAG, '检测到 POWERDOWN 事件！')
        break
      case 'GUEST_PANICKED':
        eventType = 'GUEST_PANICKED'
        break
      default:
        eventType = 'UNKNOWN'
        hilog.info(DOMAIN, TAG, '未知事件类型: %{public}s', eventName)
    }
    
    // 调用回调
    if (this.onEvent) {
      hilog.info(DOMAIN, TAG, '调用事件回调，事件类型: %{public}s', eventType)
      this.onEvent(eventType, data)
    }
  }
  
  /**
   * 等待 Greeting
   */
  private async waitForGreeting(): Promise<boolean> {
    const timeout = 10000 // 增加到 10 秒，解决 PC 端响应慢的问题
    const startTime = Date.now()
    
    while (Date.now() - startTime < timeout) {
      const lineEndIndex = this.pendingData.indexOf('\n')
      if (lineEndIndex !== -1) {
        const line = this.pendingData.substring(0, lineEndIndex).trim()
        this.pendingData = this.pendingData.substring(lineEndIndex + 1)
        
        if (line.length > 0) {
          try {
            const msg: QmpMessage = JSON.parse(line) as QmpMessage
            if (msg.QMP) {
              return true
            }
          } catch (e) {
            continue
          }
        }
      }
      
      await new Promise<void>((resolve: () => void) => setTimeout(resolve, 50))
    }
    
    return false
  }
  
  /**
   * 发送 QMP 命令
   */
  private async sendCommand(command: string): Promise<boolean> {
    if (!this.client) return false
    
    try {
      const request: QmpRequest = { execute: command }
      const requestJson = JSON.stringify(request) + '\n'
      const encoder = util.TextEncoder.create()
      const buffer = encoder.encodeInto(requestJson)
      
      const sendOptions: socket.LocalSendOptions = {
        data: buffer.buffer,
        encoding: 'utf-8'
      }
      
      await this.client.send(sendOptions)
      
      // 等待响应
      const timeout = 3000
      const startTime = Date.now()
      
      while (Date.now() - startTime < timeout) {
        const lineEndIndex = this.pendingData.indexOf('\n')
        if (lineEndIndex !== -1) {
          const line = this.pendingData.substring(0, lineEndIndex).trim()
          this.pendingData = this.pendingData.substring(lineEndIndex + 1)
          
          if (line.length > 0) {
            try {
              const msg: QmpMessage = JSON.parse(line) as QmpMessage
              if (msg.return !== undefined) {
                return true
              }
              if (msg.error) {
                return false
              }
              // 如果是事件，处理它但继续等待响应
              if (msg.event) {
                this.handleEvent(msg.event, msg.data)
              }
            } catch (e) {
              continue
            }
          }
        }
        
        await new Promise<void>((resolve: () => void) => setTimeout(resolve, 50))
      }
      
      return false
    } catch (e) {
      hilog.error(DOMAIN, TAG, '发送命令失败: %{public}s', JSON.stringify(e))
      return false
    }
  }
  
  /**
   * 查询虚拟机状态
   */
  async queryStatus(): Promise<QmpStatusResult | null> {
    if (!this.client || !this.isConnected) return null
    
    try {
      const request: QmpRequest = { execute: 'query-status' }
      const requestJson = JSON.stringify(request) + '\n'
      const encoder = util.TextEncoder.create()
      const buffer = encoder.encodeInto(requestJson)
      
      const sendOptions: socket.LocalSendOptions = {
        data: buffer.buffer,
        encoding: 'utf-8'
      }
      
      await this.client.send(sendOptions)
      
      // 等待响应
      const timeout = 3000
      const startTime = Date.now()
      
      while (Date.now() - startTime < timeout) {
        const lineEndIndex = this.pendingData.indexOf('\n')
        if (lineEndIndex !== -1) {
          const line = this.pendingData.substring(0, lineEndIndex).trim()
          this.pendingData = this.pendingData.substring(lineEndIndex + 1)
          
          if (line.length > 0) {
            try {
              const msg: QmpMessage = JSON.parse(line) as QmpMessage
              if (msg.return !== undefined) {
                const result: QmpStatusResult = {
                  status: (msg.return as Record<string, Object>)['status'] as string || '',
                  running: (msg.return as Record<string, Object>)['running'] as boolean || false,
                  singlestep: (msg.return as Record<string, Object>)['singlestep'] as boolean || false
                }
                return result
              }
              if (msg.error) {
                return null
              }
              // 如果是事件，处理它但继续等待响应
              if (msg.event) {
                this.handleEvent(msg.event, msg.data)
              }
            } catch (e) {
              continue
            }
          }
        }
        
        await new Promise<void>((resolve: () => void) => setTimeout(resolve, 50))
      }
      
      return null
    } catch (e) {
      hilog.error(DOMAIN, TAG, '查询状态失败: %{public}s', JSON.stringify(e))
      return null
    }
  }
  
  /**
   * 启动定期状态检查
   */
  private startStatusCheck(): void {
    this.stopStatusCheck()
    
    hilog.info(DOMAIN, TAG, '启动定期状态检查，间隔: %{public}d ms', this.statusCheckInterval)
    
    this.statusCheckTimer = setInterval(async (): Promise<void> => {
      if (!this.isRunning || !this.isConnected) {
        hilog.debug(DOMAIN, TAG, '跳过状态检查: isRunning=%{public}s, isConnected=%{public}s',
                    this.isRunning.toString(), this.isConnected.toString())
        return
      }
      
      hilog.info(DOMAIN, TAG, '执行定期状态查询...')
      const status = await this.queryStatus()
      if (status) {
        hilog.info(DOMAIN, TAG, '虚拟机状态: status=%{public}s, running=%{public}s', 
                   status.status, status.running.toString())
        
        // 如果虚拟机处于关机状态
        if (status.status === 'shutdown' && !status.running) {
          hilog.info(DOMAIN, TAG, '===== 通过状态检查检测到虚拟机已关机 =====')
          if (this.onEvent) {
            const eventData: QmpEventData = { guest: true, reason: 'status-check' }
            this.onEvent('SHUTDOWN', eventData)
          }
        }
      } else {
        hilog.warn(DOMAIN, TAG, '状态查询返回 null')
      }
    }, this.statusCheckInterval)
  }
  
  /**
   * 停止定期状态检查
   */
  private stopStatusCheck(): void {
    if (this.statusCheckTimer !== -1) {
      clearInterval(this.statusCheckTimer)
      this.statusCheckTimer = -1
    }
  }
  
  /**
   * 检查是否已连接
   */
  isAlive(): boolean {
    return this.isConnected
  }
}

// 全局单例实例
let globalListener: QmpEventListener | null = null

/**
 * 获取全局 QMP 事件监听器实例
 */
export function getQmpEventListener(): QmpEventListener | null {
  return globalListener
}

/**
 * 启动全局 QMP 事件监听
 * @param socketPath QMP socket 路径
 * @param onEvent 事件回调
 */
export async function startQmpEventListener(
  socketPath: string, 
  onEvent: QmpEventCallback
): Promise<boolean> {
  // 如果已有监听器在运行，先停止
  if (globalListener) {
    await globalListener.stop()
  }
  
  globalListener = new QmpEventListener(socketPath)
  globalListener.onEvent = onEvent
  
  return await globalListener.start()
}

/**
 * 停止全局 QMP 事件监听
 */
export async function stopQmpEventListener(): Promise<void> {
  if (globalListener) {
    await globalListener.stop()
    globalListener = null
  }
}

export default QmpEventListener
