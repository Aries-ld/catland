// SceneClock：按所在地经纬度和当前时间在本地算太阳高度 / 方位（NOAA 简化公式），驱动天空颜色、光斑角度。
// 不联网；所在地默认新加坡（与天气数据源 NEA 一致）。
import Foundation
import SwiftUI

struct SceneLocation {
    let name: String
    let latitude: Double
    let longitude: Double

    static let singapore = SceneLocation(name: "新加坡", latitude: 1.2903, longitude: 103.8520)
}

struct SunPosition {
    /// 太阳高度角（度），负数为地平线以下。
    let altitude: Double
    /// 方位角（度，北 0 东 90）。
    let azimuth: Double
}

enum SceneClock {
    static func sun(at date: Date, location loc: SceneLocation = .singapore) -> SunPosition {
        let rad = Double.pi / 180
        let jd = date.timeIntervalSince1970 / 86400 + 2440587.5
        let n = jd - 2451545.0
        let L = (280.460 + 0.9856474 * n).truncatingRemainder(dividingBy: 360)
        let g = (357.528 + 0.9856003 * n).truncatingRemainder(dividingBy: 360) * rad
        let lambda = (L + 1.915 * sin(g) + 0.020 * sin(2 * g)) * rad
        let epsilon = (23.439 - 0.0000004 * n) * rad
        let ra = atan2(cos(epsilon) * sin(lambda), cos(lambda))
        let dec = asin(sin(epsilon) * sin(lambda))
        let gmst = (18.697374558 + 24.06570982441908 * n).truncatingRemainder(dividingBy: 24)
        let lst = (gmst * 15 + loc.longitude) * rad
        let ha = lst - ra
        let lat = loc.latitude * rad
        let alt = asin(sin(lat) * sin(dec) + cos(lat) * cos(dec) * cos(ha))
        let az = atan2(-sin(ha), tan(dec) * cos(lat) - sin(lat) * cos(ha))
        return SunPosition(altitude: alt / rad, azimuth: (az / rad + 360).truncatingRemainder(dividingBy: 360))
    }

    /// 0 = 正午般明亮，1 = 深夜。按太阳高度在 -8°~+10° 之间平滑过渡（含晨昏蒙影）。
    static func darkness(_ sun: SunPosition) -> Double {
        let t = (10 - sun.altitude) / 18
        return min(1, max(0, t))
    }

    /// 晨昏程度：太阳在 -6°~+8° 时出现橙粉色调，峰值在地平线附近。
    static func twilight(_ sun: SunPosition) -> Double {
        let d = abs(sun.altitude - 1)
        return max(0, 1 - d / 7)
    }
}

/// 天空配色：白天 / 晨昏 / 夜晚三组，按 darkness 与 twilight 混合；阴雨天降低饱和度。
enum SkyPalette {
    struct Stops { let top: RGB; let horizon: RGB }

    struct RGB {
        var r: Double, g: Double, b: Double
        static func hex(_ v: UInt32) -> RGB { RGB(r: Double(v >> 16 & 0xFF) / 255, g: Double(v >> 8 & 0xFF) / 255, b: Double(v & 0xFF) / 255) }
        func mix(_ o: RGB, _ t: Double) -> RGB { RGB(r: r + (o.r - r) * t, g: g + (o.g - g) * t, b: b + (o.b - b) * t) }
        func grey(_ t: Double) -> RGB { let l = r * 0.3 + g * 0.59 + b * 0.11; return mix(RGB(r: l, g: l, b: l), t) }
        var color: Color { Color(red: r, green: g, blue: b) }
    }

    static let day = Stops(top: .hex(0x4F9BE8), horizon: .hex(0xBDE0FA))
    static let dusk = Stops(top: .hex(0x5A4C93), horizon: .hex(0xF59A6B))
    static let night = Stops(top: .hex(0x0A1230), horizon: .hex(0x23305A))

    static func stops(darkness d: Double, twilight tw: Double, overcast: Double) -> Stops {
        var top = day.top.mix(night.top, d)
        var horizon = day.horizon.mix(night.horizon, d)
        top = top.mix(dusk.top, tw * 0.6)
        horizon = horizon.mix(dusk.horizon, tw * 0.85)
        return Stops(top: top.grey(overcast * 0.7), horizon: horizon.grey(overcast * 0.6))
    }
}

/// 场景当前的时间、天气与鼠标视差输入。
struct SceneEnv {
    var date: Date
    var condition: String
    var temperature: Double?
    /// 鼠标在刘海区域内的水平位置，-1（左）~ 1（右）。
    var mouse: CGFloat
}

/// 确定性伪随机（SplitMix64）：同一种子每帧生成相同的楼群 / 星星 / 雨滴，画面稳定不闪。
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
