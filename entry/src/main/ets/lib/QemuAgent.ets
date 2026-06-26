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
  signal?: number
}

// QGA JSON-RPC 响应接口  
interface QGAResponse {
  return?: QGAResponseData
  error?: QGAError
  id?: number
}

interface QGAError {
  class: string
  desc: string
}

// 基础响应类型
type QGAResponseData = Object;

// 类型安全的空响应标记，用于 waitForResponse=false 等不需要实际响应内容的场景
interface EmptyQgaResponse {
}

// 具体业务接口定义
export interface QGANetworkAddress {
  'ip-address': string
  'ip-address-type': string
  prefix: number
}

export interface QGANetworkInterface {
  name: string
  'hardware-address'?: string
  'ip-addresses'?: QGANetworkAddress[]
  statistics?: Record<string, number>
}

export interface QGADiskInfo {
  name: string
  partition?: boolean
  dependencies?: string[]
  address?: Record<string, string>
  alias?: string
}

export interface QGAFilesystemInfo {
  name: string
  mountpoint: string
  type: string
  'used-bytes'?: number
  'total-bytes'?: number
  disk?: QGADiskInfo[]
}

export interface QGAVcpuInfo {
  'logical-id': number
  online: boolean
  'can-offline'?: boolean
}

export interface QGAExecStatus {
  exited: boolean
  'exit-code'?: number
  signal?: number
  'out-data'?: string
  'err-data'?: string
  'out-truncated'?: boolean
  'err-truncated'?: boolean
}

export interface QGAGuestInfo {
  version: string
  supported_commands: Record<string, boolean>[]
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
  // 队列式锁，避免无限 promise 链泄漏
  private lockQueue: (() => void)[] = []
  private locked: boolean = false
  // 事件驱动的响应等待（替代忙等轮询）
  private responseResolve: ((line: string) => void) | null = null
  private responseReject: ((e: Error) => void) | null = null
  private responseTimer: number | null = null
  // Socket 意外断开回调（由 Manager 设置以触发自动重连）
  onDisconnect: (() => void) | null = null

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

      const address: socket.LocalAddress = {
        address: this.socketPath
      }
      const connectOptions: socket.LocalConnectOptions = {
        address,
        timeout: 1000  // 恢复至 1000ms，配合 VmController 的 Smart Skip 逻辑确保稳定性
      }

      await this.client.connect(connectOptions)

      // 设置消息接收监听器
      this.client.on('message', (value: socket.LocalSocketMessageInfo): void => {
        const decoder: util.TextDecoder = util.TextDecoder.create('utf-8')
        const message: string = decoder.decodeToString(new Uint8Array(value.message))
        this.pendingResponse += message
        // 事件驱动：检查是否有等待中的 Promise，直接解析响应行
        if (this.responseResolve) {
          const lineEndIndex = this.pendingResponse.indexOf('\n')
          if (lineEndIndex !== -1) {
            const line = this.pendingResponse.substring(0, lineEndIndex)
            this.pendingResponse = this.pendingResponse.substring(lineEndIndex + 1)
            const resolve = this.responseResolve
            this.responseResolve = null
            this.responseReject = null
            if (this.responseTimer !== null) {
              clearTimeout(this.responseTimer)
              this.responseTimer = null
            }
            resolve(line)
          }
        }
      })

      // [修复] 监听错误事件
      this.client.on('error', (err: Error): void => {
        hilog.error(DOMAIN, 'QemuAgent', 'Socket 错误: %{public}s', JSON.stringify(err))
        this.isConnected = false
      })

      // [修复] 监听关闭事件
      this.client.on('close', (): void => {
        hilog.info(DOMAIN, 'QemuAgent', 'Socket 连接已关闭')
        this.isConnected = false
        if (this.onDisconnect) {
          hilog.info(DOMAIN, 'QemuAgent', '触发断线回调，尝试自动重连')
          this.onDisconnect()
        }
      })

      this.isConnected = true
      hilog.info(DOMAIN, 'QemuAgent', '已连接到 QGA: %{public}s', this.socketPath)

      // 连接后立即执行流同步，确保通信可靠
      const synced = await this.sync()
      if (!synced) {
        hilog.error(DOMAIN, 'QemuAgent', 'QGA 流同步失败，断开连接')
        await this.disconnect()
        return false
      }

      return true
    } catch (e) {
      hilog.error(DOMAIN, 'QemuAgent', '连接 QGA 失败: %{public}s', JSON.stringify(e))
      await this.disconnect()
      return false
    }
  }



  /**
   * 断开连接
   * [修复1.1] 完全清理：移除监听器、关闭连接、清空缓冲区
   */
  async disconnect(): Promise<void> {
    const client: socket.LocalSocket | null = this.client
    this.client = null // 立即置空，防止重入
    this.isConnected = false
    this.pendingResponse = ''
    // [修复] reject 挂起的 Promise，防止 sendCommand 永久 await
    if (this.responseReject) {
      this.responseReject(new Error('Disconnected'))
      this.responseReject = null
    }
    this.responseResolve = null
    if (this.responseTimer !== null) {
      clearTimeout(this.responseTimer)
      this.responseTimer = null
    }

    if (client) {
      try {
        client.off('message')
        client.off('error')
        client.off('close')
        await client.close()
      } catch (e) {
        hilog.warn(DOMAIN, 'QemuAgent', '关闭连接时异常: %{public}s', JSON.stringify(e))
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
  private async sendCommand<T extends QGAResponseData>(command: string, args?: QGAArguments, waitForResponse: boolean = true, timeoutMs: number = 10000): Promise<T | null> {
    if (!this.client || !this.isConnected) {
      hilog.error(DOMAIN, 'QemuAgent', '发送命令失败：未连接到 QGA (命令: %{public}s)', command)
      return null
    }

    const currentId = ++this.requestId

    try {
      // [修复] 增加互斥锁，防止心跳探测与业务命令冲突导致响应错位
      const release = await this.lock();

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
          // 发送成功标记：调用方应仅判断非 null，不访问返回值成员
          return {} as EmptyQgaResponse as T
        }

        // 事件驱动：等待完整响应行（替代忙等轮询）
        const startTime = Date.now()
        while (Date.now() - startTime < timeoutMs) {
          if (!this.isConnected) {
            hilog.error(DOMAIN, 'QemuAgent', '等待响应期间连接断开 (命令: %{public}s)', command)
            return null
          }

          let line: string
          try {
            line = await new Promise<string>((resolve, reject) => {
              this.responseResolve = resolve
              this.responseReject = reject
              this.responseTimer = setTimeout(() => {
                this.responseResolve = null
                this.responseReject = null
                reject(new Error('timeout'))
              }, Math.max(timeoutMs - (Date.now() - startTime), 10))
            })
          } catch (_) {
            // 单次等待超时或 disconnect，继续下一次尝试（isConnected 检查会捕获）
            this.responseResolve = null
            this.responseReject = null
            continue
          }

          if (line.length > 0) {
            try {
              // 处理 QGA 特有的 0xFF 引导符
              const braceIndex = line.indexOf('{')
              if (braceIndex > 0) {
                line = line.substring(braceIndex)
              } else if (braceIndex === -1) {
                continue
              }

              const result: QGAResponse = JSON.parse(line) as QGAResponse

              if (result.id !== undefined && result.id !== currentId) {
                hilog.warn(DOMAIN, 'QemuAgent', '收到过时响应: 期望 %{public}d, 收到 %{public}d', currentId, result.id)
                continue
              }

              if (result.error) {
                hilog.error(DOMAIN, 'QemuAgent', 'QGA 返回错误: %{public}s (命令: %{public}s)', JSON.stringify(result.error), command)
                return null
              }

              return (result.return as T) || ({} as EmptyQgaResponse as T)
            } catch (e) {
              hilog.warn(DOMAIN, 'QemuAgent', 'JSON 解析失败 (命令: %{public}s)', command)
              continue
            }
          }
        }

        // hilog.error(DOMAIN, 'QemuAgent', '等待响应超时 (命令: %{public}s, 已等待 %{public}d ms)，强制断开连接', command, Date.now() - startTime) // Original line
        hilog.error(DOMAIN, 'QemuAgent', '等待响应超时 (命令: %{public}s)，强制断开连接', command)
        // [修复] 超时意味着底层的 Socket 缓冲可能已乱序或虚拟机代理检测失效，必须彻底重连
        this.isConnected = false
        await this.disconnect()
        return null
      } finally {
        release();
      }
    } catch (e) {
      hilog.error(DOMAIN, 'QemuAgent', '执行命令异常: %{public}s (命令: %{public}s)', JSON.stringify(e), command)
      this.isConnected = false  // 标记连接已断开
      await this.disconnect() // [修复] 捕获异常时也断开连接
      return null
    }
  }

  /**
   * 命令锁实现（队列式，避免无限 promise 链泄漏）
   */
  private async lock(): Promise<() => void> {
    return new Promise<void>(resolve => {
      this.lockQueue.push(resolve)
      this.tryAcquire()
    }).then(() => () => this.releaseLock())
  }

  private tryAcquire(): void {
    if (!this.locked && this.lockQueue.length > 0) {
      this.locked = true
      // 安全：上面已通过 length > 0 保证队列非空
      const next = this.lockQueue.shift()!
      next()
    }
  }

  private releaseLock(): void {
    this.locked = false
    this.tryAcquire()
  }

  /**
   * 关机
   */
  async shutdown(): Promise<boolean> {
    const args: QGAArguments = { mode: 'powerdown' }
    const result = await this.sendCommand<Record<string, Object>>('guest-shutdown', args, false)
    return result !== null
  }

  /**
   * 重启
   */
  async reboot(): Promise<boolean> {
    const args: QGAArguments = { mode: 'reboot' }
    const result = await this.sendCommand<Record<string, Object>>('guest-shutdown', args, false)
    return result !== null
  }

  /**
   * 暂停（挂起到 RAM）
   */
  async suspend(): Promise<boolean> {
    const result = await this.sendCommand<Record<string, Object>>('guest-suspend-ram', undefined, false)
    return result !== null
  }

  /**
   * QGA 流同步 (guest-sync-delimited)
   * [优化] 在发送指令前发送 0xFF 字节以冲刷缓冲区，并发送随机 ID 以同步
   */
  private async sync(): Promise<boolean> {
    const syncToken = Math.floor(Math.random() * 2147483647)

    try {
      if (this.client) {
        // 1. 发送 0xFF 字符流引导，强制 Guest 端重置 JSON 解析器
        const resetBuffer = new ArrayBuffer(1)
        const view = new Uint8Array(resetBuffer)
        view[0] = 0xFF
        await this.client.send({ data: resetBuffer })
        // QGA 协议要求：0xFF 引导符发送后需等待对端刷新并重置解析器状态
        // 50ms 在绝大多数设备上已足够，无需过长阻塞
        await new Promise<void>(resolve => setTimeout(resolve, 50))
      }

      // 2. 发送同步指令并验证返回 ID
      const response = await this.sendCommand<number>('guest-sync-delimited', { id: syncToken })
      return response !== null && response === syncToken
    } catch (e) {
      hilog.error(DOMAIN, 'QemuAgent', 'QGA 流同步异常: %{public}s', JSON.stringify(e))
      return false
    }
  }

  /**
   * Ping 检查 QGA 是否响应
   */
  async ping(): Promise<boolean> {
    const result = await this.sendCommand<Record<string, Object>>('guest-ping')
    return result !== null
  }

  /**
   * 获取虚拟机信息
   */
  async getInfo(): Promise<QGAGuestInfo | null> {
    return await this.sendCommand<QGAGuestInfo>('guest-info')
  }

  /**
   * 获取主机名
   */
  async getHostName(): Promise<string | null> {
    const result = await this.sendCommand<Record<string, string>>('guest-get-host-name')
    if (result && typeof result === 'object') {
      return result['host-name'] || null
    }
    return null
  }

  /**
   * 获取网络接口信息
   */
  async getNetworkInterfaces(): Promise<QGANetworkInterface[] | null> {
    const result = await this.sendCommand<QGANetworkInterface[]>('guest-network-get-interfaces')
    if (result && Array.isArray(result)) {
      return result
    }
    return null
  }

  /**
   * 获取文件系统信息
   */
  async getFilesystemInfo(): Promise<QGAFilesystemInfo[] | null> {
    const result = await this.sendCommand<QGAFilesystemInfo[]>('guest-get-fsinfo')
    if (result && Array.isArray(result)) {
      return result
    }
    return null
  }

  /**
   * 获取 vCPU 信息
   */
  async getVcpus(): Promise<QGAVcpuInfo[] | null> {
    const result = await this.sendCommand<QGAVcpuInfo[]>('guest-get-vcpus')
    if (result && Array.isArray(result)) {
      return result
    }
    return null
  }

  /**
   * 在虚拟机内执行命令
   */
  async exec(path: string, args?: string[]): Promise<number | null> {
    const execArgs: QGAArguments = {
      path: path,
      'capture-output': true
    }
    if (args) {
      execArgs.arg = args
    }
    const result = await this.sendCommand<Record<string, number>>('guest-exec', execArgs)
    if (result && typeof result === 'object') {
      return result['pid'] || null
    }
    return null
  }

  /**
   * 获取执行结果
   */
  async execStatus(pid: number): Promise<QGAExecStatus | null> {
    const args: QGAArguments = { pid }
    return await this.sendCommand<QGAExecStatus>('guest-exec-status', args)
  }

  /**
   * 执行命令并获取输出（便捷方法）
   * [优化] 增加超时清理逻辑，防止进程堆积
   */
  async execAndGetOutput(path: string, args?: string[], timeoutMs: number = 5000): Promise<string | null> {
    const pid = await this.exec(path, args)
    if (!pid) return null

    // 等待命令执行完成
    const startTime = Date.now()
    while (Date.now() - startTime < timeoutMs) {
      await new Promise<void>((resolve: () => void) => setTimeout(resolve, 200))
      const status = await this.execStatus(pid)

      if (status && status.exited) {
        const outData = (status as Object as Record<string, Object>)['out-data'] as string
        if (outData) {
          // Base64 解码
          try {
            const decoder = util.TextDecoder.create('utf-8')
            const base64Helper = new util.Base64Helper()
            const decoded = base64Helper.decodeSync(outData)
            return decoder.decodeToString(decoded)
          } catch (e) {
            hilog.error(DOMAIN, 'QemuAgent', '解码输出失败: %{public}s', JSON.stringify(e))
          }
        }
        return ''
      }
    }

    // 超时清理：尝试杀死该进程
    hilog.warn(DOMAIN, 'QemuAgent', '命令执行超时 (PID: %{public}d)，尝试清理...', pid)
    await this.kill(pid)

    return null
  }

  /**
   * 杀死虚拟机内的进程
   */
  async kill(pid: number, signal: number = 15): Promise<boolean> {
    const args: QGAArguments = { pid, signal }
    const result = await this.sendCommand<Record<string, Object>>('guest-process-signal', args)
    return result !== null
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

  /**
   * [优化] 一次 shell exec 获取 meminfo + cpu stats + ssh 状态，替代原来三次独立调用
   * 节省 2 次 QGA socket 往返（~10s → ~3s）
   */
  async getSystemInfo(): Promise<SystemInfo | null> {
    const output = await this.execAndGetOutput('/bin/sh',
      ['-c', 'cat /proc/meminfo /proc/stat; echo "===SSH==="; pgrep sshd || echo NONE; echo "===SSH_END==="'],
      8000)
    if (!output) return null

    // 按分隔符拆分三段
    const sshMarker = '\n===SSH==='
    const sshEndMarker = '\n===SSH_END==='
    const sshStart = output.lastIndexOf(sshMarker)
    const sshEnd = output.lastIndexOf(sshEndMarker)

    let combinedData: string
    let sshOutput: string
    if (sshStart !== -1 && sshEnd !== -1 && sshEnd > sshStart) {
      combinedData = output.substring(0, sshStart)
      sshOutput = output.substring(sshStart + sshMarker.length + 1, sshEnd).trim()
    } else {
      combinedData = output
      sshOutput = ''
    }

    // 解析 /proc/meminfo 部分：提取 kB 行
    const memory: Record<string, number> = {}
    const memRegex = /^(\w+):\s+(\d+)\s*kB/gm
    let memMatch: RegExpExecArray | null
    while ((memMatch = memRegex.exec(combinedData)) !== null) {
      // 只取 meminfo 行（/proc/stat 的 cpu 行不以冒号结尾）
      if (memMatch[1] && memMatch[2]) {
        memory[memMatch[1]] = parseInt(memMatch[2]) * 1024
      }
    }

    // 解析 /proc/stat 部分：提取 cpu  行
    let cpuStats: CpuStats | null = null
    const cpuRegex = /^cpu\s\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/gm
    const cpuMatch = cpuRegex.exec(combinedData)
    if (cpuMatch) {
      const user = parseInt(cpuMatch[1])
      const nice = parseInt(cpuMatch[2])
      const system = parseInt(cpuMatch[3])
      const idle = parseInt(cpuMatch[4])
      const iowait = parseInt(cpuMatch[5])
      const irq = parseInt(cpuMatch[6])
      const softirq = parseInt(cpuMatch[7])
      const total = user + nice + system + idle + iowait + irq + softirq
      cpuStats = { total, idle }
    }

    // 解析 SSH 状态
    const sshRunning = sshOutput.length > 0 && sshOutput !== 'NONE'

    return { memory, cpuStats, sshRunning }
  }
}

export interface SystemInfo {
  memory: Record<string, number>
  cpuStats: CpuStats | null
  sshRunning: boolean
}

export interface CpuStats {
  total: number
  idle: number
}

export default QemuAgent
