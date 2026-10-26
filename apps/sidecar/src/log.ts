/** 结构化日志：JSONL 落盘 + 按大小轮转 + 敏感字段脱敏。stdout 留给 RPC，日志永不写 stdout。 */
import { appendFileSync, existsSync, mkdirSync, renameSync, rmSync, statSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'

export type LogLevel = 'debug' | 'info' | 'warn' | 'error'

const LEVEL_RANK: Record<LogLevel, number> = { debug: 10, info: 20, warn: 30, error: 40 }

const SENSITIVE_KEY = /cookie|token|password|secret|authorization|session|private_?key|api_?key/i

export interface Logger {
  debug(msg: string, ctx?: Record<string, unknown>): void
  info(msg: string, ctx?: Record<string, unknown>): void
  warn(msg: string, ctx?: Record<string, unknown>): void
  error(msg: string, ctx?: Record<string, unknown>): void
  child(ctx: Record<string, unknown>): Logger
}

export interface FileLoggerOptions {
  dir?: string
  file?: string
  level?: LogLevel
  maxBytes?: number
  maxFiles?: number
  /** 同时镜像到 stderr，方便开发时观察。 */
  mirrorStderr?: boolean
  now?: () => Date
}

export function defaultLogDir(): string {
  return process.env.CATLAND_LOG_DIR ?? join(homedir(), 'Library', 'Logs', 'catland')
}

/** 递归脱敏：键名命中敏感词的值一律替换，防止 cookie / key 进日志。 */
export function redact(value: unknown, depth = 0): unknown {
  if (depth > 6 || value === null || typeof value !== 'object') return value
  if (Array.isArray(value)) return value.map((v) => redact(v, depth + 1))
  const out: Record<string, unknown> = {}
  for (const [k, v] of Object.entries(value)) out[k] = SENSITIVE_KEY.test(k) ? '[REDACTED]' : redact(v, depth + 1)
  return out
}

export function createFileLogger(opts: FileLoggerOptions = {}): Logger {
  const dir = opts.dir ?? defaultLogDir()
  const path = join(dir, opts.file ?? 'sidecar.log')
  const minRank = LEVEL_RANK[opts.level ?? (process.env.CATLAND_LOG_LEVEL as LogLevel | undefined) ?? 'info'] ?? LEVEL_RANK.info
  const maxBytes = opts.maxBytes ?? 5 * 1024 * 1024
  const maxFiles = opts.maxFiles ?? 5
  const now = opts.now ?? (() => new Date())
  mkdirSync(dir, { recursive: true, mode: 0o700 })

  const rotate = () => {
    rmSync(`${path}.${maxFiles}`, { force: true })
    for (let i = maxFiles - 1; i >= 1; i--) if (existsSync(`${path}.${i}`)) renameSync(`${path}.${i}`, `${path}.${i + 1}`)
    renameSync(path, `${path}.1`)
  }

  const write = (level: LogLevel, msg: string, base: Record<string, unknown>, ctx?: Record<string, unknown>) => {
    if (LEVEL_RANK[level] < minRank) return
    const line = JSON.stringify({ ts: now().toISOString(), level, msg, ...(redact({ ...base, ...ctx }) as object) }) + '\n'
    try {
      if (existsSync(path) && statSync(path).size + line.length > maxBytes) rotate()
      appendFileSync(path, line, { mode: 0o600 })
    } catch (err) {
      process.stderr.write(`[catland] log write failed: ${(err as Error).message}\n`)
    }
    if (opts.mirrorStderr) process.stderr.write(line)
  }

  const make = (base: Record<string, unknown>): Logger => ({
    debug: (m, c) => write('debug', m, base, c),
    info: (m, c) => write('info', m, base, c),
    warn: (m, c) => write('warn', m, base, c),
    error: (m, c) => write('error', m, base, c),
    child: (c) => make({ ...base, ...c }),
  })
  return make({})
}

/** 测试用：把日志收集到内存。 */
export function createMemoryLogger(): Logger & { records: Array<{ level: LogLevel; msg: string } & Record<string, unknown>> } {
  const records: Array<{ level: LogLevel; msg: string } & Record<string, unknown>> = []
  const make = (base: Record<string, unknown>): Logger => {
    const w = (level: LogLevel) => (msg: string, ctx?: Record<string, unknown>) =>
      void records.push({ level, msg, ...(redact({ ...base, ...ctx }) as object) })
    return { debug: w('debug'), info: w('info'), warn: w('warn'), error: w('error'), child: (c) => make({ ...base, ...c }) }
  }
  return Object.assign(make({}), { records })
}
