import { hilog } from '@kit.PerformanceAnalysisKit'
import QemuAgent from './QemuAgent'
import appOption from '../model/appOption'

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
  
  private constructor() {}
  
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
      return this.agent
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
      hilog.warn(DOMAIN, 'AgentManager', '%{public}s 尝试释放非自己的连接', userId)
      return
    }
    
    hilog.info(DOMAIN, 'AgentManager', '%{public}s 释放连接', userId)
    
    // 断开当前连接
    if (this.agent) {
      try {
        await this.agent.disconnect()
      } catch (e) {
        // 忽略断开错误
      }
      this.agent = null
    }
    this.currentUser = null
    
    // 处理等待队列中的下一个请求
    await this.processQueue()
  }
  
  /**
   * 强制释放当前连接（用于高优先级抢占）
   */
  private async forceRelease(): Promise<void> {
    hilog.info(DOMAIN, 'AgentManager', '强制释放连接，当前使用者: %{public}s', this.currentUser || 'none')
    
    if (this.agent) {
      try {
        await this.agent.disconnect()
      } catch (e) {
        // 忽略断开错误
      }
      this.agent = null
    }
    this.currentUser = null
  }
  
  /**
   * 创建新连接
   */
  private async createConnection(userId: string): Promise<QemuAgent | null> {
    const appTempDir = AppStorage.get(appOption.appTempDir) as string
    if (!appTempDir) {
      hilog.error(DOMAIN, 'AgentManager', 'appTempDir 未设置')
      return null
    }
    
    const qgaSocket = appTempDir + '/qga_socket'
    
    try {
      this.agent = new QemuAgent(qgaSocket)
      const connected = await this.agent.connect()
      
      if (connected) {
        this.currentUser = userId
        hilog.info(DOMAIN, 'AgentManager', '%{public}s 连接成功', userId)
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
   * 处理等待队列
   */
  private async processQueue(): Promise<void> {
    if (this.isProcessing || this.waitQueue.length === 0 || this.currentUser) {
      return
    }
    
    this.isProcessing = true
    
    const request = this.waitQueue.shift()
    if (request) {
      hilog.info(DOMAIN, 'AgentManager', '处理队列请求: %{public}s', request.userId)
      const agent = await this.createConnection(request.userId)
      request.resolve(agent)
    }
    
    this.isProcessing = false
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
