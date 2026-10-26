// 季节模块：季节判定 + 季节样式表（行道树配色、飘落粒子、窗角装饰、天色倾向、小猫行为偏好）+ 对应图层。
// 新增 / 调整季节表现：改 SeasonStyle.of 里对应季节的那一项即可。
import SwiftUI

/// 季节：按日期 + 所在纬度（南半球季节相反；南北回归线之间是「常夏」，没有四季）。
enum SceneSeason: String, CaseIterable {
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

    /// 当前季节（渲染时更新），供小猫行为引擎读取。
    nonisolated(unsafe) static var current: SceneSeason = .tropical

    func catWeight(_ action: String) -> Double { SeasonStyle.of(self).catWeights[action] ?? 1 }
}

enum SeasonParticle { case petals([UInt32]), leaves([UInt32]), fireflies, none }
enum SeasonOrnament { case blossomBranch([UInt32]), maple([UInt32]), ivyAndChime, icicles, monstera }

struct SeasonStyle {
    /// 行道树树冠配色；nil 表示冬天的枯枝。
    let treeColors: [UInt32]?
    /// 树冠上点缀的花（春天）。
    let blossom: UInt32?
    let particle: SeasonParticle
    let ornament: SeasonOrnament
    let frost: Bool
    let skyTop: UInt32?, skyTopMix: Double
    let horizon: UInt32?, horizonMix: Double
    let catWeights: [String: Double]

    func tint(_ s: SkyPalette.Stops, dark: Double) -> SkyPalette.Stops {
        SkyPalette.Stops(top: skyTop.map { s.top.mix(.hex($0), skyTopMix * (1 - dark)) } ?? s.top,
                         horizon: horizon.map { s.horizon.mix(.hex($0), horizonMix * (1 - dark)) } ?? s.horizon)
    }

    static func of(_ s: SceneSeason) -> SeasonStyle {
        switch s {
        case .spring:
            return SeasonStyle(treeColors: [0x8ACB6B, 0x9FD67E], blossom: 0xF7A8C4, particle: .petals([0xF7A8C4, 0xFFD1E0]),
                               ornament: .blossomBranch([0xF7A8C4, 0xFFD1E0, 0xF48FB1]), frost: false,
                               skyTop: nil, skyTopMix: 0, horizon: 0xF6D6E2, horizonMix: 0.1, catWeights: ["play": 1.8])
        case .summer:
            return SeasonStyle(treeColors: [0x3F8F4A, 0x4FA057], blossom: nil, particle: .fireflies, ornament: .ivyAndChime, frost: false,
                               skyTop: nil, skyTopMix: 0, horizon: nil, horizonMix: 0, catWeights: ["roll": 1.6, "stretch": 1.6, "nap": 0.7])
        case .autumn:
            return SeasonStyle(treeColors: [0xE38A2F, 0xC9472E, 0xE8B83A], blossom: nil, particle: .leaves([0xE38A2F, 0xC9472E, 0xE8B83A]),
                               ornament: .maple([0xD9452B, 0xE8862F, 0xC93A2E]), frost: false,
                               skyTop: nil, skyTopMix: 0, horizon: 0xF3D2A0, horizonMix: 0.14, catWeights: ["play": 1.8])
        case .winter:
            return SeasonStyle(treeColors: nil, blossom: nil, particle: .none, ornament: .icicles, frost: true,
                               skyTop: 0xC9D6E6, skyTopMix: 0.12, horizon: 0xE6EDF5, horizonMix: 0.2,
                               catWeights: ["nap": 2, "loaf": 2, "walk": 0.6, "play": 0.6])
        case .tropical:
            return SeasonStyle(treeColors: [0x2F8F5B, 0x3A9E66], blossom: nil, particle: .fireflies, ornament: .monstera, frost: false,
                               skyTop: nil, skyTopMix: 0, horizon: nil, horizonMix: 0, catWeights: ["roll": 1.6])
        }
    }
}

/// 岸边行道树：配色来自季节样式；冬天只剩枝干（下雪时枝头积雪）；有风时树冠摇摆。
struct TreesLayer: SceneLayer {
    let id = "trees"
    let stage = SceneStage.shore
    func draw(_ c: SceneCanvas) {
        let style = c.seasonStyle
        let y = c.cityBase
        var rng = SeededRandom(seed: 404)
        var x = 2 + c.parallax(4)
        let night = c.dark * 0.3 // 岸边有路灯照着，夜里也看得出季节颜色
        let sway = c.cond == "windy" ? Int((sin(c.t * 3) * 1).rounded()) : 0
        while x < c.cols {
            let w = 3 + Int(rng.next() % 2)
            let trunk = c.rgb(0x6B4E3D).mix(c.rgb(0x1E1612), night).color
            c.fill(x + w / 2, y - 1, 1, 2, trunk)
            if let colors = style.treeColors {
                let leaf = c.rgb(colors[Int(rng.next() % UInt64(colors.count))]).mix(c.rgb(0x0F1A14), night)
                c.fill(x + sway, y - 3, w, 2, leaf.color)
                c.fill(x + 1 + sway, y - 4, max(1, w - 2), 1, leaf.color)
                if let b = style.blossom, rng.next() % 2 == 0 {
                    c.fill(x + Int(rng.next() % UInt64(w)) + sway, y - 3 - Int(rng.next() % 2), 1, 1, c.rgb(b).mix(c.rgb(0x3A2A33), night).color)
                }
            } else {
                c.fill(x + w / 2 - 1 + sway, y - 2, 1, 1, trunk); c.fill(x + w / 2 + 1 + sway, y - 2, 1, 1, trunk); c.fill(x + w / 2, y - 3, 1, 1, trunk)
                if c.cond == "snow" || c.cond == "sleet" { c.fill(x + w / 2 - 1 + sway, y - 3, 3, 1, Color.white.opacity(0.85)) }
            }
            x += w + 3 + Int(rng.next() % 4)
        }
    }
}

/// 岸边路灯：夜里亮起暖光，照亮附近的树。
struct StreetLampsLayer: SceneLayer {
    let id = "streetLamps"
    let stage = SceneStage.shore
    func draw(_ c: SceneCanvas) {
        let y = c.cityBase
        var x = 9 + c.parallax(4)
        while x < c.cols {
            c.fill(x, y - 3, 1, 3, Color(red: 0.25, green: 0.26, blue: 0.3))
            c.fill(x - 1, y - 4, 3, 1, Color(red: 0.3, green: 0.3, blue: 0.34))
            if c.dark > 0.35 {
                c.fill(x, y - 4, 1, 1, Color(red: 1, green: 0.88, blue: 0.6))
                c.fill(x - 3, y - 6, 7, 6, Color(red: 1, green: 0.8, blue: 0.45).opacity(0.16 * c.dark))
                c.fill(x - 1, y - 5, 3, 4, Color(red: 1, green: 0.8, blue: 0.45).opacity(0.14 * c.dark))
            }
            x += 18
        }
    }
}

/// 季节粒子：花瓣 / 落叶（有风时更多更斜）、夏夜萤火虫。
struct SeasonParticlesLayer: SceneLayer {
    let id = "seasonParticles"
    let stage = SceneStage.seasonFX
    func draw(_ c: SceneCanvas) {
        switch c.seasonStyle.particle {
        case .petals(let colors), .leaves(let colors):
            guard !c.raining else { return }
            drift(c, colors: colors, count: c.cond == "windy" ? 14 : 7, seed: c.season == .spring ? 31 : 37)
        case .fireflies:
            guard c.dark > 0.6, !c.raining else { return }
            fireflies(c, count: 8)
        case .none:
            break
        }
    }

    func drift(_ c: SceneCanvas, colors: [UInt32], count: Int, seed: UInt64) {
        let windy = c.cond == "windy"
        var rng = SeededRandom(seed: seed)
        for _ in 0..<count {
            let speed = 0.06 + Double(rng.next() % 50) / 1000
            let ph = Double(rng.next() % 1000) / 1000
            let k = (ph + c.t * speed).truncatingRemainder(dividingBy: 1)
            let x0 = Int(rng.next() % UInt64(c.cols + 20))
            let x = x0 - Int(k * (windy ? 60 : 18)) + Int((sin(c.t * 2 + Double(x0)) * 1.5).rounded())
            let y = c.skyTop + Int(k * Double(c.floorTop - c.skyTop))
            c.fill(x, y, 1, 1, c.rgb(colors[Int(rng.next() % UInt64(colors.count))]).mix(c.rgb(0x1A1A24), c.dark * 0.2).color)
        }
    }

    func fireflies(_ c: SceneCanvas, count: Int, spread: Int = 4) {
        var rng = SeededRandom(seed: 53)
        for _ in 0..<count {
            let bx = Int(rng.next() % UInt64(max(1, c.cols))), by = c.cityBase - 2 - Int(rng.next() % UInt64(spread))
            let blink = 0.5 + 0.5 * sin(c.t * (1.5 + Double(rng.next() % 3)) + Double(bx))
            let dx = Int((sin(c.t * 0.7 + Double(bx)) * 2).rounded())
            c.fill(bx + dx, by, 1, 1, Color(red: 0.85, green: 1, blue: 0.45).opacity(blink * max(0.6, c.dark)))
        }
    }
}

/// 窗角的季节装饰（室内，白天夜里都看得见）。
struct SeasonOrnamentLayer: SceneLayer {
    let id = "seasonOrnament"
    let stage = SceneStage.ornament
    func draw(_ c: SceneCanvas) {
        let lit = 1 - c.dark * 0.25
        func col(_ hex: UInt32) -> Color { c.rgb(hex).mix(c.rgb(0x1A1A24), 1 - lit).color }
        let right = c.cols - 1
        // 镜像绘制：左上角 (x) 与右上角 (right - x)
        func both(_ x: Int, _ y: Int, _ w: Int = 1, _ h: Int = 1, _ color: Color) { c.fill(x, y, w, h, color); c.fill(right - x - w + 1, y, w, h, color) }
        let sway = Int((sin(c.t * 1.2) * 0.6).rounded())
        switch c.seasonStyle.ornament {
        case .blossomBranch(let palette), .maple(let palette):
            let spring = c.season == .spring
            let branch = col(0x6B4A36)
            for k in 0..<10 { both(k, k / 2, 1, 1, branch) }
            both(4, 3, 1, 2, branch); both(7, 4, 1, 2, branch)
            let blooms: [(Int, Int)] = [(2, 2), (5, 1), (8, 3), (4, 5), (7, 6), (10, 5), (1, 0)]
            for (i, b) in blooms.enumerated() {
                both(b.0 + (i % 2 == 0 ? sway : 0), b.1, 2, 2, col(palette[i % palette.count]))
                if spring { both(b.0 + 1, b.1, 1, 1, col(0xFFF2F6)) }
            }
        case .ivyAndChime:
            let vine = col(0x4FA057), dark2 = col(0x2F7A3A)
            for k in 0..<9 { both((k % 2) + (k > 4 ? sway : 0), 1 + k, 2, 1, k % 3 == 0 ? dark2 : vine) }
            both(0, 0, 6, 1, vine)
            let bx = right - 8 + sway
            c.fill(right - 8, 1, 1, 3, col(0xBFC7D5))
            c.fill(bx - 1, 4, 3, 2, Color(red: 0.6, green: 0.85, blue: 1).opacity(0.9))
            c.fill(bx, 6, 1, 2, col(0xE04B5A))
        case .icicles:
            both(0, 0, 14, 1, Color.white.opacity(0.85))
            for (i, x) in stride(from: 1, to: 14, by: 3).enumerated() {
                let len = 1 + (i * 7 + 3) % 3
                both(x, 1, 1, len, Color(red: 0.85, green: 0.94, blue: 1).opacity(0.85))
                if (Int(c.t * 0.7) + i) % 9 == 0 { both(x, 1 + len + 1, 1, 1, Color(red: 0.8, green: 0.92, blue: 1).opacity(0.7)) }
            }
        case .monstera:
            let leaf = col(0x2E8B57), vein = col(0x1F6B40)
            for k in 0..<7 { both(0, k, 7 - k, 1, leaf) }
            for k in 0..<6 { both(k, k, 1, 1, vein) }
            both(4, 2, 1, 1, col(0x4FB37A))
        }
    }
}

/// 冬天（或下雪时）玻璃四角结霜。
struct FrostLayer: SceneLayer {
    let id = "frost"
    let stage = SceneStage.ornament
    func draw(_ c: SceneCanvas) {
        guard c.seasonStyle.frost || c.cond == "snow" else { return }
        let frost = Color(red: 0.9, green: 0.95, blue: 1).opacity(0.35 + 0.15 * (1 - c.dark))
        for (x0, dir) in [(0, 1), (c.cols - 1, -1)] {
            for k in 0..<6 { c.fill(x0 + dir * k, c.floorTop - 1 - k / 2, 1, 1 + (6 - k) / 2, frost) }
        }
        if c.hasNotch {
            let nc = c.notchCols
            for k in 0..<4 { c.fill(nc.lowerBound - 3 - k, c.notchRows + 1 + k / 2, 1, 1, frost); c.fill(nc.upperBound + 3 + k, c.notchRows + 1 + k / 2, 1, 1, frost) }
        }
    }
}
