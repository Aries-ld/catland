import { describe, expect, it } from 'vitest'
import { CatbusCallError } from '../src/catbus/runner.ts'
import type { Item } from '../src/catbus/types.ts'
import { FeedMixer, MemorySeenStore, type MixerOptions } from '../src/content/mixer.ts'
import { cardKey, type FeedCard, type FeedPage, type PlatformAdapter } from '../src/content/types.ts'
import { createMemoryLogger } from '../src/log.ts'

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))

const item = (id: string, kind = 'video'): Item => ({
  id, kind, url: `https://e/${id}`, title: id, text: null, author: null, created_at: null, cover: null,
  media: [], stats: { views: null, likes: null, comments: null, collects: null, shares: null }, price: null, status: null,
})

/** 可编程的平台替身：每页 pageSize 条，id 递增；可注入错误与延迟。 */
class FakeAdapter implements PlatformAdapter {
  fetches = 0
  resolves = 0
  feedError: (() => Error | null) | null = null
  resolveError: ((id: string) => Error | null) | null = null
  resolveDelayMs = 0
  ttlMs = 60 * 60_000
  pageIds: ((page: number) => string[]) | null = null
  readonly platform: string
  private readonly pageSize: number

  constructor(platform: string, pageSize = 4) {
    this.platform = platform
    this.pageSize = pageSize
  }

  async fetchFeed(): Promise<FeedPage> {
    const page = this.fetches++
    const err = this.feedError?.()
    if (err) throw err
    const ids = this.pageIds?.(page) ?? Array.from({ length: this.pageSize }, (_, i) => `${page * this.pageSize + i}`)
    return { items: ids.map((id) => item(id, id.startsWith('t') ? 'text' : 'video')), cursor: `c${page}`, hasMore: true }
  }

  async resolve(it: Item, signal?: AbortSignal): Promise<FeedCard | null> {
    this.resolves++
    if (this.resolveDelayMs) await sleep(this.resolveDelayMs)
    if (signal?.aborted) throw new CatbusCallError('ABORTED', 'aborted')
    const err = this.resolveError?.(it.id)
    if (err) throw err
    if (it.kind === 'text') return null
    const now = Date.now()
    return {
      key: cardKey(this.platform, it.id), platform: this.platform, id: it.id, url: it.url, kind: 'video', title: it.title, text: null,
      author: null, createdAt: null, cover: null, stats: it.stats, video: { url: `https://cdn/${it.id}.mp4`, headers: {}, width: 1, height: 1, duration: 1 },
      images: [], resolvedAt: now, expiresAt: now + this.ttlMs,
    }
  }
}

function mixer(over: Partial<MixerOptions> = {}) {
  return new FeedMixer({
    logger: createMemoryLogger(), feedMinIntervalMs: 0, resolveMinIntervalMs: 0, backoffBaseMs: 20, backoffMaxMs: 40, riskCooldownMs: 10_000, ...over,
  })
}

describe('FeedMixer', () => {
  it('后台预取到 readyAhead 张，next() 不等待网络', async () => {
    const a = new FakeAdapter('bilibili')
    const m = mixer({ readyAhead: 5 })
    m.setSources([a])
    await sleep(30)
    expect(m.sourceStates()[0]!.ready).toBe(5)
    const t0 = performance.now()
    const cards = await m.next(3)
    expect(performance.now() - t0).toBeLessThan(5)
    expect(cards.map((c) => c.id)).toEqual(['0', '1', '2'])
    await sleep(30)
    expect(m.sourceStates()[0]!.ready).toBe(5) // 取走后自动补满
    m.stop()
  })

  it('首屏缓冲为空时等待第一张，超时返回空', async () => {
    const a = new FakeAdapter('xhs')
    a.resolveDelayMs = 40
    const m = mixer()
    m.setSources([a])
    expect((await m.next(1, { waitMs: 500 })).length).toBe(1)
    const slow = new FakeAdapter('x')
    slow.resolveDelayMs = 300
    const m2 = mixer()
    m2.setSources([slow])
    expect(await m2.next(1, { waitMs: 50 })).toEqual([])
    m.stop()
    m2.stop()
  })

  it('多平台交错，同一平台最多连续 maxConsecutive 条', async () => {
    const a = new FakeAdapter('bilibili', 10)
    const b = new FakeAdapter('xhs', 10)
    b.resolveDelayMs = 15 // xhs 慢，缓冲里会先堆满 bilibili
    const m = mixer({ readyAhead: 8, maxConsecutive: 2 })
    m.setSources([a, b])
    const seq: string[] = []
    for (let i = 0; i < 6; i++) {
      await sleep(40)
      seq.push(...(await m.next(2)).map((c) => c.platform))
    }
    for (let i = 2; i < seq.length; i++) expect(seq[i] === seq[i - 1] && seq[i] === seq[i - 2]).toBe(false)
    expect(new Set(seq)).toEqual(new Set(['bilibili', 'xhs']))
    m.stop()
  })

  it('产出率低的平台（大量纯文字）也能保持合理占比', async () => {
    const a = new FakeAdapter('bilibili', 10)
    const b = new FakeAdapter('xhs', 10)
    const x = new FakeAdapter('x', 9)
    x.pageIds = (p) => Array.from({ length: 9 }, (_, i) => (i % 3 === 0 ? `${p}-${i}` : `t${p}-${i}`)) // 2/3 是纯文字
    x.resolveDelayMs = 5
    const m = mixer({ readyAhead: 6 })
    m.setSources([a, b, x])
    const counts: Record<string, number> = {}
    for (let i = 0; i < 18; i++) {
      await sleep(25)
      for (const c of await m.next(1)) counts[c.platform] = (counts[c.platform] ?? 0) + 1
    }
    expect(counts.x).toBeGreaterThanOrEqual(4)
    expect(counts.bilibili).toBeLessThanOrEqual(8)
    m.stop()
  })

  it('均匀混排：快慢不同的三个平台长期占比接近均分，且不连续出现同一平台', async () => {
    const fast = new FakeAdapter('bilibili', 10)
    const mid = new FakeAdapter('xhs', 10)
    mid.resolveDelayMs = 4
    const slow = new FakeAdapter('x', 10)
    slow.resolveDelayMs = 10
    const m = mixer()
    m.setSources([fast, mid, slow])
    const seq: string[] = []
    for (let i = 0; i < 30; i++) {
      await sleep(15)
      seq.push(...(await m.next(1)).map((c) => c.platform))
    }
    const counts = seq.reduce<Record<string, number>>((acc, p) => ({ ...acc, [p]: (acc[p] ?? 0) + 1 }), {})
    for (const p of ['bilibili', 'xhs', 'x']) {
      expect(counts[p]).toBeGreaterThanOrEqual(8)
      expect(counts[p]).toBeLessThanOrEqual(12)
    }
    for (let i = 1; i < seq.length; i++) expect(seq[i]).not.toBe(seq[i - 1])
    m.stop()
  })

  it('同一平台最多连续 3 条：慢平台还在供货时稍等它，而不是一直给快平台', async () => {
    const fast = new FakeAdapter('bilibili', 10)
    const slow = new FakeAdapter('xhs', 10)
    slow.resolveDelayMs = 120 // 慢到缓冲里几乎全是 bilibili
    const m = mixer({ readyAhead: 8, maxConsecutive: 1, balanceWaitMs: 400 })
    m.setSources([fast, slow])
    const seq: string[] = []
    for (let k = 0; k < 6; k++) {
      await sleep(20)
      seq.push(...(await m.next(2)).map((c) => c.platform))
    }
    let run = 1
    for (let i = 1; i < seq.length; i++) {
      run = seq[i] === seq[i - 1] ? run + 1 : 1
      expect(run).toBeLessThanOrEqual(3)
    }
    expect(seq).toContain('xhs')
    m.stop()
  })

  it('新连接的平台立刻出现在下一批卡片里', async () => {
    const a = new FakeAdapter('bilibili', 10)
    const m = mixer({ readyAhead: 6 })
    m.setSources([a])
    await sleep(30) // 缓冲里攒满 bilibili
    const b = new FakeAdapter('douyin', 10)
    b.resolveDelayMs = 60
    m.setSources([a, b])
    const batch = (await m.next(3)).map((c) => c.platform)
    expect(batch[0]).toBe('douyin')
    m.stop()
  })

  it('去重：跨页重复、已看过的内容不再出现；纯文字被过滤', async () => {
    const a = new FakeAdapter('x')
    a.pageIds = (p) => (p === 0 ? ['1', '2', 't1', '3'] : ['2', '3', '4', 'seen', `${p}0`])
    const seen = new MemorySeenStore()
    seen.add(cardKey('x', 'seen'))
    const m = mixer({ readyAhead: 4, seen })
    m.setSources([a])
    const ids: string[] = []
    for (let i = 0; i < 4; i++) {
      await sleep(20)
      ids.push(...(await m.next(5)).map((c) => c.id))
    }
    expect(new Set(ids).size).toBe(ids.length)
    expect(ids).not.toContain('t1')
    expect(ids).not.toContain('seen')
    expect(ids.slice(0, 4)).toEqual(['1', '2', '3', '4'])
    expect(seen.has(cardKey('x', '1'))).toBe(true)
    m.stop()
  })

  it('风控只冷却该平台，其他平台照常供货，并通知状态', async () => {
    const a = new FakeAdapter('xhs')
    const b = new FakeAdapter('bilibili')
    a.feedError = () => new CatbusCallError('RISK_CONTROL', 'captcha')
    const m = mixer({ readyAhead: 4 })
    const events: string[] = []
    m.on('source', (s) => events.push(`${s.platform}:${s.status}`))
    m.setSources([a, b])
    await sleep(30)
    const cards = await m.next(4)
    expect(cards.every((c) => c.platform === 'bilibili')).toBe(true)
    expect(events).toContain('xhs:cooldown')
    const xhs = m.sourceStates().find((s) => s.platform === 'xhs')!
    expect(xhs.status).toBe('cooldown')
    expect(xhs.lastError?.code).toBe('RISK_CONTROL')
    expect(a.fetches).toBe(1) // 冷却期间不再请求
    m.stop()
  })

  it('登录失效的平台暂停；网络错误退避后自动恢复', async () => {
    const a = new FakeAdapter('douyin')
    a.feedError = () => new CatbusCallError('AUTH_EXPIRED', 'expired')
    const b = new FakeAdapter('x')
    b.feedError = () => (b.fetches === 1 ? new CatbusCallError('NETWORK', 'reset') : null)
    const m = mixer({ readyAhead: 2 })
    m.setSources([a, b])
    await sleep(5)
    expect(m.sourceStates().find((s) => s.platform === 'x')!.status).toBe('backoff')
    await sleep(80)
    expect(m.sourceStates().find((s) => s.platform === 'douyin')!.status).toBe('auth')
    expect(m.sourceStates().find((s) => s.platform === 'x')!.status).toBe('active')
    expect((await m.next(2)).length).toBe(2)
    m.stop()
  })

  it('单条解析失败直接跳过，连续 3 次才退避', async () => {
    const a = new FakeAdapter('kuaishou', 10)
    a.resolveError = (id) => (id === '1' ? new Error('deleted') : null)
    const m = mixer({ readyAhead: 3 })
    m.setSources([a])
    await sleep(30)
    const ids = (await m.next(3)).map((c) => c.id)
    expect(ids).toEqual(['0', '2', '3'])
    expect(m.sourceStates()[0]!.status).toBe('active')
    m.stop()
  })

  it('移除信息源时清掉它的待播卡片', async () => {
    const a = new FakeAdapter('bilibili')
    const b = new FakeAdapter('xhs')
    const m = mixer({ readyAhead: 6 })
    m.setSources([a, b])
    await sleep(30)
    m.setSources([a])
    const cards = await m.next(6)
    expect(cards.every((c) => c.platform === 'bilibili')).toBe(true)
    expect(m.sourceStates().map((s) => s.platform)).toEqual(['bilibili'])
    m.stop()
  })

  it('快过期的卡片不下发，重新解析后再给', async () => {
    const a = new FakeAdapter('xhs')
    a.ttlMs = 30_000 // 小于 expiryMargin 60s：缓冲里的卡片都算快过期
    const m = mixer({ readyAhead: 2 })
    m.setSources([a])
    await sleep(20)
    const before = a.resolves
    expect(await m.next(1)).toEqual([])
    await sleep(20)
    expect(a.resolves).toBeGreaterThan(before)
    m.stop()
  })

  it('refresh 重新解析已下发的卡片', async () => {
    const a = new FakeAdapter('bilibili')
    const m = mixer({ readyAhead: 1 })
    m.setSources([a])
    const [card] = await m.next(1, { waitMs: 200 })
    const again = await m.refresh(card!.key)
    expect(again?.key).toBe(card!.key)
    expect(await m.refresh('nope:1')).toBeNull()
    m.stop()
  })
})
