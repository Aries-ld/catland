/** 各平台的推荐流适配：取列表、补详情、解析出可直接播放的媒体与所需请求头。 */
import type { CatbusClient } from '../accounts/service.ts'
import { CatbusCallError } from '../catbus/runner.ts'
import type { Item, Media } from '../catbus/types.ts'
import type { Logger } from '../log.ts'
import { cardKey, type FeedCard, type FeedPage, type Headers, type ImageSource, type PlatformAdapter, type SearchHit, type VideoSource } from './types.ts'

export const DESKTOP_UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36'

/** 媒体 CDN 的防盗链要求（实测）：带错 Referer 也会 403，所以按平台给，不统一带。 */
export const MEDIA_HEADERS: Record<string, Headers> = {
  bilibili: { Referer: 'https://www.bilibili.com/', 'User-Agent': DESKTOP_UA },
  xhs: {},
  x: {},
  douyin: { Referer: 'https://www.douyin.com/', 'User-Agent': DESKTOP_UA },
  kuaishou: { Referer: 'https://www.kuaishou.com/', 'User-Agent': DESKTOP_UA },
  tiktok: { Referer: 'https://www.tiktok.com/', 'User-Agent': DESKTOP_UA },
  weibo: { Referer: 'https://weibo.com/', 'User-Agent': DESKTOP_UA },
}

const DEFAULT_TTL_MS = 20 * 60_000
const FEED_PAGE = 10
const SEARCH_PAGE = 10

export interface AdapterDeps {
  catbus: CatbusClient
  logger: Logger
  fetch?: typeof globalThis.fetch
  now?: () => number
}

/** 通用适配：列表自带媒体就直接用，否则 item get 补详情，再不行 item media。 */
export class CatbusAdapter implements PlatformAdapter {
  readonly platform: string
  protected readonly catbus: CatbusClient
  protected readonly log: Logger
  protected readonly now: () => number
  protected readonly headers: Headers

  constructor(platform: string, deps: AdapterDeps) {
    this.platform = platform
    this.catbus = deps.catbus
    this.log = deps.logger.child({ mod: 'adapter', platform })
    this.now = deps.now ?? Date.now
    this.headers = MEDIA_HEADERS[platform] ?? {}
  }

  async fetchFeed(cursor: string | null, signal?: AbortSignal): Promise<FeedPage> {
    const argv = [this.platform, 'feed', 'list', '--limit', String(FEED_PAGE), ...(cursor ? ['--cursor', cursor] : [])]
    const { data, page } = await this.catbus.run<Item[]>(argv, { signal })
    return { items: data, cursor: page?.cursor ?? null, hasMore: page?.has_more ?? false }
  }

  /** 关键词搜索（综合排序）。关键词放在 `--` 之后，以 `-` 开头也不会被当成选项。 */
  async search(query: string, cursor: string | null, signal?: AbortSignal): Promise<FeedPage> {
    const argv = [this.platform, 'item', 'search', '--limit', String(SEARCH_PAGE), ...(cursor ? ['--cursor', cursor] : []), '--', query]
    const { data, page } = await this.catbus.run<Item[]>(argv, { signal })
    return { items: data, cursor: page?.cursor ?? null, hasMore: page?.has_more ?? false }
  }

  async resolve(item: Item, signal?: AbortSignal, fresh = false): Promise<FeedCard | null> {
    if (!isVisual(item)) return null
    let detail = item
    if (fresh || !hasPlayable(detail)) detail = await this.getDetail(item, signal)
    if (!hasPlayable(detail)) {
      const { data } = await this.catbus.run<Media[]>([this.platform, 'item', 'media', item.url], { signal })
      detail = { ...detail, media: data }
    }
    return this.toCard(detail)
  }

  protected async getDetail(item: Item, signal?: AbortSignal): Promise<Item> {
    const { data } = await this.catbus.run<Item>([this.platform, 'item', 'get', item.url], { signal })
    return mergeItem(item, data)
  }

  protected toCard(item: Item, override: { video?: VideoSource | null; ttlMs?: number } = {}): FeedCard | null {
    const video = override.video !== undefined ? override.video : pickVideo(item.media, this.headers)
    const images = item.media.filter((m) => m.type === 'image' && isHttpUrl(m.url)).map((m) => this.image(m.url, m.width, m.height))
    if (!video && images.length === 0) return null
    const now = this.now()
    return {
      key: cardKey(this.platform, item.id),
      platform: this.platform,
      id: item.id,
      url: item.url,
      kind: video ? 'video' : 'image',
      title: item.title,
      text: item.text,
      author: item.author,
      createdAt: item.created_at,
      cover: item.cover ? this.image(item.cover, video?.width ?? null, video?.height ?? null) : (images[0] ?? null),
      stats: item.stats,
      video,
      images,
      resolvedAt: now,
      expiresAt: now + (override.ttlMs ?? DEFAULT_TTL_MS),
    }
  }

  private image(url: string, width: number | null, height: number | null): ImageSource {
    return { url, headers: this.headers, width, height }
  }
}

/** 小红书：列表只有封面，用 item get 一次拿全文、图集和视频。 */
export class XhsAdapter extends CatbusAdapter {
  constructor(deps: AdapterDeps) {
    super('xhs', deps)
  }

  override async resolve(item: Item, signal?: AbortSignal): Promise<FeedCard | null> {
    if (!isVisual(item)) return null
    return this.toCard(await this.getDetail(item, signal))
  }
}

interface BiliDim {
  width: number
  height: number
  rotate: number
}

/**
 * B 站：catbus 的 item media 给的是分离的 DASH 音视频轨，AVPlayer 冷启动 ~9s 且时长识别错误；
 * 改走网页 H5 播放器的公开 MP4 接口（音视频合一，720P，不带登录态），实测首帧 ~1.7s。
 * 匿名请求不带设备 cookie 会被 412 拦截，所以先向 finger/spi 领一个访客 buvid（与账号无关）。
 */
export class BilibiliAdapter extends CatbusAdapter {
  private readonly fetch: typeof globalThis.fetch
  private buvid: Promise<string> | null = null

  constructor(deps: AdapterDeps) {
    super('bilibili', deps)
    this.fetch = deps.fetch ?? globalThis.fetch
  }

  override async resolve(item: Item, signal?: AbortSignal): Promise<FeedCard | null> {
    if (item.kind !== 'video') return null
    return this.toCard(item, { video: await this.html5Mp4(item.id, signal), ttlMs: 60 * 60_000 })
  }

  private async html5Mp4(bvid: string, signal?: AbortSignal): Promise<VideoSource> {
    const view = await this.api<{ cid: number; duration: number; dimension?: BiliDim; pages?: Array<{ cid: number; duration: number; dimension?: BiliDim }> }>(
      `https://api.bilibili.com/x/web-interface/view?bvid=${encodeURIComponent(bvid)}`,
      signal,
    )
    // 多 P 稿件只播第 1P；view.duration 是全部分 P 的总时长。
    const page = view.pages?.find((p) => p.cid === view.cid) ?? view.pages?.[0]
    const play = await this.api<{ durl?: Array<{ url: string; length: number }> }>(
      `https://api.bilibili.com/x/player/playurl?bvid=${encodeURIComponent(bvid)}&cid=${view.cid}&qn=64&fnval=1&platform=html5&high_quality=1`,
      signal,
    )
    const durl = play.durl?.[0]
    if (!durl?.url) throw new Error('playurl has no durl')
    const dim = page?.dimension ?? view.dimension
    const [width, height] = dim ? (dim.rotate ? [dim.height, dim.width] : [dim.width, dim.height]) : [null, null]
    return { url: durl.url, headers: this.headers, width, height, duration: page?.duration ?? Math.round(durl.length / 1000) }
  }

  private visitorCookie(signal?: AbortSignal): Promise<string> {
    this.buvid ??= this.get('https://api.bilibili.com/x/frontend/finger/spi', '', signal)
      .then(async (res) => {
        const body = (await res.json()) as { data?: { b_3?: string; b_4?: string } }
        if (!body.data?.b_3) throw new Error('finger/spi returned no buvid')
        return `buvid3=${body.data.b_3}; buvid4=${body.data.b_4 ?? ''}`
      })
      .catch((err) => {
        this.buvid = null
        throw err
      })
    return this.buvid
  }

  private async api<T>(url: string, signal?: AbortSignal): Promise<T> {
    let res = await this.get(url, await this.visitorCookie(signal), signal)
    if (res.status === 412) {
      await res.body?.cancel()
      this.buvid = null
      res = await this.get(url, await this.visitorCookie(signal), signal)
      if (res.status === 412) throw new CatbusCallError('RISK_CONTROL', 'bilibili HTTP 412', { detail: { kind: 'rate_limit' } })
    }
    if (!res.ok) throw new Error(`HTTP ${res.status}`)
    const body = (await res.json()) as { code: number; message?: string; data?: T }
    if (body.code !== 0 || !body.data) throw new Error(`bilibili code ${body.code}: ${body.message ?? ''}`)
    return body.data
  }

  private get(url: string, cookie: string, signal?: AbortSignal): Promise<Response> {
    const timeout = AbortSignal.timeout(8_000)
    const headers = cookie ? { ...this.headers, Cookie: cookie } : this.headers
    return this.fetch(url, { headers, signal: signal ? AbortSignal.any([signal, timeout]) : timeout })
  }
}

export function createAdapter(platform: string, deps: AdapterDeps): PlatformAdapter {
  if (platform === 'xhs') return new XhsAdapter(deps)
  if (platform === 'bilibili') return new BilibiliAdapter(deps)
  return new CatbusAdapter(platform, deps)
}

/** 搜索结果 → 封面网格条目；纯文字等没有画面的内容返回 null。 */
export function toSearchHit(platform: string, item: Item): SearchHit | null {
  if (!isVisual(item)) return null
  const headers = MEDIA_HEADERS[platform] ?? {}
  const video = item.media.find((m) => m.type === 'video')
  const firstImage = item.media.find((m) => m.type === 'image' && isHttpUrl(m.url))
  const coverUrl = item.cover && isHttpUrl(item.cover) ? item.cover : (firstImage?.url ?? null)
  return {
    key: cardKey(platform, item.id),
    platform,
    id: item.id,
    url: item.url,
    kind: item.kind === 'video' || video ? 'video' : 'image',
    title: item.title ?? item.text,
    author: item.author,
    cover: coverUrl ? { url: coverUrl, headers, width: video?.width ?? firstImage?.width ?? null, height: video?.height ?? firstImage?.height ?? null } : null,
    stats: item.stats,
    duration: video?.duration != null ? Math.round(video.duration) : null,
  }
}

/** 刷刷流只放有画面的内容；纯文字推文等先跳过。 */
function isVisual(item: Item): boolean {
  return item.kind !== 'text' && item.kind !== 'article'
}

/** 有可直接播放 / 显示的媒体。抖音推荐流里的 media.url 是内部 uri（不是 http 地址），不算，需要再 item get 补全。 */
function hasPlayable(item: Item): boolean {
  return item.media.some((m) => (m.type === 'video' || m.type === 'image') && isHttpUrl(m.url))
}

function isHttpUrl(url: string): boolean {
  return /^https?:\/\//i.test(url)
}

function pickVideo(media: Media[], headers: Headers): VideoSource | null {
  const videos = media.filter((m) => m.type === 'video' && isHttpUrl(m.url))
  if (videos.length === 0) return null
  const audio = media.find((m) => m.type === 'audio')
  if (audio) return null // 分离音视频轨 AVPlayer 无法流畅播放，丢弃
  const v = videos[0]!
  return { url: v.url, headers, width: v.width, height: v.height, duration: v.duration, ...(isHls(v.url) ? { hls: true } : {}) }
}

/** 快手的实时转封装流（vod-rt-remux/hls-ts/…/xxx.mp4）是 HLS 播放列表，地址却以 .mp4 结尾。 */
export function isHls(url: string): boolean {
  return /\.m3u8(\?|$)/i.test(url) || /\/hls-ts\//i.test(url) || /vod-rt-remux/i.test(url)
}

/** 详情覆盖列表字段，但列表里有、详情里为空的值保留。 */
function mergeItem(list: Item, detail: Item): Item {
  const pick = <T>(a: T | null, b: T | null) => a ?? b
  return {
    ...list,
    ...detail,
    title: pick(detail.title, list.title),
    text: pick(detail.text, list.text),
    cover: pick(detail.cover, list.cover),
    author: pick(detail.author, list.author),
    created_at: pick(detail.created_at, list.created_at),
    stats: Object.fromEntries(Object.entries(detail.stats).map(([k, v]) => [k, v ?? list.stats[k as keyof Item['stats']]])) as Item['stats'],
  }
}
