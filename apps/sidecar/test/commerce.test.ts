import { describe, expect, it } from 'vitest'
import type { CatbusClient } from '../src/accounts/service.ts'
import { CatbusCallError, type CatbusResult } from '../src/catbus/runner.ts'
import type { Item } from '../src/catbus/types.ts'
import { BREAKER_STEPS_MS, JdGate, JdRestingError, type GateState } from '../src/commerce/gate.ts'
import { CommerceService, parseProduct } from '../src/commerce/service.ts'
import { createMemoryLogger } from '../src/log.ts'
import { Store } from '../src/store/store.ts'

function clock(start = 1_000_000_000) {
  let t = start
  const slept: number[] = []
  return { now: () => t, tick: (ms: number) => (t += ms), sleep: async (ms: number) => { slept.push(ms); t += ms }, slept }
}

function gate(c = clock(), storage?: { load: () => GateState | null; save: (s: GateState) => void }) {
  const trips: unknown[] = []
  const g = new JdGate({ logger: createMemoryLogger(), now: c.now, sleep: c.sleep, random: () => 0, storage, onTrip: (r) => trips.push(r) })
  return { g, c, trips }
}

const risk = () => new CatbusCallError('RISK_CONTROL', '403', { detail: { kind: 'rate_limit' } })

describe('JdGate', () => {
  it('一次只发一个，两次之间留间隔：用户主动 15 秒、后台 60 秒', async () => {
    const { g, c } = gate()
    await g.run('user', async () => 1)
    await g.run('user', async () => 2)
    expect(c.slept).toEqual([15_000])
    c.tick(11 * 60_000) // 过了刚登录的预热期也无所谓：没登录过
    await g.run('background', async () => 3)
    expect(c.slept).toEqual([15_000]) // 上次结束已经过了很久，不用等
    await g.run('background', async () => 4)
    expect(c.slept).toEqual([15_000, 60_000])
  })

  it('用户主动的插到排队中的后台请求前面', async () => {
    const { g } = gate()
    const order: string[] = []
    let release!: () => void
    const first = g.run('background', () => new Promise<void>((r) => { order.push('bg1'); release = r }))
    const bg2 = g.run('background', async () => { order.push('bg2') })
    const user = g.run('user', async () => { order.push('user') })
    await Promise.resolve()
    release()
    await Promise.all([first, bg2, user])
    expect(order).toEqual(['bg1', 'user', 'bg2'])
  })

  it('被风控：熔断、不重试、排队的全部作废；时长逐级加长，24 小时没再被拦就回到第一级；状态存本机', async () => {
    let saved: GateState | null = null
    const storage = { load: () => saved, save: (s: GateState) => { saved = s } }
    const { g, c, trips } = gate(clock(), storage)
    let calls = 0
    await expect(g.run('user', async () => { calls++; throw risk() })).rejects.toThrow(CatbusCallError)
    expect(g.rest()).toMatchObject({ kind: 'resting', resumeAt: c.now() + BREAKER_STEPS_MS[0]! })
    expect(trips).toHaveLength(1)
    // 歇着时直接拒绝，不发请求
    await expect(g.run('user', async () => { calls++ })).rejects.toBeInstanceOf(JdRestingError)
    expect(calls).toBe(1)
    // 重启（新实例读同一份状态）也不会提前恢复
    expect(new JdGate({ logger: createMemoryLogger(), now: c.now, storage }).rest()).not.toBeNull()
    // 恢复后再被拦：第二级 2 小时
    c.tick(BREAKER_STEPS_MS[0]!)
    await expect(g.run('user', async () => { throw risk() })).rejects.toThrow()
    expect(g.rest()!.resumeAt - c.now()).toBe(BREAKER_STEPS_MS[1])
    expect(g.cautious()).toBe(true)
    // 之后 24 小时以上没再被拦：回到第一级
    c.tick(BREAKER_STEPS_MS[1]! + 25 * 3600_000)
    expect(g.cautious()).toBe(false)
    await expect(g.run('user', async () => { throw new CatbusCallError('RISK_CONTROL', 'captcha', { detail: { kind: 'captcha' } }) })).rejects.toThrow()
    expect(g.rest()).toMatchObject({ kind: 'verify', resumeAt: c.now() + BREAKER_STEPS_MS[0]! })
  })

  it('刚登录的 10 分钟里不跑后台请求，用户主动的照常', async () => {
    const { g, c } = gate()
    g.noteLogin()
    await expect(g.run('background', async () => 1)).rejects.toBeInstanceOf(JdRestingError)
    await expect(g.run('user', async () => 2)).resolves.toBe(2)
    c.tick(10 * 60_000)
    await expect(g.run('background', async () => 3)).resolves.toBe(3)
  })
})

class FakeCatbus implements CatbusClient {
  calls: string[] = []
  next: (() => unknown) | null = null
  async run<T>(argv: readonly string[]): Promise<CatbusResult<T>> {
    this.calls.push(argv.join(' '))
    const v = this.next ? this.next() : items(['1', '2'])
    return { data: v as T, page: { cursor: '#skip=20', has_more: true }, account: 'default' }
  }
}

function items(ids: string[]): Item[] {
  return ids.map((id) => ({
    id, kind: 'product', url: `https://item.jd.com/${id}.html`, title: `键盘 ${id}`, text: null, author: { id: 's', name: '罗技G京东自营旗舰店', url: null },
    created_at: null, cover: `https://img14.360buyimg.com/${id}.jpg`, media: [], stats: { views: null, likes: null, comments: 50000, collects: null, shares: null },
    price: { amount: 299.9, currency: 'CNY' }, status: null,
  }))
}

function commerce() {
  const c = clock()
  const catbus = new FakeCatbus()
  const store = new Store({ path: ':memory:', now: c.now })
  const g = new JdGate({ logger: createMemoryLogger(), now: c.now, sleep: c.sleep, random: () => 0 })
  const svc = new CommerceService({ catbus, gate: g, store, logger: createMemoryLogger(), now: c.now })
  return { c, catbus, store, g, svc }
}

describe('CommerceService', () => {
  it('搜索：商品快照（价格、店铺、评价量级）；30 分钟内同一个词不重复请求；标出已在心愿单的', async () => {
    const { c, catbus, svc } = commerce()
    const p = await svc.search('机械键盘')
    expect(p.products[0]).toMatchObject({ sku: '1', price: 299.9, shop: '罗技G京东自营旗舰店', comments: 50000, wished: false })
    expect(p).toMatchObject({ cursor: '#skip=20', hasMore: true, rest: null, cachedAt: null })
    expect(catbus.calls).toEqual(['jd item search 机械键盘 --sort general'])
    svc.addWish(p.products[0]!)
    expect((await svc.search('机械键盘')).products[0]!.wished).toBe(true)
    expect(catbus.calls).toHaveLength(1)
    c.tick(31 * 60_000)
    catbus.next = () => items(['1', '2']).map((it) => ({ ...it, price: { amount: 279, currency: 'CNY' } }))
    await svc.search('机械键盘')
    expect(catbus.calls).toHaveLength(2)
    // 再搜到心愿单里的商品：顺手记下新价格，不多发请求
    expect(svc.wishes().entries[0]!.history.map((h) => h.price)).toEqual([299.9, 279])
  })

  it('被风控：返回上次的结果和时间、不能翻页；之后歇着期间不再请求', async () => {
    const { c, catbus, svc } = commerce()
    await svc.search('机械键盘')
    const fetchedAt = c.now()
    c.tick(40 * 60_000)
    catbus.next = () => { throw new CatbusCallError('RISK_CONTROL', '403') }
    const p = await svc.search('机械键盘')
    expect(p.products.map((x) => x.sku)).toEqual(['1', '2'])
    expect(p.rest).toMatchObject({ kind: 'resting' })
    expect(p.cachedAt).toBe(fetchedAt)
    expect(p.hasMore).toBe(false)
    const n = catbus.calls.length
    const q = await svc.search('降噪耳机') // 没有缓存：空结果 + rest
    expect(q).toMatchObject({ products: [], rest: { kind: 'resting' }, cachedAt: null })
    expect(catbus.calls).toHaveLength(n)
  })

  it('未登录京东：auth 标记，不算风控', async () => {
    const { catbus, svc, g } = commerce()
    catbus.next = () => { throw new CatbusCallError('AUTH_REQUIRED', 'login') }
    expect(await svc.search('键盘')).toMatchObject({ auth: true, rest: null })
    expect(g.rest()).toBeNull()
  })

  it('心愿单：最多 30 件；加入时记下价格；同价只延长曲线，不堆点', async () => {
    const { c, store, svc } = commerce()
    for (let i = 0; i < 30; i++) svc.addWish(parseProduct({ sku: String(i), title: `t${i}`, price: 100, url: 'https://item.jd.com/1.html' })!)
    expect(() => svc.addWish(parseProduct({ sku: '99', title: 'x', price: 1 })!)).toThrow(/最多 30 件/)
    svc.addWish(parseProduct({ sku: '0', title: '改了标题', price: 100 })!) // 已在心愿单：只更新快照，不算超限
    c.tick(3600_000); store.recordPrice('0', 100)
    c.tick(3600_000); store.recordPrice('0', 100)
    c.tick(3600_000); store.recordPrice('0', 90)
    const e = svc.wishes().entries.find((w) => w.product.sku === '0')!
    expect(e.product.title).toBe('改了标题')
    expect(e.history.map((h) => h.price)).toEqual([100, 100, 90])
    svc.removeWish('0')
    expect(svc.wishes().entries).toHaveLength(29)
  })

  it('parseProduct：SKU 必须是数字，链接只认京东的', () => {
    expect(parseProduct({ sku: 'abc', title: 'x' })).toBeNull()
    expect(parseProduct({ sku: '1', title: 'x', url: 'javascript:alert(1)' })!.url).toBe('https://item.jd.com/1.html')
    expect(parseProduct({ sku: '1', title: 'x', url: 'https://item.m.jd.com/product/1.html' })!.url).toBe('https://item.m.jd.com/product/1.html')
  })
})
