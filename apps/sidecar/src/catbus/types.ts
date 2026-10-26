/** catbus 统一信封与归一化类型（对应 vendor/catbus/docs/guide/output.md）。 */

export type CatbusErrorCode =
  | 'ERROR'
  | 'USAGE'
  | 'UNSUPPORTED'
  | 'CONFIRM_REQUIRED'
  | 'AUTH_REQUIRED'
  | 'AUTH_EXPIRED'
  | 'NOT_IMPLEMENTED'
  | 'RISK_CONTROL'
  | 'NETWORK'
  | 'UPSTREAM'

/** catland 在 runner 层补充的错误：子进程本身的失败。 */
export type RunnerErrorCode = 'TIMEOUT' | 'ABORTED' | 'SPAWN_FAILED' | 'BAD_OUTPUT'

export type CallErrorCode = CatbusErrorCode | RunnerErrorCode

export interface Page {
  cursor: string | null
  has_more: boolean
}

export interface EnvelopeError {
  code: CatbusErrorCode
  message: string
  hint: string | null
  detail: unknown
}

export interface Envelope<T = unknown> {
  ok: boolean
  platform: string | null
  endpoint: string | null
  resource: string | null
  action: string | null
  account: string | null
  data: T
  page: Page | null
  error: EnvelopeError | null
}

export interface UserRef {
  id: string
  name: string | null
  url: string | null
}

export interface Media {
  id: string | null
  type: string
  url: string
  width: number | null
  height: number | null
  duration: number | null
}

export interface Item {
  id: string
  kind: string
  url: string
  title: string | null
  text: string | null
  author: UserRef | null
  created_at: string | null
  cover: string | null
  media: Media[]
  stats: { views: number | null; likes: number | null; comments: number | null; collects: number | null; shares: number | null }
  price: { amount: number; currency: string } | null
  status: string | null
}

export interface Comment {
  id: string
  item_id: string
  parent_id: string | null
  author: UserRef | null
  text: string
  created_at: string | null
  stats: { likes: number | null; replies: number | null }
}

export interface Account {
  platform: string
  endpoint: string
  account: string
  current: boolean
  user: UserRef | null
  method: string | null
  updated_at: string | null
}

export interface AuthStatus {
  logged_in: boolean
  user: UserRef | null
  method: string | null
  expires_at: string | null
}
