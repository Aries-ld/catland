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

export interface SearchResult {
  status: 'ok' | 'resting' | 'auth' | 'unsupported'
  hits: SearchHit[]
  cursor: string | null
  hasMore: boolean
}

export interface SearchDeps {
  logger: Logger
  adapterFor: (platform: string) => PlatformAdapter
  mixer: Pick<FeedMixer, 'statusOf' | 'reportError'>
  now?: () => number
  sleep?: (ms: number) => Promise<void>
  /** 同一平台两次搜索请求的最小间隔。 */
  minIntervalMs?: number
  /** 同一关键词同一页的缓存时长。 */
  cacheTtlMs?: number
}

const ITEM_MEMORY = 500
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

  private readonly deps: SearchDeps

  constructor(deps: SearchDeps) {
    this.deps = deps
    this.log = deps.logger.child({ mod: 'search' })
    this.now = deps.now ?? Date.now
    this.sleep = deps.sleep ?? ((ms) => new Promise((r) => setTimeout(r, ms)))
    this.minIntervalMs = deps.minIntervalMs ?? 2_000
    this.cacheTtlMs = deps.cacheTtlMs ?? 5 * 60_000
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

    // 限速：同一平台的搜索请求排队，两次之间至少隔 minIntervalMs
    const at = Math.max(this.now(), this.nextAt.get(platform) ?? 0)
    this.nextAt.set(platform, at + this.minIntervalMs)
    if (at > this.now()) await this.sleep(at - this.now())

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

  /** 点开一条搜索结果：解析出可播放媒体。 */
  async resolve(key: string): Promise<FeedCard | null> {
    const d = this.items.get(key)
    if (!d) return null
    try {
      return await this.deps.adapterFor(d.platform).resolve(d.item)
    } catch (err) {
      this.deps.mixer.reportError(d.platform, err)
      throw err
    }
  }

  has(key: string): boolean {
    return this.items.has(key)
  }
}
