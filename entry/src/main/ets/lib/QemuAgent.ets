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
  id?: number
  path?: string
  arg?: string[]
  'capture-output'?: boolean
  pid?: number
}

// QGA JSON-RPC 响应接口  
interface QGAResponse {
  return?: ESObject
  error?: QGAError
  id?: number
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
  private isConnected: boolean = false

  constructor(socketPath: string) {
    this.socketPath = socketPath
  }

  /**
   * 连接到 QGA LocalSocket
   * [修复1.2] 连接前完全清理旧状态
   */
  async connect(): Promise<boolean> {
    // 先断开旧连接，确保干净状态
    await this.disconnect()
    
    try {
      if (!fs.accessSync(this.socketPath, fs.AccessModeType.EXIST)) {
        hilog.error(DOMAIN, 'QemuAgent', 'Socket 文件不存在: %{public}s', this.socketPath)
        return false
      }

      this.client = socket.constructLocalSocketInstance()
      this.pendingResponse = ''  // 清理缓冲区
      this.requestId = 0  // 重置请求 ID
      
      const connectOptions: socket.LocalConnectOptions = {
        address: {
          address: this.socketPath
        },
        timeout: 3000  // 3秒连接超时
      }
      
      await this.client.connect(connectOptions)
      
      // 设置消息接收监听器
      this.client.on('message', (value: socket.LocalSocketMessageInfo): void => {
        const decoder: util.TextDecoder = util.TextDecoder.create('utf-8')
        const message: string = decoder.decodeToString(new Uint8Array(value.message))
        this.pendingResponse += message
      })

      // [修复] 监听错误事件
      this.client.on('error', (err: ESObject): void => {
        hilog.error(DOMAIN, 'QemuAgent', 'Socket 错误: %{public}s', JSON.stringify(err))
        this.isConnected = false
      })

      // [修复] 监听关闭事件
      this.client.on('close', (): void => {
        hilog.info(DOMAIN, 'QemuAgent', 'Socket 连接已关闭')
        this.isConnected = false
      })
      
      this.isConnected = true
      hilog.info(DOMAIN, 'QemuAgent', '已连接到 QGA: %{public}s', this.socketPath)
      
      // 连接后立即执行流同步，确保通信可靠
      await this.sync()
      
      return true
    } catch (e) {
      hilog.error(DOMAIN, 'QemuAgent', '连接 QGA 失败: %{public}s', JSON.stringify(e as ESObject))
      await this.disconnect()
      return false
    }
  }

  /**
   * QGA 流同步 (guest-sync-delimited)
   * 发送一个随机数，QGA 会返回相同的随机数，用于清理缓冲区并同步状态
   */
  private async sync(): Promise<boolean> {
    const syncId = Math.floor(Math.random() * 1000000)
    hilog.info(DOMAIN, 'QemuAgent', '执行 QGA 流同步 (id=%{public}d)', syncId)
    
    // 直接构造同步命令，不使用 sendCommand 以免死循环
    const request: QGARequest = { 
      execute: 'guest-sync-delimited', 
      arguments: { id: syncId } as QGAArguments,
      id: syncId 
    }
    const requestJson = JSON.stringify(request) + '\n'
    
    try {
      const encoder = util.TextEncoder.create()
      const buffer = encoder.encodeInto(requestJson)
      await this.client?.send({ data: buffer.buffer, encoding: 'utf-8' })
      
      const startTime = Date.now()
      const timeout = 5000
      
      while (Date.now() - startTime < timeout) {
        if (!this.isConnected) return false
        
        const lineEndIndex = this.pendingResponse.indexOf('\n')
        if (lineEndIndex !== -1) {
          const line = this.pendingResponse.substring(0, lineEndIndex).trim()
          this.pendingResponse = this.pendingResponse.substring(lineEndIndex + 1)
          
          // QGA 同步响应可能包含 0xFF 字节，这里简单判断包含 syncId 即可
          if (line.includes(syncId.toString())) {
            hilog.info(DOMAIN, 'QemuAgent', 'QGA 流同步成功')
            return true
          }
        }
        await new Promise<void>((resolve: () => void) => setTimeout(resolve, 100))
      }
      hilog.warn(DOMAIN, 'QemuAgent', 'QGA 流同步超时')
      return false
    } catch (e) {
      hilog.error(DOMAIN, 'QemuAgent', 'QGA 流同步异常: %{public}s', JSON.stringify(e as ESObject))
      return false
    }
  }

  /**
   * 断开连接
   * [修复1.1] 完全清理：移除监听器、关闭连接、清空缓冲区
   */
  async disconnect(): Promise<void> {
    const client = this.client
    this.client = null // 立即置空，防止重入
    this.isConnected = false
    this.pendingResponse = ''

    if (client) {
      try {
        client.off('message')
        client.off('error')
        client.off('close')
        await client.close()
      } catch (e) {
        // 忽略关闭错误
      }
      hilog.info(DOMAIN, 'QemuAgent', 'QGA 连接已断开')
    }
  }

  /**
   * [修复1.4] 检查连接是否存活
   */
  isAlive(): boolean {
    return this.isConnected && this.client !== null
  }

  /**
   * 向 QGA 发送 JSON-RPC 命令
   * [修复1.3] 改进响应等待逻辑
   */
  private async sendCommand(command: string, args?: QGAArguments, waitForResponse: boolean = true): Promise<ESObject | null> {
    if (!this.client || !this.isConnected) {
      hilog.error(DOMAIN, 'QemuAgent', '发送命令失败：未连接到 QGA (命令: %{public}s)', command)
      return null
    }

    const currentId = ++this.requestId

    try {
      const request: QGARequest = {
        execute: command,
        arguments: args,
        id: currentId
      }

      const requestJson = JSON.stringify(request) + '\n'
      const encoder = util.TextEncoder.create()
      const buffer = encoder.encodeInto(requestJson)

      const sendOptions: socket.LocalSendOptions = {
        data: buffer.buffer,
        encoding: 'utf-8'
      }
      
      // 发送前清空缓冲区（确保读到的是这次请求的响应）
      this.pendingResponse = ''
      
      await this.client.send(sendOptions)
      hilog.info(DOMAIN, 'QemuAgent', '发送命令: %{public}s (id=%{public}d)', command, currentId)

      if (!waitForResponse) {
        return {}
      }

      // 等待响应，使用更合理的超时和间隔
      const startTime: number = Date.now()
      const timeout: number = 10000  // 增加到 10 秒超时，解决 PC 端响应慢的问题
      
      while (Date.now() - startTime < timeout) {
        // 检查连接状态
        if (!this.isConnected) {
          hilog.error(DOMAIN, 'QemuAgent', '等待响应期间连接断开 (命令: %{public}s)', command)
          return null
        }

        // 检查是否有完整的响应行
        const lineEndIndex = this.pendingResponse.indexOf('\n')
        if (lineEndIndex !== -1) {
          const line = this.pendingResponse.substring(0, lineEndIndex).trim()
          this.pendingResponse = this.pendingResponse.substring(lineEndIndex + 1)
          
          if (line.length > 0) {
            try {
              const result: QGAResponse = JSON.parse(line) as QGAResponse
              
              // 检查响应 ID 是否匹配（如果响应包含 ID）
              if (result.id !== undefined && result.id !== currentId) {
                hilog.warn(DOMAIN, 'QemuAgent', '收到过时响应: 期望 %{public}d, 收到 %{public}d (内容: %{public}s)', currentId, result.id, line)
                continue  // 跳过不匹配的响应
              }
              
              if (result.error) {
                hilog.error(DOMAIN, 'QemuAgent', 'QGA 返回错误: %{public}s (命令: %{public}s)', JSON.stringify(result.error), command)
                return null
              }
              
              return result.return || {}
            } catch (e) {
              hilog.warn(DOMAIN, 'QemuAgent', 'JSON 解析失败: %{public}s (命令: %{public}s)', line, command)
              continue
            }
          }
        }
        
        // 等待 50ms 后重试
        await new Promise<void>((resolve: () => void) => setTimeout(resolve, 50))
      }
      
      hilog.error(DOMAIN, 'QemuAgent', '等待响应超时 (命令: %{public}s, 已等待 %{public}d ms)', command, Date.now() - startTime)
      return null
    } catch (e) {
      hilog.error(DOMAIN, 'QemuAgent', '执行命令异常: %{public}s (命令: %{public}s)', JSON.stringify(e as ESObject), command)
      this.isConnected = false  // 标记连接已断开
      return null
    }
  }

  /**
   * 关机
   */
  async shutdown(): Promise<boolean> {
    const args: QGAArguments = { mode: 'powerdown' }
    const result: ESObject | null = await this.sendCommand('guest-shutdown', args, false)
    return result !== null
  }

  /**
   * 重启
   */
  async reboot(): Promise<boolean> {
    const args: QGAArguments = { mode: 'reboot' }
    const result: ESObject | null = await this.sendCommand('guest-shutdown', args, false)
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

  /**
   * 获取主机名
   */
  async getHostName(): Promise<string | null> {
    const result: ESObject | null = await this.sendCommand('guest-get-host-name')
    if (result && typeof result === 'object') {
      return (result as Record<string, string>)['host-name'] || null
    }
    return null
  }

  /**
   * 获取网络接口信息
   */
  async getNetworkInterfaces(): Promise<ESObject[] | null> {
    const result: ESObject | null = await this.sendCommand('guest-network-get-interfaces')
    if (result && Array.isArray(result)) {
      return result as ESObject[]
    }
    return null
  }

  /**
   * 获取文件系统信息
   */
  async getFilesystemInfo(): Promise<ESObject[] | null> {
    const result: ESObject | null = await this.sendCommand('guest-get-fsinfo')
    if (result && Array.isArray(result)) {
      return result as ESObject[]
    }
    return null
  }

  /**
   * 获取 vCPU 信息
   */
  async getVcpus(): Promise<ESObject[] | null> {
    const result: ESObject | null = await this.sendCommand('guest-get-vcpus')
    if (result && Array.isArray(result)) {
      return result as ESObject[]
    }
    return null
  }

  /**
   * 在虚拟机内执行命令
   */
  async exec(path: string, args?: string[]): Promise<number | null> {
    interface ExecArgs {
      path: string
      arg?: string[]
      'capture-output'?: boolean
    }
    const execArgs: ExecArgs = {
      path: path,
      'capture-output': true
    }
    if (args) {
      execArgs.arg = args
    }
    const result: ESObject | null = await this.sendCommand('guest-exec', execArgs as ESObject)
    if (result && typeof result === 'object') {
      return (result as Record<string, number>)['pid'] || null
    }
    return null
  }

  /**
   * 获取执行结果
   */
  async execStatus(pid: number): Promise<ESObject | null> {
    interface ExecStatusArgs {
      pid: number
    }
    const args: ExecStatusArgs = { pid }
    return await this.sendCommand('guest-exec-status', args as ESObject)
  }

  /**
   * 执行命令并获取输出（便捷方法）
   */
  async execAndGetOutput(path: string, args?: string[]): Promise<string | null> {
    const pid = await this.exec(path, args)
    if (!pid) return null

    // 等待命令执行完成
    for (let i = 0; i < 20; i++) {
      await new Promise<void>((resolve: () => void) => setTimeout(resolve, 100))
      const status: ESObject | null = await this.execStatus(pid)
      if (status && (status as Record<string, boolean>)['exited']) {
        const outData = (status as Record<string, string>)['out-data']
        if (outData) {
          // Base64 解码
          try {
            const decoder = util.TextDecoder.create('utf-8')
            const base64Helper = new util.Base64Helper()
            const decoded = base64Helper.decodeSync(outData)
            return decoder.decodeToString(decoded)
          } catch (e) {
            hilog.error(DOMAIN, 'QemuAgent', '解码输出失败: %{public}s', JSON.stringify(e as ESObject))
          }
        }
        return ''
      }
    }
    return null
  }

  /**
   * 获取内存信息（通过 /proc/meminfo）
   */
  async getMemoryInfo(): Promise<Record<string, number> | null> {
    // 使用 sh -c cat 以提高兼容性
    const output = await this.execAndGetOutput('/bin/sh', ['-c', 'cat /proc/meminfo'])
    if (!output) return null
    
    const result: Record<string, number> = {}
    const lines = output.split('\n')
    for (const line of lines) {
      const match = line.match(/^(\w+):\s+(\d+)\s*kB/)
      if (match) {
        result[match[1]] = parseInt(match[2]) * 1024  // 转换为字节
      }
    }
    return result
  }

  /**
   * 获取 CPU 统计信息（用于计算使用率）
   */
  async getCpuStats(): Promise<CpuStats | null> {
    // 使用 sh -c cat 以提高兼容性
    const output = await this.execAndGetOutput('/bin/sh', ['-c', 'cat /proc/stat'])
    if (!output) return null
    
    const lines = output.split('\n')
    for (const line of lines) {
      if (line.startsWith('cpu ')) {
        const parts = line.split(/\s+/)
        if (parts.length >= 5) {
          const user = parseInt(parts[1])
          const nice = parseInt(parts[2])
          const system = parseInt(parts[3])
          const idle = parseInt(parts[4])
          const iowait = parts.length > 5 ? parseInt(parts[5]) : 0
          const irq = parts.length > 6 ? parseInt(parts[6]) : 0
          const softirq = parts.length > 7 ? parseInt(parts[7]) : 0
          
          const total = user + nice + system + idle + iowait + irq + softirq
          
          const stats: CpuStats = { total, idle }
          return stats
        }
      }
    }
    return null
  }

  /**
   * 检查 SSH 是否运行
   */
  async isSshRunning(): Promise<boolean> {
    // 使用 sh -c 来执行 pgrep，利用 shell 的 PATH 查找命令，兼容性更好
    // 同时尝试 pgrep 和 pidof
    const output = await this.execAndGetOutput('/bin/sh', ['-c', 'pgrep sshd || pidof sshd'])
    return output !== null && output.trim().length > 0
  }
}

export interface CpuStats {
  total: number
  idle: number
}

export default QemuAgent
