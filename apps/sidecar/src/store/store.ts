/** 本地数据库（node:sqlite）：看过、点赞、收藏、浏览历史、设置。只存在本机，权限 0600。 */
import { chmodSync, existsSync, mkdirSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'
import { DatabaseSync } from 'node:sqlite'
import type { SeenStore } from '../content/mixer.ts'
import type { FeedCard } from '../content/types.ts'

export type Collection = 'like' | 'collect'

/** 收藏夹 / 历史里展示用的卡片快照：去掉会过期的媒体地址，打开时再重新解析。 */
export interface CardSnapshot {
  key: string
  platform: string
  id: string
  url: string
  kind: FeedCard['kind']
  title: string | null
  text: string | null
  author: FeedCard['author']
  cover: string | null
  createdAt: string | null
  /** 视频时长（秒），封面上显示；图文 / 旧数据为 null。 */
  duration?: number | null
}

export interface SavedEntry {
  card: CardSnapshot
  at: string
}

export interface HistoryEntry extends SavedEntry {
  dwellMs: number
}

export interface Settings {
  /** 视频默认静音（上班摸鱼场景）。 */
  muted: boolean
  /** 每个板块启用的信息源；undefined 表示「全部已登录的平台」。 */
  sources: Partial<Record<'content' | 'commerce', string[]>>
  /** 猫咪之家的天气联动（请求 NEA 开放数据，不带用户信息）。 */
  weather: boolean
}

const DEFAULT_SETTINGS: Settings = { muted: true, sources: {}, weather: true }

const SCHEMA_VERSION = 1

const MIGRATIONS: Record<number, string> = {
  1: `
    CREATE TABLE seen (key TEXT PRIMARY KEY, platform TEXT NOT NULL, at INTEGER NOT NULL);
    CREATE INDEX seen_at ON seen(at);
    CREATE TABLE saved (kind TEXT NOT NULL, key TEXT NOT NULL, card TEXT NOT NULL, at INTEGER NOT NULL, PRIMARY KEY (kind, key));
    CREATE INDEX saved_kind_at ON saved(kind, at DESC);
    CREATE TABLE history (key TEXT PRIMARY KEY, card TEXT NOT NULL, at INTEGER NOT NULL, dwell_ms INTEGER NOT NULL DEFAULT 0);
    CREATE INDEX history_at ON history(at DESC);
    CREATE TABLE settings (name TEXT PRIMARY KEY, value TEXT NOT NULL);
  `,
}

export function defaultDataDir(): string {
  return process.env.CATLAND_DATA_DIR ?? join(homedir(), 'Library', 'Application Support', 'catland')
}

export function snapshot(card: FeedCard): CardSnapshot {
  return {
    key: card.key, platform: card.platform, id: card.id, url: card.url, kind: card.kind, title: card.title, text: card.text,
    author: card.author, cover: card.cover?.url ?? null, createdAt: card.createdAt, duration: card.video?.duration ?? null,
  }
}

export interface StoreOptions {
  /** 数据库文件路径；':memory:' 用于测试。 */
  path?: string
  now?: () => number
  /** 「看过」保留多久，过期后允许再次刷到。 */
  seenTtlMs?: number
  historyLimit?: number
}

export class Store implements SeenStore {
  private readonly db: DatabaseSync
  private readonly now: () => number
  private readonly seenTtlMs: number
  private readonly historyLimit: number
  private readonly seenCache = new Set<string>()

  constructor(opts: StoreOptions = {}) {
    const path = opts.path ?? join(defaultDataDir(), 'catland.db')
    if (path !== ':memory:') {
      const dir = join(path, '..')
      if (!existsSync(dir)) mkdirSync(dir, { recursive: true, mode: 0o700 })
      chmodSync(dir, 0o700) // WAL / SHM 文件按 umask 创建，靠目录权限挡住其他用户
    }
    this.db = new DatabaseSync(path)
    if (path !== ':memory:') chmodSync(path, 0o600)
    this.now = opts.now ?? Date.now
    this.seenTtlMs = opts.seenTtlMs ?? 30 * 24 * 3600_000
    this.historyLimit = opts.historyLimit ?? 2000
    this.db.exec('PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL; PRAGMA foreign_keys = ON;')
    this.migrate()
    this.prune()
    for (const row of this.db.prepare('SELECT key FROM seen').all() as Array<{ key: string }>) this.seenCache.add(row.key)
  }

  private migrate(): void {
    const current = (this.db.prepare('PRAGMA user_version').get() as { user_version: number }).user_version
    for (let v = current + 1; v <= SCHEMA_VERSION; v++) {
      this.db.exec('BEGIN')
      try {
        this.db.exec(MIGRATIONS[v]!)
        this.db.exec(`PRAGMA user_version = ${v}`)
        this.db.exec('COMMIT')
      } catch (err) {
        this.db.exec('ROLLBACK')
        throw err
      }
    }
  }

  /** 启动时清理过期的「看过」和超量的历史。 */
  prune(): void {
    this.db.prepare('DELETE FROM seen WHERE at < ?').run(this.now() - this.seenTtlMs)
    this.db.prepare('DELETE FROM history WHERE key NOT IN (SELECT key FROM history ORDER BY at DESC LIMIT ?)').run(this.historyLimit)
  }

  // SeenStore：内存集合挡热路径，写库保证跨会话。
  has(key: string): boolean {
    return this.seenCache.has(key)
  }

  add(key: string): void {
    if (this.seenCache.has(key)) return
    this.seenCache.add(key)
    this.db.prepare('INSERT OR IGNORE INTO seen (key, platform, at) VALUES (?, ?, ?)').run(key, key.split(':')[0]!, this.now())
  }

  save(kind: Collection, card: CardSnapshot): void {
    this.db.prepare('INSERT INTO saved (kind, key, card, at) VALUES (?, ?, ?, ?) ON CONFLICT (kind, key) DO NOTHING').run(kind, card.key, JSON.stringify(card), this.now())
  }

  /** 重新解析后更新快照（标题、封面地址等），点赞 / 收藏 / 历史里都更新。 */
  updateSnapshot(card: CardSnapshot): void {
    const json = JSON.stringify(card)
    this.db.prepare('UPDATE saved SET card = ? WHERE key = ?').run(json, card.key)
    this.db.prepare('UPDATE history SET card = ? WHERE key = ?').run(json, card.key)
  }

  /** 这条还在不在任何一个收藏夹里（都取消后可以删掉本地封面）。 */
  isSaved(key: string): boolean {
    return this.db.prepare('SELECT 1 FROM saved WHERE key = ? LIMIT 1').get(key) !== undefined
  }

  unsave(kind: Collection, key: string): void {
    this.db.prepare('DELETE FROM saved WHERE kind = ? AND key = ?').run(kind, key)
  }

  /** 批量查询一组卡片的点赞 / 收藏状态（客户端渲染操作栏用）。 */
  states(keys: string[]): Record<string, { liked: boolean; collected: boolean }> {
    const out: Record<string, { liked: boolean; collected: boolean }> = {}
    for (const k of keys) out[k] = { liked: false, collected: false }
    if (keys.length === 0) return out
    const rows = this.db.prepare(`SELECT kind, key FROM saved WHERE key IN (${keys.map(() => '?').join(',')})`).all(...keys) as Array<{ kind: Collection; key: string }>
    for (const r of rows) out[r.key]![r.kind === 'like' ? 'liked' : 'collected'] = true
    return out
  }

  /** 按时间倒序分页；before 为上一页最后一条的时间（毫秒）。 */
  listSaved(kind: Collection, opts: { limit?: number; before?: number } = {}): { entries: SavedEntry[]; next: number | null } {
    const limit = clampLimit(opts.limit)
    const rows = this.db.prepare('SELECT card, at FROM saved WHERE kind = ? AND at < ? ORDER BY at DESC LIMIT ?').all(kind, opts.before ?? Number.MAX_SAFE_INTEGER, limit + 1) as Array<{ card: string; at: number }>
    return page(rows, limit, (r) => ({ card: JSON.parse(r.card) as CardSnapshot, at: new Date(r.at).toISOString() }))
  }

  /** 记录一次浏览；同一条再看时更新时间、累加停留时长。 */
  recordView(card: CardSnapshot, dwellMs: number): void {
    const dwell = Math.max(0, Math.round(dwellMs))
    this.db
      .prepare('INSERT INTO history (key, card, at, dwell_ms) VALUES (?, ?, ?, ?) ON CONFLICT (key) DO UPDATE SET at = excluded.at, card = excluded.card, dwell_ms = dwell_ms + excluded.dwell_ms')
      .run(card.key, JSON.stringify(card), this.now(), dwell)
  }

  listHistory(opts: { limit?: number; before?: number } = {}): { entries: HistoryEntry[]; next: number | null } {
    const limit = clampLimit(opts.limit)
    const rows = this.db.prepare('SELECT card, at, dwell_ms FROM history WHERE at < ? ORDER BY at DESC LIMIT ?').all(opts.before ?? Number.MAX_SAFE_INTEGER, limit + 1) as Array<{ card: string; at: number; dwell_ms: number }>
    return page(rows, limit, (r) => ({ card: JSON.parse(r.card) as CardSnapshot, at: new Date(r.at).toISOString(), dwellMs: r.dwell_ms }))
  }

  clearHistory(): void {
    this.db.exec('DELETE FROM history')
  }

  getSettings(): Settings {
    const rows = this.db.prepare('SELECT name, value FROM settings').all() as Array<{ name: string; value: string }>
    const out: Record<string, unknown> = { ...DEFAULT_SETTINGS }
    for (const r of rows) if (r.name in DEFAULT_SETTINGS) out[r.name] = JSON.parse(r.value)
    return out as unknown as Settings
  }

  /** 只接受已知的设置项，并做类型校验。 */
  updateSettings(patch: Partial<Settings>): Settings {
    if (patch.muted !== undefined && typeof patch.muted !== 'boolean') throw new TypeError('muted must be boolean')
    if (patch.weather !== undefined && typeof patch.weather !== 'boolean') throw new TypeError('weather must be boolean')
    if (patch.sources !== undefined) {
      const ok = typeof patch.sources === 'object' && patch.sources !== null &&
        Object.entries(patch.sources).every(([k, v]) => (k === 'content' || k === 'commerce') && (v === undefined || (Array.isArray(v) && v.every((p) => typeof p === 'string'))))
      if (!ok) throw new TypeError('sources must be { content?: string[], commerce?: string[] }')
    }
    const upsert = this.db.prepare('INSERT INTO settings (name, value) VALUES (?, ?) ON CONFLICT (name) DO UPDATE SET value = excluded.value')
    for (const [k, v] of Object.entries(patch)) if (k in DEFAULT_SETTINGS && v !== undefined) upsert.run(k, JSON.stringify(v))
    return this.getSettings()
  }

  close(): void {
    this.db.close()
  }
}

function clampLimit(limit: number | undefined): number {
  return Math.min(Math.max(Math.trunc(limit ?? 30), 1), 200)
}

function page<R extends { at: number }, E>(rows: R[], limit: number, map: (r: R) => E): { entries: E[]; next: number | null } {
  const more = rows.length > limit
  const slice = more ? rows.slice(0, limit) : rows
  return { entries: slice.map(map), next: more ? slice.at(-1)!.at : null }
}
