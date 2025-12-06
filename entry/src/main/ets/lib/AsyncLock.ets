
interface QueueItem {
  resolve: () => void
  reject: (reason?: Error) => void
}

export class AsyncLock {
  private locked: boolean = false
  private queue: QueueItem[] = []

  async acquire(): Promise<void> {
    if (!this.locked) {
      this.locked = true
      return
    }

    return new Promise<void>((resolve, reject) => {
      const item: QueueItem = {
        resolve: resolve,
        reject: reject
      }
      this.queue.push(item)
    })
  }

  release(): void {
    if (this.queue.length > 0) {
      const next = this.queue.shift()
      if (next) {
        next.resolve()
      }
    } else {
      this.locked = false
    }
  }

  reset(): void {
    // 拒绝所有在队列中等待的请求，防止死锁
    this.queue.forEach(item => {
      item.reject(new Error("AsyncLock reset: connection aborted"))
    })
    this.queue = []
    this.locked = false
  }

  isLocked(): boolean {
    return this.locked
  }

  async runExclusive<T>(callback: () => Promise<T>): Promise<T> {
    await this.acquire()
    try {
      return await callback()
    } finally {
      this.release()
    }
  }
}
