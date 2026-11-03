/**
 * CommerceService：购物小助手（ADR 0005，先只接京东）。
 * - 搜索：catbus jd item search，经 JdGate 排队；同一关键词 + 排序 + 页 30 分钟内用缓存；
 *   京东歇着或被拦时返回上次的结果（标注时间）和 rest 状态，界面据此显示兜底卡片。
 * - 商品页不请求详情：用搜索结果里的快照（详情接口风控最严）。
 * - 心愿单：只存在本机，最多 30 件；加入时记下当时的价格。
 */
import { CatbusCallError } from '../catbus/runner.ts'
import type { Item } from '../catbus/types.ts'
import type { CatbusClient } from '../accounts/service.ts'
import type { Logger } from '../log.ts'
import type { ProductSnapshot, Store, WishEntry } from '../store/store.ts'
import { WISH_LIMIT } from '../store/store.ts'
import { JdGate, JdRestingError, type RestState } from './gate.ts'

export const JD_SORTS = ['general', 'sales', 'price_asc', 'price_desc', 'comments'] as const
export type JdSort = (typeof JD_SORTS)[number]

const CACHE_TTL_MS = 30 * 60_000
const CACHE_MAX = 50

export interface ProductPage {
  products: Array<ProductSnapshot & { wished: boolean }>
  cursor: string | null
  hasMore: boolean
  /** 京东歇着：界面显示兜底卡片 */
  rest: RestState | null
  /** 结果来自缓存时的取得时间（毫秒）；新鲜结果为 null */
  cachedAt: number | null
  /** 未登录京东 */
  auth: boolean
}

export class WishLimitError extends Error {}

export class CommerceService {
  private readonly cache = new Map<string, { at: number; page: Omit<ProductPage, 'products' | 'rest' | 'cachedAt' | 'auth'> & { products: ProductSnapshot[] } }>()
  private readonly log: Logger
  private readonly deps: { catbus: CatbusClient; gate: JdGate; store: Store; logger: Logger; now?: () => number }

  constructor(deps: { catbus: CatbusClient; gate: JdGate; store: Store; logger: Logger; now?: () => number }) {
    this.deps = deps
    this.log = deps.logger.child({ mod: 'commerce' })
  }

  private now(): number {
    return this.deps.now?.() ?? Date.now()
  }

  rest(): RestState | null {
    return this.deps.gate.rest()
  }

  async search(query: string, sort: JdSort = 'general', cursor: string | null = null): Promise<ProductPage> {
    const key = `${sort}\u0000${cursor ?? ''}\u0000${query}`
    const hit = this.cache.get(key)
    if (hit && this.now() - hit.at < CACHE_TTL_MS) return this.decorate(hit.page, null, null)
    try {
      const argv = ['jd', 'item', 'search', query, '--sort', sort, ...(cursor ? ['--cursor', cursor] : [])]
      const r = await this.deps.gate.run('user', () => this.deps.catbus.run<Item[]>(argv))
      const page = { products: r.data.map(toProduct).filter((p): p is ProductSnapshot => p !== null), cursor: r.page?.cursor ?? null, hasMore: !!r.page?.has_more }
      this.cache.delete(key)
      this.cache.set(key, { at: this.now(), page })
      if (this.cache.size > CACHE_MAX) this.cache.delete(this.cache.keys().next().value!)
      this.log.info('jd search', { len: query.length, sort, got: page.products.length, more: page.hasMore })
      return this.decorate(page, null, null)
    } catch (err) {
      const rest = err instanceof JdRestingError ? err.rest : err instanceof CatbusCallError && err.code === 'RISK_CONTROL' ? this.rest() : null
      if (rest) return this.decorate(hit?.page ?? { products: [], cursor: null, hasMore: false }, rest, hit?.at ?? null)
      if (err instanceof CatbusCallError && (err.code === 'AUTH_REQUIRED' || err.code === 'AUTH_EXPIRED')) {
        return { products: [], cursor: null, hasMore: false, rest: null, cachedAt: null, auth: true }
      }
      throw err
    }
  }

  private decorate(page: { products: ProductSnapshot[]; cursor: string | null; hasMore: boolean }, rest: RestState | null, cachedAt: number | null): ProductPage {
    const wished = this.deps.store.isWished(page.products.map((p) => p.sku))
    return {
      products: page.products.map((p) => ({ ...p, wished: wished.has(p.sku) })),
      cursor: rest ? null : page.cursor,
      hasMore: rest ? false : page.hasMore,
      rest,
      cachedAt,
      auth: false,
    }
  }

  addWish(p: ProductSnapshot): void {
    if (this.deps.store.isWished([p.sku]).size === 0 && this.deps.store.wishCount() >= WISH_LIMIT) throw new WishLimitError(`心愿单最多 ${WISH_LIMIT} 件`)
    this.deps.store.addWish(p)
  }

  removeWish(sku: string): void {
    this.deps.store.removeWish(sku)
  }

  wishes(): { entries: WishEntry[]; rest: RestState | null } {
    return { entries: this.deps.store.listWish(), rest: this.rest() }
  }
}

/** catbus 的 jd Item → 商品快照。没有 SKU 或标题的丢掉。 */
export function toProduct(it: Item): ProductSnapshot | null {
  if (!it?.id || !it.title) return null
  const price = it.price && typeof it.price.amount === 'number' && Number.isFinite(it.price.amount) ? it.price.amount : null
  return {
    sku: String(it.id),
    title: it.title,
    price,
    shop: it.author?.name ?? null,
    cover: typeof it.cover === 'string' ? it.cover : null,
    url: it.url || `https://item.jd.com/${it.id}.html`,
    comments: typeof it.stats?.comments === 'number' ? it.stats.comments : null,
  }
}

/** 解析客户端传来的商品快照（加心愿单用）：只认识的字段、类型都对。 */
export function parseProduct(v: unknown): ProductSnapshot | null {
  if (!v || typeof v !== 'object') return null
  const p = v as Record<string, unknown>
  if (typeof p.sku !== 'string' || !/^\d{1,20}$/.test(p.sku) || typeof p.title !== 'string' || !p.title) return null
  const s = (x: unknown) => (typeof x === 'string' ? x : null)
  const n = (x: unknown) => (typeof x === 'number' && Number.isFinite(x) ? x : null)
  const url = s(p.url)
  return {
    sku: p.sku, title: p.title.slice(0, 300), price: n(p.price), shop: s(p.shop), cover: s(p.cover),
    url: url && /^https:\/\/([a-z0-9-]+\.)*jd\.com\//i.test(url) ? url : `https://item.jd.com/${p.sku}.html`,
    comments: n(p.comments),
  }
}
