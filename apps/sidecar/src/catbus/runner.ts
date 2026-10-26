/** CatbusRunner：以子进程调用 catbus CLI，负责超时、取消、并发、信封解析与错误归一。 */
import { spawn } from 'node:child_process'
import { createRequire } from 'node:module'
import { dirname, join } from 'node:path'
import type { Logger } from '../log.ts'
import { Semaphore } from '../util/semaphore.ts'
import type { CallErrorCode, Envelope, Page } from './types.ts'

/** 值可能是凭证或个人信息的选项：日志里只记录选项名。 */
const SECRET_FLAGS = new Set(['--cookie', '--password', '--code', '--phone', '--username'])

/** 可以由上层决定重试的错误；RISK_CONTROL 明确不在其中。 */
const RETRYABLE: ReadonlySet<CallErrorCode> = new Set(['NETWORK', 'UPSTREAM', 'TIMEOUT'])

export class CatbusCallError extends Error {
  readonly code: CallErrorCode
  readonly hint: string | null
  readonly detail: unknown
  readonly exitCode: number | null

  constructor(code: CallErrorCode, message: string, extra: { hint?: string | null; detail?: unknown; exitCode?: number | null } = {}) {
    super(message)
    this.name = 'CatbusCallError'
    this.code = code
    this.hint = extra.hint ?? null
    this.detail = extra.detail ?? null
    this.exitCode = extra.exitCode ?? null
  }

  get retryable(): boolean {
    return RETRYABLE.has(this.code)
  }
}

export interface CatbusResult<T> {
  data: T
  page: Page | null
  account: string | null
}

export interface RunOptions {
  timeoutMs?: number
  signal?: AbortSignal
  /** 通过 stdin 传给 catbus（如 `--cookie -`），避免凭证出现在进程参数里。 */
  stdin?: string
  /** catbus 的进度提示（如「已扫码，请在手机上确认」）逐行回调。 */
  onStderrLine?: (line: string) => void
}

export interface CatbusRunnerOptions {
  logger: Logger
  /** 可执行文件；默认用当前 Node 运行随包的 catbus-cli，打包后无需全局安装。 */
  command?: string
  prefixArgs?: string[]
  env?: NodeJS.ProcessEnv
  defaultTimeoutMs?: number
  maxConcurrent?: number
  /** 同一平台的并发上限，降低触发风控的概率。 */
  maxPerPlatform?: number
  killGraceMs?: number
}

export function resolveBundledCatbus(): { command: string; prefixArgs: string[] } {
  const require = createRequire(import.meta.url)
  const pkgDir = dirname(require.resolve('catbus-cli/package.json'))
  return { command: process.execPath, prefixArgs: [join(pkgDir, 'dist', 'cli', 'main.js')] }
}

export function redactArgv(argv: readonly string[]): string[] {
  return argv.map((arg, i) => {
    const prev = argv[i - 1]
    if (prev !== undefined && SECRET_FLAGS.has(prev)) return '[REDACTED]'
    const eq = arg.indexOf('=')
    if (eq > 0 && SECRET_FLAGS.has(arg.slice(0, eq))) return `${arg.slice(0, eq)}=[REDACTED]`
    return arg
  })
}

export class CatbusRunner {
  private readonly log: Logger
  private readonly command: string
  private readonly prefixArgs: string[]
  private readonly env: NodeJS.ProcessEnv
  private readonly defaultTimeoutMs: number
  private readonly killGraceMs: number
  private readonly global: Semaphore
  private readonly maxPerPlatform: number
  private readonly perPlatform = new Map<string, Semaphore>()

  constructor(opts: CatbusRunnerOptions) {
    const bundled = opts.command ? null : resolveBundledCatbus()
    this.log = opts.logger.child({ mod: 'catbus' })
    this.command = opts.command ?? bundled!.command
    this.prefixArgs = opts.prefixArgs ?? bundled?.prefixArgs ?? []
    this.env = { ...process.env, ...opts.env, NO_COLOR: '1' }
    this.defaultTimeoutMs = opts.defaultTimeoutMs ?? 45_000
    this.killGraceMs = opts.killGraceMs ?? 2_000
    this.global = new Semaphore(opts.maxConcurrent ?? 4)
    this.maxPerPlatform = opts.maxPerPlatform ?? 2
  }

  /** argv 不含 `catbus` 本身，如 `['bilibili', 'feed', 'list', '--limit', '10']`。 */
  async run<T>(argv: readonly string[], opts: RunOptions = {}): Promise<CatbusResult<T>> {
    if (argv.length === 0) throw new CatbusCallError('USAGE', 'empty catbus argv')
    const platform = argv[0]!
    let sem = this.perPlatform.get(platform)
    if (!sem) this.perPlatform.set(platform, (sem = new Semaphore(this.maxPerPlatform)))
    return this.global.use(() => sem.use(() => this.exec<T>(argv, opts)))
  }

  private exec<T>(argv: readonly string[], opts: RunOptions): Promise<CatbusResult<T>> {
    const timeoutMs = opts.timeoutMs ?? this.defaultTimeoutMs
    const safeArgv = redactArgv(argv)
    const started = performance.now()
    this.log.debug('spawn', { argv: safeArgv, timeoutMs })

    return new Promise((resolve, reject) => {
      if (opts.signal?.aborted) return reject(new CatbusCallError('ABORTED', 'aborted before start'))

      const child = spawn(this.command, [...this.prefixArgs, ...argv], {
        env: this.env,
        stdio: [opts.stdin === undefined ? 'ignore' : 'pipe', 'pipe', 'pipe'],
      })
      const stdout: Buffer[] = []
      let stderrTail = ''
      let stderrBuf = ''
      let killedFor: 'TIMEOUT' | 'ABORTED' | null = null
      let settled = false

      const kill = (reason: 'TIMEOUT' | 'ABORTED') => {
        if (killedFor || child.exitCode !== null) return
        killedFor = reason
        child.kill('SIGTERM')
        setTimeout(() => child.exitCode === null && child.kill('SIGKILL'), this.killGraceMs).unref()
      }
      const timer = setTimeout(() => kill('TIMEOUT'), timeoutMs)
      const onAbort = () => kill('ABORTED')
      opts.signal?.addEventListener('abort', onAbort, { once: true })

      const finish = (fn: () => void) => {
        if (settled) return
        settled = true
        clearTimeout(timer)
        opts.signal?.removeEventListener('abort', onAbort)
        fn()
      }

      child.stdout!.on('data', (b: Buffer) => stdout.push(b))
      child.stderr!.on('data', (b: Buffer) => {
        const s = b.toString('utf8')
        stderrTail = (stderrTail + s).slice(-2000)
        stderrBuf += s
        let nl: number
        while ((nl = stderrBuf.indexOf('\n')) >= 0) {
          const line = stderrBuf.slice(0, nl).trimEnd()
          stderrBuf = stderrBuf.slice(nl + 1)
          if (line) opts.onStderrLine?.(line)
        }
      })
      if (opts.stdin !== undefined) {
        child.stdin!.on('error', () => {})
        child.stdin!.end(opts.stdin)
      }

      child.on('error', (err) =>
        finish(() => {
          this.log.error('spawn failed', { argv: safeArgv, err: err.message })
          reject(new CatbusCallError('SPAWN_FAILED', err.message))
        }),
      )

      child.on('close', (exitCode) =>
        finish(() => {
          const ms = Math.round(performance.now() - started)
          if (stderrBuf.trim()) opts.onStderrLine?.(stderrBuf.trim())
          if (killedFor) {
            this.log.warn('killed', { argv: safeArgv, reason: killedFor, ms })
            return reject(new CatbusCallError(killedFor, killedFor === 'TIMEOUT' ? `catbus timed out after ${timeoutMs}ms` : 'aborted'))
          }
          let env: Envelope<T>
          try {
            env = parseEnvelope<T>(Buffer.concat(stdout).toString('utf8'))
          } catch (err) {
            this.log.error('bad output', { argv: safeArgv, exitCode, ms, err: (err as Error).message, stderr: stderrTail })
            return reject(new CatbusCallError('BAD_OUTPUT', (err as Error).message, { exitCode, detail: { stderr: stderrTail } }))
          }
          if (!env.ok || env.error) {
            const e = env.error ?? { code: 'ERROR' as const, message: 'catbus returned ok=false', hint: null, detail: null }
            const level = e.code === 'RISK_CONTROL' ? 'warn' : 'info'
            this.log[level]('catbus error', { argv: safeArgv, exitCode, ms, code: e.code, message: e.message, hint: e.hint })
            return reject(new CatbusCallError(e.code, e.message, { hint: e.hint, detail: e.detail, exitCode }))
          }
          this.log.info('ok', { argv: safeArgv, ms, account: env.account, count: Array.isArray(env.data) ? env.data.length : undefined })
          resolve({ data: env.data, page: env.page, account: env.account })
        }),
      )
    })
  }
}

/** stdout 规范上只有一个 JSON 信封；容错取最后一个非空行，防止上游意外打印。 */
export function parseEnvelope<T>(stdout: string): Envelope<T> {
  const text = stdout.trim()
  if (!text) throw new Error('catbus produced no stdout')
  const candidates = [text, text.split('\n').filter((l) => l.trim()).at(-1)!]
  for (const c of candidates) {
    try {
      const v = JSON.parse(c) as Envelope<T>
      if (v && typeof v === 'object' && 'ok' in v) return v
    } catch {}
  }
  throw new Error(`catbus stdout is not an envelope: ${text.slice(0, 200)}`)
}
