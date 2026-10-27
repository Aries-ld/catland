import { describe, expect, it } from 'vitest'
import type { CatbusClient } from '../src/accounts/service.ts'
import type { CatbusResult, RunOptions } from '../src/catbus/runner.ts'
import type { Item, Media } from '../src/catbus/types.ts'
import { BilibiliAdapter, CatbusAdapter, createAdapter, MEDIA_HEADERS, XhsAdapter } from '../src/content/adapters.ts'
import { createMemoryLogger } from '../src/log.ts'

const stats = { views: null, likes: 10, comments: null, collects: null, shares: null }
const item = (over: Partial<Item> = {}): Item => ({
  id: '1', kind: 'video', url: 'https://e/1', title: 't', text: null, author: { id: 'a', name: 'A', url: null }, created_at: null,
  cover: 'https://img/c.jpg', media: [], stats, price: null, status: null, ...over,
})
const media = (type: string, url: string, w = 720, h = 1280): Media => ({ id: null, type, url, width: w, height: h, duration: 10 })

class StubCatbus implements CatbusClient {
  calls: string[][] = []
  private readonly reply: (argv: readonly string[]) => unknown
  constructor(reply: (argv: readonly string[]) => unknown) {
    this.reply = reply
  }
  async run<T>(argv: readonly string[], _opts?: RunOptions): Promise<CatbusResult<T>> {
    this.calls.push([...argv])
    return { data: this.reply(argv) as T, page: { cursor: 'next', has_more: true }, account: 'default' }
  }
}

const deps = (catbus: CatbusClient, fetch?: typeof globalThis.fetch) => ({ catbus, logger: createMemoryLogger(), now: () => 1_000, fetch })

describe('CatbusAdapter', () => {
  it('fetchFeed 带 --limit 与游标，映射分页', async () => {
    const c = new StubCatbus(() => [item()])
    const a = new CatbusAdapter('x', deps(c))
    const p = await a.fetchFeed('abc')
    expect(c.calls[0]).toEqual(['x', 'feed', 'list', '--limit', '10', '--cursor', 'abc'])
    expect(p).toMatchObject({ cursor: 'next', hasMore: true })
  })

  it('列表已带媒体时不再发请求，按平台附请求头', async () => {
    const c = new StubCatbus(() => { throw new Error('should not call') })
    const card = await new CatbusAdapter('x', deps(c)).resolve(item({ media: [media('video', 'https://v/1.mp4')] }))
    expect(card).toMatchObject({ key: 'x:1', kind: 'video', video: { url: 'https://v/1.mp4', headers: MEDIA_HEADERS.x } })
    expect(card!.expiresAt).toBe(1_000 + 20 * 60_000)
    expect(c.calls).toEqual([])
  })

  it('缺媒体时依次 item get → item media', async () => {
    const c = new StubCatbus((argv) => (argv[2] === 'get' ? item() : [media('video', 'https://v/2.mp4')]))
    const card = await new CatbusAdapter('douyin', deps(c)).resolve(item())
    expect(c.calls.map((a) => a[2])).toEqual(['get', 'media'])
    expect(card?.video?.headers.Referer).toBe('https://www.douyin.com/')
  })

  it('推荐流里的媒体地址不是 http 地址（抖音给的是内部 uri）时，用 item get 补全', async () => {
    const c = new StubCatbus(() => item({ media: [media('video', 'https://v26-web.douyinvod.com/x.mp4')] }))
    const card = await new CatbusAdapter('douyin', deps(c)).resolve(item({ media: [media('video', 'aeb0f54fda681deeb6ab45c94cde9de5')] }))
    expect(c.calls.map((a) => a[2])).toEqual(['get'])
    expect(card?.video?.url).toBe('https://v26-web.douyinvod.com/x.mp4')
  })

  it('纯文字和分离音视频轨的内容被过滤', async () => {
    const c = new StubCatbus(() => item())
    const a = new CatbusAdapter('x', deps(c))
    expect(await a.resolve(item({ kind: 'text' }))).toBeNull()
    expect(await a.resolve(item({ media: [media('video', 'https://v'), media('audio', 'https://a')] }))).toBeNull()
  })
})

describe('XhsAdapter', () => {
  it('用 item get 拿图集与全文，保留列表里有而详情为空的字段', async () => {
    const detail = item({ kind: 'image', text: '正文', cover: null, media: [media('image', 'https://i/1'), media('image', 'https://i/2')], stats: { ...stats, likes: null, comments: 5 } })
    const c = new StubCatbus(() => detail)
    const card = await new XhsAdapter(deps(c)).resolve(item({ kind: 'image' }))
    expect(c.calls).toEqual([['xhs', 'item', 'get', 'https://e/1']])
    expect(card).toMatchObject({ kind: 'image', text: '正文', cover: { url: 'https://img/c.jpg' }, stats: { likes: 10, comments: 5 } })
    expect(card!.images.map((i) => i.url)).toEqual(['https://i/1', 'https://i/2'])
  })
})

describe('BilibiliAdapter', () => {
  const json = (body: unknown) => new Response(JSON.stringify(body), { status: 200, headers: { 'content-type': 'application/json' } })

  /** 模拟 B 站：spi 发 buvid；view / playurl 没带 buvid 时 412；可指定前 n 次 412。 */
  function biliFetch(opts: { always412?: boolean; first412?: number; viewCode?: number } = {}) {
    const log: Array<{ url: string; headers: Record<string, string> }> = []
    let spi = 0
    let left412 = opts.first412 ?? 0
    const fetch = (async (url: string, init?: RequestInit) => {
      const headers = init?.headers as Record<string, string>
      log.push({ url, headers })
      if (url.includes('finger/spi')) return json({ code: 0, data: { b_3: `B3-${++spi}`, b_4: 'B4' } })
      if (!headers.Cookie?.includes('buvid3=') || opts.always412 || left412-- > 0) return new Response('', { status: 412 })
      if (url.includes('/view')) {
        return opts.viewCode
          ? json({ code: opts.viewCode, message: '啥都木有' })
          : json({ code: 0, data: { cid: 42, duration: 9999, pages: [{ cid: 42, duration: 537, dimension: { width: 1080, height: 1920, rotate: 0 } }, { cid: 43, duration: 9462 }] } })
      }
      return json({ code: 0, data: { durl: [{ url: 'https://cdn/b.mp4', length: 537000 }] } })
    }) as typeof globalThis.fetch
    return { fetch, log, spiCalls: () => spi }
  }
  const noCatbus = () => new StubCatbus(() => { throw new Error('catbus not needed') })

  it('走 H5 MP4：带访客 buvid 与 Referer，多 P 只取第 1P 的时长和尺寸', async () => {
    const f = biliFetch()
    const a = new BilibiliAdapter(deps(noCatbus(), f.fetch))
    const card = await a.resolve(item({ id: 'BV1' }))
    const play = f.log.find((l) => l.url.includes('playurl'))!
    expect(play.url).toContain('bvid=BV1&cid=42&qn=64&fnval=1&platform=html5')
    expect(f.log.filter((l) => !l.url.includes('spi')).every((l) => l.headers.Referer === 'https://www.bilibili.com/' && l.headers.Cookie === 'buvid3=B3-1; buvid4=B4')).toBe(true)
    expect(card).toMatchObject({ key: 'bilibili:BV1', video: { url: 'https://cdn/b.mp4', width: 1080, height: 1920, duration: 537 } })
    expect(card!.video!.headers.Cookie).toBeUndefined() // 媒体 CDN 不需要 cookie
    expect(card!.expiresAt).toBe(1_000 + 60 * 60_000)
    await a.resolve(item({ id: 'BV2' }))
    expect(f.spiCalls()).toBe(1) // buvid 复用
  })

  it('412 时换一个 buvid 重试一次', async () => {
    const f = biliFetch({ first412: 1 })
    expect(await new BilibiliAdapter(deps(noCatbus(), f.fetch)).resolve(item({ id: 'BV3' }))).not.toBeNull()
    expect(f.spiCalls()).toBe(2)
  })

  it('持续 412 报 RISK_CONTROL，让混排器冷却该平台', async () => {
    const f = biliFetch({ always412: true })
    await expect(new BilibiliAdapter(deps(noCatbus(), f.fetch)).resolve(item({ id: 'BV4' }))).rejects.toMatchObject({ code: 'RISK_CONTROL' })
  })

  it('业务错误码抛出普通错误', async () => {
    const f = biliFetch({ viewCode: -404 })
    await expect(new BilibiliAdapter(deps(noCatbus(), f.fetch)).resolve(item({ id: 'BV5' }))).rejects.toThrow('-404')
  })
})

describe('createAdapter', () => {
  it('按平台选择适配器', () => {
    const c = new StubCatbus(() => null)
    expect(createAdapter('xhs', deps(c))).toBeInstanceOf(XhsAdapter)
    expect(createAdapter('bilibili', deps(c))).toBeInstanceOf(BilibiliAdapter)
    expect(createAdapter('x', deps(c)).constructor).toBe(CatbusAdapter)
  })
})
