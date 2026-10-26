// 彩蛋模块：每天按日期「抽签」——工作日约 45% 的天有一个，周末约 80% 的天有一到两个；
// 只在符合季节 / 星期的池子里抽，真正出现还要看当下的天气和时间。
// 新增彩蛋：实现 SceneEgg（适用条件 + 出现条件 + 绘制），加进 Eggs.all。
import SwiftUI

protocol SceneEgg {
    var id: String { get }
    /// .shoreEvents = 窗外；.indoor = 室内地面。
    var stage: SceneStage { get }
    /// 稀有度：被抽中的概率倍数（1 = 普通）。
    var rarity: Double { get }
    func fits(_ season: SceneSeason, weekend: Bool) -> Bool
    func visible(_ c: SceneCanvas) -> Bool
    func draw(_ c: SceneCanvas)
}

extension SceneEgg {
    var rarity: Double { 1 }
}

enum Eggs {
    static let all: [SceneEgg] = [PaperBoat(), Rainbow(), Kite(), Balloon(), ShootingStar(), UFO(), Coffee(), Watermelon(), Snowman(), LeafPile()]

    nonisolated(unsafe) static var forced: String?

    static func today(_ c: SceneCanvas) -> [SceneEgg] {
        if let f = forced { return all.filter { $0.id == f } }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: c.env.date) ?? 0
        var rng = SeededRandom(seed: UInt64(day) &* 2654435761)
        guard Double(rng.next() % 1000) / 1000 < (c.isWeekend ? 0.8 : 0.45) else { return [] }
        var pool = all.filter { $0.fits(c.season, weekend: c.isWeekend) && Double(rng.next() % 1000) / 1000 < $0.rarity }
        var out: [SceneEgg] = []
        for _ in 0..<(c.isWeekend ? 2 : 1) where !pool.isEmpty { out.append(pool.remove(at: Int(rng.next() % UInt64(pool.count)))) }
        return out
    }
}

struct EggsLayer: SceneLayer {
    let id: String
    let stage: SceneStage
    init(stage: SceneStage) { self.stage = stage; id = "eggs.\(stage.rawValue)" }
    func draw(_ c: SceneCanvas) {
        for e in Eggs.today(c) where e.stage == stage && e.visible(c) { e.draw(c) }
    }
}

// MARK: - 窗外

struct PaperBoat: SceneEgg {
    let id = "paperBoat", stage = SceneStage.shoreEvents
    func fits(_ s: SceneSeason, weekend: Bool) -> Bool { true }
    func visible(_ c: SceneCanvas) -> Bool { c.raining }
    func draw(_ c: SceneCanvas) {
        let x = Int((c.t * 1.2).truncatingRemainder(dividingBy: Double(c.cols + 10))) - 5, y = c.cityBase + 1
        let bob = Int(c.t * 2) % 2
        c.fill(x, y + bob, 5, 1, Color.white.opacity(0.9)); c.fill(x + 1, y + 1 + bob, 3, 1, Color(white: 0.8)); c.fill(x + 2, y - 1 + bob, 1, 1, .white)
    }
}

struct Rainbow: SceneEgg {
    let id = "rainbow", stage = SceneStage.seasonFX
    func fits(_ s: SceneSeason, weekend: Bool) -> Bool { [.spring, .summer, .tropical].contains(s) }
    func visible(_ c: SceneCanvas) -> Bool { c.dark < 0.3 && c.clearSky && c.hour >= 14 && c.hour <= 18.5 }
    func draw(_ c: SceneCanvas) { RainbowArc.draw(c, center: c.wingL, alpha: 0.45) }
}

enum RainbowArc {
    static func draw(_ c: SceneCanvas, center: Int, alpha: Double) {
        let colors: [UInt32] = [0xFF5D5D, 0xFFA24B, 0xFFE15B, 0x6FD16F, 0x5DA9FF, 0x9B7BFF]
        let r0 = min(12, c.cityBase - c.skyTop - 2)
        for (i, hex) in colors.enumerated() {
            let r = Double(r0 - i)
            for a in stride(from: 0.0, through: Double.pi, by: 0.06) {
                c.fill(center + Int((cos(a) * r).rounded()), c.cityBase - Int((sin(a) * r).rounded()), 1, 1, c.rgb(hex).color.opacity(alpha))
            }
        }
    }
}

struct Kite: SceneEgg {
    let id = "kite", stage = SceneStage.skyEvents
    func fits(_ s: SceneSeason, weekend: Bool) -> Bool { [.spring, .autumn].contains(s) }
    func visible(_ c: SceneCanvas) -> Bool { c.dark < 0.5 && !c.raining }
    func draw(_ c: SceneCanvas) {
        let kx = c.wingR + Int((sin(c.t * 0.8) * 2).rounded()), ky = c.skyTop + 3 + Int((sin(c.t * 1.3) * 1).rounded())
        c.fill(kx, ky - 1, 1, 1, c.rgb(0xFF5D5D).color); c.fill(kx - 1, ky, 3, 1, c.rgb(0xFFE15B).color); c.fill(kx, ky + 1, 1, 1, c.rgb(0xFF5D5D).color)
        for k in 1...4 { c.fill(kx + Int((sin(c.t * 3 + Double(k)) * 1).rounded()), ky + 1 + k, 1, 1, c.rgb(0x5DA9FF).color.opacity(0.8)) }
        for k in 1..<max(2, min(10, c.cityBase - ky)) { c.fill(kx - k / 2, ky + 2 + k, 1, 1, Color.white.opacity(0.25)) }
    }
}

struct Balloon: SceneEgg {
    let id = "balloon", stage = SceneStage.skyEvents
    func fits(_ s: SceneSeason, weekend: Bool) -> Bool { weekend && s != .winter }
    func visible(_ c: SceneCanvas) -> Bool { c.dark < 0.5 && c.clearSky }
    func draw(_ c: SceneCanvas) { HotAirBalloon.draw(c, x: Int((c.t * 0.5).truncatingRemainder(dividingBy: Double(c.cols + 12))) - 6, y: c.skyTop + 3, palette: [0xFF6B6B, 0xFFD84A, 0x5DA9FF]) }
}

enum HotAirBalloon {
    static func draw(_ c: SceneCanvas, x: Int, y: Int, palette: [UInt32]) {
        for (i, hex) in palette.enumerated() { c.fill(x + i * 2 - 1, y, 2, 4, c.rgb(hex).color) }
        c.fill(x, y - 1, 3, 1, c.rgb(palette[0]).color); c.fill(x + 1, y + 4, 1, 1, Color(white: 0.4)); c.fill(x, y + 5, 3, 1, c.rgb(0x8A5A2B).color)
    }
}

struct ShootingStar: SceneEgg {
    let id = "shootingStar", stage = SceneStage.skyEvents
    func fits(_ s: SceneSeason, weekend: Bool) -> Bool { true }
    func visible(_ c: SceneCanvas) -> Bool { c.dark > 0.7 && c.clearSky }
    func draw(_ c: SceneCanvas) {
        let k = c.t.truncatingRemainder(dividingBy: 25)
        guard k < 0.8 else { return }
        Meteor.draw(c, x: c.wingR + 6 - Int(k / 0.8 * 14), y: c.skyTop + 1 + Int(k / 0.8 * 6), length: 4)
    }
}

enum Meteor {
    static func draw(_ c: SceneCanvas, x: Int, y: Int, length: Int, alpha: Double = 1) {
        for j in 0..<length { c.fill(x + j, y - j / 2, 1, 1, Color.white.opacity(alpha * (1 - Double(j) / Double(length + 1)))) }
    }
}

struct UFO: SceneEgg {
    let id = "ufo", stage = SceneStage.skyEvents
    let rarity = 0.1
    func fits(_ s: SceneSeason, weekend: Bool) -> Bool { true }
    func visible(_ c: SceneCanvas) -> Bool { c.dark > 0.6 }
    func draw(_ c: SceneCanvas) {
        let ux = c.wingL + Int((sin(c.t * 0.6) * 3).rounded()), uy = c.skyTop + 3
        c.fill(ux - 3, uy, 7, 1, Color(white: 0.7)); c.fill(ux - 1, uy - 1, 3, 1, Color(red: 0.6, green: 0.9, blue: 1))
        for (i, dx) in [-2, 0, 2].enumerated() { c.fill(ux + dx, uy + 1, 1, 1, (Int(c.t * 3) + i) % 2 == 0 ? Color.yellow : Color.red) }
        if Int(c.t / 6) % 2 == 0 { c.fill(ux - 1, uy + 2, 3, max(0, c.cityBase - uy - 2), Color(red: 0.7, green: 1, blue: 0.8).opacity(0.18)) }
    }
}

// MARK: - 室内地面

struct Coffee: SceneEgg {
    let id = "coffee", stage = SceneStage.indoor
    func fits(_ s: SceneSeason, weekend: Bool) -> Bool { !weekend }
    func visible(_ c: SceneCanvas) -> Bool { c.hour >= 8 && c.hour < 11.5 }
    func draw(_ c: SceneCanvas) {
        let x = 3, y = c.floorTop
        c.fill(x, y - 3, 3, 3, .white); c.fill(x + 3, y - 2, 1, 1, .white); c.fill(x, y - 3, 3, 1, c.rgb(0x6B4226).color)
        for k in 0..<3 {
            let ph = (c.t * 0.8 + Double(k) * 0.33).truncatingRemainder(dividingBy: 1)
            c.fill(x + 1 + Int((sin(c.t * 2 + Double(k)) * 1).rounded()), y - 4 - Int(ph * 4), 1, 1, Color.white.opacity(0.5 * (1 - ph)))
        }
    }
}

struct Watermelon: SceneEgg {
    let id = "watermelon", stage = SceneStage.indoor
    func fits(_ s: SceneSeason, weekend: Bool) -> Bool { [.summer, .tropical].contains(s) }
    func visible(_ c: SceneCanvas) -> Bool { c.hour >= 12 && c.hour < 19 }
    func draw(_ c: SceneCanvas) {
        let x = c.cols - 10, y = c.floorTop
        c.fill(x, y - 1, 6, 1, c.rgb(0x3F9B4A).color); c.fill(x + 1, y - 2, 4, 1, c.rgb(0xFF5D6C).color); c.fill(x + 2, y - 3, 2, 1, c.rgb(0xFF5D6C).color)
        c.fill(x + 2, y - 2, 1, 1, .black); c.fill(x + 4, y - 2, 1, 1, .black)
    }
}

struct Snowman: SceneEgg {
    let id = "snowman", stage = SceneStage.indoor
    func fits(_ s: SceneSeason, weekend: Bool) -> Bool { s == .winter }
    func visible(_ c: SceneCanvas) -> Bool { c.cond == "snow" || c.cond == "sleet" }
    func draw(_ c: SceneCanvas) {
        let x = c.cols - 10, y = c.floorTop
        c.fill(x, y - 3, 4, 3, .white); c.fill(x + 1, y - 5, 2, 2, .white)
        c.fill(x + 1, y - 5, 1, 1, .black); c.fill(x + 3, y - 4, 1, 1, c.rgb(0xFF8A2A).color); c.fill(x, y - 6, 4, 1, c.rgb(0xC93A2E).color)
    }
}

struct LeafPile: SceneEgg {
    let id = "leafPile", stage = SceneStage.indoor
    func fits(_ s: SceneSeason, weekend: Bool) -> Bool { s == .autumn }
    func visible(_ c: SceneCanvas) -> Bool { true }
    func draw(_ c: SceneCanvas) {
        let x = c.cols - 10, y = c.floorTop
        let colors: [UInt32] = [0xE38A2F, 0xC9472E, 0xE8B83A]
        for i in 0..<9 { c.fill(x - 2 + i, y - 1 - (i > 1 && i < 7 ? 1 : 0), 1, 1, c.rgb(colors[i % 3]).color) }
        c.fill(x + 1, y - 3, 3, 1, c.rgb(0xE38A2F).color)
    }
}
