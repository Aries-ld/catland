// 天气模块：天气样式表（名称、阴沉度、云量、是否湿）+ 天气效果（按类型注册）。
// 新增天气：在 WeatherStyle.table 加一行；需要专属画面时在 WeatherEffects.all 加一个 WeatherEffect。
import SwiftUI

struct WeatherStyle {
    let name: String
    /// 是否有降水（雨、雪、冰雹等）：影响飞鸟、彩蛋、事件等是否出现。
    let wet: Bool
    let baseOvercast: Double
    let overcastPerIntensity: Double
    let baseClouds: Int
    let cloudsPerIntensity: Int

    func overcast(_ intensity: Double) -> Double { baseOvercast + overcastPerIntensity * intensity }
    func clouds(_ intensity: Double) -> Int { baseClouds + Int(Double(cloudsPerIntensity) * intensity) }

    static let table: [String: WeatherStyle] = [
        "clear": .init(name: "晴", wet: false, baseOvercast: 0, overcastPerIntensity: 0, baseClouds: 1, cloudsPerIntensity: 0),
        "partly": .init(name: "少云", wet: false, baseOvercast: 0.15, overcastPerIntensity: 0, baseClouds: 3, cloudsPerIntensity: 0),
        "cloudy": .init(name: "多云", wet: false, baseOvercast: 0.35, overcastPerIntensity: 0.4, baseClouds: 3, cloudsPerIntensity: 4),
        "fog": .init(name: "雾", wet: false, baseOvercast: 0.6, overcastPerIntensity: 0, baseClouds: 2, cloudsPerIntensity: 0),
        "haze": .init(name: "霾", wet: false, baseOvercast: 0.45, overcastPerIntensity: 0, baseClouds: 3, cloudsPerIntensity: 0),
        "drizzle": .init(name: "毛毛雨", wet: true, baseOvercast: 0.6, overcastPerIntensity: 0, baseClouds: 5, cloudsPerIntensity: 0),
        "rain": .init(name: "雨", wet: true, baseOvercast: 0.6, overcastPerIntensity: 0.3, baseClouds: 6, cloudsPerIntensity: 0),
        "thunder": .init(name: "雷雨", wet: true, baseOvercast: 0.95, overcastPerIntensity: 0, baseClouds: 7, cloudsPerIntensity: 0),
        "hail": .init(name: "冰雹", wet: true, baseOvercast: 0.95, overcastPerIntensity: 0, baseClouds: 7, cloudsPerIntensity: 0),
        "sleet": .init(name: "雨夹雪", wet: true, baseOvercast: 0.8, overcastPerIntensity: 0, baseClouds: 6, cloudsPerIntensity: 0),
        "snow": .init(name: "雪", wet: true, baseOvercast: 0.55, overcastPerIntensity: 0.25, baseClouds: 5, cloudsPerIntensity: 0),
        "windy": .init(name: "大风", wet: false, baseOvercast: 0.2, overcastPerIntensity: 0, baseClouds: 4, cloudsPerIntensity: 0),
    ]

    static func of(_ cond: String) -> WeatherStyle { table[cond] ?? table["partly"]! }
}

/// 一种天气画面效果；`conditions` 为空表示对所有天气生效。
protocol WeatherEffect {
    var conditions: Set<String> { get }
    func draw(_ c: SceneCanvas, top: Int, bottom: Int)
}

enum WeatherEffects {
    static let all: [WeatherEffect] = [HazeEffect(), FogEffect(), RainEffect(), HailEffect(), SnowEffect(), LightningEffect()]
}

struct WeatherLayer: SceneLayer {
    let id = "weather"
    let stage = SceneStage.weather
    func draw(_ c: SceneCanvas) {
        for e in WeatherEffects.all where e.conditions.isEmpty || e.conditions.contains(c.cond) {
            e.draw(c, top: c.skyTop, bottom: c.floorTop)
        }
    }
}

/// 雨雪随风倾斜的程度。
private func slant(_ c: SceneCanvas) -> Int { c.cond == "windy" ? 2 : (c.intensity > 0.8 ? 1 : 0) }

struct HazeEffect: WeatherEffect {
    let conditions: Set<String> = ["haze"]
    func draw(_ c: SceneCanvas, top: Int, bottom: Int) {
        c.fill(0, top, c.cols, bottom - top, Color(red: 0.86, green: 0.8, blue: 0.66).opacity(0.22 + 0.2 * c.intensity))
    }
}

/// 一层层缓慢飘动的雾带，越靠近水面越浓，远处楼群几乎看不见。
struct FogEffect: WeatherEffect {
    let conditions: Set<String> = ["fog"]
    func draw(_ c: SceneCanvas, top: Int, bottom: Int) {
        c.fill(0, top, c.cols, bottom - top, Color(white: 0.85).opacity(0.25 + 0.25 * c.intensity - c.dark * 0.1))
        for k in 0..<4 {
            let y = c.cityBase - 8 + k * 3
            let shift = Int((c.t * (0.8 + Double(k) * 0.3)).truncatingRemainder(dividingBy: Double(c.cols)))
            for x in stride(from: -c.cols + shift, to: c.cols, by: 18) { c.fill(x, y, 12, 2, Color(white: 0.92).opacity(0.22 + 0.06 * Double(k))) }
        }
    }
}

/// 毛毛雨 / 小中大雨 / 雷雨 / 冰雹 / 雨夹雪的雨丝；大雨时地面溅起水花。
struct RainEffect: WeatherEffect {
    let conditions: Set<String> = ["drizzle", "rain", "thunder", "hail", "sleet"]
    func draw(_ c: SceneCanvas, top: Int, bottom: Int) {
        let i = c.intensity
        c.fill(0, top, c.cols, bottom - top, Color(red: 0.5, green: 0.56, blue: 0.68).opacity(0.08 + 0.14 * i))
        var rng = SeededRandom(seed: 99)
        let drizzle = c.cond == "drizzle"
        let n = Int(Double(c.cols) * (drizzle ? 0.25 : 0.2 + 0.45 * i) * (c.cond == "sleet" ? 0.6 : 1))
        let speed = drizzle ? 0.7 : 1.2 + i * 0.8
        let s = slant(c)
        for _ in 0..<n {
            let x0 = Int(rng.next() % UInt64(c.cols + 8))
            let ph = Double(rng.next() % 1000) / 1000
            let y = top + Int((ph + c.t * speed).truncatingRemainder(dividingBy: 1) * Double(bottom - top + 2)) - 1
            let len = drizzle ? 1 : (i > 0.75 ? 3 : 2)
            c.fill(x0 - (y - top) * (1 + s) / 3, y, 1, len, Color(red: 0.82, green: 0.88, blue: 0.96).opacity(drizzle ? 0.35 : 0.5))
        }
        if i > 0.7, !drizzle {
            var srng = SeededRandom(seed: UInt64(Int(c.t * 6)))
            for _ in 0..<(c.cols / 12) {
                let x = Int(srng.next() % UInt64(max(1, c.cols)))
                c.fill(x - 1, bottom - 1, 1, 1, Color.white.opacity(0.4)); c.fill(x + 1, bottom - 1, 1, 1, Color.white.opacity(0.4))
            }
        }
    }
}

struct HailEffect: WeatherEffect {
    let conditions: Set<String> = ["hail"]
    func draw(_ c: SceneCanvas, top: Int, bottom: Int) {
        var rng = SeededRandom(seed: 71)
        for _ in 0..<(c.cols / 4) {
            let x0 = Int(rng.next() % UInt64(c.cols)), ph = Double(rng.next() % 1000) / 1000
            let k = (ph + c.t * 1.8).truncatingRemainder(dividingBy: 1)
            c.fill(x0, top + Int(k * Double(bottom - top)), 1, 1, Color.white.opacity(0.9))
            if k > 0.95 { c.fill(x0 + 1, bottom - 2, 1, 1, Color.white.opacity(0.7)) } // 弹起
        }
    }
}

/// 小中大雪 / 雨夹雪的雪花；窗台积雪随雪量变厚。
struct SnowEffect: WeatherEffect {
    let conditions: Set<String> = ["snow", "sleet"]
    func draw(_ c: SceneCanvas, top: Int, bottom: Int) {
        let i = c.intensity, sleet = c.cond == "sleet"
        var rng = SeededRandom(seed: 61)
        let n = Int(Double(c.cols) * (sleet ? 0.15 : 0.15 + 0.4 * i))
        let s = slant(c)
        for _ in 0..<n {
            let x0 = Int(rng.next() % UInt64(c.cols + 4)), ph = Double(rng.next() % 1000) / 1000
            let y = top + Int((ph + c.t * (0.12 + i * 0.1)).truncatingRemainder(dividingBy: 1) * Double(bottom - top))
            let sway = Int((sin(c.t * 1.3 + Double(x0)) * 1.2).rounded()) - (y - top) * s / 4
            let big = i > 0.75 && rng.next() % 4 == 0
            c.fill(x0 + sway, y, big ? 2 : 1, big ? 2 : 1, Color.white.opacity(0.85))
        }
        let depth = sleet ? 1 : (i > 0.75 ? 2 : 1)
        c.fill(0, bottom - depth, c.cols, depth, Color.white.opacity(sleet ? 0.35 : 0.6))
    }
}

struct LightningEffect: WeatherEffect {
    let conditions: Set<String> = ["thunder", "hail"]
    func draw(_ c: SceneCanvas, top: Int, bottom: Int) {
        let k = c.t.truncatingRemainder(dividingBy: 9)
        guard k < 0.16 else { return }
        c.fill(0, top, c.cols, bottom - top, Color.white.opacity(k < 0.05 ? 0.5 : 0.22))
        var b = SeededRandom(seed: UInt64(Int(c.t / 9) & 0xFFFF) + 3)
        var x = Int(b.next() % UInt64(max(1, c.cols)))
        for y in top..<(bottom - 4) { x += Int(b.next() % 3) - 1; c.fill(x, y, 1, 1, .white) }
    }
}
