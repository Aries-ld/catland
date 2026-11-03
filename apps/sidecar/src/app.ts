/** App：组装各服务，维护「信息源 = 已登录 ∩ 用户勾选」的联动，并把能力注册成 RPC 方法。 */
import { AccountService, type BrowserCookie, type CatbusClient } from './accounts/service.ts'
import { getPlatform } from './accounts/catalog.ts'
import { createAdapter, MEDIA_HEADERS } from './content/adapters.ts'
import { CommentService } from './content/comments.ts'
import { FeedMixer } from './content/mixer.ts'
import { SearchService } from './content/search.ts'
import type { FeedCard, PlatformAdapter } from './content/types.ts'
import type { Logger } from './log.ts'
import { bool, oneOf, optInt, optStr, ParamError, RpcServer, str } from './rpc/server.ts'
import { CoverCache } from './store/covers.ts'
import { exportLibrary, importLibrary, LibraryFileError } from './store/library.ts'
import { JdGate, type GateState, type RestState } from './commerce/gate.ts'
import { CommerceService, JD_SORTS, parseProduct, WishLimitError } from './commerce/service.ts'
import { defaultDataDir, snapshot, type CardSnapshot, type Settings, Store } from './store/store.ts'
import type { Item } from './catbus/types.ts'
import { isAbsolute, join } from 'node:path'
import { WeatherService } from './weather/weather.ts'

export const VERSION = '0.0.1'

const SNAPSHOT_MEMORY = 500

export interface AppDeps {
  catbus: CatbusClient
  logger: Logger
  store: Store
  /** 测试注入：自定义适配器。 */
  adapterFor?: (platform: string) => PlatformAdapter
  mixer?: FeedMixer
  weather?: WeatherService
  covers?: CoverCache
  /** 测试注入：京东请求总闸（间隔、熔断）。 */
  jdGate?: JdGate
}

export class App {
  readonly accounts: AccountService
  readonly mixer: FeedMixer
  readonly store: Store
  private readonly comments: CommentService
  private readonly search: SearchService
  private readonly covers: CoverCache
  private readonly weather: WeatherService
  readonly jdGate: JdGate
  private readonly commerce: CommerceService
  private notifyRest: (r: RestState) => void = () => {}
  private readonly log: Logger
  private readonly adapterFor: (platform: string) => PlatformAdapter
  private readonly adapters = new Map<string, PlatformAdapter>()
  /** 已下发卡片的快照：点赞、收藏、浏览记录、评论都按 key 找回原始链接。 */
  private readonly snapshots = new Map<string, CardSnapshot>()
  private enabled: string[] = []

  constructor(deps: AppDeps) {
    this.log = deps.logger.child({ mod: 'app' })
    this.store = deps.store
    this.accounts = new AccountService({ catbus: deps.catbus, logger: deps.logger })
    this.comments = new CommentService({ catbus: deps.catbus })
    this.weather = deps.weather ?? new WeatherService({ logger: deps.logger })
    this.mixer = deps.mixer ?? new FeedMixer({ logger: deps.logger, seen: deps.store })
    this.adapterFor = deps.adapterFor ?? ((p) => createAdapter(p, { catbus: deps.catbus, logger: deps.logger }))
    this.search = new SearchService({ logger: deps.logger, adapterFor: (p) => this.adapter(p), mixer: this.mixer })
    this.covers = deps.covers ?? new CoverCache({ dir: join(defaultDataDir(), 'covers'), logger: deps.logger })
    this.jdGate = deps.jdGate ?? new JdGate({
      logger: deps.logger,
      storage: { load: () => deps.store.getKv<GateState>('jdGate'), save: (s) => deps.store.setKv('jdGate', s) },
      onTrip: (r) => this.notifyRest(r),
    })
    this.commerce = new CommerceService({ catbus: deps.catbus, gate: this.jdGate, store: deps.store, logger: deps.logger })
  }

  async start(): Promise<void> {
    await this.accounts.refresh()
    this.syncSources()
    this.accounts.on('changed', () => this.syncSources())
    // 热搜在后台分散地取（每 5 分钟最多取一个平台，每个平台最多 1 小时一次），打开搜索页时只读缓存
    this.search.startHotSchedule(() => this.enabled)
  }

  stop(): void {
    this.search.stopHotSchedule()
    this.mixer.stop()
    this.store.close()
  }

  enabledSources(): string[] {
    return this.enabled
  }

  /** 已登录的内容平台 ∩ 用户勾选（未设置时为全部已登录）。 */
  private syncSources(): void {
    const connected = this.accounts.platforms()
      .filter((p) => p.connected && !p.unavailable && p.health !== 'expired' && p.sections.includes('content'))
      .map((p) => p.id)
    const chosen = this.store.getSettings().sources.content
    const next = chosen ? connected.filter((p) => chosen.includes(p)) : connected
    if (next.join() === this.enabled.join()) return
    this.enabled = next
    this.log.info('sources', { sources: next })
    this.mixer.setSources(next.map((p) => this.adapter(p)))
  }

  private adapter(platform: string): PlatformAdapter {
    let a = this.adapters.get(platform)
    if (!a) this.adapters.set(platform, (a = this.adapterFor(platform)))
    return a
  }

  private remember(card: FeedCard): void {
    this.snapshots.delete(card.key)
    this.snapshots.set(card.key, snapshot(card))
    if (this.snapshots.size > SNAPSHOT_MEMORY) this.snapshots.delete(this.snapshots.keys().next().value!)
  }

  /** 找回卡片快照：先查本次会话下发过的，再查收藏 / 历史里的。 */
  private lookup(key: string): CardSnapshot {
    const s = this.snapshots.get(key) ?? this.store.findSnapshot(key)
    if (!s) throw new ParamError(`unknown card: ${key}`)
    return s
  }

  private backfilling = false

  private async backfillCovers(cards: CardSnapshot[]): Promise<void> {
    if (this.backfilling || cards.length === 0) return
    this.backfilling = true
    try {
      for (const c of cards.slice(0, 50)) await this.covers.save(c.key, c.cover, MEDIA_HEADERS[c.platform])
    } finally {
      this.backfilling = false
    }
  }

  register(rpc: RpcServer): void {
    this.accounts.on('changed', () => rpc.notify('accounts.changed', { platforms: this.accounts.platforms() }))
    this.notifyRest = (r) => rpc.notify('commerce.rest', r)
    this.mixer.on('source', (s) => {
      rpc.notify('feed.source', s)
      if (s.status === 'auth') void this.accounts.checkHealth(s.platform).catch(() => {})
    })

    const platform = (p: Record<string, unknown>) => {
      const id = str(p, 'platform')
      if (!getPlatform(id)) throw new ParamError(`unknown platform: ${id}`)
      return id
    }

    rpc
      .register('app.hello', () => ({ version: VERSION, settings: this.store.getSettings() }))

      .register('accounts.list', () => this.accounts.platforms())
      .register('accounts.refresh', () => this.accounts.refresh())
      .register('accounts.checkHealth', (p) => this.accounts.checkHealth(platform(p)))
      .register('accounts.loginQrcode', async (p, ctx) => {
        const id = platform(p)
        const account = await this.accounts.loginQrcode(id, { account: optStr(p, 'account'), onEvent: (e) => ctx.notify('accounts.login', e) })
        if (id === 'jd') this.jdGate.noteLogin() // 刚登录的 10 分钟里不跑后台的京东请求
        return account
      })
      .register('accounts.loginCookie', (p) => {
        const cookies = p.cookies
        const ok = typeof cookies === 'string' || (Array.isArray(cookies) && cookies.every((c) => c && typeof c.name === 'string' && typeof c.value === 'string'))
        if (!ok) throw new ParamError('cookies must be a cookie header string or [{name, value, domain?, path?, expires?}]')
        return this.accounts.loginCookie(platform(p), cookies as string | BrowserCookie[], { account: optStr(p, 'account') })
      })
      .register('accounts.cancelLogin', (p) => ({ cancelled: this.accounts.cancelLogin(platform(p)) }))
      .register('accounts.logout', async (p) => {
        await this.accounts.logout(platform(p), optStr(p, 'account'))
        return this.accounts.platforms()
      })
      .register('accounts.use', async (p) => {
        await this.accounts.use(platform(p), str(p, 'account'))
        return this.accounts.platforms()
      })

      .register('feed.next', async (p) => {
        const cards = await this.mixer.next(optInt(p, 'count', 1, 10) ?? 1, { waitMs: optInt(p, 'waitMs', 0, 15_000) ?? 0 })
        cards.forEach((c) => this.remember(c))
        const states = this.store.states(cards.map((c) => c.key))
        return { cards: cards.map((c) => ({ ...c, ...states[c.key]! })), sources: this.enabled, availability: cards.length > 0 ? { state: 'ok', resumeAt: null } : this.mixer.availability() }
      })
      .register('feed.refresh', async (p) => {
        const card = await this.mixer.refresh(str(p, 'key'))
        if (card) this.remember(card)
        return card
      })
      .register('feed.sources', () => ({ enabled: this.enabled, states: this.mixer.sourceStates() }))
      // 调试：所有平台假装冷却 N 秒（只给调试版的 catland-debug feed:rest:<秒> 用，不请求平台）
      .register('debug.simulateCooldown', (p) => {
        const only = Array.isArray(p.platforms) ? (p.platforms as unknown[]).filter((x): x is string => typeof x === 'string') : undefined
        this.mixer.simulateCooldown((optInt(p, 'seconds', 10, 3600) ?? 150) * 1000, only?.length ? only : undefined)
        return this.mixer.availability()
      })
      .register('feed.view', (p) => {
        this.store.recordView(this.lookup(str(p, 'key')), optInt(p, 'dwellMs', 0, 24 * 3600_000) ?? 0)
        return null
      })

      .register('search.query', (p) => {
        const query = str(p, 'query').trim()
        if (query.length === 0 || query.length > 60) throw new ParamError('query must be 1–60 characters')
        return this.search.query(platform(p), query, optStr(p, 'cursor') ?? null)
      })
      .register('search.hot', (p) => {
        const ps = p.platforms
        if (!Array.isArray(ps) || !ps.every((x) => typeof x === 'string' && getPlatform(x))) throw new ParamError('platforms must be platform ids')
        return this.search.hot(ps as string[])
      })
      .register('search.resolve', async (p) => {
        const card = await this.search.resolve(str(p, 'key'), p.fresh === true)
        if (!card) return null
        this.remember(card)
        return { ...card, ...this.store.states([card.key])[card.key]! }
      })

      .register('comments.list', (p) => {
        const card = this.lookup(str(p, 'key'))
        return this.comments.list(card.platform, card.url, optStr(p, 'cursor'))
      })
      .register('comments.replies', (p) => {
        const card = this.lookup(str(p, 'key'))
        return this.comments.replies(card.platform, card.url, str(p, 'commentId'), optStr(p, 'cursor'))
      })

      .register('interact.set', (p) => {
        const key = str(p, 'key')
        const kind = oneOf(p, 'kind', ['like', 'collect'] as const)
        if (bool(p, 'on')) {
          const card = this.lookup(key)
          this.store.save(kind, card)
          // 封面地址会过期：点赞 / 收藏时把封面存到本机
          if (!this.covers.localUrl(key)) void this.covers.save(key, card.cover, MEDIA_HEADERS[card.platform])
        } else {
          this.store.unsave(kind, key)
          if (!this.store.isSaved(key)) this.covers.remove(key)
        }
        return this.store.states([key])[key]
      })
      .register('interact.states', (p) => {
        const keys = p.keys
        if (!Array.isArray(keys) || !keys.every((k) => typeof k === 'string') || keys.length > 200) throw new ParamError('keys must be string[] (≤ 200)')
        return this.store.states(keys)
      })
      .register('interact.list', (p) => {
        const page = this.store.listSaved(oneOf(p, 'kind', ['like', 'collect'] as const), { limit: optInt(p, 'limit', 1, 200), before: optInt(p, 'before', 0, Number.MAX_SAFE_INTEGER) })
        const entries = page.entries.map((e) => ({ ...e, localCover: this.covers.localUrl(e.card.key) }))
        // 以前收藏、还没存过封面的：后台按原地址补存（地址还没过期的能存上；过期的等点开时用新地址补）
        void this.backfillCovers(entries.filter((e) => !e.localCover).map((e) => e.card))
        return { ...page, entries }
      })
      // 点开一条点赞 / 收藏：按快照重新解析出可播放媒体（地址一定重新取），并顺手更新本地封面
      .register('saved.resolve', async (p) => {
        const snap = this.lookup(str(p, 'key'))
        if (!getPlatform(snap.platform)) return null
        const item: Item = {
          id: snap.id, kind: snap.kind, url: snap.url, title: snap.title, text: snap.text, author: snap.author,
          created_at: snap.createdAt, cover: snap.cover, media: [],
          stats: { views: null, likes: null, comments: null, collects: null, shares: null }, price: null, status: null,
        }
        const card = await this.adapter(snap.platform).resolve(item, undefined, true)
        if (!card) return null
        this.remember(card)
        this.store.updateSnapshot(snapshot(card))
        if (card.cover) void this.covers.save(card.key, card.cover.url, card.cover.headers)
        return { ...card, ...this.store.states([card.key])[card.key]! }
      })

      .register('history.list', (p) => {
        const page = this.store.listHistory({ limit: optInt(p, 'limit', 1, 200), before: optInt(p, 'before', 0, Number.MAX_SAFE_INTEGER) })
        // 同时点赞 / 收藏过的，封面已存在本机，优先用它
        return { ...page, entries: page.entries.map((e) => ({ ...e, localCover: this.covers.localUrl(e.card.key) })) }
      })
      .register('history.remove', (p) => {
        this.store.removeHistory(str(p, 'key'))
        return null
      })
      // 导出 / 导入点赞、收藏、浏览历史（含本机封面，不含登录凭证）；路径来自用户在系统存储面板里选的位置
      .register('library.export', (p) => exportLibrary(this.store, this.covers, absPath(p)))
      .register('library.import', (p) => {
        try {
          return importLibrary(this.store, this.covers, absPath(p))
        } catch (err) {
          if (err instanceof LibraryFileError || (err as NodeJS.ErrnoException).code === 'ENOENT') throw new ParamError((err as Error).message)
          throw err
        }
      })
      // 购物小助手（ADR 0005）：京东搜索、心愿单
      .register('commerce.search', (p) => {
        const query = str(p, 'query').trim()
        if (query.length === 0 || query.length > 60) throw new ParamError('query must be 1–60 characters')
        const sort = (optStr(p, 'sort') ?? 'general') as (typeof JD_SORTS)[number]
        if (!JD_SORTS.includes(sort)) throw new ParamError(`sort must be one of ${JD_SORTS.join(' / ')}`)
        return this.commerce.search(query, sort, optStr(p, 'cursor') ?? null)
      })
      .register('commerce.status', () => ({ rest: this.commerce.rest() }))
      .register('wish.list', () => this.commerce.wishes())
      .register('wish.add', (p) => {
        const product = parseProduct(p.product)
        if (!product) throw new ParamError('product must be { sku, title, price, shop, cover, url, comments }')
        try {
          this.commerce.addWish(product)
        } catch (err) {
          if (err instanceof WishLimitError) throw new ParamError(err.message)
          throw err
        }
        return null
      })
      .register('wish.remove', (p) => {
        this.commerce.removeWish(str(p, 'sku'))
        return null
      })
      .register('history.clear', () => {
        this.store.clearHistory()
        return null
      })

      .register('weather.get', (p) => {
        if (!this.store.getSettings().weather) return null
        const lat = p.latitude, lon = p.longitude
        const ok = typeof lat === 'number' && typeof lon === 'number' && Math.abs(lat) <= 90 && Math.abs(lon) <= 180
        return this.weather.get(ok ? { latitude: lat, longitude: lon } : undefined)
      })

      .register('settings.get', () => this.store.getSettings())
      .register('settings.update', (p) => {
        let s: Settings
        try {
          s = this.store.updateSettings(p as Partial<Settings>)
        } catch (err) {
          if (err instanceof TypeError) throw new ParamError(err.message)
          throw err
        }
        this.syncSources()
        return s
      })
  }
}

function absPath(p: Record<string, unknown>): string {
  const path = str(p, 'path')
  if (!isAbsolute(path)) throw new ParamError('path must be absolute')
  return path
}
