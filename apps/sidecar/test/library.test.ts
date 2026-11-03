import { mkdtempSync, readFileSync, statSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { describe, expect, it } from 'vitest'
import { CoverCache } from '../src/store/covers.ts'
import { exportLibrary, importLibrary, LibraryFileError } from '../src/store/library.ts'
import { snapshot, Store } from '../src/store/store.ts'
import type { FeedCard } from '../src/content/types.ts'
import { createMemoryLogger } from '../src/log.ts'

const card = (id: string, platform = 'xhs'): FeedCard => ({
  key: `${platform}:${id}`, platform, id, url: `https://e/${id}`, kind: 'video', title: `t${id}`, text: null, author: { id: 'u', name: null, url: null }, createdAt: null,
  cover: { url: `https://c/${id}`, headers: {}, width: 1, height: 1 }, stats: { views: null, likes: null, comments: null, collects: null, shares: null },
  video: { url: `https://v/${id}`, headers: {}, width: 1, height: 1, duration: 12 }, images: [], resolvedAt: 0, expiresAt: 0,
})

function workspace(now = 1_000_000) {
  const dir = mkdtempSync(join(tmpdir(), 'catland-lib-'))
  const store = new Store({ path: join(dir, 'catland.db'), now: () => now })
  const covers = new CoverCache({ dir: join(dir, 'covers'), logger: createMemoryLogger() })
  return { dir, store, covers }
}

describe('library export / import', () => {
  it('导出后在另一台 Mac 导入：点赞、收藏、历史、封面都回来，时间不变；文件只有本人可读', () => {
    const a = workspace()
    a.store.save('like', snapshot(card('1')))
    a.store.save('collect', snapshot(card('1')))
    a.store.save('collect', snapshot(card('2', 'bilibili')))
    a.store.recordView(snapshot(card('3')), 4200)
    a.covers.write('xhs:1', Buffer.from('jpeg-bytes'))
    const file = join(a.dir, 'out.json')
    expect(exportLibrary(a.store, a.covers, file)).toEqual({ likes: 1, collects: 2, history: 1, covers: 1 })
    expect(statSync(file).mode & 0o777).toBe(0o600)
    expect(readFileSync(file, 'utf8')).not.toMatch(/cookie|token/i)

    const b = workspace(2_000_000)
    expect(importLibrary(b.store, b.covers, file)).toEqual({ likes: 1, collects: 2, history: 1, covers: 1 })
    expect(b.store.states(['xhs:1', 'bilibili:2'])).toEqual({ 'xhs:1': { liked: true, collected: true }, 'bilibili:2': { liked: false, collected: true } })
    expect(b.store.listSaved('like').entries[0]).toMatchObject({ card: { key: 'xhs:1', duration: 12 }, at: new Date(1_000_000).toISOString() })
    expect(b.store.listHistory().entries[0]).toMatchObject({ card: { key: 'xhs:3' }, dwellMs: 4200 })
    expect(b.covers.read('xhs:1')?.toString()).toBe('jpeg-bytes')
    // 再导入一次：都已经有了，不重复
    expect(importLibrary(b.store, b.covers, file)).toEqual({ likes: 0, collects: 0, history: 0, covers: 0 })
  })

  it('合并：本机已有的不被覆盖', () => {
    const a = workspace()
    a.store.save('like', snapshot(card('1')))
    const file = join(a.dir, 'out.json')
    exportLibrary(a.store, a.covers, file)
    const b = workspace(5_000_000)
    b.store.save('like', { ...snapshot(card('1')), title: '本机标题' })
    expect(importLibrary(b.store, b.covers, file).likes).toBe(0)
    expect(b.store.listSaved('like').entries[0]).toMatchObject({ card: { title: '本机标题' }, at: new Date(5_000_000).toISOString() })
  })

  it('拒绝不是 catland 的文件、来自更新版本的文件；跳过字段不对的卡片', () => {
    const b = workspace()
    const bad = join(b.dir, 'bad.json')
    writeFileSync(bad, '{"hello":1}')
    expect(() => importLibrary(b.store, b.covers, bad)).toThrow(LibraryFileError)
    writeFileSync(bad, 'not json')
    expect(() => importLibrary(b.store, b.covers, bad)).toThrow(LibraryFileError)
    writeFileSync(bad, JSON.stringify({ format: 'catland-library', version: 99 }))
    expect(() => importLibrary(b.store, b.covers, bad)).toThrow(/更新版本/)
    const ok = snapshot(card('1'))
    writeFileSync(bad, JSON.stringify({
      format: 'catland-library', version: 1,
      saved: [
        { kind: 'like', at: '2026-01-01T00:00:00Z', card: ok },
        { kind: 'like', at: '2026-01-01T00:00:00Z', card: { ...ok, key: 'xhs:other' } },       // key 和 id 对不上
        { kind: 'like', at: '2026-01-01T00:00:00Z', card: { ...snapshot(card('9', 'nope')) } }, // 不认识的平台
        { kind: 'like', at: '2026-01-01T00:00:00Z', card: { ...snapshot(card('8')), url: 'javascript:alert(1)' } },
        { kind: 'admin', at: '2026-01-01T00:00:00Z', card: snapshot(card('7')) },
      ],
      history: [{ at: 'yesterday?', card: snapshot(card('6')) }],
    }))
    expect(importLibrary(b.store, b.covers, bad)).toEqual({ likes: 1, collects: 0, history: 0, covers: 0 })
  })
})
