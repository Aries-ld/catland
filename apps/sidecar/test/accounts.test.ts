import { mkdtempSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { describe, expect, it } from 'vitest'
import { AccountService, type CatbusClient, type LoginEvent } from '../src/accounts/service.ts'
import { CatbusCallError, type CatbusResult, type RunOptions } from '../src/catbus/runner.ts'
import type { Account } from '../src/catbus/types.ts'
import { createMemoryLogger } from '../src/log.ts'

type Handler = (argv: readonly string[], opts: RunOptions) => Promise<unknown> | unknown

/** 按 argv 前缀脚本化的 catbus 替身，记录每次调用。 */
class FakeCatbus implements CatbusClient {
  calls: Array<{ argv: readonly string[]; opts: RunOptions }> = []
  private readonly routes: Array<[string, Handler]> = []
  accounts: Account[] = []

  constructor() {
    this.on('auth list', () => this.accounts)
  }

  on(prefix: string, h: Handler): this {
    this.routes.unshift([prefix, h])
    return this
  }

  async run<T>(argv: readonly string[], opts: RunOptions = {}): Promise<CatbusResult<T>> {
    this.calls.push({ argv, opts })
    const key = argv.join(' ')
    const route = this.routes.find(([p]) => key.startsWith(p))
    if (!route) throw new Error(`unexpected catbus call: ${key}`)
    return { data: (await route[1](argv, opts)) as T, page: null, account: null }
  }
}

const acct = (platform: string, account = 'default', current = true): Account => ({
  platform, endpoint: 'web', account, current, user: { id: `${platform}-u`, name: `${platform}-name`, url: null }, method: 'qrcode', updated_at: null,
})

function setup() {
  const catbus = new FakeCatbus()
  const svc = new AccountService({ catbus, logger: createMemoryLogger() })
  return { catbus, svc }
}

describe('AccountService.refresh / platforms', () => {
  it('按目录列出全部平台，已登录的点亮并带当前账号', async () => {
    const { catbus, svc } = setup()
    catbus.accounts = [acct('bilibili'), acct('xhs', 'work', false), acct('xhs'), { ...acct('xianyu'), endpoint: 'app' }]
    const list = await svc.refresh()
    expect(list.map((p) => p.id)).toEqual(['xhs', 'douyin', 'bilibili', 'kuaishou', 'x', 'tiktok', 'weibo', 'jd', 'taobao', 'xianyu'])
    const xhs = list.find((p) => p.id === 'xhs')!
    expect(xhs.connected).toBe(true)
    expect(xhs.current?.account).toBe('default')
    expect(xhs.accounts).toHaveLength(2)
    expect(list.find((p) => p.id === 'douyin')!.connected).toBe(false)
    expect(list.find((p) => p.id === 'xianyu')!.connected).toBe(false) // 只认 web 端
    expect(list.find((p) => p.id === 'x')!.primaryLogin).toBe('cookie')
  })
})

describe('置灰的平台', () => {
  it('X、TikTok 标记为暂未开放，且不能发起登录', async () => {
    const { svc } = setup()
    const list = await svc.refresh()
    expect(list.filter((p) => p.unavailable).map((p) => p.id)).toEqual(['x', 'tiktok'])
    expect(list.find((p) => p.id === 'xhs')!.unavailable).toBeNull()
    await expect(svc.loginCookie('x', 'auth_token=a; ct0=b')).rejects.toMatchObject({ code: 'USAGE' })
    await expect(svc.loginCookie('tiktok', 'sessionid=a')).rejects.toMatchObject({ code: 'USAGE' })
  })
})

describe('AccountService.checkHealth', () => {
  it.each([
    [{ logged_in: true }, 'ok'],
    [{ logged_in: false }, 'expired'],
    [new CatbusCallError('AUTH_EXPIRED', 'x'), 'expired'],
    [new CatbusCallError('RISK_CONTROL', 'x'), 'risk'],
    [new CatbusCallError('NETWORK', 'x'), 'unknown'],
  ])('%o → %s', async (result, expected) => {
    const { catbus, svc } = setup()
    catbus.accounts = [acct('bilibili')]
    catbus.on('bilibili auth status', () => {
      if (result instanceof Error) throw result
      return result
    })
    await svc.refresh()
    expect(await svc.checkHealth('bilibili')).toBe(expected)
    expect(svc.platforms().find((p) => p.id === 'bilibili')!.health).toBe(expected)
  })
})

describe('AccountService.loginQrcode', () => {
  it('把二维码 PNG 以 base64 推给客户端，过滤字符画，转发进度，成功后刷新', async () => {
    const { catbus, svc } = setup()
    const png = join(mkdtempSync(join(tmpdir(), 'catland-qr-')), 'qrcode.png')
    writeFileSync(png, Buffer.from([0x89, 0x50, 0x4e, 0x47]))
    catbus.on('bilibili auth login', (_argv, opts) => {
      opts.onStderrLine?.('▄▄▄▄ █▀▀▀█ ▄▄')
      opts.onStderrLine?.(`[catbus] 请用 App 扫码。二维码图片：${png}`)
      opts.onStderrLine?.('[catbus] 已扫码，请在手机上确认')
      catbus.accounts = [acct('bilibili')]
      return acct('bilibili')
    })
    const events: LoginEvent[] = []
    let changed = 0
    svc.on('changed', () => changed++)
    const account = await svc.loginQrcode('bilibili', { onEvent: (e) => events.push(e) })

    expect(account.platform).toBe('bilibili')
    expect(events).toEqual([
      { type: 'progress', platform: 'bilibili', message: '已扫码，请在手机上确认' },
      { type: 'qrcode', platform: 'bilibili', png: 'iVBORw==' },
    ])
    const login = catbus.calls.find((c) => c.argv.includes('login'))!
    expect(login.argv).toEqual(['bilibili', 'auth', 'login', '--method', 'qrcode'])
    expect(login.opts.timeoutMs).toBeGreaterThanOrEqual(5 * 60_000)
    const state = svc.platforms().find((p) => p.id === 'bilibili')!
    expect(state).toMatchObject({ connected: true, health: 'ok', loginInProgress: false })
    expect(changed).toBeGreaterThanOrEqual(2)
  })

  it('只支持 cookie 的平台拒绝扫码', async () => {
    const { svc } = setup()
    await expect(svc.loginQrcode('weibo')).rejects.toMatchObject({ code: 'UNSUPPORTED' })
  })

  it('同一平台不能并发登录；cancelLogin 中止进行中的登录', async () => {
    const { catbus, svc } = setup()
    catbus.on('xhs auth login', (_a, opts) => new Promise((_, reject) => opts.signal!.addEventListener('abort', () => reject(new CatbusCallError('ABORTED', 'aborted')))))
    const first = svc.loginQrcode('xhs')
    await expect(svc.loginQrcode('xhs')).rejects.toMatchObject({ code: 'USAGE' })
    expect(svc.platforms().find((p) => p.id === 'xhs')!.loginInProgress).toBe(true)
    expect(svc.cancelLogin('xhs')).toBe(true)
    await expect(first).rejects.toMatchObject({ code: 'ABORTED' })
    expect(svc.platforms().find((p) => p.id === 'xhs')!.loginInProgress).toBe(false)
    expect(svc.cancelLogin('xhs')).toBe(false)
  })
})

describe('AccountService.loginCookie', () => {
  it('cookie 经 stdin 传入，不进 argv；默认非 cookie 的平台补 --method cookie', async () => {
    const { catbus, svc } = setup()
    catbus.on('xhs auth login', () => acct('xhs'))
    catbus.on('weibo auth login', () => acct('weibo'))
    await svc.loginCookie('xhs', [{ name: 'web_session', value: 'SECRET', domain: '.xiaohongshu.com' }])
    await svc.loginCookie('weibo', 'SUB=SECRET; SUBP=1', { account: 'work' })
    const [xhs, wb] = catbus.calls.filter((c) => c.argv.includes('login'))
    expect(xhs!.argv).toEqual(['xhs', 'auth', 'login', '--method', 'cookie', '--cookie', '-'])
    expect(JSON.parse(xhs!.opts.stdin!)).toEqual([{ name: 'web_session', value: 'SECRET', domain: '.xiaohongshu.com' }])
    expect(wb!.argv).toEqual(['weibo', 'auth', 'login', '--cookie', '-', '-a', 'work'])
    expect(catbus.calls.every((c) => !c.argv.join(' ').includes('SECRET'))).toBe(true)
  })

  it('空 cookie 直接拒绝', async () => {
    const { svc } = setup()
    await expect(svc.loginCookie('x', [])).rejects.toMatchObject({ code: 'USAGE' })
    await expect(svc.loginCookie('x', '  ')).rejects.toMatchObject({ code: 'USAGE' })
  })
})

describe('AccountService.logout / use / 校验', () => {
  it('logout 默认登出当前账号并刷新', async () => {
    const { catbus, svc } = setup()
    catbus.accounts = [acct('bilibili')]
    catbus.on('bilibili auth logout', () => {
      catbus.accounts = []
      return acct('bilibili', 'default', false)
    })
    await svc.refresh()
    await svc.logout('bilibili')
    expect(catbus.calls.map((c) => c.argv.join(' '))).toContain('bilibili auth logout -a default')
    expect(svc.platforms().find((p) => p.id === 'bilibili')!.connected).toBe(false)
  })

  it('没有账号时 logout 报 USAGE', async () => {
    const { svc } = setup()
    await expect(svc.logout('douyin')).rejects.toMatchObject({ code: 'USAGE' })
  })

  it('use 切换账号', async () => {
    const { catbus, svc } = setup()
    catbus.on('xhs auth use', () => acct('xhs', 'work'))
    await svc.use('xhs', 'work')
    expect(catbus.calls.map((c) => c.argv.join(' '))).toContain('xhs auth use work')
  })

  it('拒绝未知平台和可能被当成选项的账号名', async () => {
    const { svc } = setup()
    await expect(svc.checkHealth('12306')).rejects.toMatchObject({ code: 'USAGE' })
    await expect(svc.use('xhs', '-y')).rejects.toMatchObject({ code: 'USAGE' })
    await expect(svc.loginCookie('x', 'a=1', { account: 'Work' })).rejects.toMatchObject({ code: 'USAGE' })
  })
})
