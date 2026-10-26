/** 真机冒烟：经 CatbusRunner 调用随包 catbus，列出账号并拉每个已登录平台的一条推荐。只读，不做写操作。 */
import { CatbusCallError, CatbusRunner } from '../src/catbus/runner.ts'
import type { Account, Item } from '../src/catbus/types.ts'
import { createFileLogger } from '../src/log.ts'

const logger = createFileLogger({ mirrorStderr: false })
const runner = new CatbusRunner({ logger })

const { data: accounts } = await runner.run<Account[]>(['auth', 'list'])
console.log('accounts:', accounts.map((a) => `${a.platform}:${a.user?.name}`))

for (const p of ['bilibili', 'xhs', 'x']) {
  const t0 = performance.now()
  try {
    const { data, page } = await runner.run<Item[]>([p, 'feed', 'list', '--limit', '1'], { timeoutMs: 60_000 })
    const it = data[0]
    console.log(`${p} ${Math.round(performance.now() - t0)}ms`, it?.kind, it?.title ?? it?.text?.slice(0, 30), `media=${it?.media.length}`, `has_more=${page?.has_more}`)
  } catch (e) {
    const err = e as CatbusCallError
    console.log(`${p} FAILED`, err.code, err.message, err.hint)
  }
}
