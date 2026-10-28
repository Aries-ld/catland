/** 真机冒烟：在已登录的内容平台上搜一个关键词，记录每个平台的耗时与结果数，并点开每个平台的第一条检查可播放。只读。 */
import { AccountService } from '../src/accounts/service.ts'
import { CatbusRunner } from '../src/catbus/runner.ts'
import { createAdapter } from '../src/content/adapters.ts'
import { FeedMixer } from '../src/content/mixer.ts'
import { SearchService } from '../src/content/search.ts'
import type { PlatformAdapter } from '../src/content/types.ts'
import { createFileLogger } from '../src/log.ts'

const QUERY = process.argv[2] ?? '露营装备'
const logger = createFileLogger()
const catbus = new CatbusRunner({ logger })
const accounts = new AccountService({ catbus, logger })
const platforms = (await accounts.refresh()).filter((p) => p.connected && !p.unavailable && p.sections.includes('content')).map((p) => p.id)
console.log(`搜索「${QUERY}」：${platforms.join(', ')}`)

const adapters = new Map<string, PlatformAdapter>(platforms.map((p) => [p, createAdapter(p, { catbus, logger })]))
const mixer = new FeedMixer({ logger }) // 不 setSources：只借用风控状态接口，不刷推荐流
const search = new SearchService({ logger, mixer, adapterFor: (p) => adapters.get(p)! })

const t0 = performance.now()
await Promise.all(platforms.map(async (p) => {
  try {
    const r = await search.query(p, QUERY)
    const ms = Math.round(performance.now() - t0)
    const first = r.hits[0]
    console.log(`  ${p.padEnd(9)} ${String(ms).padStart(5)}ms  ${r.status}  ${r.hits.length} 条  首条：${first?.title?.slice(0, 20) ?? '-'}  封面：${first?.cover ? '有' : '无'}  时长：${first?.duration ?? '-'}`)
    if (!first) return
    const card = await search.resolve(first.key)
    const src = card?.video ?? card?.images[0]
    if (!src) return console.log(`    ${p} 点开：没有可用媒体`)
    const res = await fetch(src.url, { headers: { ...src.headers, Range: 'bytes=0-1023' }, signal: AbortSignal.timeout(8000) })
    await res.body?.cancel()
    console.log(`    ${p} 点开：${card!.kind} HTTP ${res.status}`)
  } catch (err) {
    console.log(`  ${p} 失败：${(err as Error).message}`)
  }
}))
mixer.stop()
