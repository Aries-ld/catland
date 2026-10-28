/**
 * SearchService：跨平台搜索（ADR 0004）。
 * App 对每个已连接平台分别调用 query，各自返回，谁先回来谁先显示；点开结果时 resolve 成可播放的 FeedCard。
 * 风控与推荐流共用：平台在冷却中直接返回 resting 不发请求，搜索里遇到风控也让推荐流一起冷却。
 */
import { CatbusCallError } from '../catbus/runner.ts'
import type { Item } from '../catbus/types.ts'
import type { Logger } from '../log.ts'
import { toSearchHit } from './adapters.ts'
import type { FeedMixer } from './mixer.ts'
import { type FeedCard, type PlatformAdapter, type SearchHit } from './types.ts'

export interface HotWord {
  text: string
  platform: string
  heat: number | null
}

export interface SearchResult {
  status: 'ok' | 'resting' | 'auth' | 'unsupported'
  hits: SearchHit[]
  cursor: string | null
  hasMore: boolean
}

export interface SearchDeps {
  logger: Logger
  adapterFor: (platform: string) => PlatformAdapter
  mixer: Pick<FeedMixer, 'statusOf' | 'reportError' | 'acquire'>
  now?: () => number
  sleep?: (ms: number) => Promise<void>
  /** 同一平台两次搜索请求的最小间隔。 */
  minIntervalMs?: number
  /** 同一关键词同一页的缓存时长。 */
  cacheTtlMs?: number
}

const ITEM_MEMORY = 500
/** 同一平台每分钟最多搜索几次。 */
const SEARCH_PER_MINUTE = 6
const CACHE_SIZE = 60

export class SearchService {
  private readonly log: Logger
  private readonly now: () => number
  private readonly sleep: (ms: number) => Promise<void>
  private readonly minIntervalMs: number
  private readonly cacheTtlMs: number
  private readonly items = new Map<string, { item: Item; platform: string }>()
  private readonly cache = new Map<string, { at: number; result: SearchResult }>()
  /** 每个平台下一次允许发起搜索的时间（串行排队，避免连续回车打爆一个平台）。 */
  private readonly nextAt = new Map<string, number>()
  private readonly recent = new Map<string, number[]>()
  /** 热搜缓存（后台每个平台最多 1 小时取一次）；catbus 没实现的平台记住，不再请求。 */
  private readonly hotCache = new Map<string, { at: number; words: HotWord[] }>()
  private readonly hotUnsupported = new Set<string>()
  private readonly hotInflight = new Map<string, Promise<HotWord[]>>()
  static readonly HOT_TTL_MS = 60 * 60_000
  private hotTimer: NodeJS.Timeout | null = null

  private readonly deps: SearchDeps

  constructor(deps: SearchDeps) {
    this.deps = deps
    this.log = deps.logger.child({ mod: 'search' })
    this.now = deps.now ?? Date.now
    this.sleep = deps.sleep ?? ((ms) => new Promise((r) => setTimeout(r, ms)))
    this.minIntervalMs = deps.minIntervalMs ?? 3_000
    this.cacheTtlMs = deps.cacheTtlMs ?? 10 * 60_000
  }

  async query(platform: string, query: string, cursor: string | null = null): Promise<SearchResult> {
    const q = query.trim()
    const status = this.deps.mixer.statusOf(platform)
    if (status === 'cooldown') return { status: 'resting', hits: [], cursor: null, hasMore: false }
    if (status === 'auth') return { status: 'auth', hits: [], cursor: null, hasMore: false }
    const adapter = this.deps.adapterFor(platform)
    if (!adapter.search) return { status: 'unsupported', hits: [], cursor: null, hasMore: false }

    const cacheKey = `${platform}\u0000${q}\u0000${cursor ?? ''}`
    const hit = this.cache.get(cacheKey)
    if (hit && this.now() - hit.at < this.cacheTtlMs) return hit.result

    // 限速：同一平台的搜索请求排队，两次之间至少隔 minIntervalMs；每分钟最多 6 次；
    // 再和推荐流共用这个平台的请求预算（每分钟 / 每小时上限），搜索不会额外放大对平台的请求
    const recent = (this.recent.get(platform) ?? []).filter((t) => t > this.now() - 60_000)
    const minuteAt = recent.length >= SEARCH_PER_MINUTE ? recent[0]! + 60_000 : 0
    const at = Math.max(this.now(), this.nextAt.get(platform) ?? 0, minuteAt)
    this.nextAt.set(platform, at + this.minIntervalMs)
    this.recent.set(platform, [...recent, at])
    if (at > this.now()) await this.sleep(at - this.now())
    const budgetWait = this.deps.mixer.acquire(platform)
    if (budgetWait > 0) await this.sleep(budgetWait)

    try {
      const page = await adapter.search(q, cursor)
      const hits: SearchHit[] = []
      for (const item of page.items) {
        const h = toSearchHit(platform, item)
        if (!h) continue
        hits.push(h)
        this.items.delete(h.key)
        this.items.set(h.key, { item, platform })
        if (this.items.size > ITEM_MEMORY) this.items.delete(this.items.keys().next().value!)
      }
      const result: SearchResult = { status: 'ok', hits, cursor: page.hasMore ? page.cursor : null, hasMore: page.hasMore }
      this.cache.set(cacheKey, { at: this.now(), result })
      if (this.cache.size > CACHE_SIZE) this.cache.delete(this.cache.keys().next().value!)
      this.log.info('search', { platform, got: page.items.length, hits: hits.length, page: cursor ?? 'first' })
      return result
    } catch (err) {
      const code = err instanceof CatbusCallError ? err.code : 'ERROR'
      this.deps.mixer.reportError(platform, err)
      this.log.warn('search failed', { platform, code, message: (err as Error).message })
      if (code === 'RISK_CONTROL') return { status: 'resting', hits: [], cursor: null, hasMore: false }
      if (code === 'AUTH_REQUIRED' || code === 'AUTH_EXPIRED') return { status: 'auth', hits: [], cursor: null, hasMore: false }
      throw err
    }
  }

  /** 点开一条搜索结果：解析出可播放媒体。fresh：播放失败后重新取地址。 */
  async resolve(key: string, fresh = false): Promise<FeedCard | null> {
    const d = this.items.get(key)
    if (!d) return null
    try {
      return await this.deps.adapterFor(d.platform).resolve(d.item, undefined, fresh)
    } catch (err) {
      this.deps.mixer.reportError(d.platform, err)
      throw err
    }
  }

  /**
   * 各平台的实时热搜：只读缓存，不发请求（打开搜索页时不会卡、不会闪）。
   * 按平台等比例轮流合并、去重（热点各平台大多一样）。一个平台都还没取过时，先取一个平台再返回。
   */
  async hot(platforms: string[]): Promise<HotWord[]> {
    if (!platforms.some((p) => this.hotCache.has(p))) {
      const first = platforms.find((p) => !this.hotUnsupported.has(p) && this.deps.adapterFor(p).hotKeywords)
      if (first) await this.refreshHot(first)
    }
    const lists = platforms.map((p) => this.hotCache.get(p)?.words ?? [])
    const out: HotWord[] = []
    const seen = new Set<string>()
    for (let i = 0; out.length < 30 && lists.some((l) => i < l.length); i++) {
      for (const l of lists) {
        const w = l[i]
        const norm = w?.text.replace(/\s+/g, '').toLowerCase()
        if (w && norm && !seen.has(norm)) { seen.add(norm); out.push(w) }
      }
    }
    return out
  }

  /**
   * 后台定时取热搜：每 tickMs 只取一个平台（缓存最旧、超过 1 小时的那个），把请求分散开；
   * 风控冷却 / 登录失效 / catbus 没实现的平台跳过。
   */
  startHotSchedule(platforms: () => string[], tickMs = 5 * 60_000, firstDelayMs = 5_000): void {
    this.stopHotSchedule()
    const tick = () => {
      const due = platforms()
        .filter((p) => !this.hotUnsupported.has(p) && this.deps.adapterFor(p).hotKeywords)
        .filter((p) => this.now() - (this.hotCache.get(p)?.at ?? 0) >= SearchService.HOT_TTL_MS)
        .sort((a, b) => (this.hotCache.get(a)?.at ?? 0) - (this.hotCache.get(b)?.at ?? 0))
      if (due[0]) void this.refreshHot(due[0])
    }
    this.hotTimer = setTimeout(function loop(this: SearchService) {
      tick()
      this.hotTimer = setTimeout(loop.bind(this), tickMs)
      this.hotTimer.unref()
    }.bind(this), firstDelayMs)
    this.hotTimer.unref()
  }

  stopHotSchedule(): void {
    if (this.hotTimer) clearTimeout(this.hotTimer)
    this.hotTimer = null
  }

  private async refreshHot(platform: string): Promise<HotWord[]> {
    const cached = this.hotCache.get(platform)
    const status = this.deps.mixer.statusOf(platform)
    if (status === 'cooldown' || status === 'auth') return cached?.words ?? []
    const adapter = this.deps.adapterFor(platform)
    if (!adapter.hotKeywords) return []
    let p = this.hotInflight.get(platform)
    if (!p) {
      p = adapter.hotKeywords()
        .then((ks) => {
          const words = ks.map((k) => ({ text: k.text, platform, heat: k.heat }))
          this.hotCache.set(platform, { at: this.now(), words })
          this.log.info('hot keywords', { platform, count: words.length })
          return words
        })
        .catch((err) => {
          const code = err instanceof CatbusCallError ? err.code : 'ERROR'
          if (code === 'NOT_IMPLEMENTED' || code === 'UNSUPPORTED') this.hotUnsupported.add(platform)
          else this.deps.mixer.reportError(platform, err)
          this.log.info('hot keywords unavailable', { platform, code })
          return cached?.words ?? []
        })
        .finally(() => this.hotInflight.delete(platform))
      this.hotInflight.set(platform, p)
    }
    return p
  }

  has(key: string): boolean {
    return this.items.has(key)
  }
}
