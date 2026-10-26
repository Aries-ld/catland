import { existsSync, mkdtempSync, readFileSync, statSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { describe, expect, it } from 'vitest'
import { createFileLogger, redact } from '../src/log.ts'

const tmp = () => mkdtempSync(join(tmpdir(), 'catland-log-'))

describe('createFileLogger', () => {
  it('写 JSONL，带时间戳、级别、上下文，过滤低级别', () => {
    const dir = tmp()
    const log = createFileLogger({ dir, level: 'info', now: () => new Date('2026-10-26T00:00:00Z') })
    log.debug('hidden')
    log.child({ mod: 'catbus' }).info('ok', { ms: 12 })
    const lines = readFileSync(join(dir, 'sidecar.log'), 'utf8').trim().split('\n').map((l) => JSON.parse(l))
    expect(lines).toEqual([{ ts: '2026-10-26T00:00:00.000Z', level: 'info', msg: 'ok', mod: 'catbus', ms: 12 }])
    expect(statSync(join(dir, 'sidecar.log')).mode & 0o777).toBe(0o600)
  })

  it('超过大小上限时轮转，最多保留 maxFiles 份', () => {
    const dir = tmp()
    const log = createFileLogger({ dir, maxBytes: 200, maxFiles: 2 })
    for (let i = 0; i < 30; i++) log.info('x'.repeat(50), { i })
    expect(existsSync(join(dir, 'sidecar.log.1'))).toBe(true)
    expect(existsSync(join(dir, 'sidecar.log.2'))).toBe(true)
    expect(existsSync(join(dir, 'sidecar.log.3'))).toBe(false)
    expect(statSync(join(dir, 'sidecar.log')).size).toBeLessThanOrEqual(200)
  })

  it('敏感字段不会落盘', () => {
    const dir = tmp()
    createFileLogger({ dir }).info('login', { cookie: 'SESSDATA=secret', nested: { apiKey: 'k', ok: 1 } })
    const text = readFileSync(join(dir, 'sidecar.log'), 'utf8')
    expect(text).not.toContain('secret')
    expect(JSON.parse(text).nested).toEqual({ apiKey: '[REDACTED]', ok: 1 })
  })
})

describe('redact', () => {
  it('处理数组与原始值', () => {
    expect(redact([{ token: 't', a: 1 }, 2])).toEqual([{ token: '[REDACTED]', a: 1 }, 2])
    expect(redact('plain')).toBe('plain')
  })
})
