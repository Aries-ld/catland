/** 端到端冒烟：像 macOS App 一样以子进程启动 sidecar，经 stdio RPC 走一遍主要流程。数据目录用临时目录。 */
import { spawn } from 'node:child_process'
import { mkdtempSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { createInterface } from 'node:readline'
import { fileURLToPath } from 'node:url'

const main = fileURLToPath(new URL('../src/main.ts', import.meta.url))
const dataDir = mkdtempSync(join(tmpdir(), 'catland-e2e-'))
const t0 = performance.now()
const child = spawn(process.execPath, [main], { env: { ...process.env, CATLAND_DATA_DIR: dataDir }, stdio: ['pipe', 'pipe', 'inherit'] })

const pending = new Map<number, (m: any) => void>()
const notes: any[] = []
let ready: () => void
const readyP = new Promise<void>((r) => (ready = r))
let nonJson = 0
createInterface({ input: child.stdout }).on('line', (line) => {
  let m: any
  try {
    m = JSON.parse(line)
  } catch {
    nonJson++
    return
  }
  if (m.id !== undefined) pending.get(m.id)?.(m)
  else {
    notes.push(m)
    if (m.method === 'app.ready') ready()
  }
})
let seq = 0
const call = (method: string, params?: unknown): Promise<any> =>
  new Promise((resolve, reject) => {
    const id = ++seq
    pending.set(id, (m) => (m.error ? reject(new Error(`${method}: ${JSON.stringify(m.error)}`)) : resolve(m.result)))
    child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n')
  })
const ms = (t: number) => `${Math.round(performance.now() - t)}ms`

const hello = await call('app.hello')
console.log(`hello ${ms(t0)}`, hello)
await readyP
console.log(`app.ready ${ms(t0)}`, notes.find((n) => n.method === 'app.ready').params.sources)

const tf = performance.now()
const first = await call('feed.next', { count: 1, waitMs: 15000 })
console.log(`首屏 feed.next ${ms(tf)}（自启动 ${ms(t0)}）`, first.cards.map((c: any) => `${c.platform}:${c.kind}`))

const cards = [...first.cards]
for (let i = 0; i < 5; i++) {
  await new Promise((r) => setTimeout(r, 800))
  const t = performance.now()
  const r = await call('feed.next', { count: 1 })
  console.log(`  swipe #${i + 1} ${ms(t)} ${r.cards.map((c: any) => `${c.platform}:${c.kind}`)}`)
  cards.push(...r.cards)
}
const c0 = cards[0]
await call('feed.view', { key: c0.key, dwellMs: 4200 })
console.log('like →', await call('interact.set', { key: c0.key, kind: 'like', on: true }))
const tc = performance.now()
const comments = await call('comments.list', { key: c0.key })
console.log(`comments ${ms(tc)} n=${comments.comments.length} hasMore=${comments.hasMore} 首条=${comments.comments[0]?.text?.slice(0, 20)}`)
console.log('history', (await call('history.list')).entries.map((e: any) => `${e.card.key} ${e.dwellMs}ms`))
console.log('likes', (await call('interact.list', { kind: 'like' })).entries.map((e: any) => e.card.title?.slice(0, 20)))
console.log('sources', (await call('feed.sources')).states.map((s: any) => `${s.platform}:${s.status}`).join(' '))
console.log('stdout 非 JSON 行:', nonJson)

const te = performance.now()
child.stdin.end()
child.on('exit', (code) => console.log(`stdin 关闭后退出 code=${code} 用时 ${ms(te)}`))
