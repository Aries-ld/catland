import { PassThrough } from 'node:stream'
import { describe, expect, it } from 'vitest'
import { App } from '../src/app.ts'
import type { CatbusClient } from '../src/accounts/service.ts'
import { CatbusCallError, type CatbusResult, type RunOptions } from '../src/catbus/runner.ts'
import type { Account, Item } from '../src/catbus/types.ts'
import { FeedMixer } from '../src/content/mixer.ts'
import { cardKey, type FeedCard, type FeedPage, type PlatformAdapter } from '../src/content/types.ts'
import { createMemoryLogger } from '../src/log.ts'
import { ParamError, RPC_ERRORS, RpcServer } from '../src/rpc/server.ts'
import { Store } from '../src/store/store.ts'

/** 测试用客户端：发请求、等回复、收通知。 */
function connect(rpc: RpcServer) {
  const toServer = new PassThrough()
  const fromServer = new PassThrough()
  const done = rpc.serve(toServer, fromServer)
  const pending = new Map<number, (msg: any) => void>()
  const notes: Array<{ method: string; params: any }> = []
  let buf = ''
  fromServer.on('data', (b: Buffer) => {
    buf += b.toString()
    let nl
    while ((nl = buf.indexOf('\n')) >= 0) {
      const msg = JSON.parse(buf.slice(0, nl))
      buf = buf.slice(nl + 1)
      if (msg.id !== undefined && pending.has(msg.id)) pending.get(msg.id)!(msg)
      else if (msg.method) notes.push(msg)
      else pending.get(-1)?.(msg)
    }
  })
  let seq = 0
  const raw = (line: string) =>
    new Promise<any>((resolve) => {
      pending.set(-1, resolve)
      toServer.write(line + '\n')
    })
  const call = (method: string, params?: unknown) =>
    new Promise<any>((resolve) => {
      const id = ++seq
      pending.set(id, resolve)
      toServer.write(JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n')
    })
  const ok = async (method: string, params?: unknown) => {
    const r = await call(method, params)
    if (r.error) throw new Error(`${method}: ${JSON.stringify(r.error)}`)
    return r.result
  }
  return { call, ok, raw, notes, close: () => toServer.end(), done }
}

describe('RpcServer', () => {
  const server = () =>
    new RpcServer({ logger: createMemoryLogger() })
      .register('echo', (p) => p)
      .register('bad', () => { throw new ParamError('x is required') })
      .register('catbus', () => { throw new CatbusCallError('RISK_CONTROL', 'captcha', { hint: '稍后再试' }) })
      .register('crash', () => { throw new Error('boom') })
      .register('slow', () => new Promise((r) => setTimeout(() => r('slow'), 50)))
      .register('push', (_p, ctx) => { ctx.notify('hello', { a: 1 }); return null })

  it('正常调用与错误映射', async () => {
    const c = connect(server())
    expect((await c.call('echo', { a: 1 })).result).toEqual({ a: 1 })
    expect((await c.call('echo')).result).toEqual({})
    expect((await c.call('nope')).error.code).toBe(RPC_ERRORS.METHOD_NOT_FOUND)
    expect((await c.call('echo', [1])).error.code).toBe(RPC_ERRORS.INVALID_PARAMS)
    expect((await c.call('bad')).error).toEqual({ code: RPC_ERRORS.INVALID_PARAMS, message: 'x is required' })
    expect((await c.call('catbus')).error).toEqual({ code: RPC_ERRORS.APP, message: 'captcha', data: { code: 'RISK_CONTROL', hint: '稍后再试', retryable: false } })
    expect((await c.call('crash')).error.code).toBe(RPC_ERRORS.INTERNAL)
    expect((await c.raw('{not json')).error.code).toBe(RPC_ERRORS.PARSE)
    expect((await c.raw('{"jsonrpc":"1.0","id":9,"method":"echo"}')).error.code).toBe(RPC_ERRORS.INVALID_REQUEST)
    c.close()
    await c.done
  })

  it('请求并发处理，慢请求不阻塞后续请求；支持服务端通知', async () => {
    const c = connect(server())
    const order: string[] = []
    await Promise.all([c.ok('slow').then(() => order.push('slow')), c.ok('echo', { fast: 1 }).then(() => order.push('fast'))])
    expect(order).toEqual(['fast', 'slow'])
    await c.ok('push')
    expect(c.notes).toEqual([{ jsonrpc: '2.0', method: 'hello', params: { a: 1 } }])
  })
})

// —— App 端到端（替身 catbus + 替身适配器）——

const account = (platform: string): Account => ({ platform, endpoint: 'web', account: 'default', current: true, user: { id: 'u', name: 'n', url: null }, method: 'qrcode', updated_at: null })

class FakeCatbus implements CatbusClient {
  accounts: Account[] = [account('xhs'), account('bilibili'), account('jd')]
  calls: string[] = []
  async run<T>(argv: readonly string[], _opts?: RunOptions): Promise<CatbusResult<T>> {
    this.calls.push(argv.join(' '))
    const key = argv.join(' ')
    if (key === 'auth list') return { data: this.accounts as T, page: null, account: null }
    if (argv[1] === 'comment' && argv[2] === 'list') return { data: [{ id: 'c1', item_id: '1', parent_id: null, author: null, text: '好', created_at: null, stats: { likes: 1, replies: 0 } }] as T, page: { cursor: 'n', has_more: true }, account: null }
    if (argv[1] === 'auth' && argv[2] === 'logout') {
      this.accounts = this.accounts.filter((a) => a.platform !== argv[0])
      return { data: null as T, page: null, account: null }
    }
    throw new Error(`unexpected ${key}`)
  }
}

class StubAdapter implements PlatformAdapter {
  readonly platform: string
  private n = 0
  constructor(platform: string) {
    this.platform = platform
  }
  async fetchFeed(): Promise<FeedPage> {
    const base = this.n
    this.n += 5
    const items: Item[] = Array.from({ length: 5 }, (_, i) => ({
      id: String(base + i), kind: 'video', url: `https://${this.platform}/${base + i}`, title: 't', text: null, author: null, created_at: null, cover: null, media: [],
      stats: { views: null, likes: null, comments: null, collects: null, shares: null }, price: null, status: null,
    }))
    return { items, cursor: null, hasMore: true }
  }
  async resolve(it: Item): Promise<FeedCard> {
    return {
      key: cardKey(this.platform, it.id), platform: this.platform, id: it.id, url: it.url, kind: 'video', title: it.title, text: null, author: null, createdAt: null,
      cover: null, stats: it.stats, video: { url: 'https://v.mp4', headers: {}, width: 1, height: 1, duration: 1 }, images: [], resolvedAt: Date.now(), expiresAt: Date.now() + 3600_000,
    }
  }
}

async function startApp() {
  const logger = createMemoryLogger()
  const catbus = new FakeCatbus()
  const store = new Store({ path: ':memory:' })
  const mixer = new FeedMixer({ logger, seen: store, feedMinIntervalMs: 0, resolveMinIntervalMs: 0 })
  const app = new App({ catbus, logger, store, mixer, adapterFor: (p) => new StubAdapter(p) })
  const rpc = new RpcServer({ logger })
  app.register(rpc)
  await app.start()
  return { app, catbus, client: connect(rpc) }
}

describe('App via RPC', () => {
  it('信息源 = 已登录的内容平台（不含电商）；刷卡片带点赞状态', async () => {
    const { app, client } = await startApp()
    expect((await client.ok('feed.sources')).enabled).toEqual(['xhs', 'bilibili'])
    const first = (await client.ok('feed.next', { count: 4, waitMs: 1000 })).cards
    expect(first.length).toBeGreaterThanOrEqual(1) // 首屏只等第一张，不为凑满而等
    await new Promise((r) => setTimeout(r, 30))
    const cards = [...first, ...(await client.ok('feed.next', { count: 4 - first.length })).cards]
    expect(cards.length).toBe(4)
    expect(new Set(cards.map((c: FeedCard) => c.platform))).toEqual(new Set(['xhs', 'bilibili']))
    expect(cards[0]).toMatchObject({ liked: false, collected: false })
    app.stop()
  })

  it('点赞收藏落本地库，列表可查，状态随卡片下发；不调用平台写接口', async () => {
    const { app, client, catbus } = await startApp()
    const { cards } = await client.ok('feed.next', { count: 2, waitMs: 1000 })
    const key = cards[0].key
    expect(await client.ok('interact.set', { key, kind: 'like', on: true })).toEqual({ liked: true, collected: false })
    expect(await client.ok('interact.set', { key, kind: 'collect', on: true })).toEqual({ liked: true, collected: true })
    expect((await client.ok('interact.list', { kind: 'like' })).entries[0].card.key).toBe(key)
    expect(await client.ok('interact.set', { key, kind: 'like', on: false })).toEqual({ liked: false, collected: true })
    expect((await client.ok('interact.states', { keys: [key, 'x:none'] }))[key]).toEqual({ liked: false, collected: true })
    expect(catbus.calls.some((c) => /\b(like|collect)\b/.test(c))).toBe(false)
    expect((await client.call('interact.set', { key: 'nope:1', kind: 'like', on: true })).error.code).toBe(RPC_ERRORS.INVALID_PARAMS)
    expect((await client.call('interact.set', { key, kind: 'digg', on: true })).error.code).toBe(RPC_ERRORS.INVALID_PARAMS)
    app.stop()
  })

  it('浏览记录与评论按卡片 key 找回原链接', async () => {
    const { app, client, catbus } = await startApp()
    const { cards } = await client.ok('feed.next', { count: 1, waitMs: 1000 })
    await client.ok('feed.view', { key: cards[0].key, dwellMs: 3200 })
    expect((await client.ok('history.list')).entries[0]).toMatchObject({ card: { key: cards[0].key }, dwellMs: 3200 })
    const page = await client.ok('comments.list', { key: cards[0].key })
    expect(page).toMatchObject({ cursor: 'n', hasMore: true, comments: [{ id: 'c1', text: '好' }] })
    expect(catbus.calls).toContain(`${cards[0].platform} comment list ${cards[0].url} --limit 20`)
    await client.ok('history.clear')
    expect((await client.ok('history.list')).entries).toEqual([])
    app.stop()
  })

  it('设置：默认静音；勾选信息源立即生效；登出平台自动移出信息源并推送通知', async () => {
    const { app, client } = await startApp()
    expect((await client.ok('app.hello')).settings.muted).toBe(true)
    await client.ok('settings.update', { sources: { content: ['bilibili'] } })
    expect((await client.ok('feed.sources')).enabled).toEqual(['bilibili'])
    await client.ok('settings.update', { sources: { content: ['bilibili', 'xhs'] } })
    expect((await client.call('settings.update', { muted: 1 })).error.code).toBe(RPC_ERRORS.INVALID_PARAMS)
    await client.ok('accounts.logout', { platform: 'bilibili' })
    expect((await client.ok('feed.sources')).enabled).toEqual(['xhs'])
    expect(client.notes.some((n) => n.method === 'accounts.changed')).toBe(true)
    expect((await client.call('accounts.checkHealth', { platform: '12306' })).error.code).toBe(RPC_ERRORS.INVALID_PARAMS)
    app.stop()
  })

  it('跨会话不重复：看过的卡片下次启动不再出现', async () => {
    const logger = createMemoryLogger()
    const store = new Store({ path: ':memory:' })
    store.add('xhs:0')
    store.add('bilibili:0')
    const mixer = new FeedMixer({ logger, seen: store, feedMinIntervalMs: 0, resolveMinIntervalMs: 0 })
    const app = new App({ catbus: new FakeCatbus(), logger, store, mixer, adapterFor: (p) => new StubAdapter(p) })
    const rpc = new RpcServer({ logger })
    app.register(rpc)
    await app.start()
    const { cards } = await connect(rpc).ok('feed.next', { count: 6, waitMs: 1000 })
    expect(cards.map((c: FeedCard) => c.key)).not.toContain('xhs:0')
    expect(cards.map((c: FeedCard) => c.key)).not.toContain('bilibili:0')
    app.stop()
  })
})
