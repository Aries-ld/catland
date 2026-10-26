/** sidecar 入口：由 macOS App 以子进程启动，经 stdio 通信；stdin 关闭（App 退出）即退出，不留孤儿进程。 */
import { App } from './app.ts'
import { CatbusRunner } from './catbus/runner.ts'
import { createFileLogger } from './log.ts'
import { RpcServer } from './rpc/server.ts'
import { Store } from './store/store.ts'

// stdout 只能有 RPC 消息：任何误用 console.log 的输出都改到 stderr。
console.log = (...args: unknown[]) => console.error(...args)

const logger = createFileLogger({ mirrorStderr: process.env.CATLAND_LOG_STDERR === '1' })
process.on('uncaughtException', (err) => {
  logger.error('uncaught exception', { err: err.stack ?? String(err) })
  process.exit(1)
})
process.on('unhandledRejection', (err) => logger.error('unhandled rejection', { err: (err as Error)?.stack ?? String(err) }))

const store = new Store()
const app = new App({ catbus: new CatbusRunner({ logger }), logger, store })
const rpc = new RpcServer({ logger })
app.register(rpc)

let stopping = false
const shutdown = (reason: string) => {
  if (stopping) return
  stopping = true
  logger.info('shutdown', { reason })
  app.stop()
  process.exit(0)
}
process.on('SIGTERM', () => shutdown('SIGTERM'))
process.on('SIGINT', () => shutdown('SIGINT'))

logger.info('start', { pid: process.pid, node: process.version })
const serving = rpc.serve(process.stdin, process.stdout)
// 先接请求再拉账号：accounts.list 等调用在启动期间也能拿到（可能为空的）结果。
app.start().then(
  () => rpc.notify('app.ready', { sources: app.enabledSources(), platforms: app.accounts.platforms() }),
  (err) => {
    logger.error('start failed', { err: (err as Error).stack ?? String(err) })
    rpc.notify('app.error', { message: (err as Error).message })
  },
)
await serving
shutdown('stdin closed')
