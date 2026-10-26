import { describe, expect, it } from 'vitest'
import { Semaphore } from '../src/util/semaphore.ts'

describe('Semaphore', () => {
  it('同时运行数不超过上限，即便有新调用在释放间隙进入', async () => {
    const sem = new Semaphore(2)
    let active = 0
    let peak = 0
    const task = () =>
      sem.use(async () => {
        peak = Math.max(peak, ++active)
        await new Promise((r) => setTimeout(r, 5))
        active--
      })
    const first = Array.from({ length: 5 }, task)
    await new Promise((r) => setTimeout(r, 6))
    await Promise.all([...first, ...Array.from({ length: 5 }, task)])
    expect(peak).toBe(2)
  })

  it('fn 抛错也会释放名额', async () => {
    const sem = new Semaphore(1)
    await expect(sem.use(async () => { throw new Error('boom') })).rejects.toThrow('boom')
    await expect(sem.use(async () => 1)).resolves.toBe(1)
  })

  it('拒绝非法上限', () => {
    expect(() => new Semaphore(0)).toThrow(RangeError)
  })
})
