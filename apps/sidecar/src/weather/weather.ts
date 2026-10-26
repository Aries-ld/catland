/**
 * 天气：按 Mac 系统定位给出的经纬度取当地天气。
 *  - 新加坡境内：NEA 官方开放数据（data.gov.sg），匿名 GET。
 *  - 其他地区：Open-Meteo（无需 key）。坐标先四舍五入到 0.1°（约 10km）再发送，不暴露精确位置。
 * 只发天气请求，不带任何用户信息；按坐标缓存 30 分钟，失败时返回上次结果。设置里可关闭。
 */
import type { Logger } from '../log.ts'

export type Condition = 'clear' | 'partly' | 'cloudy' | 'haze' | 'rain' | 'thunder' | 'windy' | 'snow'

export interface Weather {
  condition: Condition
  /** 数据源的原始描述，如 "Thundery Showers" / "WMO 61"。 */
  text: string
  area: string
  temperature: number | null
  validUntil: string | null
  fetchedAt: string
  source: 'NEA' | 'Open-Meteo'
}

export interface Coordinates {
  latitude: number
  longitude: number
}

export const SINGAPORE: Coordinates = { latitude: 1.2903, longitude: 103.852 }

const NEA_FORECAST = 'https://api-open.data.gov.sg/v2/real-time/api/two-hr-forecast'
const NEA_TEMPERATURE = 'https://api-open.data.gov.sg/v2/real-time/api/air-temperature'
const OPEN_METEO = 'https://api.open-meteo.com/v1/forecast'

export function inSingapore(c: Coordinates): boolean {
  return c.latitude > 1.15 && c.latitude < 1.48 && c.longitude > 103.6 && c.longitude < 104.1
}

/** NEA 两小时预报文本 → 场景天气。未知文本按多云处理。 */
export function classify(text: string): Condition {
  const t = text.toLowerCase()
  if (t.includes('thunder')) return 'thunder'
  if (t.includes('snow')) return 'snow'
  if (t.includes('rain') || t.includes('shower') || t.includes('drizzle')) return 'rain'
  if (t.includes('haz') || t.includes('mist') || t.includes('fog')) return 'haze'
  if (t.includes('wind')) return 'windy'
  if (t.includes('partly')) return 'partly'
  if (t.includes('fair') || t.includes('sunny') || t.includes('clear')) return 'clear'
  return 'cloudy'
}

/** WMO 天气代码（Open-Meteo）→ 场景天气；风速 ≥ 30km/h 的晴 / 少云算「有风」。 */
export function classifyWmo(code: number, windKmh = 0): Condition {
  let c: Condition
  if (code <= 1) c = 'clear'
  else if (code === 2) c = 'partly'
  else if (code === 3) c = 'cloudy'
  else if (code === 45 || code === 48) c = 'haze'
  else if ((code >= 71 && code <= 77) || code === 85 || code === 86) c = 'snow'
  else if (code >= 95) c = 'thunder'
  else if (code >= 51 && code <= 82) c = 'rain'
  else c = 'cloudy'
  return (c === 'clear' || c === 'partly') && windKmh >= 30 ? 'windy' : c
}

/** 粗化坐标：保留一位小数。 */
export function coarse(c: Coordinates): Coordinates {
  return { latitude: Math.round(c.latitude * 10) / 10, longitude: Math.round(c.longitude * 10) / 10 }
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
  private readonly cache = new Map<string, { at: number; value: Weather }>()
  private readonly inflight = new Map<string, Promise<Weather | null>>()

  constructor(opts: WeatherOptions) {
    this.log = opts.logger.child({ mod: 'weather' })
    this.area = opts.area ?? 'City'
    this.ttlMs = opts.ttlMs ?? 30 * 60_000
    this.fetch = opts.fetch ?? globalThis.fetch
    this.now = opts.now ?? Date.now
  }

  async get(where: Coordinates = SINGAPORE): Promise<Weather | null> {
    const c = coarse(where)
    const key = `${c.latitude},${c.longitude}`
    const hit = this.cache.get(key)
    if (hit && this.now() - hit.at < this.ttlMs) return hit.value
    let p = this.inflight.get(key)
    if (!p) {
      p = this.load(c, key).finally(() => this.inflight.delete(key))
      this.inflight.set(key, p)
    }
    return p
  }

  private async load(c: Coordinates, key: string): Promise<Weather | null> {
    try {
      const value = inSingapore(c) ? await this.nea() : await this.openMeteo(c)
      this.cache.set(key, { at: this.now(), value })
      this.log.info('weather', { source: value.source, condition: value.condition, text: value.text, temperature: value.temperature, at: key })
      return value
    } catch (err) {
      this.log.warn('weather fetch failed', { err: (err as Error).message, at: key })
      return this.cache.get(key)?.value ?? null
    }
  }

  private async nea(): Promise<Weather> {
    const forecast = await this.json<{ data: { items: Array<{ valid_period?: { end?: string }; forecasts: Array<{ area: string; forecast: string }> }> } }>(NEA_FORECAST)
    const item = forecast.data.items[0]
    if (!item) throw new Error('no forecast items')
    const mine = item.forecasts.find((f) => f.area === this.area) ?? mostCommon(item.forecasts)
    if (!mine) throw new Error('empty forecasts')
    const temperature = await this.neaTemperature().catch(() => null)
    return {
      condition: classify(mine.forecast), text: mine.forecast, area: mine.area, temperature,
      validUntil: item.valid_period?.end ?? null, fetchedAt: new Date(this.now()).toISOString(), source: 'NEA',
    }
  }

  /** 全岛气象站读数的平均值，保留一位小数。 */
  private async neaTemperature(): Promise<number | null> {
    const t = await this.json<{ data: { readings: Array<{ data: Array<{ value: number }> }> } }>(NEA_TEMPERATURE)
    const values = t.data.readings[0]?.data.map((d) => d.value).filter((v) => Number.isFinite(v)) ?? []
    return values.length ? Math.round((values.reduce((a, b) => a + b, 0) / values.length) * 10) / 10 : null
  }

  private async openMeteo(c: Coordinates): Promise<Weather> {
    const url = `${OPEN_METEO}?latitude=${c.latitude}&longitude=${c.longitude}&current=temperature_2m,weather_code,wind_speed_10m&timezone=auto`
    const d = await this.json<{ current?: { temperature_2m?: number; weather_code?: number; wind_speed_10m?: number } }>(url)
    const code = d.current?.weather_code
    if (typeof code !== 'number') throw new Error('open-meteo: no current weather')
    return {
      condition: classifyWmo(code, d.current?.wind_speed_10m ?? 0), text: `WMO ${code}`, area: `${c.latitude},${c.longitude}`,
      temperature: typeof d.current?.temperature_2m === 'number' ? Math.round(d.current.temperature_2m * 10) / 10 : null,
      validUntil: null, fetchedAt: new Date(this.now()).toISOString(), source: 'Open-Meteo',
    }
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
