/** App：组装各服务，维护「信息源 = 已登录 ∩ 用户勾选」的联动，并把能力注册成 RPC 方法。 */
import { AccountService, type BrowserCookie, type CatbusClient } from './accounts/service.ts'
import { getPlatform } from './accounts/catalog.ts'
import { createAdapter } from './content/adapters.ts'
import { CommentService } from './content/comments.ts'
import { FeedMixer } from './content/mixer.ts'
import type { FeedCard, PlatformAdapter } from './content/types.ts'
import type { Logger } from './log.ts'
import { bool, oneOf, optInt, optStr, ParamError, RpcServer, str } from './rpc/server.ts'
import { snapshot, type CardSnapshot, type Settings, Store } from './store/store.ts'
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
}

export class App {
  readonly accounts: AccountService
  readonly mixer: FeedMixer
  readonly store: Store
  private readonly comments: CommentService
  private readonly weather: WeatherService
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
  }

  async start(): Promise<void> {
    await this.accounts.refresh()
    this.syncSources()
    this.accounts.on('changed', () => this.syncSources())
  }

  stop(): void {
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
    const s = this.snapshots.get(key) ?? this.findSaved(key)
    if (!s) throw new ParamError(`unknown card: ${key}`)
    return s
  }

  private findSaved(key: string): CardSnapshot | undefined {
    for (const kind of ['like', 'collect'] as const) {
      const hit = this.store.listSaved(kind, { limit: 200 }).entries.find((e) => e.card.key === key)
      if (hit) return hit.card
    }
    return this.store.listHistory({ limit: 200 }).entries.find((e) => e.card.key === key)?.card
  }

  register(rpc: RpcServer): void {
    this.accounts.on('changed', () => rpc.notify('accounts.changed', { platforms: this.accounts.platforms() }))
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
      .register('accounts.loginQrcode', (p, ctx) =>
        this.accounts.loginQrcode(platform(p), { account: optStr(p, 'account'), onEvent: (e) => ctx.notify('accounts.login', e) }),
      )
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
        return { cards: cards.map((c) => ({ ...c, ...states[c.key]! })), sources: this.enabled }
      })
      .register('feed.refresh', async (p) => {
        const card = await this.mixer.refresh(str(p, 'key'))
        if (card) this.remember(card)
        return card
      })
      .register('feed.sources', () => ({ enabled: this.enabled, states: this.mixer.sourceStates() }))
      .register('feed.view', (p) => {
        this.store.recordView(this.lookup(str(p, 'key')), optInt(p, 'dwellMs', 0, 24 * 3600_000) ?? 0)
        return null
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
        if (bool(p, 'on')) this.store.save(kind, this.lookup(key))
        else this.store.unsave(kind, key)
        return this.store.states([key])[key]
      })
      .register('interact.states', (p) => {
        const keys = p.keys
        if (!Array.isArray(keys) || !keys.every((k) => typeof k === 'string') || keys.length > 200) throw new ParamError('keys must be string[] (≤ 200)')
        return this.store.states(keys)
      })
      .register('interact.list', (p) =>
        this.store.listSaved(oneOf(p, 'kind', ['like', 'collect'] as const), { limit: optInt(p, 'limit', 1, 200), before: optInt(p, 'before', 0, Number.MAX_SAFE_INTEGER) }),
      )

      .register('history.list', (p) => this.store.listHistory({ limit: optInt(p, 'limit', 1, 200), before: optInt(p, 'before', 0, Number.MAX_SAFE_INTEGER) }))
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
