// 城市模块：远景楼群（雾化）、近景楼群 + 城市地标（按所在城市注册）、海湾水面、地铁隧道。
// 新增城市地标：实现 Landmark（skyline + 占位 + 绘制），加进 Landmarks.all；LocationProvider 的 Skyline 里登记城市坐标。
import SwiftUI

/// 楼群配色（随昼夜 / 晨昏 / 阴天变化），地标与普通高楼共用。
struct CityPalette {
    let body: SkyPalette.RGB
    let shade: SkyPalette.RGB
    let windowDay: SkyPalette.RGB

    init(_ c: SceneCanvas) {
        body = c.rgb(0x8EA4BC).mix(c.rgb(0x26304F), c.dark).mix(c.rgb(0xC98A6E), c.dusk * 0.25).grey(c.overcast * 0.25)
        shade = body.mix(c.rgb(0x0E1426), 0.25)
        windowDay = body.mix(c.rgb(0xE6F0FA), 0.35)
    }
}

extension SceneCanvas {
    func building(x: Int, w: Int, h: Int, base: Int, palette pal: CityPalette, rng: inout SeededRandom) {
        fill(x, base - h, w, h, pal.body.color)
        fill(x + w - 1, base - h, 1, h, pal.shade.color)
        if rng.next() % 3 == 0 { fill(x + w / 2, base - h - 1, 1, 1, pal.body.color) } // 天线
        litWindows(x: x, w: w - 1, top: base - h + 1, bottom: base, seed: rng.next(), palette: pal)
    }

    /// 窗格：白天浅色格子，夜里随机亮起暖灯并偶尔闪烁。
    func litWindows(x: Int, w: Int, top: Int, bottom: Int, seed: UInt64, palette pal: CityPalette) {
        var rng = SeededRandom(seed: seed)
        for wy in stride(from: top, to: bottom - 1, by: 2) {
            for wx in stride(from: x, to: x + w, by: 2) {
                let roll = rng.next()
                if dark > 0.5 {
                    guard roll % 3 != 0 else { continue }
                    let flicker = roll % 37 == 0 && Int(t / 3) % 2 == 0
                    if !flicker { fill(wx, wy, 1, 1, (roll % 5 == 0 ? Color(red: 0.75, green: 0.9, blue: 1) : Color(red: 1, green: 0.84, blue: 0.5)).opacity(0.85 * dark)) }
                } else if roll % 2 == 0 {
                    fill(wx, wy, 1, 1, pal.windowDay.color.opacity(0.7))
                }
            }
        }
    }

    /// 地标锚点：左翼、右翼各一个（随近景视差移动）。
    var landmarkLeft: Int { (hasNotch ? max(1, notchCols.lowerBound / 2 - 6) : cols / 5) + parallax(3) }
    var landmarkRight: Int { (hasNotch ? notchCols.upperBound + 1 + (cols - notchCols.upperBound - 1) / 2 : cols * 4 / 5) + parallax(3) }
}

// MARK: - 地标

protocol Landmark {
    var skyline: Skyline { get }
    /// 地标占用的列范围：普通高楼会避开。
    func reserved(_ c: SceneCanvas) -> [ClosedRange<Int>]
    func draw(_ c: SceneCanvas, base: Int, palette: CityPalette)
}

enum Landmarks {
    /// 地标来自各城市的场景包（Presentation/Cities/）。
    static func of(_ s: Skyline) -> Landmark? { CityPacks.of(s)?.landmark }
}

// MARK: - 地标绘制工具

extension SceneCanvas {
    /// 地标中心列：两翼中心 + 视差。刘海挡住中间，地标只放在两侧看得见的地方。
    var markL: Int { wingL + parallax(3) }
    /// 右翼地标略往刘海一侧靠，避开右上角的季节装饰（藤蔓、落叶）。
    var markR: Int { wingR - 2 + parallax(3) }
    var night: Bool { dark > 0.5 }

    /// 地标专用配色：比普通楼群更深、更饱和，前排最深，白天受光面有一条亮边；夜里是深色剪影（再加灯光）。
    func landmarkTone(depth: Double) -> (body: SkyPalette.RGB, lit: SkyPalette.RGB) {
        let day = rgb(0x4F6A8C).mix(rgb(0x7F96B2), depth * 0.6)
        let body = haze(day.mix(rgb(0x141A2E), dark * 0.85).mix(rgb(0xC07A62), dusk * 0.2), depth * 0.22)
        return (body, body.mix(rgb(0xF2F6FA), night ? 0.08 : 0.45))
    }

    /// 夜里楼体上的窗灯：隔行隔列随机亮（深夜亮得少），偶尔一盏闪一下。
    func towerLights(x: Int, w: Int, top: Int, bottom: Int, seed: UInt64, warm: Bool = true) {
        guard night else { return }
        var rng = SeededRandom(seed: seed)
        let lateFactor = hour >= 23 || hour < 5 ? 0.45 : 1.0
        for y in stride(from: top + 1, to: bottom, by: 2) {
            for xx in stride(from: x, to: x + w, by: 2) where Double(rng.next() % 100) < 55 * lateFactor {
                let c = warm ? Color(red: 1, green: 0.84, blue: 0.5) : Color(red: 0.7, green: 0.88, blue: 1)
                fill(xx, y, 1, 1, c.opacity(0.85 * dark))
            }
        }
    }

    /// 实心像素圆（球体），左上角一点高光。
    func disc(_ cx: Int, _ cy: Int, _ r: Int, _ col: SkyPalette.RGB, highlight: SkyPalette.RGB? = nil) {
        for dy in -r...r {
            let w = Int((sqrt(Double(r * r) - Double(dy * dy)) + 0.35).rounded(.down))
            fill(cx - w, cy + dy, w * 2 + 1, 1, col.color)
        }
        if let h = highlight, r >= 2 { fill(cx - r / 2, cy - r / 2, 1, 1, h.color) }
    }

    /// 后排建筑：往天空色里雾化一些，拉开前后层次（横向放不下时靠前后叠放）。
    func haze(_ base: SkyPalette.RGB, _ k: Double) -> SkyPalette.RGB {
        base.mix(sky.horizon.mix(rgb(0x0E1426), dark * 0.6), k)
    }

    /// 夜里一条沿竖线往上流动的灯（上海中心的灯带、中国尊的竖向灯光）。
    func flowingLight(x: Int, from bottom: Int, to top: Int, color: Color, speed: Double = 6) {
        let span = max(1, bottom - top)
        let head = bottom - Int((t * speed).truncatingRemainder(dividingBy: Double(span)))
        for k in 0..<4 where head + k <= bottom { fill(x, head + k, 1, 1, color.opacity(0.9 - Double(k) * 0.2)) }
    }
}

// MARK: - 手绘像素地标

/// 手绘像素图：每个字符一个像素（空格 / . 为透明），按调色板上色。地标不按比例拉伸，收起和悬停都是同一张图。
/// 夜里：楼体压成深色剪影，「灯」像素发光并带一圈淡淡的光晕，地标才会从夜色里跳出来。
struct PixelSprite {
    let rows: [String]
    var width: Int { rows.map(\.count).max() ?? 0 }
    var height: Int { rows.count }

    func at(_ x: Int, _ y: Int) -> Character {
        guard rows.indices.contains(y) else { return " " }
        let line = Array(rows[y])
        return line.indices.contains(x) ? line[x] : " "
    }

    /// 轮廓像素：上下左右任意一边是透明（夜里的轮廓灯就画在这些像素上）。
    func isEdge(_ x: Int, _ y: Int) -> Bool {
        [(-1, 0), (1, 0), (0, -1), (0, 1)].contains { at(x + $0.0, y + $0.1) == " " || at(x + $0.0, y + $0.1) == "." }
    }

    /// 以底边中点为锚点绘制。color(字符, x, y, 是否轮廓) 返回 nil 表示透明；glow 返回非 nil 时在该像素周围加光晕。
    func draw(_ c: SceneCanvas, centerX: Int, base: Int, color: (Character, Int, Int, Bool) -> Color?, glow: (Character, Bool) -> Color? = { _, _ in nil }) {
        let x0 = centerX - width / 2, y0 = base - height
        for (y, line) in rows.enumerated() {
            for (x, ch) in line.enumerated() where ch != " " && ch != "." {
                if let g = glow(ch, isEdge(x, y)) {
                    for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] { c.fill(x0 + x + dx, y0 + y + dy, 1, 1, g) }
                }
            }
        }
        for (y, line) in rows.enumerated() {
            for (x, ch) in line.enumerated() where ch != " " && ch != "." {
                if let col = color(ch, x, y, isEdge(x, y)) { c.fill(x0 + x, y0 + y, 1, 1, col) }
            }
        }
    }
}

extension SceneCanvas {
    /// 白天色和夜色按天黑程度过渡（傍晚带一点暖色）。
    func dayNight(_ day: UInt32, _ night: UInt32) -> Color {
        rgb(day).mix(rgb(0xC07A62), dusk * 0.15).mix(rgb(night), dark).color
    }
    /// 夜里才亮的灯：白天是窗格色，夜里是灯色。
    func lamp(_ day: UInt32, _ on: Color) -> Color {
        dark > 0.5 ? on : rgb(day).mix(rgb(0x2A3550), dark).color
    }
}

// MARK: - 地标细网格

/// 地标用更细的网格画：1pt 一格（Retina 上 2 个物理像素，依然锐利），比普通楼群（1.5pt）精细 1.5 倍。
/// 收起时刘海两侧只有约 39pt 宽、37pt 高，按 1.5pt 一格画不出东方明珠的细长比例和球体，所以地标单独提高精度。
struct FineGrid {
    let c: SceneCanvas
    static let unit: CGFloat = 1
    func f(_ coarse: Int) -> Int { Int((CGFloat(coarse) * c.p / Self.unit).rounded()) }
    /// 楼顶最高到这里：悬停时离窗框上沿留 4 格；收起时两侧没有窗框挡着，只留 1 格，把高度都给地标。
    var top: Int { f(c.skyTop) + (c.heightScale > 1.3 ? 4 : 1) }
    /// 地标底边：压到海湾后面 3 格（会被前景栏杆挡住），多给一点高度。
    func base(_ coarse: Int) -> Int { f(coarse) + 3 }
    /// 宽度缩放：收起时高度只有悬停的一半左右，宽度按同样比例收窄，保持修长的比例（不被压成矮胖）。
    func scale(forHeight h: Int) -> Double { min(1, max(0.62, Double(h) / 58)) }
    func sw(_ w: Double, _ s: Double, min m: Int = 1) -> Int { max(m, Int((w * s).rounded())) }
    func fill(_ x: Int, _ y: Int, _ w: Int = 1, _ h: Int = 1, _ col: Color) {
        let u = Self.unit
        c.ctx.fill(Path(CGRect(x: CGFloat(x) * u, y: CGFloat(y) * u, width: CGFloat(w) * u, height: CGFloat(h) * u)), with: .color(col))
    }
    func rgb(_ hex: UInt32) -> SkyPalette.RGB { c.rgb(hex) }
    /// 白天色 → 夜色按天黑程度过渡。
    func dn(_ day: UInt32, _ night: UInt32) -> SkyPalette.RGB { c.rgb(day).mix(c.rgb(0xC07A62), c.dusk * 0.12).mix(c.rgb(night), c.dark) }
    /// 夜里的灯：亮度跟着天黑程度淡入。
    func lit(_ col: Color, _ a: Double = 1) -> Color { col.opacity(a * min(1, max(0, (c.dark - 0.35) / 0.35))) }
}

// MARK: - 图层

extension SceneCanvas {
    /// 近景楼群的位置（避开地标的预留区）。楼群图层和霓虹招牌共用，保证招牌挂在楼上。
    var nearBuildings: [(x: Int, w: Int, h: Int)] {
        let reserved = Landmarks.of(env.location.skyline)?.reserved(self) ?? []
        var rng = SeededRandom(seed: 88)
        var out: [(x: Int, w: Int, h: Int)] = []
        var x = -2 + parallax(3)
        while x < cols + 2 {
            let w = 3 + Int(rng.next() % 4), h = tall(4 + Int(rng.next() % 8))
            if !reserved.contains(where: { $0.overlaps(x...(x + w)) }) { out.append((x, w, h)) }
            x += w + Int(rng.next() % 3)
        }
        return out
    }
}

struct FarCityLayer: SceneLayer {
    let id = "farCity"
    let stage = SceneStage.farCity
    func draw(_ c: SceneCanvas) {
        let base = c.cityBase
        let tone = c.sky.horizon.mix(c.rgb(0x6F7FA0), 0.45).mix(c.rgb(0x18203C), c.dark * 0.85).grey(c.overcast * 0.35)
        var rng = SeededRandom(seed: 2026)
        var x = -4 + c.parallax(1)
        while x < c.cols + 4 {
            let w = 3 + Int(rng.next() % 5), h = c.tall(5 + Int(rng.next() % 9))
            c.fill(x, base - h, w, h, tone.color)
            if c.dark > 0.5 {
                for wy in stride(from: base - h + 1, to: base - 1, by: 2) {
                    for wx in x..<(x + w) where rng.next() % 6 == 0 { c.fill(wx, wy, 1, 1, Color(red: 1, green: 0.86, blue: 0.6).opacity(0.45 * c.dark)) }
                }
            }
            x += w + Int(rng.next() % 2)
        }
    }
}

struct NearCityLayer: SceneLayer {
    let id = "nearCity"
    let stage = SceneStage.nearCity
    func draw(_ c: SceneCanvas) {
        let base = c.cityBase
        let pal = CityPalette(c)
        let landmark = Landmarks.of(c.env.location.skyline)
        var rng = SeededRandom(seed: 89)
        for b in c.nearBuildings { c.building(x: b.x, w: b.w, h: b.h, base: base, palette: pal, rng: &rng) }
        landmark?.draw(c, base: base, palette: pal)
    }
}

/// 海湾：从城市地平线到地面，倒映楼群灯光。
struct WaterLayer: SceneLayer {
    let id = "water"
    let stage = SceneStage.water
    func draw(_ c: SceneCanvas) {
        let y = c.cityBase, h = max(2, c.floorTop - c.cityBase)
        let water = c.sky.horizon.mix(c.rgb(0x2E5C7A), 0.5).mix(c.rgb(0x0B1530), c.dark * 0.8)
        for k in 0..<h { c.fill(0, y + k, c.cols, 1, water.mix(c.rgb(0x0A1424), Double(k) / Double(h) * 0.35).color) }
        var rng = SeededRandom(seed: 13)
        for _ in 0..<(c.cols / 5 * max(1, h / 2)) {
            let x = Int(rng.next() % UInt64(max(1, c.cols)))
            let row = Int(rng.next() % UInt64(h))
            let len = 1 + Int(rng.next() % 3)
            if (Int(c.t * 2) + x + row) % 5 != 0 {
                c.fill(x, y + row, len, 1, (c.dark > 0.5 ? Color(red: 1, green: 0.85, blue: 0.5) : Color.white).opacity(0.3 - Double(row) * 0.02))
            }
        }
    }
}

/// 刘海 = 隧道口：两侧混凝土洞口，刘海底边下方是贯穿全宽的高架桥；桥上跑的车由城市场景包决定。
struct MetroLayer: SceneLayer {
    let id = "metro"
    let stage = SceneStage.transit
    func draw(_ c: SceneCanvas) {
        guard c.notch.tunnel, c.notchRows > 6 else { return }
        let nc = c.notchCols, trackRow = c.notchRows - 1
        let concrete = c.rgb(0xB9BEC7).mix(c.rgb(0x3A4054), c.dark * 0.75)
        let concreteDark = concrete.mix(c.rgb(0x10131C), 0.35)
        let bridgeY = c.notchRows
        c.fill(0, bridgeY, c.cols, 1, concrete.color)
        c.fill(0, bridgeY + 1, c.cols, 1, concreteDark.color.opacity(0.8))
        for x in stride(from: 6 + c.parallax(3), to: c.cols, by: 22) where !nc.contains(x) {
            c.fill(x, bridgeY + 2, 2, max(0, c.cityBase - bridgeY - 2), concreteDark.color.opacity(0.85))
        }
        // 桥上跑什么由城市场景包决定（上海 / 新加坡是地铁，北京是长安街车流）
        CityPacks.of(c.env.location.skyline)?.elements.filter { $0.stage == .transit }.forEach { $0.draw(c) }
        for side in [nc.lowerBound - 2, nc.upperBound + 1] {
            c.fill(side, trackRow - 6, 2, 7, concrete.color)
            c.fill(side + (side < nc.lowerBound ? 1 : 0), trackRow - 5, 1, 6, concreteDark.color)
        }
        c.fill(nc.lowerBound - 3, trackRow - 7, 4, 1, concrete.color)
        c.fill(nc.upperBound, trackRow - 7, 4, 1, concrete.color)
    }
}
