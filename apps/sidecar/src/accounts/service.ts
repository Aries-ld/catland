/** AccountService：连接面板的数据源——平台点亮状态、扫码 / cookie 登录、登出、切换账号、登录态体检。 */
import { EventEmitter } from 'node:events'
import { readFile } from 'node:fs/promises'
import type { Logger } from '../log.ts'
import { CatbusCallError, type CatbusResult, type RunOptions } from '../catbus/runner.ts'
import type { Account, AuthStatus } from '../catbus/types.ts'
import { ACCOUNT_NAME_RE, getPlatform, PLATFORMS, type PlatformSpec } from './catalog.ts'

/** AccountService 只依赖 runner 的这一个方法，便于替换与测试。 */
export interface CatbusClient {
  run<T>(argv: readonly string[], opts?: RunOptions): Promise<CatbusResult<T>>
}

export type Health = 'ok' | 'expired' | 'risk' | 'unknown'

export interface PlatformState {
  id: string
  name: string
  primaryLogin: PlatformSpec['primaryLogin']
  loginUrl: string
  requiredCookies: string[][]
  sections: PlatformSpec['sections']
  connected: boolean
  current: Account | null
  accounts: Account[]
  health: Health
  loginInProgress: boolean
}

export type LoginEvent =
  | { type: 'qrcode'; platform: string; png: string /* base64 */ }
  | { type: 'progress'; platform: string; message: string }

export interface LoginOptions {
  account?: string
  signal?: AbortSignal
  onEvent?: (e: LoginEvent) => void
}

/** 浏览器 / WKHTTPCookieStore 导出的 cookie，catbus 接受这种 JSON 数组。 */
export interface BrowserCookie {
  name: string
  value: string
  domain?: string
  path?: string
  expires?: number
}

const QR_LINE = /二维码图片：(\S+\.png)/
const QR_LOGIN_TIMEOUT_MS = 6 * 60_000

export class AccountService extends EventEmitter<{ changed: [] }> {
  private readonly catbus: CatbusClient
  private readonly log: Logger
  private accounts: Account[] = []
  private readonly health = new Map<string, Health>()
  private readonly logins = new Map<string, AbortController>()

  constructor(deps: { catbus: CatbusClient; logger: Logger }) {
    super()
    this.catbus = deps.catbus
    this.log = deps.logger.child({ mod: 'accounts' })
  }

  /** 重新读取本地已保存的账号（不联网）。 */
  async refresh(): Promise<PlatformState[]> {
    const { data } = await this.catbus.run<Account[]>(['auth', 'list'])
    this.accounts = data.filter((a) => a.endpoint === 'web')
    return this.platforms()
  }

  platforms(): PlatformState[] {
    return PLATFORMS.map((p) => {
      const accounts = this.accounts.filter((a) => a.platform === p.id)
      const current = accounts.find((a) => a.current) ?? null
      return {
        id: p.id,
        name: p.name,
        primaryLogin: p.primaryLogin,
        loginUrl: p.loginUrl,
        requiredCookies: p.requiredCookies,
        sections: p.sections,
        connected: current !== null,
        current,
        accounts,
        health: current ? (this.health.get(p.id) ?? 'unknown') : 'unknown',
        loginInProgress: this.logins.has(p.id),
      }
    })
  }

  /** 在线校验当前账号是否仍有效。风控 / 网络错误不判为失效，避免误把用户「登出」。 */
  async checkHealth(platformId: string): Promise<Health> {
    this.spec(platformId)
    let health: Health
    try {
      const { data } = await this.catbus.run<AuthStatus>([platformId, 'auth', 'status'])
      health = data.logged_in ? 'ok' : 'expired'
    } catch (e) {
      const code = e instanceof CatbusCallError ? e.code : 'ERROR'
      health = code === 'AUTH_EXPIRED' || code === 'AUTH_REQUIRED' ? 'expired' : code === 'RISK_CONTROL' ? 'risk' : 'unknown'
      if (health === 'unknown') this.log.warn('health check failed', { platform: platformId, code })
    }
    this.health.set(platformId, health)
    this.emit('changed')
    return health
  }

  async loginQrcode(platformId: string, opts: LoginOptions = {}): Promise<Account> {
    const spec = this.spec(platformId)
    if (spec.primaryLogin !== 'qrcode') throw new CatbusCallError('UNSUPPORTED', `${spec.name} 不支持扫码登录`, { hint: '使用网页登录' })
    const argv = [platformId, 'auth', 'login', '--method', 'qrcode', ...this.accountArgs(opts.account)]
    return this.withLogin(platformId, opts.signal, async (signal) => {
      const pending: Promise<void>[] = []
      const onStderrLine = (line: string) => {
        if (!line.startsWith('[catbus]')) return // 终端字符画二维码等非提示行
        const qr = QR_LINE.exec(line)
        if (qr) {
          pending.push(
            readFile(qr[1]!)
              .then((buf) => opts.onEvent?.({ type: 'qrcode', platform: platformId, png: buf.toString('base64') }))
              .catch((err) => this.log.error('read qrcode failed', { platform: platformId, err: (err as Error).message })),
          )
          return
        }
        opts.onEvent?.({ type: 'progress', platform: platformId, message: line.replace(/^\[catbus\]\s*/, '') })
      }
      try {
        const { data } = await this.catbus.run<Account>(argv, { timeoutMs: QR_LOGIN_TIMEOUT_MS, signal, onStderrLine })
        return data
      } finally {
        await Promise.all(pending)
      }
    })
  }

  /** 网页登录完成后由客户端提交 cookie；经 stdin 传给 catbus，由 catbus 在线校验后才保存。 */
  async loginCookie(platformId: string, cookies: BrowserCookie[] | string, opts: Omit<LoginOptions, 'onEvent'> = {}): Promise<Account> {
    const spec = this.spec(platformId)
    const payload = typeof cookies === 'string' ? cookies : JSON.stringify(cookies)
    if (!payload.trim() || (Array.isArray(cookies) && cookies.length === 0)) throw new CatbusCallError('USAGE', '没有可提交的 cookie')
    const argv = [platformId, 'auth', 'login', ...(spec.catbusDefault === 'cookie' ? [] : ['--method', 'cookie']), '--cookie', '-', ...this.accountArgs(opts.account)]
    return this.withLogin(platformId, opts.signal, async (signal) => (await this.catbus.run<Account>(argv, { stdin: payload, signal, timeoutMs: 60_000 })).data)
  }

  cancelLogin(platformId: string): boolean {
    const ac = this.logins.get(platformId)
    ac?.abort()
    return ac !== undefined
  }

  async logout(platformId: string, account?: string): Promise<void> {
    this.spec(platformId)
    const target = account ?? this.accounts.find((a) => a.platform === platformId && a.current)?.account
    if (!target) throw new CatbusCallError('USAGE', '该平台没有已登录的账号')
    await this.catbus.run([platformId, 'auth', 'logout', ...this.accountArgs(target)])
    this.health.delete(platformId)
    this.log.info('logged out', { platform: platformId, account: target })
    await this.refresh()
    this.emit('changed')
  }

  async use(platformId: string, account: string): Promise<void> {
    this.spec(platformId)
    await this.catbus.run([platformId, 'auth', 'use', this.checkAccount(account)])
    this.health.delete(platformId)
    await this.refresh()
    this.emit('changed')
  }

  private async withLogin(platformId: string, outer: AbortSignal | undefined, fn: (signal: AbortSignal) => Promise<Account>): Promise<Account> {
    if (this.logins.has(platformId)) throw new CatbusCallError('USAGE', '该平台已有进行中的登录', { hint: '先取消当前登录' })
    const ac = new AbortController()
    const onOuterAbort = () => ac.abort()
    outer?.addEventListener('abort', onOuterAbort, { once: true })
    this.logins.set(platformId, ac)
    this.emit('changed')
    try {
      const account = await fn(ac.signal)
      this.health.set(platformId, 'ok')
      this.log.info('logged in', { platform: platformId, account: account.account, method: account.method })
      await this.refresh()
      return account
    } catch (e) {
      this.log.warn('login failed', { platform: platformId, code: (e as CatbusCallError).code, message: (e as Error).message })
      throw e
    } finally {
      outer?.removeEventListener('abort', onOuterAbort)
      this.logins.delete(platformId)
      this.emit('changed')
    }
  }

  private spec(platformId: string): PlatformSpec {
    const spec = getPlatform(platformId)
    if (!spec) throw new CatbusCallError('USAGE', `未知平台：${platformId}`)
    return spec
  }

  private checkAccount(name: string): string {
    if (!ACCOUNT_NAME_RE.test(name)) throw new CatbusCallError('USAGE', `账号名不合法：${name}`, { hint: '只能用小写字母、数字、_ 和 -，以字母或数字开头，最长 32 位' })
    return name
  }

  private accountArgs(account: string | undefined): string[] {
    return account === undefined ? [] : ['-a', this.checkAccount(account)]
  }
}
