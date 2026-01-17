import { hilog } from '@kit.PerformanceAnalysisKit'
import QemuAgent from './QemuAgent'
import appOption from '../model/appOption'
import napi from 'libentry.so'

const DOMAIN = 0x0000

// 队列配置
const MAX_QUEUE_SIZE = 3           // 队列最大长度
const ENABLE_DEDUP = true          // 启用去重（同组件只保留最新请求）

// 连接请求优先级
export enum AgentPriority {
  LOW = 0,      // 后台监控（VmStatusBar）
  NORMAL = 1,   // 普通操作
  HIGH = 2      // 用户操作（PowerManagement）
}

// 连接请求
interface ConnectionRequest {
  userId: string
  priority: AgentPriority
  resolve: (agent: QemuAgent | null) => void
  reject: (error: Error) => void
  timestamp: number
}

// 连接状态
interface ManagerStatus {
  currentUser: string | null
  queueLength: number
  isConnected: boolean
}

/**
 * QemuAgent 连接管理器（单例）
 * 统一管理 QGA Socket 连接，避免多组件同时访问导致的竞争问题
 */
class QemuAgentManagerImpl {
  private static instance: QemuAgentManagerImpl | null = null

  private agent: QemuAgent | null = null
  private currentUser: string | null = null
  private waitQueue: ConnectionRequest[] = []
  private isProcessing: boolean = false
  private keepAliveTimer: number = -1

  private constructor() { }

  static getInstance(): QemuAgentManagerImpl {
    if (!QemuAgentManagerImpl.instance) {
      QemuAgentManagerImpl.instance = new QemuAgentManagerImpl()
    }
    return QemuAgentManagerImpl.instance
  }

  /**
   * 获取 Agent 连接
   * @param userId 使用者标识
   * @param priority 优先级，默认 NORMAL
   * @param timeout 超时时间（毫秒），默认 5000
   */
  async acquire(userId: string, priority: AgentPriority = AgentPriority.NORMAL, timeout: number = 5000): Promise<QemuAgent | null> {
    hilog.info(DOMAIN, 'AgentManager', '请求连接: %{public}s, 优先级: %{public}d', userId, priority)

    // 如果当前没有使用者，直接获取
    if (!this.currentUser) {
      return await this.createConnection(userId)
    }

    // 如果是同一个使用者，直接返回现有连接
    if (this.currentUser === userId && this.agent) {
      // [修复] 即使是同一用户，也要检查 Agent 是否真的存活（防止 Socket 已断开但逻辑状态未更新）
      if (this.agent.isAlive()) {
        hilog.info(DOMAIN, 'AgentManager', '用户 %{public}s 复用现有活跃 Agent', userId);
        return this.agent;
      }
      hilog.warn(DOMAIN, 'AgentManager', '用户 %{public}s 的 Agent 已失效，准备释放并重新创建', userId);
      await this.forceRelease();
      // [修复] 释放后管理器变为空忙，直接重新连接，不要去排队
      return await this.createConnection(userId);
    }

    // 高优先级请求可以抢占低优先级
    if (priority === AgentPriority.HIGH && this.currentUser !== userId) {
      hilog.info(DOMAIN, 'AgentManager', '高优先级请求，要求 %{public}s 释放连接', this.currentUser)
      await this.forceRelease()
      return await this.createConnection(userId)
    }

    // 否则加入等待队列
    return new Promise<QemuAgent | null>((resolve: (agent: QemuAgent | null) => void, reject: (error: Error) => void) => {
      // 去重：移除同一用户的旧请求
      if (ENABLE_DEDUP) {
        const existingIndex = this.waitQueue.findIndex((r: ConnectionRequest) => r.userId === userId)
        if (existingIndex !== -1) {
          const oldRequest = this.waitQueue.splice(existingIndex, 1)[0]
          hilog.info(DOMAIN, 'AgentManager', '去重：移除 %{public}s 的旧请求', userId)
          oldRequest.resolve(null)  // 通知旧请求已取消
        }
      }

      // 队列满时拒绝新请求
      if (this.waitQueue.length >= MAX_QUEUE_SIZE) {
        hilog.warn(DOMAIN, 'AgentManager', '队列已满（%{public}d），拒绝 %{public}s', MAX_QUEUE_SIZE, userId)
        resolve(null)
        return
      }

      const request: ConnectionRequest = {
        userId,
        priority,
        resolve,
        reject,
        timestamp: Date.now()
      }

      // 按优先级插入队列
      let inserted = false
      for (let i = 0; i < this.waitQueue.length; i++) {
        if (this.waitQueue[i].priority < priority) {
          this.waitQueue.splice(i, 0, request)
          inserted = true
          break
        }
      }
      if (!inserted) {
        this.waitQueue.push(request)
      }

      hilog.info(DOMAIN, 'AgentManager', '%{public}s 加入等待队列，当前队列长度: %{public}d/%{public}d', userId, this.waitQueue.length, MAX_QUEUE_SIZE)

      // 设置超时
      setTimeout(() => {
        const index = this.waitQueue.findIndex((r: ConnectionRequest) => r.userId === userId && r.timestamp === request.timestamp)
        if (index !== -1) {
          this.waitQueue.splice(index, 1)
          hilog.warn(DOMAIN, 'AgentManager', '%{public}s 等待超时', userId)
          resolve(null)
        }
      }, timeout)
    })
  }

  /**
   * 释放连接
   * @param userId 使用者标识
   */
  async release(userId: string): Promise<void> {
    if (this.currentUser !== userId) {
      if (this.currentUser) {
        hilog.debug(DOMAIN, 'AgentManager', '忽略 %{public}s 的释放请求 (当前实际持有者: %{public}s)', userId, this.currentUser)
      }
      return
    }

    hilog.info(DOMAIN, 'AgentManager', '%{public}s 释放连接 (进入空闲复用状态)', userId)

    // 软释放：不关闭连接，只清除使用者标识
    // 这样下次 acquire 可以直接复用
    this.currentUser = null

    // 处理等待队列中的下一个请求
    await this.processQueue()
  }

  /**
   * 强制释放当前连接（用于高优先级抢占或彻底清理）
   */
  private async forceRelease(): Promise<void> {
    hilog.info(DOMAIN, 'AgentManager', '强制释放并关闭连接，当前使用者: %{public}s', this.currentUser || 'none')

    if (this.agent) {
      try {
        await this.agent.disconnect()
      } catch (e) {
        // 忽略断开错误
      }
      this.agent = null
    }
    this.currentUser = null
    this.stopKeepAlive()

    // [修复] 强制释放后，唤醒等待队列，防止请求挂起
    await this.processQueue()
  }

  /**
   * 创建新连接
   */
  private async createConnection(userId: string): Promise<QemuAgent | null> {
    // 如果已有连接且可用，直接复用
    if (this.agent && this.agent.isAlive()) {
      hilog.info(DOMAIN, 'AgentManager', '复用现有空闲连接: %{public}s', userId)
      this.currentUser = userId
      return this.agent
    }

    const appTempDir = AppStorage.get(appOption.appTempDir) as string
    if (!appTempDir) {
      hilog.error(DOMAIN, 'AgentManager', 'appTempDir 未设置')
      return null
    }

    const qgaSocket = appTempDir + '/qga_socket'

    try {
      // 彻底清理旧连接
      if (this.agent) {
        await this.agent.disconnect()
      }

      this.agent = new QemuAgent(qgaSocket)
      const connected = await this.agent.connect()

      if (connected) {
        this.currentUser = userId
        hilog.info(DOMAIN, 'AgentManager', '%{public}s 连接成功', userId)

        // 启动心跳保活
        this.startKeepAlive()

        return this.agent
      } else {
        this.agent = null
        hilog.error(DOMAIN, 'AgentManager', '%{public}s 连接失败', userId)
        return null
      }
    } catch (e) {
      this.agent = null
      hilog.error(DOMAIN, 'AgentManager', '创建连接失败: %{public}s', JSON.stringify(e))
      return null
    }
  }

  /**
   * 启动心跳保活
   */
  private startKeepAlive(): void {
    this.stopKeepAlive()

    hilog.info(DOMAIN, 'AgentManager', '启动 QGA 心跳保活 (20s)')
    this.keepAliveTimer = setInterval(async () => {
      const currentAgent = this.agent

      if (!currentAgent || !currentAgent.isAlive()) {
        this.stopKeepAlive()
        return
      }

      // [修复] 如果当前有使用者正在操作，不要发送心跳 ping，防止 pendingResponse 被清空导致业务指令超时
      if (this.currentUser) {
        hilog.debug(DOMAIN, 'AgentManager', '业务正在占用 Agent，跳过此轮心跳')
        return
      }

      try {
        hilog.debug(DOMAIN, 'AgentManager', '发送 QGA 心跳 (ping)...')
        const success = await currentAgent.ping()

        if (!success) {
          hilog.warn(DOMAIN, 'AgentManager', 'QGA 心跳失败，尝试自动重连...')
          // P1-10修复: 心跳失败后尝试自动重连一次
          const reconnected = await currentAgent.connect()
          if (reconnected) {
            hilog.info(DOMAIN, 'AgentManager', 'QGA 自动重连成功')
          } else {
            hilog.error(DOMAIN, 'AgentManager', 'QGA 自动重连失败，清理连接')
            await this.forceRelease()
          }
        }
      } catch (e) {
        hilog.error(DOMAIN, 'AgentManager', '心跳执行异常: %{public}s', JSON.stringify(e))
      }
    }, 20000) // 20秒一次心跳
  }

  /**
   * 停止心跳保活
   */
  private stopKeepAlive(): void {
    if (this.keepAliveTimer !== -1) {
      clearInterval(this.keepAliveTimer)
      this.keepAliveTimer = -1
      hilog.info(DOMAIN, 'AgentManager', '停止 QGA 心跳保活')
    }
  }

  /**
   * 处理等待队列
   */
  private async processQueue(): Promise<void> {
    if (this.isProcessing || this.waitQueue.length === 0 || this.currentUser) {
      return
    }

    this.isProcessing = true

    try {
      // 循环处理，直到有用户成功连接或队列为空
      while (this.waitQueue.length > 0 && !this.currentUser) {
        const request = this.waitQueue.shift()
        if (request) {
          hilog.info(DOMAIN, 'AgentManager', '处理队列请求: %{public}s', request.userId)
          const agent = await this.createConnection(request.userId)

          if (agent) {
            // 连接成功，currentUser 已在 createConnection 中设置
            request.resolve(agent)
            // 循环结束，currentUser 不为空
          } else {
            // 连接失败，继续处理下一个请求
            hilog.warn(DOMAIN, 'AgentManager', '%{public}s 连接失败，尝试下一个请求', request.userId)
            request.resolve(null)
          }
        }
      }
    } finally {
      this.isProcessing = false

      // 如果还有等待的请求且当前无用户，继续尝试（递归保护）
      if (this.waitQueue.length > 0 && !this.currentUser && !this.isProcessing) {
        this.processQueue()
      }
    }
  }

  /**
   * 获取当前连接状态
   */
  getStatus(): ManagerStatus {
    const status: ManagerStatus = {
      currentUser: this.currentUser,
      queueLength: this.waitQueue.length,
      isConnected: this.agent !== null && this.agent.isAlive()
    }
    return status
  }
}

// 导出单例
export const QemuAgentManager = QemuAgentManagerImpl.getInstance()
export default QemuAgentManager
