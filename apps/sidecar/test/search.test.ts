import { describe, expect, it } from 'vitest'
import { isHls, toSearchHit } from '../src/content/adapters.ts'
import { CatbusCallError } from '../src/catbus/runner.ts'
import type { Item } from '../src/catbus/types.ts'
import { FeedMixer } from '../src/content/mixer.ts'
import { SearchService } from '../src/content/search.ts'
import { cardKey, type FeedCard, type FeedPage, type PlatformAdapter } from '../src/content/types.ts'
import { createMemoryLogger } from '../src/log.ts'

const stats = { views: null, likes: 10, comments: null, collects: null, shares: null }
const item = (id: string, over: Partial<Item> = {}): Item => ({
  id, kind: 'video', url: `https://e/${id}`, title: `t${id}`, text: null, author: { id: 'u', name: 'a', url: null, avatar: null } as Item['author'],
  created_at: null, cover: `https://img/${id}.jpg`, media: [], stats, price: null, status: null, ...over,
})

class FakeSearch implements PlatformAdapter {
  calls: Array<{ query: string; cursor: string | null }> = []
  error: Error | null = null
  readonly platform: string
  constructor(platform: string) {
    this.platform = platform
  }
  async fetchFeed(): Promise<FeedPage> {
    return { items: [], cursor: null, hasMore: false }
  }
  async search(query: string, cursor: string | null): Promise<FeedPage> {
    this.calls.push({ query, cursor })
    if (this.error) throw this.error
    const start = cursor ? Number(cursor) : 0
    return { items: [item(`${start}`), item(`${start + 1}`, { kind: 'text' }), item(`${start + 2}`, { kind: 'image' })], cursor: `${start + 3}`, hasMore: true }
  }
  hotCalls = 0
  hotError: Error | null = null
  async hotKeywords() {
    this.hotCalls++
    if (this.hotError) throw this.hotError
    return [{ text: `${this.platform}热词1`, heat: null }, { text: '共同热词', heat: null }, { text: `${this.platform}热词2`, heat: 9 }]
  }
  async resolve(it: Item): Promise<FeedCard | null> {
    const now = Date.now()
    return {
      key: cardKey(this.platform, it.id), platform: this.platform, id: it.id, url: it.url, kind: 'video', title: it.title, text: null, author: null,
      createdAt: null, cover: null, stats: it.stats, video: { url: `https://cdn/${it.id}.mp4`, headers: {}, width: 1, height: 1, duration: 1 },
      images: [], resolvedAt: now, expiresAt: now + 60_000,
    }
  }
}

function setup(opts: { minIntervalMs?: number } = {}) {
  const logger = createMemoryLogger()
  const adapters = new Map<string, FakeSearch>([['xhs', new FakeSearch('xhs')], ['douyin', new FakeSearch('douyin')]])
  // 推荐流翻页间隔拉得很长：测试里只用它的风控状态
  const mixer = new FeedMixer({ logger, riskCooldownMs: 60_000, feedMinIntervalMs: 3_600_000 })
  mixer.setSources([...adapters.values()])
  const slept: number[] = []
  const search = new SearchService({
    logger, mixer, adapterFor: (p) => adapters.get(p)!, minIntervalMs: opts.minIntervalMs ?? 0,
    sleep: async (ms) => { slept.push(ms) },
  })
  return { adapters, mixer, search, slept }
}

describe('toSearchHit', () => {
  it('keeps cover, duration and platform headers; skips text-only items', () => {
    const h = toSearchHit('douyin', item('1', { cover: null, media: [{ type: 'video', url: 'https://v/1.mp4', width: 720, height: 1280, duration: 156.4 } as Item['media'][number]] }))
    expect(h).toMatchObject({ key: 'douyin:1', kind: 'video', duration: 156, cover: null })
    const x = toSearchHit('xhs', item('2', { kind: 'image' }))
    expect(x).toMatchObject({ kind: 'image', cover: { url: 'https://img/2.jpg' }, title: 't2' })
    expect(toSearchHit('xhs', item('3', { kind: 'text' }))).toBeNull()
    expect(toSearchHit('bilibili', item('4'))?.cover?.headers.Referer).toBe('https://www.bilibili.com/')
  })
})

describe('isHls', () => {
  it('spots Kuaishou realtime remux playlists that end in .mp4', () => {
    expect(isHls('https://v23-vod-3.kwaicdn.com/vod-rt-remux/hls-ts/v0/REALTIME_REMUX_TS_4999/video-def/enc_1_b.mp4/1_15bb.m3u8?x=1')).toBe(true)
    expect(isHls('https://v23-vod-3.kwaicdn.com/vod-rt-remux/hls-ts/v0/REALTIME_REMUX_TS_4999/video-def/enc_1_b.mp4/1_15bb')).toBe(true)
    expect(isHls('https://v1.kwaicdn.com/ksc2/abc.mp4?pkey=1')).toBe(false)
  })
})

describe('SearchService', () => {
  it('returns hits per platform with a cursor for the next page', async () => {
    const { search, adapters } = setup()
    const r = await search.query('xhs', '  露营  ')
    expect(r.status).toBe('ok')
    expect(r.hits.map((h) => h.key)).toEqual(['xhs:0', 'xhs:2']) // 纯文字被跳过
    expect(r.cursor).toBe('3')
    expect(adapters.get('xhs')!.calls[0]).toEqual({ query: '露营', cursor: null })
    const next = await search.query('xhs', '露营', r.cursor)
    expect(next.hits.map((h) => h.key)).toEqual(['xhs:3', 'xhs:5'])
  })

  it('caches the same query and page instead of asking the platform again', async () => {
    const { search, adapters } = setup()
    await search.query('xhs', '露营')
    await search.query('xhs', '露营')
    expect(adapters.get('xhs')!.calls).toHaveLength(1)
    await search.query('xhs', '帐篷')
    expect(adapters.get('xhs')!.calls).toHaveLength(2)
  })

  it('spaces out requests to the same platform', async () => {
    const { search, slept } = setup({ minIntervalMs: 2_000 })
    await search.query('xhs', 'a')
    await search.query('xhs', 'b')
    await search.query('douyin', 'a') // 其他平台不受影响
    expect(slept).toHaveLength(1)
    expect(slept[0]).toBeGreaterThan(1_000)
  })

  it('shares risk control with the feed: a throttled search cools the platform down, and resting platforms are skipped', async () => {
    const { search, adapters, mixer } = setup()
    adapters.get('douyin')!.error = new CatbusCallError('RISK_CONTROL', 'blocked')
    expect((await search.query('douyin', '露营')).status).toBe('resting')
    expect(mixer.statusOf('douyin')).toBe('cooldown')
    adapters.get('douyin')!.error = null
    expect((await search.query('douyin', '帐篷')).status).toBe('resting')
    expect(adapters.get('douyin')!.calls).toHaveLength(1) // 冷却中不再发请求
    expect((await search.query('xhs', '露营')).status).toBe('ok') // 其他平台照常
  })

  it('reports expired logins as auth and pauses the platform', async () => {
    const { search, adapters, mixer } = setup()
    adapters.get('xhs')!.error = new CatbusCallError('AUTH_EXPIRED', 'expired')
    expect((await search.query('xhs', '露营')).status).toBe('auth')
    expect(mixer.statusOf('xhs')).toBe('auth')
  })

  it('other errors are thrown to the caller and do not pause the feed', async () => {
    const { search, adapters, mixer } = setup()
    adapters.get('xhs')!.error = new Error('boom')
    await expect(search.query('xhs', '露营')).rejects.toThrow('boom')
    expect(mixer.statusOf('xhs')).toBe('active')
  })

  it('a retry after a playback failure asks for a fresh address', async () => {
    const { search, adapters } = setup()
    await search.query('xhs', '露营')
    const calls: boolean[] = []
    const a = adapters.get('xhs')!
    const orig = a.resolve.bind(a)
    a.resolve = async (it: Item, _signal?: AbortSignal, fresh?: boolean) => { calls.push(fresh ?? false); return orig(it) }
    await search.resolve('xhs:0')
    await search.resolve('xhs:0', true)
    expect(calls).toEqual([false, true])
  })

  it('hot keywords: merged round-robin, deduped, cached, and unsupported platforms are remembered', async () => {
    const { search, adapters } = setup()
    adapters.get('douyin')!.hotError = new CatbusCallError('NOT_IMPLEMENTED', 'douyin keyword hot 尚未实现')
    const words = await search.hot(['xhs', 'douyin'])
    expect(words.map((w) => w.text)).toEqual(['xhs热词1', '共同热词', 'xhs热词2'])
    expect(words[0]!.platform).toBe('xhs')
    await search.hot(['xhs', 'douyin'])
    expect(adapters.get('xhs')!.hotCalls).toBe(1) // 30 分钟缓存
    expect(adapters.get('douyin')!.hotCalls).toBe(1) // 没实现：记住，不再请求
  })

  it('hot keywords skip platforms in cooldown', async () => {
    const { search, adapters, mixer } = setup()
    mixer.reportError('xhs', new CatbusCallError('RISK_CONTROL', 'blocked'))
    expect(await search.hot(['xhs'])).toEqual([])
    expect(adapters.get('xhs')!.hotCalls).toBe(0)
  })

  it('resolves an opened hit into a playable card', async () => {
    const { search } = setup()
    await search.query('xhs', '露营')
    const card = await search.resolve('xhs:0')
    expect(card?.video?.url).toBe('https://cdn/0.mp4')
    expect(await search.resolve('xhs:unknown')).toBeNull()
  })
})
