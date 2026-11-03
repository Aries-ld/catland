/**
 * JdGate：京东请求的总闸（ADR 0005）。搜索、盯价、订单都从这里过：
 * - 同一时间只发一个；两次之间留间隔（用户主动的 15 秒起，后台的 60 秒起，再加随机 0～30 秒）；
 * - 用户主动的请求插到后台请求前面；
 * - 刚登录的 10 分钟里不跑后台请求；
 * - 一次 RISK_CONTROL 就熔断：京东所有请求暂停，不重试，时长逐级加长 30 分钟 → 2 小时 → 6 小时 → 24 小时；
 *   连续 24 小时没再被拦，下一次从第一级算。熔断状态存本机，重启 App 也不会提前恢复。
 */
import { CatbusCallError } from '../catbus/runner.ts'
import type { Logger } from '../log.ts'

export type Priority = 'user' | 'background'
export type RestKind = 'resting' | 'verify'

export interface RestState {
  kind: RestKind
  /** 毫秒时间戳 */
  resumeAt: number
}

export interface GateState {
  level: number
  until: number
  kind: RestKind
  lastTripAt: number
}

export interface GateStorage {
  load(): GateState | null
  save(s: GateState): void
}

export const BREAKER_STEPS_MS = [30 * 60_000, 2 * 3600_000, 6 * 3600_000, 24 * 3600_000]
const CLEAN_RESET_MS = 24 * 3600_000
const WARMUP_MS = 10 * 60_000
/** 被拦过之后这么久里，后台请求放慢（盯价每 4 小时一次，见 CommerceService）。 */
export const CAUTIOUS_MS = 24 * 3600_000

/** 京东歇着时调用方收到的错误：没有真的发请求。 */
export class JdRestingError extends Error {
  readonly rest: RestState
  constructor(rest: RestState) {
    super('京东在歇会儿')
    this.rest = rest
    this.name = 'JdRestingError'
  }
}

export interface JdGateOptions {
  logger: Logger
  storage?: GateStorage
  now?: () => number
  sleep?: (ms: number) => Promise<void>
  random?: () => number
  userGapMs?: number
  backgroundGapMs?: number
  jitterMs?: number
  /** 熔断时（第一次进入暂停）通知上层，比如让小猫说一句。 */
  onTrip?: (rest: RestState) => void
}

interface Job {
  priority: Priority
  run: () => Promise<void>
}

export class JdGate {
  private readonly log: Logger
  private readonly storage: GateStorage | undefined
  private readonly now: () => number
  private readonly sleep: (ms: number) => Promise<void>
  private readonly random: () => number
  private readonly userGap: number
  private readonly backgroundGap: number
  private readonly jitter: number
  private readonly onTrip: ((r: RestState) => void) | undefined
  private state: GateState
  private readonly queue: Job[] = []
  private busy = false
  private lastEnd = 0
  private loginAt = 0

  constructor(opts: JdGateOptions) {
    this.log = opts.logger.child({ mod: 'jd-gate' })
    this.storage = opts.storage
    this.now = opts.now ?? Date.now
    this.sleep = opts.sleep ?? ((ms) => new Promise((r) => setTimeout(r, ms)))
    this.random = opts.random ?? Math.random
    this.userGap = opts.userGapMs ?? 15_000
    this.backgroundGap = opts.backgroundGapMs ?? 60_000
    this.jitter = opts.jitterMs ?? 30_000
    this.onTrip = opts.onTrip
    this.state = opts.storage?.load() ?? { level: 0, until: 0, kind: 'resting', lastTripAt: 0 }
  }

  /** 现在是否在歇着；不在歇着时为 null。 */
  rest(): RestState | null {
    return this.state.until > this.now() ? { kind: this.state.kind, resumeAt: this.state.until } : null
  }

  /** 最近被拦过（24 小时内）：后台请求要放慢。 */
  cautious(): boolean {
    return this.state.lastTripAt > 0 && this.now() - this.state.lastTripAt < CAUTIOUS_MS
  }

  noteLogin(): void {
    this.loginAt = this.now()
  }

  /** 后台请求现在能不能跑：不在歇着、不在刚登录的 10 分钟里。 */
  backgroundAllowed(): boolean {
    return !this.rest() && this.now() - this.loginAt >= WARMUP_MS
  }

  /** 排队执行一次京东请求。歇着时直接抛 JdRestingError（不发请求）；被风控时熔断并把原错误抛出去。 */
  run<T>(priority: Priority, fn: () => Promise<T>): Promise<T> {
    const r = this.rest()
    if (r) return Promise.reject(new JdRestingError(r))
    return new Promise<T>((resolve, reject) => {
      const job: Job = {
        priority,
        run: async () => {
          const rest = this.rest()
          if (rest) return reject(new JdRestingError(rest))
          if (priority === 'background' && !this.backgroundAllowed()) return reject(new JdRestingError(rest ?? { kind: 'resting', resumeAt: this.loginAt + WARMUP_MS }))
          const gap = (priority === 'user' ? this.userGap : this.backgroundGap) + this.random() * this.jitter
          const wait = this.lastEnd + gap - this.now()
          if (this.lastEnd > 0 && wait > 0) await this.sleep(wait)
          try {
            resolve(await fn())
          } catch (err) {
            if (err instanceof CatbusCallError && err.code === 'RISK_CONTROL') this.trip(isCaptcha(err.detail) ? 'verify' : 'resting')
            reject(err)
          } finally {
            this.lastEnd = this.now()
          }
        },
      }
      // 用户主动的插到所有后台请求前面
      const at = priority === 'user' ? this.queue.findIndex((j) => j.priority === 'background') : -1
      if (at >= 0) this.queue.splice(at, 0, job)
      else this.queue.push(job)
      void this.pump()
    })
  }

  private async pump(): Promise<void> {
    if (this.busy) return
    this.busy = true
    try {
      while (this.queue.length > 0) await this.queue.shift()!.run()
    } finally {
      this.busy = false
    }
  }

  /** 熔断：暂停所有京东请求，时长逐级加长；排队中的请求全部作废。 */
  trip(kind: RestKind): RestState {
    const now = this.now()
    const level = this.state.lastTripAt > 0 && now - this.state.lastTripAt < CLEAN_RESET_MS ? Math.min(this.state.level + 1, BREAKER_STEPS_MS.length - 1) : 0
    this.state = { level, until: now + BREAKER_STEPS_MS[level]!, kind, lastTripAt: now }
    this.storage?.save(this.state)
    const rest = { kind, resumeAt: this.state.until }
    this.log.warn('jd tripped', { kind, level, minutes: BREAKER_STEPS_MS[level]! / 60_000 })
    for (const j of this.queue.splice(0)) void j.run() // 都会因为 rest() 而直接拒绝
    this.onTrip?.(rest)
    return rest
  }
}

function isCaptcha(detail: unknown): boolean {
  return !!detail && typeof detail === 'object' && (detail as { kind?: unknown }).kind === 'captcha'
}
