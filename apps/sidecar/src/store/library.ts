/**
 * 点赞 / 收藏 / 浏览历史的导出与导入：一个 JSON 文件，封面以 base64 内嵌，换 Mac 或备份时用。
 * 不包含登录凭证和设置。导入是合并：已有的不覆盖，保留原来的时间。
 */
import { readFileSync, renameSync, statSync, writeFileSync } from 'node:fs'
import { getPlatform } from '../accounts/catalog.ts'
import type { CoverCache } from './covers.ts'
import type { CardSnapshot, Collection, Store } from './store.ts'

export const LIBRARY_FORMAT = 'catland-library'
export const LIBRARY_VERSION = 1
const MAX_FILE_BYTES = 1024 * 1024 * 1024

export interface LibraryCounts {
  likes: number
  collects: number
  history: number
  covers: number
}

export function exportLibrary(store: Store, covers: CoverCache, path: string, now = Date.now()): LibraryCounts {
  const { saved, history } = store.dumpLibrary()
  const coverMap: Record<string, string> = {}
  for (const s of saved) {
    if (coverMap[s.card.key]) continue
    const buf = covers.read(s.card.key)
    if (buf) coverMap[s.card.key] = buf.toString('base64')
  }
  const doc = {
    format: LIBRARY_FORMAT,
    version: LIBRARY_VERSION,
    exportedAt: new Date(now).toISOString(),
    saved: saved.map((s) => ({ kind: s.kind, at: new Date(s.at).toISOString(), card: s.card })),
    history: history.map((h) => ({ at: new Date(h.at).toISOString(), dwellMs: h.dwellMs, card: h.card })),
    covers: coverMap,
  }
  // 先写临时文件再改名：写到一半出错不会留下半个文件；只有本人可读
  const tmp = `${path}.tmp-${process.pid}`
  writeFileSync(tmp, JSON.stringify(doc), { mode: 0o600 })
  renameSync(tmp, path)
  return {
    likes: saved.filter((s) => s.kind === 'like').length,
    collects: saved.filter((s) => s.kind === 'collect').length,
    history: history.length,
    covers: Object.keys(coverMap).length,
  }
}

export class LibraryFileError extends Error {}

/** 导入：返回实际新增的条数（已有的不算）。文件格式不对时抛 LibraryFileError。 */
export function importLibrary(store: Store, covers: CoverCache, path: string): LibraryCounts {
  if (statSync(path).size > MAX_FILE_BYTES) throw new LibraryFileError('文件太大')
  let doc: unknown
  try {
    doc = JSON.parse(readFileSync(path, 'utf8'))
  } catch {
    throw new LibraryFileError('不是 catland 导出的文件')
  }
  const d = doc as Record<string, unknown>
  if (!d || d.format !== LIBRARY_FORMAT) throw new LibraryFileError('不是 catland 导出的文件')
  if (typeof d.version !== 'number' || d.version > LIBRARY_VERSION) throw new LibraryFileError('这个文件来自更新版本的 catland，请先升级')
  const counts: LibraryCounts = { likes: 0, collects: 0, history: 0, covers: 0 }
  const coverMap = (d.covers && typeof d.covers === 'object' ? d.covers : {}) as Record<string, unknown>
  for (const raw of Array.isArray(d.saved) ? d.saved : []) {
    const e = raw as Record<string, unknown>
    const card = parseCard(e.card), at = parseTime(e.at)
    if (!card || at === null || (e.kind !== 'like' && e.kind !== 'collect')) continue
    if (store.importSaved(e.kind as Collection, card, at)) counts[e.kind === 'like' ? 'likes' : 'collects']++
    const b64 = coverMap[card.key]
    if (typeof b64 === 'string' && !covers.localUrl(card.key) && covers.write(card.key, Buffer.from(b64, 'base64'))) counts.covers++
  }
  for (const raw of Array.isArray(d.history) ? d.history : []) {
    const e = raw as Record<string, unknown>
    const card = parseCard(e.card), at = parseTime(e.at)
    if (!card || at === null) continue
    const dwell = typeof e.dwellMs === 'number' && Number.isFinite(e.dwellMs) ? Math.max(0, Math.round(e.dwellMs)) : 0
    if (store.importHistory(card, at, dwell)) counts.history++
  }
  store.prune()
  return counts
}

function parseTime(v: unknown): number | null {
  if (typeof v !== 'string') return null
  const t = Date.parse(v)
  return Number.isFinite(t) ? t : null
}

const optString = (v: unknown): string | null => (typeof v === 'string' ? v : null)

/** 只认识的字段、类型都对、平台是 catland 支持的，才导入。 */
function parseCard(v: unknown): CardSnapshot | null {
  if (!v || typeof v !== 'object') return null
  const c = v as Record<string, unknown>
  if (typeof c.platform !== 'string' || !getPlatform(c.platform) || typeof c.id !== 'string' || c.key !== `${c.platform}:${c.id}`) return null
  if (typeof c.url !== 'string' || (c.url !== '' && !/^https?:\/\//i.test(c.url))) return null
  if (c.kind !== 'video' && c.kind !== 'image') return null
  const cover = optString(c.cover)
  const a = c.author as Record<string, unknown> | null | undefined
  const author = a && typeof a === 'object' && typeof a.id === 'string' ? { id: a.id, name: optString(a.name), url: optString(a.url) } : null
  return {
    key: c.key, platform: c.platform, id: c.id, url: c.url, kind: c.kind,
    title: optString(c.title), text: optString(c.text), author,
    cover: cover && /^https?:\/\//i.test(cover) ? cover : null,
    createdAt: optString(c.createdAt),
    duration: typeof c.duration === 'number' && Number.isFinite(c.duration) ? c.duration : null,
  }
}
