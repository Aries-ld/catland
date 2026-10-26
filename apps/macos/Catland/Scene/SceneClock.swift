// SceneClock：按所在地经纬度和当前时间在本地算太阳高度 / 方位（NOAA 简化公式），驱动天空颜色、光斑角度。
// 不联网；所在地默认新加坡（与天气数据源 NEA 一致）。
import Foundation
import SwiftUI

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
    var location: SceneLocation = .singapore
    /// 天气强度 0~1（小雨 / 大雨、小雪 / 大雪）。
    var intensity: Double = 0.6
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

/// 季节：按日期 + 所在纬度（南半球季节相反；南北回归线之间是「常夏」，没有四季）。
enum SceneSeason: String {
    case spring, summer, autumn, winter, tropical

    static func of(_ date: Date, latitude: Double) -> SceneSeason {
        if abs(latitude) < 23.5 { return .tropical }
        var m = Calendar.current.component(.month, from: date)
        if latitude < 0 { m = (m + 5) % 12 + 1 }
        switch m {
        case 3...5: return .spring
        case 6...8: return .summer
        case 9...11: return .autumn
        default: return .winter
        }
    }

    /// 当前季节（渲染时更新），小猫的行为权重随季节变化：冬天更爱睡觉趴着，夏天更爱翻肚皮伸懒腰。
    nonisolated(unsafe) static var current: SceneSeason = .tropical

    func catWeight(_ action: String) -> Double {
        switch (self, action) {
        case (.winter, "nap"), (.winter, "loaf"): return 2
        case (.winter, "walk"), (.winter, "play"): return 0.6
        case (.summer, "roll"), (.summer, "stretch"), (.tropical, "roll"): return 1.6
        case (.summer, "nap"): return 0.7
        case (.spring, "play"), (.autumn, "play"): return 1.8 // 追花瓣 / 落叶
        default: return 1
        }
    }
}

/// 节日：用于窗边装饰的彩蛋。春节、中秋按农历，写死近几年的公历日期。
enum SceneHoliday {
    case springFestival, midAutumn, halloween, christmas, newYear, nationalDaySG

    static func active(_ date: Date) -> [SceneHoliday] {
        let cal = Calendar.current
        let y = cal.component(.year, from: date), m = cal.component(.month, from: date), d = cal.component(.day, from: date)
        var out: [SceneHoliday] = []
        func near(_ month: Int, _ day: Int, before: Int, after: Int) -> Bool {
            guard let target = cal.date(from: DateComponents(year: y, month: month, day: day)) else { return false }
            let diff = cal.dateComponents([.day], from: target, to: cal.startOfDay(for: date)).day ?? 99
            return diff >= -before && diff <= after
        }
        let springFestival: [Int: (Int, Int)] = [2026: (2, 17), 2027: (2, 6), 2028: (1, 26), 2029: (2, 13), 2030: (2, 3), 2031: (1, 23)]
        let midAutumn: [Int: (Int, Int)] = [2026: (9, 25), 2027: (9, 15), 2028: (10, 3), 2029: (9, 22), 2030: (9, 12), 2031: (10, 1)]
        if let sf = springFestival[y], near(sf.0, sf.1, before: 7, after: 15) { out.append(.springFestival) }
        if let ma = midAutumn[y], near(ma.0, ma.1, before: 1, after: 1) { out.append(.midAutumn) }
        if near(10, 31, before: 5, after: 1) { out.append(.halloween) }
        if near(12, 25, before: 7, after: 1) { out.append(.christmas) }
        if (m == 12 && d == 31) || (m == 1 && d == 1) { out.append(.newYear) }
        if m == 8 && d == 9 { out.append(.nationalDaySG) }
        return out
    }
}
