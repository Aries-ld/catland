/** 内容卡片：客户端直接可渲染、可播放的统一结构（媒体地址已解析、请求头已附上）。 */
import type { Item, UserRef } from '../catbus/types.ts'

export type Headers = Record<string, string>

export interface VideoSource {
  url: string
  headers: Headers
  width: number | null
  height: number | null
  duration: number | null
}

export interface ImageSource {
  url: string
  headers: Headers
  width: number | null
  height: number | null
}

export interface FeedCard {
  /** `${platform}:${id}`，全局唯一，用于去重、点赞、收藏。 */
  key: string
  platform: string
  id: string
  url: string
  kind: 'video' | 'image'
  title: string | null
  text: string | null
  author: UserRef | null
  createdAt: string | null
  cover: ImageSource | null
  stats: Item['stats']
  video: VideoSource | null
  images: ImageSource[]
  resolvedAt: number
  /** 媒体地址大致的失效时间；过期后需要 refresh 重新解析。 */
  expiresAt: number
}

export interface FeedPage {
  items: Item[]
  cursor: string | null
  hasMore: boolean
}

/** 搜索结果：只用于封面网格，不解析媒体；点开时再 search.resolve 成 FeedCard。 */
export interface SearchHit {
  key: string
  platform: string
  id: string
  url: string
  kind: 'video' | 'image'
  title: string | null
  author: UserRef | null
  cover: ImageSource | null
  stats: Item['stats']
  /** 视频时长（秒），平台没给时为 null。 */
  duration: number | null
}

/** 一个平台如何取推荐流、如何搜索、如何把列表项解析成可播放的卡片。 */
export interface PlatformAdapter {
  readonly platform: string
  fetchFeed(cursor: string | null, signal?: AbortSignal): Promise<FeedPage>
  search?(query: string, cursor: string | null, signal?: AbortSignal): Promise<FeedPage>
  /** 返回 null 表示这条内容不适合放进刷刷流（纯文字、没有可用媒体等）。 */
  resolve(item: Item, signal?: AbortSignal): Promise<FeedCard | null>
}

export const cardKey = (platform: string, id: string) => `${platform}:${id}`
