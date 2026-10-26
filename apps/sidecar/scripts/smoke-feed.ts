/** 真机冒烟：已登录平台混排刷 N 条，记录首屏耗时、每次划动等待、媒体地址可达性。只读。 */
import { AccountService } from '../src/accounts/service.ts'
import { CatbusRunner } from '../src/catbus/runner.ts'
import { createAdapter } from '../src/content/adapters.ts'
import { FeedMixer } from '../src/content/mixer.ts'
import type { FeedCard } from '../src/content/types.ts'
import { createFileLogger } from '../src/log.ts'

const SWIPES = Number(process.argv[2] ?? 12)
const DWELL_MS = Number(process.argv[3] ?? 2000)
const logger = createFileLogger()
const catbus = new CatbusRunner({ logger })
const accounts = new AccountService({ catbus, logger })
const platforms = (await accounts.refresh()).filter((p) => p.connected && p.sections.includes('content')).map((p) => p.id)
console.log('sources:', platforms.join(', '))

const mixer = new FeedMixer({ logger })
mixer.on('source', (s) => console.log(`  [source] ${s.platform} → ${s.status}${s.lastError ? ` (${s.lastError.code})` : ''}`))
const t0 = performance.now()
mixer.setSources(platforms.map((p) => createAdapter(p, { catbus, logger })))

async function probe(card: FeedCard): Promise<string> {
  const src = card.video ?? card.images[0]
  if (!src) return 'no-media'
  const res = await fetch(src.url, { headers: { ...src.headers, Range: 'bytes=0-1023' }, signal: AbortSignal.timeout(8000) }).catch((e) => ({ status: `ERR ${e.message}` }))
  if ('body' in res) await res.body?.cancel()
  return String(res.status)
}

const waits: number[] = []
const byPlatform: Record<string, number> = {}
for (let i = 0; i < SWIPES; i++) {
  const w0 = performance.now()
  const [card] = await mixer.next(1, { waitMs: 15_000 })
  const wait = performance.now() - w0
  if (!card) {
    console.log(`#${i} 空：缓冲没有卡片`)
    continue
  }
  if (i === 0) console.log(`首屏：${Math.round(performance.now() - t0)}ms`)
  else waits.push(wait)
  byPlatform[card.platform] = (byPlatform[card.platform] ?? 0) + 1
  const v = card.video
  const shape = v ? `video ${v.width}x${v.height} ${v.duration}s` : `image×${card.images.length}`
  console.log(`#${i} ${card.platform.padEnd(8)} wait=${Math.round(wait)}ms ${shape.padEnd(22)} http=${await probe(card)}  ${(card.title ?? card.text ?? '').replace(/\s+/g, ' ').slice(0, 30)}`)
  await new Promise((r) => setTimeout(r, DWELL_MS))
}
waits.sort((a, b) => a - b)
console.log('分布:', byPlatform, `划动等待 p50=${Math.round(waits[waits.length >> 1] ?? 0)}ms max=${Math.round(waits.at(-1) ?? 0)}ms`)
console.log('源状态:', mixer.sourceStates().map((s) => `${s.platform}:${s.status} pending=${s.pending} ready=${s.ready}`).join(' | '))
mixer.stop()
