// 天空模块：渐变天空、太阳（按所在地实时位置）、星星、月亮（真实月相）、云、飞鸟 / 夜航飞机。
import SwiftUI

struct SkyLayer: SceneLayer {
    let id = "sky"
    let stage = SceneStage.sky
    func draw(_ c: SceneCanvas) {
        let s = c.sky
        let horizon = c.cityBase
        for y in 0..<horizon {
            let k = Double(y) / Double(max(1, horizon - 1))
            c.fill(0, y, c.cols, 1, s.top.mix(s.horizon, k * k).color)
        }
    }
}

/// 月相：0 = 新月，0.5 = 满月（以 2000-01-06 18:14 UTC 的新月为基准，朔望月 29.530588 天）。
enum MoonPhase {
    static func of(_ date: Date) -> Double {
        let ref = Date(timeIntervalSince1970: 947_182_440)
        let days = date.timeIntervalSince(ref) / 86_400
        let p = (days / 29.530588).truncatingRemainder(dividingBy: 1)
        return p < 0 ? p + 1 : p
    }

    static func isFull(_ date: Date) -> Bool { abs(of(date) - 0.5) < 0.035 }
}

struct CelestialLayer: SceneLayer {
    let id = "celestial"
    let stage = SceneStage.celestial
    func draw(_ c: SceneCanvas) {
        let horizon = c.cityBase
        let dark = c.dark, overcast = c.overcast
        if dark < 0.85, overcast < 0.85 {
            // 太阳：东升（左）西落（右），高度映射到天空纵向；晨昏变橙。
            let sun = c.sun
            let x = Int(Double(c.cols) * min(1, max(0, (sun.azimuth - 60) / 240)))
            let y = horizon - 3 - Int(Double(max(1, horizon - c.skyTop - 6)) * min(1, max(0, sun.altitude / 50)))
            let core = c.rgb(0xFFF1B8).mix(c.rgb(0xFF9A55), c.dusk).color.opacity(1 - overcast * 0.7)
            c.fill(x - 1, y - 2, 3, 5, core); c.fill(x - 2, y - 1, 5, 3, core)
            c.fill(x - 3, y - 3, 7, 7, core.opacity(0.18))
        }
        guard dark > 0.55 else { return }
        let a = (dark - 0.55) / 0.45 * (1 - overcast)
        var rng = SeededRandom(seed: 7)
        for _ in 0..<40 {
            let x = Int(rng.next() % UInt64(max(1, c.cols))), y = c.skyTop + Int(rng.next() % UInt64(max(1, horizon - c.skyTop - 8)))
            let tw = 0.5 + 0.5 * sin(c.t * (0.8 + Double(rng.next() % 7) * 0.3) + Double(x))
            c.fill(x, y, 1, 1, Color.white.opacity(a * tw))
        }
        // 月亮：夜里从左慢慢移到右，形状按真实月相（新月不画）。
        let prog = min(1, max(0, ((c.hour - 19 + 24).truncatingRemainder(dividingBy: 24)) / 11))
        if c.holidays.contains(where: { $0.id == "midAutumn" }) {
            BigMoon.draw(c, progress: 1, gold: true) // 中秋整晚挂着金色大月亮
            return
        }
        // 「满月」事件进行中时由事件画升起的大月亮，这里不再画小月亮。
        let region = RestDays.region(for: c.env.location)
        if EventScheduler.active(now: c.env.date, region: region, latitude: c.env.location.latitude)?.eventID == "fullMoon" { return }
        let mx = Int(Double(c.cols - 8) * prog) + 3, my = c.skyTop + 3
        drawMoon(c, x: mx, y: my, phase: MoonPhase.of(c.env.date), alpha: min(1, a + 0.3))
    }

    /// 5×5 像素月亮：先画满月，再用同形状的天空色「影子」按月相错开遮住一部分。
    /// 上弦（phase < 0.5）亮在右，影子往左错开；下弦亮在左，影子往右错开；满月时影子完全移出。
    func drawMoon(_ c: SceneCanvas, x: Int, y: Int, phase: Double, alpha: Double) {
        let lit = 1 - abs(phase - 0.5) * 2 // 0 新月 … 1 满月
        guard lit > 0.08 else { return }
        func disc(_ cx: Int, _ col: Color) { c.fill(cx - 1, y - 2, 3, 5, col); c.fill(cx - 2, y - 1, 5, 3, col) }
        disc(x, c.rgb(0xF4F1DE).color.opacity(alpha))
        let offset = Int((lit * 5).rounded())
        if offset < 5 { disc(phase < 0.5 ? x - offset : x + offset, c.sky.top.color.opacity(alpha)) }
    }
}

struct CloudsLayer: SceneLayer {
    let id = "clouds"
    let stage = SceneStage.clouds
    func draw(_ c: SceneCanvas) {
        let count = c.weather.clouds(c.intensity)
        let tone = c.rgb(0xFFFFFF).mix(c.rgb(0x5C6475), c.overcast).mix(c.rgb(0x1E2742), c.dark * 0.85).mix(c.rgb(0xF6A27C), c.dusk * 0.4)
        var rng = SeededRandom(seed: 42)
        let speed = c.cond == "windy" ? 3.0 : 0.6
        for i in 0..<count {
            let w = 10 + Int(rng.next() % 12), y = c.skyTop + 1 + Int(rng.next() % UInt64(max(1, (c.floorTop - c.skyTop) / 3)))
            let span = Double(c.cols + w * 2)
            let x = Int((Double(rng.next() % 500) + c.t * speed * (0.6 + Double(i % 3) * 0.35)).truncatingRemainder(dividingBy: span)) - w
            let col = tone.color.opacity(0.55 + c.overcast * 0.4)
            c.fill(x, y + 2, w, 2, col); c.fill(x + w / 5, y + 1, w / 2, 1, col); c.fill(x + w / 3, y, w / 3, 1, col); c.fill(x + w * 3 / 5, y + 1, w / 3, 1, col)
        }
    }
}

