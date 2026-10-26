/** 计数信号量：限制同时运行的 catbus 子进程数。 */
export class Semaphore {
  private active = 0
  private readonly waiters: Array<() => void> = []
  private readonly limit: number

  constructor(limit: number) {
    if (!Number.isInteger(limit) || limit < 1) throw new RangeError(`semaphore limit must be >= 1, got ${limit}`)
    this.limit = limit
  }

  get pending(): number {
    return this.waiters.length
  }

  async use<T>(fn: () => Promise<T>): Promise<T> {
    // 释放时直接把名额移交给等待者（active 不变），避免新调用者在唤醒间隙插队超限。
    if (this.active >= this.limit) await new Promise<void>((resolve) => this.waiters.push(resolve))
    else this.active++
    try {
      return await fn()
    } finally {
      const next = this.waiters.shift()
      if (next) next()
      else this.active--
    }
  }
}
