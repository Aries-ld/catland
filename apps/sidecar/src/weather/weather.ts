/**
 * 天气：新加坡 NEA 官方开放数据（data.gov.sg）。只发匿名 GET，不带任何用户信息；
 * 30 分钟缓存，失败时返回上次结果。用于猫咪之家窗外的天气联动，设置里可关闭。
 */
import type { Logger } from '../log.ts'

export type Condition = 'clear' | 'partly' | 'cloudy' | 'haze' | 'rain' | 'thunder' | 'windy'

export interface Weather {
  condition: Condition
  /** NEA 原始预报文本，如 "Thundery Showers"。 */
  text: string
  area: string
  temperature: number | null
  /** 预报的有效时段结束时间。 */
  validUntil: string | null
  fetchedAt: string
  source: 'NEA'
}

const FORECAST = 'https://api-open.data.gov.sg/v2/real-time/api/two-hr-forecast'
const TEMPERATURE = 'https://api-open.data.gov.sg/v2/real-time/api/air-temperature'

/** NEA 两小时预报文本 → 场景天气。未知文本按多云处理。 */
export function classify(text: string): Condition {
  const t = text.toLowerCase()
  if (t.includes('thunder')) return 'thunder'
  if (t.includes('rain') || t.includes('shower') || t.includes('drizzle')) return 'rain'
  if (t.includes('haz') || t.includes('mist') || t.includes('fog')) return 'haze'
  if (t.includes('wind')) return 'windy'
  if (t.includes('partly')) return 'partly'
  if (t.includes('fair') || t.includes('sunny') || t.includes('clear')) return 'clear'
  return 'cloudy'
}

export interface WeatherOptions {
  logger: Logger
  area?: string
  ttlMs?: number
  fetch?: typeof globalThis.fetch
  now?: () => number
}

export class WeatherService {
  private readonly log: Logger
  private readonly area: string
  private readonly ttlMs: number
  private readonly fetch: typeof globalThis.fetch
  private readonly now: () => number
  private cached: { at: number; value: Weather } | null = null
  private inflight: Promise<Weather | null> | null = null

  constructor(opts: WeatherOptions) {
    this.log = opts.logger.child({ mod: 'weather' })
    this.area = opts.area ?? 'City'
    this.ttlMs = opts.ttlMs ?? 30 * 60_000
    this.fetch = opts.fetch ?? globalThis.fetch
    this.now = opts.now ?? Date.now
  }

  async get(): Promise<Weather | null> {
    if (this.cached && this.now() - this.cached.at < this.ttlMs) return this.cached.value
    this.inflight ??= this.load().finally(() => (this.inflight = null))
    return this.inflight
  }

  private async load(): Promise<Weather | null> {
    try {
      const forecast = await this.json<{ data: { items: Array<{ valid_period?: { end?: string }; forecasts: Array<{ area: string; forecast: string }> }> } }>(FORECAST)
      const item = forecast.data.items[0]
      if (!item) throw new Error('no forecast items')
      const mine = item.forecasts.find((f) => f.area === this.area) ?? mostCommon(item.forecasts)
      if (!mine) throw new Error('empty forecasts')
      const temperature = await this.temperature().catch(() => null)
      const value: Weather = {
        condition: classify(mine.forecast), text: mine.forecast, area: mine.area, temperature,
        validUntil: item.valid_period?.end ?? null, fetchedAt: new Date(this.now()).toISOString(), source: 'NEA',
      }
      this.cached = { at: this.now(), value }
      this.log.info('weather', { condition: value.condition, text: value.text, temperature })
      return value
    } catch (err) {
      this.log.warn('weather fetch failed', { err: (err as Error).message })
      return this.cached?.value ?? null
    }
  }

  /** 全岛气象站读数的平均值，保留一位小数。 */
  private async temperature(): Promise<number | null> {
    const t = await this.json<{ data: { readings: Array<{ data: Array<{ value: number }> }> } }>(TEMPERATURE)
    const values = t.data.readings[0]?.data.map((d) => d.value).filter((v) => Number.isFinite(v)) ?? []
    return values.length ? Math.round((values.reduce((a, b) => a + b, 0) / values.length) * 10) / 10 : null
  }

  private async json<T>(url: string): Promise<T> {
    const res = await this.fetch(url, { signal: AbortSignal.timeout(8_000), headers: { Accept: 'application/json' } })
    if (!res.ok) throw new Error(`HTTP ${res.status}`)
    return (await res.json()) as T
  }
}

function mostCommon(list: Array<{ area: string; forecast: string }>) {
  const count = new Map<string, number>()
  for (const f of list) count.set(f.forecast, (count.get(f.forecast) ?? 0) + 1)
  const top = [...count.entries()].sort((a, b) => b[1] - a[1])[0]
  return top ? { area: 'Singapore', forecast: top[0] } : undefined
}
