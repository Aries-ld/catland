import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'
import { CatbusCallError, CatbusRunner, parseEnvelope, redactArgv, resolveBundledCatbus } from '../src/catbus/runner.ts'
import { createMemoryLogger } from '../src/log.ts'

const FAKE = fileURLToPath(new URL('./fixtures/fake-catbus.mjs', import.meta.url))

function makeRunner(over: Partial<ConstructorParameters<typeof CatbusRunner>[0]> = {}) {
  const logger = createMemoryLogger()
  const runner = new CatbusRunner({ logger, command: process.execPath, prefixArgs: [FAKE], ...over })
  return { runner, logger }
}

async function catchErr(p: Promise<unknown>): Promise<CatbusCallError> {
  try {
    await p
  } catch (e) {
    return e as CatbusCallError
  }
  throw new Error('expected rejection')
}

describe('CatbusRunner', () => {
  it('解析成功信封，返回 data / page / account，并设置 NO_COLOR', async () => {
    const { runner } = makeRunner()
    const r = await runner.run<{ argv: string[]; env: { NO_COLOR: string } }>(['bilibili', 'ok', '--limit', '2'])
    expect(r.data.argv).toEqual(['bilibili', 'ok', '--limit', '2'])
    expect(r.data.env.NO_COLOR).toBe('1')
    expect(r.page).toEqual({ cursor: 'c1', has_more: true })
    expect(r.account).toBe('default')
  })

  it('把 catbus 的错误信封映射为 CatbusCallError，保留 hint 与退出码', async () => {
    const { runner } = makeRunner()
    const e = await catchErr(runner.run(['xhs', 'fail', 'AUTH_REQUIRED']))
    expect(e).toBeInstanceOf(CatbusCallError)
    expect(e.code).toBe('AUTH_REQUIRED')
    expect(e.hint).toBe('catbus xhs auth login')
    expect(e.exitCode).toBe(3)
    expect(e.retryable).toBe(false)
  })

  it('RISK_CONTROL 不可重试并记 warn，NETWORK 可重试', async () => {
    const { runner, logger } = makeRunner()
    const risk = await catchErr(runner.run(['xhs', 'fail', 'RISK_CONTROL']))
    expect(risk.retryable).toBe(false)
    expect(risk.detail).toEqual({ kind: 'captcha' })
    expect(logger.records.some((r) => r.level === 'warn' && r.code === 'RISK_CONTROL')).toBe(true)
    expect((await catchErr(runner.run(['xhs', 'fail', 'NETWORK']))).retryable).toBe(true)
  })

  it('stdout 非 JSON 或为空时报 BAD_OUTPUT', async () => {
    const { runner } = makeRunner()
    expect((await catchErr(runner.run(['x', 'garbage']))).code).toBe('BAD_OUTPUT')
    expect((await catchErr(runner.run(['x', 'empty']))).code).toBe('BAD_OUTPUT')
  })

  it('容忍信封前的杂讯行', async () => {
    const { runner } = makeRunner()
    expect((await runner.run<number[]>(['x', 'noisy'])).data).toEqual([1, 2, 3])
  })

  it('超时会杀掉子进程并报 TIMEOUT（可重试）', async () => {
    const { runner } = makeRunner()
    const e = await catchErr(runner.run(['x', 'sleep', '5000'], { timeoutMs: 150 }))
    expect(e.code).toBe('TIMEOUT')
    expect(e.retryable).toBe(true)
  })

  it('忽略 SIGTERM 的子进程在宽限期后被 SIGKILL', async () => {
    const { runner } = makeRunner({ killGraceMs: 100 })
    const t0 = Date.now()
    expect((await catchErr(runner.run(['x', 'ignore-term'], { timeoutMs: 300 }))).code).toBe('TIMEOUT')
    expect(Date.now() - t0).toBeLessThan(3000)
  })

  it('AbortSignal 取消正在运行和尚未开始的调用', async () => {
    const { runner } = makeRunner()
    const ac = new AbortController()
    const p = runner.run(['x', 'sleep', '5000'], { signal: ac.signal })
    setTimeout(() => ac.abort(), 100)
    expect((await catchErr(p)).code).toBe('ABORTED')
    expect((await catchErr(runner.run(['x', 'ok'], { signal: ac.signal }))).code).toBe('ABORTED')
  })

  it('通过 stdin 传凭证，参数里不出现', async () => {
    const { runner, logger } = makeRunner()
    const r = await runner.run<{ stdin: string }>(['x', 'stdin', '--cookie', '-'], { stdin: 'auth_token=abc; ct0=def' })
    expect(r.data.stdin).toBe('auth_token=abc; ct0=def')
    expect(JSON.stringify(logger.records)).not.toContain('auth_token=abc')
  })

  it('stderr 进度逐行回调，包括末尾没有换行的部分', async () => {
    const { runner } = makeRunner()
    const lines: string[] = []
    await runner.run(['x', 'stderr'], { onStderrLine: (l) => lines.push(l) })
    expect(lines).toEqual(['[catbus] 二维码已生成', '[catbus] 已扫码，请在手机上确认', 'partial-no-newline'])
  })

  it('同平台并发受 maxPerPlatform 限制，不同平台互不阻塞', async () => {
    const { runner } = makeRunner({ maxPerPlatform: 1, maxConcurrent: 4 })
    type T = { start: number; end: number }
    const [a, b, c] = await Promise.all([
      runner.run<T>(['bilibili', 'sleep', '200']),
      runner.run<T>(['bilibili', 'sleep', '200']),
      runner.run<T>(['xhs', 'sleep', '200']),
    ])
    const [first, second] = [a.data, b.data].sort((p, q) => p.start - q.start)
    expect(second!.start).toBeGreaterThanOrEqual(first!.end)
    expect(c.data.start).toBeLessThan(Math.max(a.data.end, b.data.end))
  })

  it('命令不存在时报 SPAWN_FAILED', async () => {
    const { runner } = makeRunner({ command: '/nonexistent/catbus', prefixArgs: [] })
    expect((await catchErr(runner.run(['x', 'ok']))).code).toBe('SPAWN_FAILED')
  })
})

describe('redactArgv', () => {
  it('隐藏凭证类选项的值', () => {
    expect(redactArgv(['x', 'auth', 'login', '--cookie', 'a=1', '--phone=138', '-a', 'work'])).toEqual([
      'x', 'auth', 'login', '--cookie', '[REDACTED]', '--phone=[REDACTED]', '-a', 'work',
    ])
  })
})

describe('parseEnvelope', () => {
  it('拒绝没有 ok 字段的 JSON', () => {
    expect(() => parseEnvelope('{"a":1}')).toThrow()
  })
})

describe('resolveBundledCatbus', () => {
  it('指向随包 catbus-cli 的入口', () => {
    const { command, prefixArgs } = resolveBundledCatbus()
    expect(command).toBe(process.execPath)
    expect(prefixArgs[0]).toMatch(/catbus-cli[/\\]dist[/\\]cli[/\\]main\.js$/)
  })
})
