import { describe, expect, it } from 'vitest'
import { createMemoryLogger } from '../src/log.ts'
import { classify, WeatherService } from '../src/weather/weather.ts'

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } })

function fakeNea(forecast = 'Thundery Showers', opts: { fail?: boolean } = {}) {
  const calls: string[] = []
  const fetch = (async (url: string) => {
    calls.push(url)
    if (opts.fail) throw new Error('offline')
    if (url.includes('two-hr-forecast')) {
      return json({ code: 0, data: { items: [{ valid_period: { end: '2026-10-26T17:30:00+08:00' }, forecasts: [{ area: 'Ang Mo Kio', forecast: 'Cloudy' }, { area: 'City', forecast }] }] } })
    }
    return json({ code: 0, data: { readings: [{ data: [{ value: 30 }, { value: 31 }, { value: 31.5 }] }] } })
  }) as typeof globalThis.fetch
  return { fetch, calls }
}

describe('classify', () => {
  it.each([
    ['Fair (Day)', 'clear'], ['Fair & Warm', 'clear'], ['Partly Cloudy (Night)', 'partly'], ['Cloudy', 'cloudy'],
    ['Light Showers', 'rain'], ['Heavy Rain', 'rain'], ['Thundery Showers', 'thunder'], ['Heavy Thundery Showers with Gusty Winds', 'thunder'],
    ['Hazy', 'haze'], ['Mist', 'haze'], ['Windy', 'windy'], ['Something New', 'cloudy'],
  ])('%s → %s', (text, c) => expect(classify(text)).toBe(c))
})

describe('WeatherService', () => {
  it('取指定区域预报与全岛平均气温，30 分钟内用缓存，不带任何用户参数', async () => {
    let t = 0
    const nea = fakeNea()
    const w = new WeatherService({ logger: createMemoryLogger(), fetch: nea.fetch, now: () => t })
    expect(await w.get()).toMatchObject({ condition: 'thunder', text: 'Thundery Showers', area: 'City', temperature: 30.8, source: 'NEA' })
    t += 10 * 60_000
    await w.get()
    expect(nea.calls).toHaveLength(2)
    t += 25 * 60_000
    await w.get()
    expect(nea.calls).toHaveLength(4)
    expect(nea.calls.every((u) => !u.includes('?'))).toBe(true)
  })

  it('并发请求合并成一次', async () => {
    const nea = fakeNea('Fair (Day)')
    const w = new WeatherService({ logger: createMemoryLogger(), fetch: nea.fetch })
    await Promise.all([w.get(), w.get(), w.get()])
    expect(nea.calls).toHaveLength(2)
  })

  it('断网时返回上次结果；从未成功过返回 null', async () => {
    let t = 0
    let fail = false
    const ok = fakeNea('Cloudy')
    const fetch = (async (u: string) => (fail ? Promise.reject(new Error('offline')) : ok.fetch(u))) as typeof globalThis.fetch
    const w = new WeatherService({ logger: createMemoryLogger(), fetch, now: () => t })
    expect((await w.get())?.condition).toBe('cloudy')
    fail = true
    t += 60 * 60_000
    expect((await w.get())?.condition).toBe('cloudy')
    expect(await new WeatherService({ logger: createMemoryLogger(), fetch: fakeNea('x', { fail: true }).fetch }).get()).toBeNull()
  })
})
