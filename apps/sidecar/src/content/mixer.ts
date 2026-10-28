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
  /** 硬上限：同一平台最多连续这么多条。超过时若其他平台还在供货，最多等 balanceWaitMs 让它们补上。 */
  maxRun?: number
  /** 为保证均匀（连续上限、新连接的平台优先）愿意等待的最长时间。 */
  balanceWaitMs?: number
  /** 风控冷却的起始时长；连续被风控时翻倍，最长 riskCooldownMaxMs。 */
  riskCooldownMs?: number
  riskCooldownMaxMs?: number
  /** 每个平台每分钟最多发起的请求数（翻页 + 解析），把单个平台的请求频率压低。 */
  requestsPerMinute?: number
  /** 每小时软上限：用到八成后每次请求至少隔 30 秒，到顶后等最早的一次滑出窗口。 */
  requestsPerHour?: number
  platformRequestsPerHour?: Record<string, number>
  /** 间隔的随机抖动比例（0.6 = 实际间隔在 1–1.6 倍之间），避免固定节拍。 */
  jitter?: number
  random?: () => number
  /** 个别平台更保守的上限（如匿名访问的 Bilibili 播放地址）。 */
  platformRequestsPerMinute?: Record<string, number>
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
  /** 最近一分钟内发起请求的时间戳（限速用）。 */
  requests: number[]
  /** 连续被风控的次数：决定下一次冷却多久。 */
  riskStrikes: number
  /** 冷却结束后的探测期：只放行一个请求，成功才恢复正常供货。 */
  probing: boolean
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
  /** 刚连接、还没下发过卡片的平台：下一次取卡时优先等它的第一张，让新平台立刻出现在刷刷流里。 */
  private readonly newcomers = new Set<string>()
  private inflight = 0
  /** 没在推荐流里的平台（搜索时用到）的请求记账。 */
  private readonly solo = new Map<string, Source>()
  private rr = 0
  private timer: NodeJS.Timeout | null = null
  private stopped = false

  constructor(opts: MixerOptions) {
    super()
    this.log = opts.logger.child({ mod: 'mixer' })
    this.seen = opts.seen ?? new MemorySeenStore()
    this.now = opts.now ?? Date.now
    this.o = {
      // 防风控（见 ADR 0002「请求节奏」）：平台看的是请求次数和节奏，不是一次拿了多少条——
      // 列表一次拉满一页；逐条取详情是大头，只为接下来一两条预取，两次之间留 1.5–2.4 秒并随机抖动。
      readyAhead: opts.readyAhead ?? 3,
      readyPerSource: opts.readyPerSource ?? 2,
      resolveConcurrency: opts.resolveConcurrency ?? 2,
      feedMinIntervalMs: opts.feedMinIntervalMs ?? 4_000,
      resolveMinIntervalMs: opts.resolveMinIntervalMs ?? 1_500,
      jitter: opts.jitter ?? 0.6,
      random: opts.random ?? Math.random,
      maxConsecutive: opts.maxConsecutive ?? 1,
      maxRun: opts.maxRun ?? 3,
      balanceWaitMs: opts.balanceWaitMs ?? 2_500,
      riskCooldownMs: opts.riskCooldownMs ?? 5 * 60_000,
      riskCooldownMaxMs: opts.riskCooldownMaxMs ?? 60 * 60_000,
      requestsPerMinute: opts.requestsPerMinute ?? 12,
      platformRequestsPerMinute: opts.platformRequestsPerMinute ?? {},
      requestsPerHour: opts.requestsPerHour ?? 300,
      platformRequestsPerHour: opts.platformRequestsPerHour ?? { xhs: 200, douyin: 200 },
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
    for (const p of [...this.newcomers]) if (!next.has(p)) this.newcomers.delete(p)
    const first = this.sources.size === 0
    for (const a of adapters) {
      if (this.sources.has(a.platform)) continue
      if (!first) this.newcomers.add(a.platform)
      this.sources.set(a.platform, {
        adapter: a, pending: [], cursor: null, fetching: false, inflight: 0, lastFetchAt: -Infinity, nextResolveAt: 0,
        status: 'active', until: 0, failures: 0, lastError: null, abort: new AbortController(),
        requests: [], riskStrikes: 0, probing: false,
      })
    }
    this.pump()
  }

  sourceStates(): SourceState[] {
    return [...this.sources.values()].map((s) => this.stateOf(s))
  }

  /** 某个平台当前的状态（不在信息源里时为 null）。搜索据此决定要不要发请求。 */
  statusOf(platform: string): SourceStatus | null {
    const s = this.sources.get(platform)
    if (!s) return null
    if (s.status !== 'active' && s.status !== 'auth' && this.now() >= s.until) return 'active' // 冷却已到期，下一次 pump 会转为探测
    return s.status
  }

  /** 推荐流以外的请求（如搜索）遇到风控 / 登录失效：和推荐流共用同一套冷却与暂停。其他错误不影响推荐流。 */
  reportError(platform: string, err: unknown): void {
    const s = this.sources.get(platform)
    const code = err instanceof CatbusCallError ? err.code : 'ERROR'
    if (!s || !['RISK_CONTROL', 'AUTH_REQUIRED', 'AUTH_EXPIRED'].includes(code)) return
    this.onError(s, err, 'refresh')
  }

  /** 取接下来 n 张卡片。缓冲为空时最多等 waitMs 拿到第一张（首屏）。 */
  async next(n: number, opts: { waitMs?: number } = {}): Promise<FeedCard[]> {
    this.dropExpired()
    if (this.ready.length === 0 && (opts.waitMs ?? 0) > 0) await this.waitReady(opts.waitMs!)
    const out: FeedCard[] = []
    const deadline = Date.now() + this.o.balanceWaitMs
    while (out.length < n && this.ready.length > 0) {
      const left = deadline - Date.now()
      // 新连接的平台：还没有就绪卡片时稍等它的第一张
      const waitingNew = [...this.newcomers].filter((p) => this.isActive(p) && !this.ready.some((c) => c.platform === p))
      if (waitingNew.length > 0 && left > 0) {
        if (await this.waitFor((c) => waitingNew.includes(c.platform), left)) continue
        for (const p of waitingNew) this.newcomers.delete(p) // 等不到就不再等，避免每次都卡
      }
      const fresh = this.ready.findIndex((c) => this.newcomers.has(c.platform)) // 新平台的第一张直接插队
      const i = fresh >= 0 ? fresh : this.pickDiverse()
      const p = this.ready[i]!.platform
      // 连续上限：再给就超了，而其他平台还在供货 → 等一下别的平台
      if (this.runLength(p) >= this.o.maxRun && left > 0 && [...this.sources.keys()].some((q) => q !== p && this.isActive(q))) {
        if (await this.waitFor((c) => c.platform !== p, deadline - Date.now())) continue
      }
      const [card] = this.ready.splice(i, 1)
      out.push(card!)
      this.markDelivered(card!)
    }
    this.pump()
    return out
  }

  /** 最近连续下发同一平台的条数。 */
  private runLength(platform: string): number {
    let n = 0
    for (let i = this.recent.length - 1; i >= 0 && this.recent[i] === platform; i--) n++
    return n
  }

  private isActive(platform: string): boolean {
    return this.sources.get(platform)?.status === 'active'
  }

  /** 等到有满足条件的就绪卡片（true）或超时（false）。 */
  private waitFor(pred: (c: FeedCard) => boolean, ms: number): Promise<boolean> {
    if (this.ready.some(pred)) return Promise.resolve(true)
    return new Promise((resolve) => {
      const check = () => {
        if (!this.ready.some(pred)) return
        clearTimeout(t)
        this.off('ready', check)
        resolve(true)
      }
      const t = setTimeout(() => {
        this.off('ready', check)
        resolve(false)
      }, Math.max(0, ms))
      this.on('ready', check)
    })
  }

  /** 播放失败（如 403 / 地址过期）时重新解析一张已下发的卡片。 */
  async refresh(key: string): Promise<FeedCard | null> {
    const d = this.items.get(key)
    const s = d && this.sources.get(d.platform)
    if (!d || !s) return null
    try {
      return await s.adapter.resolve(d.item, s.abort.signal, true) // 一定重新取地址，别复用可能已失效的
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
      if (s.status !== 'active' && s.status !== 'auth' && now >= s.until) {
        if (s.status === 'cooldown') {
          s.probing = true // 先试探一个请求，确认恢复了再正常供货
          this.log.info('cooldown over, probing', { platform: s.adapter.platform })
        }
        this.setStatus(s, 'active')
      }
    }
    const list = [...this.sources.values()]
    // 每个平台各有自己的缓冲额度：一个平台快、另一个慢时，快平台不会占满缓冲把慢平台 / 新平台挤掉。
    const perSource = Math.max(this.o.readyPerSource, Math.ceil(this.o.readyAhead / Math.max(1, list.length)))
    while (this.inflight < this.o.resolveConcurrency) {
      // 优先给「待播 + 解析中」最少的平台补货，产出率低的平台（如纯文字多的）也能保持在场。
      let best: Source | null = null
      let bestLoad = Infinity
      for (let k = 0; k < list.length; k++) {
        const s = list[(this.rr + k) % list.length]!
        if (s.status !== 'active') {
          if (s.status !== 'auth') wakeAt = Math.min(wakeAt, s.until)
          continue
        }
        const load = this.readyCount(s.adapter.platform) + s.inflight
        if (load >= perSource) continue
        if (s.probing && (s.inflight > 0 || s.fetching)) continue // 探测期只放行一个请求
        const budgetAt = this.budgetAt(s, now)
        if (budgetAt > now) {
          wakeAt = Math.min(wakeAt, budgetAt)
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
    if (s.probing && s.inflight > 0) return Infinity
    const allowedAt = Math.max(s.lastFetchAt + this.spaced(this.o.feedMinIntervalMs, s.lastFetchAt), this.budgetAt(s, now))
    if (now < allowedAt) return allowedAt
    s.fetching = true
    s.lastFetchAt = now
    s.requests.push(now)
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
    s.nextResolveAt = now + this.spaced(this.o.resolveMinIntervalMs)
    s.requests.push(now)
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

  /** 限速：最近一分钟的请求数达到上限时，返回可以再发请求的时间；否则返回 now。 */
  /** 带随机抖动的间隔。seed 相同（同一次请求）时结果相同，避免每次 pump 重新抽签。 */
  private spaced(ms: number, seed?: number): number {
    if (ms <= 0 || this.o.jitter <= 0) return ms
    if (seed !== undefined && Number.isFinite(seed)) return ms * (1 + this.o.jitter * ((Math.abs(Math.sin(seed)) * 10_000) % 1))
    return ms * (1 + this.o.jitter * this.o.random())
  }

  /** 这个平台下一次允许请求的时间：每分钟上限 + 每小时软上限。推荐流和搜索共用（见 acquire）。 */
  private budgetAt(s: Source, now: number): number {
    const p = s.adapter.platform
    while (s.requests.length > 0 && s.requests[0]! <= now - 3_600_000) s.requests.shift()
    const minuteLimit = this.o.platformRequestsPerMinute[p] ?? this.o.requestsPerMinute
    const hourLimit = this.o.platformRequestsPerHour[p] ?? this.o.requestsPerHour
    const lastMinute = s.requests.filter((t) => t > now - 60_000)
    let at = lastMinute.length < minuteLimit ? now : lastMinute[0]! + 60_000
    if (s.requests.length >= hourLimit) at = Math.max(at, s.requests[0]! + 3_600_000)
    else if (s.requests.length >= hourLimit * 0.8) at = Math.max(at, (s.requests[s.requests.length - 1] ?? 0) + 30_000)
    return at
  }

  /**
   * 调试：让所有启用的平台假装进入风控冷却 ms 毫秒（不请求平台），并清空已备好的卡片，
   * 用来验证「休息站」卡片、小岛打盹、倒计时结束后自动恢复的整条链路（catland-debug feed:rest:<秒>）。
   */
  simulateCooldown(ms: number): void {
    const until = this.now() + ms
    for (const s of this.sources.values()) {
      if (s.status === 'auth') continue
      s.until = until
      s.probing = false
      this.setStatus(s, 'cooldown')
    }
    this.ready = []
    this.log.info('simulated cooldown', { ms })
    this.schedule(until)
  }

  /**
   * 现在为什么没货、什么时候能恢复（推荐流空了时给 App 选「在路上」还是「休息站」卡片）：
   * 每个启用的平台取「冷却结束 / 额度窗口滑过」的时间，取最早的那个；两分钟内能恢复算 waiting，否则 resting。
   */
  availability(): { state: 'ok' | 'waiting' | 'resting'; resumeAt: number | null } {
    if (this.ready.length > 0) return { state: 'ok', resumeAt: null }
    const now = this.now()
    const times: number[] = []
    for (const s of this.sources.values()) {
      if (s.status === 'auth') continue
      const cooled = s.status === 'active' ? now : Math.max(now, s.until)
      times.push(Math.max(cooled, this.budgetAt(s, now)))
    }
    if (times.length === 0) return { state: 'waiting', resumeAt: null }
    const resumeAt = Math.min(...times)
    return { state: resumeAt - now > 120_000 ? 'resting' : 'waiting', resumeAt }
  }

  /**
   * 搜索也走同一个平台预算：返回还要等多少毫秒，并把这次请求记上。
   * 平台没在推荐流里（没勾选）时单独记账，规则相同。
   */
  acquire(platform: string): number {
    const now = this.now()
    let s = this.sources.get(platform) ?? this.solo.get(platform)
    if (!s) {
      s = { adapter: { platform } as PlatformAdapter, requests: [] } as unknown as Source
      this.solo.set(platform, s)
    }
    const at = Math.max(now, this.budgetAt(s, now))
    s.requests.push(at)
    return at - now
  }

  private onSuccess(s: Source): void {
    s.failures = 0
    if (s.probing) {
      s.probing = false
      s.riskStrikes = 0
      this.log.info('recovered from risk control', { platform: s.adapter.platform })
    }
    if (s.status === 'backoff') this.setStatus(s, 'active')
  }

  private onError(s: Source, err: unknown, phase: 'feed' | 'resolve' | 'refresh'): void {
    if (s.abort.signal.aborted) return
    const code = err instanceof CatbusCallError ? err.code : 'ERROR'
    if (code === 'ABORTED') return
    s.lastError = { code, message: (err as Error).message }
    const ctx = { platform: s.adapter.platform, phase, code, message: (err as Error).message }
    if (code === 'RISK_CONTROL') {
      // 同一次风控里并发请求陆续报错：已经在冷却就不再叠加
      if (s.status === 'cooldown') return
      // 用户无感：悄悄停推这个平台；连续被拦时冷却逐次翻倍（5 → 10 → 20 → … 最长 60 分钟）
      s.riskStrikes++
      s.probing = false
      const cool = Math.min(this.o.riskCooldownMs * 2 ** (s.riskStrikes - 1), this.o.riskCooldownMaxMs)
      this.log.warn('risk control, cooling down', { ...ctx, strikes: s.riskStrikes, coolMs: cool })
      s.until = this.now() + cool
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
    this.newcomers.delete(card.platform)
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
