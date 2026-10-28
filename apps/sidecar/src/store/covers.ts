/**
 * CoverCache：点赞 / 收藏时把封面缩略图存到本机（数据目录 covers/）。
 * 小红书、抖音、快手的封面地址带签名、过一阵就失效，存下来列表里才一直有封面；只存在本机，不上传。
 */
import { createHash } from 'node:crypto'
import { existsSync, mkdirSync, rmSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import type { Logger } from '../log.ts'

const MAX_BYTES = 3 * 1024 * 1024

export class CoverCache {
  private readonly dir: string
  private readonly fetch: typeof globalThis.fetch
  private readonly log: Logger

  constructor(opts: { dir: string; logger: Logger; fetch?: typeof globalThis.fetch }) {
    this.dir = opts.dir
    this.fetch = opts.fetch ?? globalThis.fetch
    this.log = opts.logger.child({ mod: 'covers' })
  }

  path(key: string): string {
    return join(this.dir, `${createHash('sha1').update(key).digest('hex')}.img`)
  }

  /** 已缓存时返回 file:// 地址，否则 null。 */
  localUrl(key: string): string | null {
    const p = this.path(key)
    return existsSync(p) ? `file://${p}` : null
  }

  /** 下载封面存到本机；失败（地址已失效等）返回 false，不抛错。 */
  async save(key: string, url: string | null | undefined, headers: Record<string, string> = {}): Promise<boolean> {
    if (!url || !/^https?:\/\//i.test(url)) return false
    try {
      const res = await this.fetch(url, { headers, signal: AbortSignal.timeout(8_000) })
      if (!res.ok) {
        await res.body?.cancel()
        this.log.info('cover not saved', { key, status: res.status })
        return false
      }
      const buf = Buffer.from(await res.arrayBuffer())
      if (buf.length === 0 || buf.length > MAX_BYTES) return false
      mkdirSync(this.dir, { recursive: true })
      writeFileSync(this.path(key), buf)
      return true
    } catch (err) {
      this.log.info('cover not saved', { key, message: (err as Error).message })
      return false
    }
  }

  remove(key: string): void {
    rmSync(this.path(key), { force: true })
  }
}
