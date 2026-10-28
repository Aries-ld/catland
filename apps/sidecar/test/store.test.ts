import { mkdtempSync, statSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { describe, expect, it } from 'vitest'
import { snapshot, Store } from '../src/store/store.ts'
import type { FeedCard } from '../src/content/types.ts'

const card = (id: string, platform = 'xhs'): FeedCard => ({
  key: `${platform}:${id}`, platform, id, url: `https://e/${id}`, kind: 'video', title: `t${id}`, text: null, author: null, createdAt: null,
  cover: { url: `https://c/${id}`, headers: {}, width: 1, height: 1 }, stats: { views: null, likes: null, comments: null, collects: null, shares: null },
  video: { url: `https://v/${id}`, headers: { Referer: 'r' }, width: 1, height: 1, duration: 1 }, images: [], resolvedAt: 0, expiresAt: 0,
})

function clock(start = 1_000_000) {
  let t = start
  return { now: () => t, tick: (ms = 1) => (t += ms) }
}

describe('Store', () => {
  it('文件权限 0600，重开后数据仍在', () => {
    const path = join(mkdtempSync(join(tmpdir(), 'catland-db-')), 'sub', 'catland.db')
    const s1 = new Store({ path })
    s1.add('xhs:1')
    s1.save('like', snapshot(card('1')))
    s1.close()
    expect(statSync(path).mode & 0o777).toBe(0o600)
    const s2 = new Store({ path })
    expect(s2.has('xhs:1')).toBe(true)
    expect(s2.states(['xhs:1'])['xhs:1']).toEqual({ liked: true, collected: false })
    s2.close()
  })

  it('看过的记录按 TTL 过期', () => {
    const path = join(mkdtempSync(join(tmpdir(), 'catland-db-')), 'c.db')
    const c = clock()
    const s1 = new Store({ path, now: c.now, seenTtlMs: 1000 })
    s1.add('x:1')
    s1.close()
    c.tick(2000)
    const s2 = new Store({ path, now: c.now, seenTtlMs: 1000 })
    expect(s2.has('x:1')).toBe(false)
    s2.close()
  })

  it('点赞 / 收藏：幂等保存、取消、批量状态、快照不含媒体地址', () => {
    const c = clock()
    const s = new Store({ path: ':memory:', now: c.now })
    s.save('like', snapshot(card('1')))
    s.save('like', snapshot(card('1')))
    s.save('collect', snapshot(card('1')))
    s.save('like', snapshot(card('2', 'bilibili')))
    expect(s.states(['xhs:1', 'bilibili:2', 'x:9'])).toEqual({
      'xhs:1': { liked: true, collected: true }, 'bilibili:2': { liked: true, collected: false }, 'x:9': { liked: false, collected: false },
    })
    s.unsave('like', 'xhs:1')
    expect(s.states(['xhs:1'])['xhs:1']).toEqual({ liked: false, collected: true })
    const { entries } = s.listSaved('like')
    expect(entries).toHaveLength(1)
    expect(entries[0]!.card).toEqual({ key: 'bilibili:2', platform: 'bilibili', id: '2', url: 'https://e/2', kind: 'video', title: 't2', text: null, author: null, cover: 'https://c/2', createdAt: null, duration: 1 })
    expect(JSON.stringify(entries)).not.toContain('https://v/')
    expect(s.states([])).toEqual({})
  })

  it('收藏列表按时间倒序分页', () => {
    const c = clock()
    const s = new Store({ path: ':memory:', now: c.now })
    for (let i = 0; i < 5; i++) {
      s.save('collect', snapshot(card(String(i))))
      c.tick(10)
    }
    const p1 = s.listSaved('collect', { limit: 2 })
    expect(p1.entries.map((e) => e.card.id)).toEqual(['4', '3'])
    const p2 = s.listSaved('collect', { limit: 2, before: p1.next! })
    expect(p2.entries.map((e) => e.card.id)).toEqual(['2', '1'])
    const p3 = s.listSaved('collect', { limit: 2, before: p2.next! })
    expect(p3.entries.map((e) => e.card.id)).toEqual(['0'])
    expect(p3.next).toBeNull()
  })

  it('浏览历史：重复浏览更新时间、累加停留时长；超量裁剪', () => {
    const path = join(mkdtempSync(join(tmpdir(), 'catland-db-')), 'h.db')
    const c = clock()
    const s = new Store({ path, now: c.now, historyLimit: 2 })
    s.recordView(snapshot(card('1')), 1000)
    c.tick()
    s.recordView(snapshot(card('2')), 500)
    c.tick()
    s.recordView(snapshot(card('1')), 250.4)
    expect(s.listHistory().entries.map((e) => [e.card.id, e.dwellMs])).toEqual([['1', 1250], ['2', 500]])
    c.tick()
    s.recordView(snapshot(card('3')), 1)
    s.close()
    const s2 = new Store({ path, now: c.now, historyLimit: 2 })
    expect(s2.listHistory().entries.map((e) => e.card.id)).toEqual(['3', '1'])
    s2.clearHistory()
    expect(s2.listHistory().entries).toEqual([])
    s2.close()
  })

  it('设置：默认静音，部分更新，拒绝非法值与未知项', () => {
    const s = new Store({ path: ':memory:' })
    expect(s.getSettings()).toEqual({ muted: true, sources: {}, weather: true })
    expect(s.updateSettings({ sources: { content: ['xhs', 'x'] } })).toEqual({ muted: true, sources: { content: ['xhs', 'x'] }, weather: true })
    expect(s.updateSettings({ muted: false }).muted).toBe(false)
    expect(() => s.updateSettings({ muted: 'no' as never })).toThrow(TypeError)
    expect(() => s.updateSettings({ sources: { video: ['x'] } as never })).toThrow(TypeError)
    s.updateSettings({ evil: 1 } as never)
    expect(Object.keys(s.getSettings())).toEqual(['muted', 'sources', 'weather'])
  })
})
