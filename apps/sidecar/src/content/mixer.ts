/**
 * FeedMixer：多平台推荐流的混排与预取。
 * 始终在后台保持 readyAhead 张「媒体已解析、可立即播放」的卡片，客户端 next() 时零等待；
 * 按平台轮询补货、限速、去重，风控 / 失效 / 网络错误按平台隔离，不拖累其他平台。
 */
import { EventEmitter } from 'node:events'
import { CatbusCallError } from '../catbus/runner.ts'
import type { Item } from '../catbus/types.ts'
import type { Logger } from '../log.ts'
import { cardKey, type FeedCard, type PlatformAdapter } from './types.ts'

export interface SeenStore {
  has(key: string): boolean
  add(key: string): void
}

export class MemorySeenStore implements SeenStore {
  private readonly keys = new Set<string>()
  has(key: string) {
    return this.keys.has(key)
  }
  add(key: string) {
    this.keys.add(key)
  }
}

export type SourceStatus = 'active' | 'backoff' | 'cooldown' | 'auth'

export interface SourceState {
  platform: string
  status: SourceStatus
  until: number | null
  lastError: { code: string; message: string } | null
  pending: number
  ready: number
}

export interface MixerOptions {
  logger: Logger
  seen?: SeenStore
  now?: () => number
  /** 后台保持的可播放卡片数（含解析中）。实际取 max(readyAhead, readyPerSource × 平台数)。 */
  readyAhead?: number
  readyPerSource?: number
  resolveConcurrency?: number
  feedMinIntervalMs?: number
  resolveMinIntervalMs?: number
  /** 同一平台最多连续出现几条。 */
  maxConsecutive?: number
  riskCooldownMs?: number
  backoffBaseMs?: number
  backoffMaxMs?: number
  /** 卡片距离过期不足这么久就重新解析，避免交给客户端后才失效。 */
  expiryMarginMs?: number
}

interface Source {
  adapter: PlatformAdapter
  pending: Item[]
  cursor: string | null
  fetching: boolean
  inflight: number
  lastFetchAt: number
  nextResolveAt: number
  status: SourceStatus
  until: number
  failures: number
  lastError: { code: string; message: string } | null
  abort: AbortController
}

const ITEM_MEMORY = 300
/** 计算平台均衡时回看的最近下发条数：窗口越长，各平台长期占比越接近均分。 */
const RECENT_WINDOW = 24

export class FeedMixer extends EventEmitter<{ ready: []; source: [SourceState] }> {
  private readonly log: Logger
  private readonly seen: SeenStore
  private readonly now: () => number
  private readonly o: Required<Omit<MixerOptions, 'logger' | 'seen' | 'now'>>
  private readonly sources = new Map<string, Source>()
  private ready: FeedCard[] = []
  private readonly known = new Set<string>()
  private readonly items = new Map<string, { item: Item; platform: string }>()
  private recent: string[] = []
  private inflight = 0
  private rr = 0
  private timer: NodeJS.Timeout | null = null
  private stopped = false

  constructor(opts: MixerOptions) {
    super()
    this.log = opts.logger.child({ mod: 'mixer' })
    this.seen = opts.seen ?? new MemorySeenStore()
    this.now = opts.now ?? Date.now
    this.o = {
      readyAhead: opts.readyAhead ?? 6,
      readyPerSource: opts.readyPerSource ?? 4,
      resolveConcurrency: opts.resolveConcurrency ?? 3,
      feedMinIntervalMs: opts.feedMinIntervalMs ?? 2_000,
      resolveMinIntervalMs: opts.resolveMinIntervalMs ?? 250,
      maxConsecutive: opts.maxConsecutive ?? 1,
      riskCooldownMs: opts.riskCooldownMs ?? 10 * 60_000,
      backoffBaseMs: opts.backoffBaseMs ?? 5_000,
      backoffMaxMs: opts.backoffMaxMs ?? 2 * 60_000,
      expiryMarginMs: opts.expiryMarginMs ?? 60_000,
    }
  }

  /** 设置启用的信息源（已登录 ∩ 用户勾选）。移除的源立即中止并清掉其待播卡片。 */
  setSources(adapters: PlatformAdapter[]): void {
    const next = new Set(adapters.map((a) => a.platform))
    for (const [p, s] of this.sources) {
      if (next.has(p)) continue
      s.abort.abort()
      this.sources.delete(p)
      this.ready = this.ready.filter((c) => c.platform !== p)
    }
    for (const a of adapters) {
      if (this.sources.has(a.platform)) continue
      this.sources.set(a.platform, {
        adapter: a, pending: [], cursor: null, fetching: false, inflight: 0, lastFetchAt: -Infinity, nextResolveAt: 0,
        status: 'active', until: 0, failures: 0, lastError: null, abort: new AbortController(),
      })
    }
    this.pump()
  }

  sourceStates(): SourceState[] {
    return [...this.sources.values()].map((s) => this.stateOf(s))
  }

  /** 取接下来 n 张卡片。缓冲为空时最多等 waitMs 拿到第一张（首屏）。 */
  async next(n: number, opts: { waitMs?: number } = {}): Promise<FeedCard[]> {
    this.dropExpired()
    if (this.ready.length === 0 && (opts.waitMs ?? 0) > 0) await this.waitReady(opts.waitMs!)
    const out: FeedCard[] = []
    while (out.length < n && this.ready.length > 0) {
      const i = this.pickDiverse()
      const [card] = this.ready.splice(i, 1)
      out.push(card!)
      this.markDelivered(card!)
    }
    this.pump()
    return out
  }

  /** 播放失败（如 403 / 地址过期）时重新解析一张已下发的卡片。 */
  async refresh(key: string): Promise<FeedCard | null> {
    const d = this.items.get(key)
    const s = d && this.sources.get(d.platform)
    if (!d || !s) return null
    try {
      return await s.adapter.resolve(d.item, s.abort.signal)
    } catch (err) {
      this.onError(s, err, 'refresh')
      return null
    }
  }

  stop(): void {
    this.stopped = true
    for (const s of this.sources.values()) s.abort.abort()
    if (this.timer) clearTimeout(this.timer)
  }

  /** 补货主循环：按轮询顺序给每个平台派发解析任务，必要时翻页。 */
  private pump(): void {
    if (this.stopped) return
    const now = this.now()
    let wakeAt = Infinity
    for (const s of this.sources.values()) {
      if (s.status !== 'active' && s.status !== 'auth' && now >= s.until) this.setStatus(s, 'active')
    }
    const list = [...this.sources.values()]
    const target = Math.max(this.o.readyAhead, this.o.readyPerSource * list.length)
    while (this.ready.length + this.inflight < target && this.inflight < this.o.resolveConcurrency) {
      // 优先给「待播 + 解析中」最少的平台补货，产出率低的平台（如 X 纯文字多）也能保持在场。
      let best: Source | null = null
      let bestLoad = Infinity
      for (let k = 0; k < list.length; k++) {
        const s = list[(this.rr + k) % list.length]!
        if (s.status !== 'active') {
          if (s.status !== 'auth') wakeAt = Math.min(wakeAt, s.until)
          continue
        }
        if (s.pending.length === 0) {
          wakeAt = Math.min(wakeAt, this.maybeFetch(s, now))
          continue
        }
        if (now < s.nextResolveAt) {
          wakeAt = Math.min(wakeAt, s.nextResolveAt)
          continue
        }
        const load = this.readyCount(s.adapter.platform) + s.inflight
        if (load < bestLoad) [best, bestLoad] = [s, load]
      }
      if (!best) break
      this.rr = (list.indexOf(best) + 1) % list.length
      this.resolveNext(best, now)
    }
    for (const s of this.sources.values()) if (s.status === 'active' && s.pending.length < 3) wakeAt = Math.min(wakeAt, this.maybeFetch(s, now))
    this.schedule(wakeAt)
  }

  /** 需要时翻一页；返回下次可以再翻的时间。 */
  private maybeFetch(s: Source, now: number): number {
    if (s.fetching) return Infinity
    const allowedAt = s.lastFetchAt + this.o.feedMinIntervalMs
    if (now < allowedAt) return allowedAt
    s.fetching = true
    s.lastFetchAt = now
    const signal = s.abort.signal
    s.adapter
      .fetchFeed(s.cursor, signal)
      .then((page) => {
        if (signal.aborted) return
        let fresh = 0
        for (const item of page.items) {
          const key = cardKey(s.adapter.platform, item.id)
          if (this.known.has(key) || this.seen.has(key)) continue
          this.known.add(key)
          s.pending.push(item)
          fresh++
        }
        // 推荐流没有尽头：到底或整页都看过时从头再要一页新的推荐。
        s.cursor = page.hasMore ? page.cursor : null
        this.onSuccess(s)
        this.log.debug('feed page', { platform: s.adapter.platform, got: page.items.length, fresh })
      })
      .catch((err) => this.onError(s, err, 'feed'))
      .finally(() => {
        s.fetching = false
        this.pump()
      })
    return Infinity
  }

  private resolveNext(s: Source, now: number): void {
    const item = s.pending.shift()!
    s.nextResolveAt = now + this.o.resolveMinIntervalMs
    this.inflight++
    s.inflight++
    const signal = s.abort.signal
    s.adapter
      .resolve(item, signal)
      .then((card) => {
        if (signal.aborted || !this.sources.has(s.adapter.platform)) return
        this.onSuccess(s)
        if (!card) return
        this.items.set(card.key, { item, platform: card.platform }) // 供 refresh 使用，下发前也可能需要
        this.ready.push(card)
        this.emit('ready')
      })
      .catch((err) => this.onError(s, err, 'resolve'))
      .finally(() => {
        this.inflight--
        s.inflight--
        this.pump()
      })
  }

  private onSuccess(s: Source): void {
    s.failures = 0
    if (s.status === 'backoff') this.setStatus(s, 'active')
  }

  private onError(s: Source, err: unknown, phase: 'feed' | 'resolve' | 'refresh'): void {
    if (s.abort.signal.aborted) return
    const code = err instanceof CatbusCallError ? err.code : 'ERROR'
    if (code === 'ABORTED') return
    s.lastError = { code, message: (err as Error).message }
    const ctx = { platform: s.adapter.platform, phase, code, message: (err as Error).message }
    if (code === 'RISK_CONTROL') {
      this.log.warn('risk control, cooling down', ctx)
      s.until = this.now() + this.o.riskCooldownMs
      this.setStatus(s, 'cooldown')
    } else if (code === 'AUTH_REQUIRED' || code === 'AUTH_EXPIRED') {
      this.log.warn('auth lost, source paused', ctx)
      this.setStatus(s, 'auth')
    } else {
      s.failures++
      this.log.warn('source error', { ...ctx, failures: s.failures })
      // 单条解析失败（作品被删等）很常见，连续 3 次才退避；翻页失败立即退避。
      if (phase === 'feed' || s.failures >= 3) {
        s.until = this.now() + Math.min(this.o.backoffBaseMs * 2 ** Math.max(0, s.failures - 1), this.o.backoffMaxMs)
        this.setStatus(s, 'backoff')
      }
    }
  }

  private setStatus(s: Source, status: SourceStatus): void {
    const changed = s.status !== status
    s.status = status
    if (status === 'active') s.until = 0
    if (changed) this.emit('source', this.stateOf(s))
  }

  private stateOf(s: Source): SourceState {
    return {
      platform: s.adapter.platform,
      status: s.status,
      until: s.until || null,
      lastError: s.lastError,
      pending: s.pending.length,
      ready: this.readyCount(s.adapter.platform),
    }
  }

  private readyCount(platform: string): number {
    let n = 0
    for (const c of this.ready) if (c.platform === platform) n++
    return n
  }

  /**
   * 均匀混排：在最近 RECENT_WINDOW 条里出现次数最少的平台优先（同分取最久没出现的，再同分取先就绪的），
   * 且同一平台不连续超过 maxConsecutive 次（只剩一个平台有货时例外）。长期下来各平台占比接近均分。
   */
  private pickDiverse(): number {
    const tail = this.recent.slice(-this.o.maxConsecutive)
    const blocked = tail.length === this.o.maxConsecutive && tail.every((p) => p === tail[0]) ? tail[0] : null
    const window = this.recent.slice(-RECENT_WINDOW)
    const seenCount = (p: string) => window.filter((x) => x === p).length
    const lastSeen = (p: string) => window.lastIndexOf(p) // -1 = 窗口内没出现过
    let best = -1
    let bestScore: [number, number] = [Infinity, Infinity]
    const visited = new Set<string>()
    for (let i = 0; i < this.ready.length; i++) {
      const p = this.ready[i]!.platform
      if (p === blocked || visited.has(p)) continue
      visited.add(p)
      const score: [number, number] = [seenCount(p), lastSeen(p)]
      if (score[0] < bestScore[0] || (score[0] === bestScore[0] && score[1] < bestScore[1])) [best, bestScore] = [i, score]
    }
    return best < 0 ? 0 : best
  }

  private markDelivered(card: FeedCard): void {
    this.seen.add(card.key)
    this.recent = [...this.recent, card.platform].slice(-RECENT_WINDOW)
    if (this.items.size > ITEM_MEMORY) this.items.delete(this.items.keys().next().value!)
  }

  /** 快过期的卡片放回队首重新解析。 */
  private dropExpired(): void {
    const limit = this.now() + this.o.expiryMarginMs
    const [fresh, stale] = [this.ready.filter((c) => c.expiresAt > limit), this.ready.filter((c) => c.expiresAt <= limit)]
    if (stale.length === 0) return
    this.ready = fresh
    for (const c of stale) {
      const d = this.items.get(c.key)
      const s = this.sources.get(c.platform)
      if (d && s) s.pending.unshift(d.item)
    }
  }

  private waitReady(ms: number): Promise<void> {
    return new Promise((resolve) => {
      const done = () => {
        clearTimeout(t)
        this.off('ready', done)
        resolve()
      }
      const t = setTimeout(done, ms)
      this.once('ready', done)
    })
  }

  private schedule(at: number): void {
    if (this.timer) clearTimeout(this.timer)
    this.timer = null
    if (!Number.isFinite(at)) return
    this.timer = setTimeout(() => this.pump(), Math.max(0, at - this.now()))
    this.timer.unref()
  }
}
