/** 行分隔 JSON-RPC 2.0（stdio）。请求并发处理，长任务（扫码登录）不阻塞其他请求；服务端可主动推送通知。 */
import { createInterface } from 'node:readline'
import type { Readable, Writable } from 'node:stream'
import { CatbusCallError } from '../catbus/runner.ts'
import type { Logger } from '../log.ts'

export const RPC_ERRORS = { PARSE: -32700, INVALID_REQUEST: -32600, METHOD_NOT_FOUND: -32601, INVALID_PARAMS: -32602, INTERNAL: -32603, APP: -32000 } as const

/** 参数校验失败。 */
export class ParamError extends Error {}

export interface HandlerContext {
  notify(method: string, params: unknown): void
}

export type Handler = (params: Record<string, unknown>, ctx: HandlerContext) => unknown

interface Request {
  jsonrpc: '2.0'
  id?: string | number | null
  method: string
  params?: unknown
}

const MAX_LINE = 8 * 1024 * 1024

export class RpcServer {
  private readonly handlers = new Map<string, Handler>()
  private readonly log: Logger
  private out: Writable | null = null

  constructor(deps: { logger: Logger }) {
    this.log = deps.logger.child({ mod: 'rpc' })
  }

  register(method: string, handler: Handler): this {
    this.handlers.set(method, handler)
    return this
  }

  notify(method: string, params: unknown): void {
    this.write({ jsonrpc: '2.0', method, params })
  }

  /** 开始读 input；input 结束时 resolve（父进程退出即 stdin 关闭）。 */
  serve(input: Readable, output: Writable): Promise<void> {
    this.out = output
    const rl = createInterface({ input, crlfDelay: Infinity })
    rl.on('line', (line) => void this.handleLine(line))
    return new Promise((resolve) => rl.once('close', resolve))
  }

  async handleLine(line: string): Promise<void> {
    if (!line.trim()) return
    if (line.length > MAX_LINE) return this.reply(null, undefined, { code: RPC_ERRORS.INVALID_REQUEST, message: 'message too large' })
    let req: Request
    try {
      req = JSON.parse(line)
    } catch {
      return this.reply(null, undefined, { code: RPC_ERRORS.PARSE, message: 'parse error' })
    }
    if (!req || req.jsonrpc !== '2.0' || typeof req.method !== 'string') {
      return this.reply(req?.id ?? null, undefined, { code: RPC_ERRORS.INVALID_REQUEST, message: 'invalid request' })
    }
    const id = req.id
    const handler = this.handlers.get(req.method)
    if (!handler) return this.reply(id, undefined, { code: RPC_ERRORS.METHOD_NOT_FOUND, message: `method not found: ${req.method}` })
    const params = req.params ?? {}
    if (typeof params !== 'object' || Array.isArray(params)) {
      return this.reply(id, undefined, { code: RPC_ERRORS.INVALID_PARAMS, message: 'params must be an object' })
    }
    const started = performance.now()
    try {
      const result = await handler(params as Record<string, unknown>, { notify: (m, p) => this.notify(m, p) })
      this.log.debug('call', { method: req.method, ms: Math.round(performance.now() - started) })
      this.reply(id, result ?? null)
    } catch (err) {
      this.reply(id, undefined, this.toError(req.method, err))
    }
  }

  private toError(method: string, err: unknown): { code: number; message: string; data?: unknown } {
    if (err instanceof ParamError) return { code: RPC_ERRORS.INVALID_PARAMS, message: err.message }
    if (err instanceof CatbusCallError) {
      this.log.info('call failed', { method, code: err.code, message: err.message })
      return { code: RPC_ERRORS.APP, message: err.message, data: { code: err.code, hint: err.hint, retryable: err.retryable } }
    }
    this.log.error('handler crashed', { method, err: (err as Error)?.stack ?? String(err) })
    return { code: RPC_ERRORS.INTERNAL, message: (err as Error)?.message ?? 'internal error' }
  }

  /** 通知（无 id）不回复。 */
  private reply(id: Request['id'], result: unknown, error?: { code: number; message: string; data?: unknown }): void {
    if (id === undefined) return
    this.write(error ? { jsonrpc: '2.0', id, error } : { jsonrpc: '2.0', id, result })
  }

  private write(msg: unknown): void {
    if (!this.out || this.out.destroyed) return
    this.out.write(JSON.stringify(msg) + '\n')
  }
}

// —— 参数校验小工具 ——

export function str(p: Record<string, unknown>, name: string): string {
  const v = p[name]
  if (typeof v !== 'string' || !v) throw new ParamError(`${name} must be a non-empty string`)
  return v
}

export function optStr(p: Record<string, unknown>, name: string): string | undefined {
  const v = p[name]
  if (v === undefined || v === null) return undefined
  if (typeof v !== 'string') throw new ParamError(`${name} must be a string`)
  return v
}

export function optInt(p: Record<string, unknown>, name: string, min: number, max: number): number | undefined {
  const v = p[name]
  if (v === undefined || v === null) return undefined
  if (typeof v !== 'number' || !Number.isFinite(v)) throw new ParamError(`${name} must be a number`)
  return Math.min(Math.max(Math.trunc(v), min), max)
}

export function bool(p: Record<string, unknown>, name: string): boolean {
  const v = p[name]
  if (typeof v !== 'boolean') throw new ParamError(`${name} must be a boolean`)
  return v
}

export function oneOf<T extends string>(p: Record<string, unknown>, name: string, values: readonly T[]): T {
  const v = p[name]
  if (typeof v !== 'string' || !values.includes(v as T)) throw new ParamError(`${name} must be one of ${values.join(', ')}`)
  return v as T
}
