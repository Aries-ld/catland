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
    static let all: [Landmark] = [SingaporeLandmarks(), ShanghaiLandmarks(), BeijingLandmarks()]
    static func of(_ s: Skyline) -> Landmark? { all.first { $0.skyline == s } }
}

/// 新加坡：左翼金沙酒店（三塔 + 顶上的船），右翼摩天轮（夜里灯光沿圆环流动变色）。
struct SingaporeLandmarks: Landmark {
    let skyline = Skyline.singapore
    func reserved(_ c: SceneCanvas) -> [ClosedRange<Int>] { [(c.landmarkLeft - 1)...(c.landmarkLeft + 13), (c.landmarkRight - 9)...(c.landmarkRight + 9)] }

    func draw(_ c: SceneCanvas, base: Int, palette pal: CityPalette) {
        let mbsX = c.landmarkLeft
        let mbsH = min(c.tall(14), base - c.skyTop - 3)
        for i in 0..<3 {
            let tx = mbsX + i * 4
            c.fill(tx, base - mbsH, 3, mbsH, pal.body.color); c.fill(tx + 2, base - mbsH, 1, mbsH, pal.shade.color)
            c.litWindows(x: tx, w: 3, top: base - mbsH + 2, bottom: base, seed: UInt64(500 + i), palette: pal)
        }
        let deck = pal.body.mix(c.rgb(0xFFFFFF), 0.2).color
        c.fill(mbsX - 1, base - mbsH - 1, 14, 1, deck); c.fill(mbsX + 11, base - mbsH - 2, 3, 1, deck)
        if c.dark > 0.5 { c.fill(mbsX, base - mbsH - 1, 12, 1, Color(red: 0.6, green: 0.8, blue: 1).opacity(0.6 * c.dark)) }

        let fx = c.landmarkRight
        let r = min(c.tall(6), max(3, (base - c.skyTop - 4) / 3))
        let cy = base - r - 3
        let ring = c.rgb(0xE8EDF2).mix(c.rgb(0x6A7798), c.dark * 0.6).color
        let shift = Int(c.t * 4)
        for (i, pt) in c.ringPoints(r).enumerated() {
            var col = ring
            if c.dark > 0.5 {
                let palette: [UInt32] = [0xFF6FB5, 0x6DD3FF, 0xB98CFF, 0xFFD84A]
                col = c.rgb(palette[((i + shift) / 3) % palette.count]).color.opacity(0.6 + 0.4 * c.dark)
            }
            c.fill(fx + pt.0, cy + pt.1, 1, 1, col)
        }
        let spoke = ring.opacity(0.45)
        for k in 1..<r { c.fill(fx + k, cy, 1, 1, spoke); c.fill(fx - k, cy, 1, 1, spoke); c.fill(fx, cy + k, 1, 1, spoke); c.fill(fx, cy - k, 1, 1, spoke) }
        for k in 0..<(base - cy) { c.fill(fx - 1 - k / 2, cy + k, 1, 1, pal.shade.color); c.fill(fx + 1 + k / 2, cy + k, 1, 1, pal.shade.color) }
    }
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

// MARK: - 上海：左翼东方明珠，右翼陆家嘴三件套

/// 上海：左翼东方明珠——细长塔身：三根斜撑托起大球，三根立柱（中间留缝）连到小球，再往上是太空舱和细长天线；
/// 球是立体着色（左上受光），夜里从里往外发出粉紫色的光、带一圈光晕。
/// 右翼陆家嘴三件套（从左到右、由后往前）：金茂（宝塔式逐层收进，夜里整栋金色泛光、每层下暗上亮）、
/// 环球金融中心（两侧往上收成刀锋、顶部梯形「开瓶器」镂空，夜里镂空一圈冷白光）、
/// 上海中心（圆润收分 + 沿扭转缝的一条线，夜里楼体暗、扭转缝是一条白色细光、顶冠发光）。
struct ShanghaiLandmarks: Landmark {
    let skyline = Skyline.shanghai
    func reserved(_ c: SceneCanvas) -> [ClosedRange<Int>] { [(c.markL - 7)...(c.markL + 7), (c.markR - 12)...(c.markR + 12)] }

    func draw(_ c: SceneCanvas, base: Int, palette pal: CityPalette) {
        let g = FineGrid(c: c)
        pearl(g, base: g.base(base))
        lujiazui(g, base: g.base(base))
    }

    /// 立体球：左上受光；夜里从中心往外发光。
    private func sphere(_ g: FineGrid, cx: Int, cy: Int, r: Int, breathe: Double) {
        let c = g.c
        let mid = g.dn(0xD64C78, 0x2A1220), hi = g.dn(0xF7B3C8, 0x40202E), lo = g.dn(0x9C2D52, 0x180A12)
        let glowA = c.dark > 0.35 ? min(1, (c.dark - 0.35) / 0.35) : 0
        if glowA > 0 { // 光晕
            for dy in -(r + 3)...(r + 3) { for dx in -(r + 3)...(r + 3) {
                let d = sqrt(Double(dx * dx + dy * dy))
                if d > Double(r) + 0.5 && d <= Double(r) + 3 { g.fill(cx + dx, cy + dy, 1, 1, Color(red: 1, green: 0.35, blue: 0.75).opacity(0.10 * glowA * (Double(r) + 3.5 - d) / 3)) }
            } }
        }
        for dy in -r...r { for dx in -r...r {
            let d2 = Double(dx * dx + dy * dy)
            guard d2 <= Double(r * r) + Double(r) * 0.6 else { continue }
            let shade = Double(-dx - dy) / Double(2 * r)
            var col = mid.mix(hi, max(0, shade) * 0.9).mix(lo, max(0, -shade) * 0.8)
            if dy == 0 || dy == 1 { col = col.mix(g.rgb(0xF4E6EE), 0.35 * (1 - c.dark)) } // 球上一圈玻璃窗带
            g.fill(cx + dx, cy + dy, 1, 1, col.color)
            if glowA > 0 {
                let k = 1 - sqrt(d2) / Double(r + 1)
                let night = g.rgb(0x8A1E6A).mix(g.rgb(0xFF5FB0), k).mix(g.rgb(0xFFE8F6), pow(k, 3) * 0.7 * breathe)
                g.fill(cx + dx, cy + dy, 1, 1, night.color.opacity(glowA))
                if dy == 0 { g.fill(cx + dx, cy + dy, 1, 1, Color.white.opacity(0.55 * glowA)) }
            }
        } }
    }

    private func pearl(_ g: FineGrid, base: Int) {
        let c = g.c
        let x = g.f(c.markL)
        let H = min(64, base - g.top)
        let rLow = H >= 50 ? 5 : (H >= 38 ? 4 : 3), rUp = H >= 50 ? 4 : (H >= 38 ? 3 : 2)
        let spread = g.sw(7, g.scale(forHeight: H), min: 4)
        let legH = Int(Double(H) * 0.13), antH = Int(Double(H) * 0.2)
        let colH = max(4, H - legH - (2 * rLow + 1) - (2 * rUp + 1) - 2 - 3 - antH + 2)
        let steel = g.dn(0xD2D9E2, 0x2A3042), steelDark = g.dn(0x96A2B3, 0x1C2030)
        let breathe = 0.75 + 0.25 * sin(c.t * 1.2)
        // 三根斜撑（左右两根往中间收，中间一根直立）
        let legTop = base - legH
        for k in 0..<legH {
            let dx = spread - (k * (spread - 2)) / max(1, legH - 1)
            g.fill(x - dx, base - 1 - k, 1, 1, steelDark.color); g.fill(x + dx, base - 1 - k, 1, 1, steelDark.color)
        }
        g.fill(x, legTop, 1, legH, steel.color)
        let lowY = legTop - rLow + 1
        // 三根立柱（中间留缝），夜里柱身一串柔和的白灯
        let colBottom = lowY - rLow, colTop = colBottom - colH
        for (i, cx) in [x - 2, x, x + 2].enumerated() {
            g.fill(cx, colTop, 1, colH, (i == 1 ? steel : steelDark).color)
            for k in stride(from: 1, to: colH, by: 3) { g.fill(cx, colBottom - k, 1, 1, g.lit(Color(red: 1, green: 0.9, blue: 0.97), 0.7)) }
        }
        sphere(g, cx: x, cy: lowY, r: rLow, breathe: breathe)
        let upY = colTop - rUp + 1
        sphere(g, cx: x, cy: upY, r: rUp, breathe: breathe)
        // 短柱 + 太空舱 + 天线
        let capTop = upY - rUp - 2
        g.fill(x - 1, capTop, 1, 2, steelDark.color); g.fill(x + 1, capTop, 1, 2, steelDark.color)
        g.fill(x - 1, capTop - 2, 3, 2, g.dn(0xD64C78, 0x2A1220).color)
        g.fill(x - 1, capTop - 2, 3, 2, g.lit(Color(red: 1, green: 0.7, blue: 0.9)))
        g.fill(x, capTop - 2 - antH, 1, antH, g.dn(0xEEF2F6, 0x40465C).color)
        if c.dark > 0.5, Int(c.t * 1.5) % 2 == 0 { g.fill(x, capTop - 3 - antH, 1, 1, Color(red: 1, green: 0.2, blue: 0.2)) }
    }

    private func lujiazui(_ g: FineGrid, base: Int) {
        let c = g.c
        let R = g.f(c.markR)
        let H = min(58, base - g.top)
        let k = g.scale(forHeight: H)
        jinMao(g, cx: R - g.sw(11, k), base: base, h: Int(Double(H) * 0.68), s: k)
        swfc(g, cx: R - 1, base: base, h: Int(Double(H) * 0.82), s: k)
        shanghaiTower(g, cx: R + g.sw(10, k), base: base, h: H, s: k)
    }

    /// 金茂：13 层宝塔式收进，每段顶部一道外挑的檐；顶上小冠 + 细尖顶。夜里整栋金色泛光，每段下暗上亮。
    private func jinMao(_ g: FineGrid, cx: Int, base: Int, h: Int, s: Double) {
        let c = g.c
        let bodyH = Int(Double(h) * 0.82)
        var y = base, w = g.sw(9, s, min: 6)
        let segs = [0.30, 0.18, 0.13, 0.10, 0.08, 0.07, 0.06, 0.05, 0.03]
        for f in segs {
            let sh = max(2, Int(Double(bodyH) * f))
            for k in 0..<sh {
                let frac = Double(k) / Double(max(1, sh - 1))
                let day = g.dn(0x625C54, 0x1E1C22).mix(g.rgb(0x8A8478), (1 - c.dark) * 0.25 * frac)
                g.fill(cx - w / 2, y - 1 - k, w, 1, day.color)
                g.fill(cx - w / 2, y - 1 - k, 1, 1, day.mix(g.rgb(0xFFFFFF), 0.18 * (1 - c.dark)).color)
                g.fill(cx - w / 2, y - 1 - k, w, 1, g.lit(g.rgb(0x7A4E14).mix(g.rgb(0xFFC85A), 0.35 + 0.65 * frac).color, 0.95))
            }
            y -= sh
            g.fill(cx - w / 2 - 1, y, w + 2, 1, g.dn(0xC2BCB0, 0x2A2830).color) // 外挑的檐
            g.fill(cx - w / 2 - 1, y, w + 2, 1, g.lit(Color(red: 1, green: 0.9, blue: 0.62)))
            w = max(3, w - 1)
        }
        // 小冠 + 尖顶
        g.fill(cx - 1, y - 3, 3, 3, g.dn(0x8A8478, 0x22202A).color)
        g.fill(cx - 1, y - 3, 3, 3, g.lit(Color(red: 1, green: 0.85, blue: 0.5)))
        g.fill(cx, y - 3 - (h - bodyH), 1, h - bodyH, g.dn(0xD8D2C6, 0x3A3640).color)
        g.fill(cx, y - 3 - (h - bodyH), 1, h - bodyH, g.lit(Color(red: 1, green: 0.93, blue: 0.75), 0.9))
    }

    /// 环球金融中心：方形底座，两侧往上收成刀锋，顶部梯形「开瓶器」镂空；左面受光。夜里楼体暗，镂空一圈冷白光，两侧棱线淡淡的光。
    private func swfc(_ g: FineGrid, cx: Int, base: Int, h: Int, s: Double) {
        let c = g.c
        let top = base - h
        for k in 0..<h {
            let r = Double(k) / Double(h)
            let w = max(5, Int(((9 - 3 * r) * s).rounded()))
            let x0 = cx - w / 2
            let light = g.dn(0xA9BCCD, 0x1C2636), dark = g.dn(0x7D93AA, 0x141C2A)
            g.fill(x0, base - 1 - k, w / 2, 1, light.color)
            g.fill(x0 + w / 2, base - 1 - k, w - w / 2, 1, dark.color)
            if k % 2 == 0 { g.fill(x0 + 1, base - 1 - k, w - 2, 1, light.mix(g.rgb(0xFFFFFF), 0.12 * (1 - c.dark)).color.opacity(0.5)) }
            // 夜里两侧棱线
            g.fill(x0, base - 1 - k, 1, 1, g.lit(Color(red: 0.75, green: 0.88, blue: 1), 0.35 + 0.4 * r))
            g.fill(x0 + w - 1, base - 1 - k, 1, 1, g.lit(Color(red: 0.75, green: 0.88, blue: 1), 0.25 + 0.4 * r))
        }
        // 「开瓶器」：顶部下方 2 行起，梯形镂空（上宽下窄），露出后面的天空
        let hole: [(Int, Int)] = s < 0.8 ? [(top + 2, 3), (top + 3, 3), (top + 4, 2), (top + 5, 1)] : [(top + 2, 4), (top + 3, 4), (top + 4, 3), (top + 5, 2)]
        let sky = c.sky.top.mix(c.sky.horizon, 0.3).color
        for (y, w) in hole { g.fill(cx - w / 2, y, w, 1, sky) }
        // 夜里：镂空一圈冷白光 + 顶边
        let ring = Color(red: 0.82, green: 0.93, blue: 1)
        for (y, w) in hole { g.fill(cx - w / 2 - 1, y, 1, 1, g.lit(ring)); g.fill(cx - w / 2 + w, y, 1, 1, g.lit(ring)) }
        g.fill(cx - 2, top + 1, 4, 1, g.lit(ring)); g.fill(cx - 1, top + 6, 2, 1, g.lit(ring))
        g.fill(cx - 3, top, 6, 1, g.lit(ring, 0.8))
    }

    /// 上海中心：圆润收分（不是三角形）+ 一条从右下绕到左上的扭转缝，顶冠略向一侧斜切。
    /// 夜里楼体暗，扭转缝是一条白色细光，零星窗灯，顶冠一圈白光。
    private func shanghaiTower(_ g: FineGrid, cx: Int, base: Int, h: Int, s: Double) {
        let c = g.c
        for k in 0..<h {
            let r = Double(k) / Double(h)
            let w = max(4, Int(((r < 0.12 ? 11 : 11 - 4.5 * pow((r - 0.12) / 0.88, 1.15)) * s).rounded()))
            let x0 = cx - w / 2
            let y = base - 1 - k
            for i in 0..<w {
                let t = Double(i) / Double(max(1, w - 1))
                let col = g.dn(0x9CC0CF, 0x13202A).mix(g.dn(0x5E8698, 0x0C161E), t)
                g.fill(x0 + i, y, 1, 1, col.color)
            }
            // 扭转缝：从右下绕到左上
            let notch = x0 + Int(Double(w - 1) * (1 - r))
            g.fill(notch, y, 1, 1, g.dn(0x3F6273, 0x0A1218).color)
            g.fill(notch, y, 1, 1, g.lit(Color(red: 0.92, green: 0.97, blue: 1), 0.95))
            if k % 3 == 1 { g.fill(x0 + (k * 7) % max(1, w), y, 1, 1, g.lit(Color(red: 0.85, green: 0.92, blue: 1), 0.35)) }
        }
        // 顶冠：向一侧斜切，夜里发光
        let topY = base - h, tw = max(4, Int((6 * s).rounded()))
        g.fill(cx - tw / 2, topY - 1, tw - 1, 1, g.dn(0x9CC0CF, 0x13202A).color)
        g.fill(cx - tw / 2, topY - 2, max(2, tw / 2), 1, g.dn(0x9CC0CF, 0x13202A).color)
        for (dy, w) in [(-2, max(2, tw / 2)), (-1, tw - 1), (0, tw)] { g.fill(cx - tw / 2, topY + dy, w, 1, g.lit(Color(red: 0.85, green: 0.94, blue: 1), 0.85)) }
    }
}

// MARK: - 北京：左翼天坛祈年殿（古），右翼 CBD 央视大楼 + 中国尊（今）

/// 北京：左翼天坛祈年殿（三层汉白玉台基、红柱圆殿、三重蓝色攒尖顶、金顶，宽而不高，不会被拉成宝塔），夜里金色泛光；
/// 右翼 CBD：央视大楼（「大裤衩」：两座斜塔在底部裙楼和顶部悬挑处连成中空的环，立面斜网格）+ 中国尊（上下宽、腰身收、顶部外扩的「尊」形）。
/// 夜里央视大楼网格亮暖灯，中国尊尊口一圈白金色光、立面灯光往上流动。
struct BeijingLandmarks: Landmark {
    let skyline = Skyline.beijing
    func reserved(_ c: SceneCanvas) -> [ClosedRange<Int>] { [(c.markL - 11)...(c.markL + 11), (c.markR - 13)...(c.markR + 11)] }

    /// 三重圆伞形屋顶（亮色顶面 + 深色檐口线、檐角微翘），层间是红色鼓座，下面红柱圆殿和三层汉白玉台基。宽而矮，不会像宝塔。
    static let temple = PixelSprite(rows: [
        "          G          ",
        "         YGY         ",
        "        bBBBb        ",
        "      dDDDDDDDd      ",
        "        RYRYR        ",
        "       bBBBBBb       ",
        "      bBBBBBBBb      ",
        "    dDDDDDDDDDDDd    ",
        "      RYRYRYRYR      ",
        "     bBBBBBBBBBb     ",
        "    bBBBBBBBBBBBb    ",
        "  dDDDDDDDDDDDDDDDd  ",
        "    RrRrRrRrRrRrR    ",
        " WWWWWWWWWWWWWWWWWWW ",
        "WMWMWMWMWMWMWMWMWMWMW",
        "WWWWWWWWWWWWWWWWWWWWW",
    ])

    /// 央视大楼按「大裤衩」画：顶上一条粗腰带（悬挑），两条腿向外叉开，中间是空的，底部一条裙楼把环收住；右边是中国尊。

    func draw(_ c: SceneCanvas, base: Int, palette pal: CityPalette) {
        let night = c.night
        let warm = Color(red: 1, green: 0.8, blue: 0.42)
        // 祈年殿：夜里打金色泛光，保留本色
        Self.temple.draw(c, centerX: c.markL, base: base, color: { ch, _, _, _ in
            switch ch {
            case "G": return warm
            case "B": return night ? c.rgb(0x3E66BE).color : c.dayNight(0x2F5AAE, 0x1A2A50)
            case "b": return night ? c.rgb(0x7A9CE0).color : c.dayNight(0x6E92D8, 0x24386A)   // 屋顶受光的一侧
            case "D": return night ? c.rgb(0x1C3264).color : c.dayNight(0x1A2F5E, 0x0E1630)   // 檐口深色线
            case "d": return night ? warm : c.dayNight(0xE0B04A, 0x3A2E14)                    // 微翘的檐角（金色）
            case "R": return night ? c.rgb(0xE0573A).color : c.dayNight(0xB8322A, 0x3E1616)
            case "r": return night ? c.rgb(0xFFB070).color : c.dayNight(0x8A2420, 0x2A1010)
            case "Y": return night ? warm : c.dayNight(0xE0B04A, 0x4A3A1A)
            case "W": return night ? c.rgb(0xF4E2BC).color : c.dayNight(0xEDEBE4, 0x4A5068)
            case "w": return night ? c.rgb(0xD8C49C).color : c.dayNight(0xCFCBC0, 0x3A3F54)
            case "M": return night ? c.rgb(0xFFF0D0).color : c.dayNight(0xFFFFFF, 0x50566E)
            default: return nil
            }
        }, glow: { ch, edge in night && edge ? warm.opacity(0.16) : nil })

        // CBD（细网格）：央视大楼 + 中国尊
        let g = FineGrid(c: c), fb = g.base(base), R = g.f(c.markR)
        let H = min(58, fb - g.top), k = g.scale(forHeight: H)
        cctv(g, cx: R - g.sw(7, k), base: fb, h: Int(Double(H) * 0.62), s: k)
        zun(g, cx: R + g.sw(10, k), base: fb, h: H, s: k)
    }

    /// 央视大楼：两座粗壮的塔楼（略向内倾）在底部裙楼和顶部 L 形悬挑处连成环，中间的洞不大；悬挑向右伸出、末端下折。
    /// 白天是银灰玻璃 + 一组方向的深色斜撑（不规则的菱形网格，不是棋盘）；
    /// 夜里楼体深灰，只有斜撑交点亮起稀疏的银白小点，楼体边缘一圈很淡的轮廓光——柔和、不碎。
    private func cctv(_ g: FineGrid, cx: Int, base: Int, h: Int, s: Double) {
        let c = g.c
        let W = g.sw(20, s, min: 13), legW = g.sw(7, s, min: 4), x0 = cx - W / 2 - 1
        let bandH = max(5, h / 4), podH = max(3, h / 6)
        var solid = Set<Int>()
        func key(_ x: Int, _ y: Int) -> Int { x * 10_000 + y }
        for k in 0..<h {
            let y = base - 1 - k
            if k < podH { for i in 0..<W { solid.insert(key(x0 + i, y)) }; continue }               // 底部裙楼
            if k >= h - bandH { for i in 2..<(W + 3) { solid.insert(key(x0 + i, y)) }; continue } // 顶部悬挑，向右多伸出 3 格
            let lean = (k - podH) * 2 / max(1, h - podH - bandH)
            for i in 0..<legW { solid.insert(key(x0 + lean + i, y)) }                           // 左塔，向右内倾
            for i in 0..<legW { solid.insert(key(x0 + W - legW - lean + i, y)) }                // 右塔，向左内倾
        }
        for k in 0..<4 { for i in W..<(W + 3) { solid.insert(key(x0 + i, base - h + bandH + k)) } } // 悬挑末端下折
        let glass = g.dn(0x8E9BAC, 0x1C222E), glassDark = g.dn(0x6E7B8E, 0x151A24), brace = g.dn(0x4A5466, 0x141820)
        for kk in solid {
            let x = kk / 10_000, y = kk % 10_000
            let edge = [(-1, 0), (1, 0), (0, -1), (0, 1)].contains { !solid.contains(key(x + $0.0, y + $0.1)) }
            let braceA = (x + y) % 6 == 0, braceB = (x - y + 600) % 9 == 0
            var col = (x - x0) < W / 2 + 1 ? glass : glassDark
            if braceA || braceB { col = col.mix(brace, 0.55) }
            g.fill(x, y, 1, 1, col.color)
            if braceA && braceB { g.fill(x, y, 1, 1, g.lit(Color(red: 0.88, green: 0.92, blue: 1), 0.9)) }   // 夜里：斜撑交点的小灯
            else if braceA { g.fill(x, y, 1, 1, g.lit(Color(red: 0.75, green: 0.82, blue: 0.95), 0.12)) }
            if edge { g.fill(x, y, 1, 1, g.lit(Color(red: 0.8, green: 0.86, blue: 1), 0.28)) }               // 夜里：很淡的轮廓光
        }
    }

    /// 中国尊：立面像古代礼器「尊」——底部略外撇，往上收到约六成高度的腰部，再向上放大，顶部平展、略窄于底部。
    /// 白天是浅蓝灰玻璃 + 很淡的楼层横线；夜里楼体暗，两侧棱线和正中的转角线是三条白色细光（真实的竖向轮廓照明），
    /// 零星暖色窗灯，顶冠一圈白光 + 航标灯。
    private func zun(_ g: FineGrid, cx: Int, base: Int, h: Int, s: Double) {
        let c = g.c
        var rng = SeededRandom(seed: 77)
        for k in 0..<h {
            let r = Double(k) / Double(h)
            let wd: Double = r < 0.04 ? 12 : (r < 0.6 ? 12 - 3.5 * pow((r - 0.04) / 0.56, 0.9) : (r < 0.97 ? 8.5 + 2.5 * pow((r - 0.6) / 0.37, 1.4) : 11.5))
            let w = max(5, Int((wd * s).rounded())), x0 = cx - w / 2, y = base - 1 - k
            for i in 0..<w {
                let t = Double(i) / Double(max(1, w - 1))
                var col = g.dn(0xA8BBCF, 0x141A26).mix(g.dn(0x7488A0, 0x0E131C), t)
                if k % 3 == 0 { col = col.mix(g.rgb(0x5A6A80), 0.18 * (1 - c.dark)) }   // 楼层横线
                g.fill(x0 + i, y, 1, 1, col.color)
            }
            // 夜里：两侧棱线 + 正中转角线
            let line = Color(red: 0.96, green: 0.95, blue: 0.9)
            g.fill(x0, y, 1, 1, g.lit(line, 0.55 + 0.35 * r))
            g.fill(x0 + w - 1, y, 1, 1, g.lit(line, 0.45 + 0.35 * r))
            g.fill(cx, y, 1, 1, g.lit(line, 0.35 + 0.45 * r))
            // 零星暖色窗灯
            if k % 2 == 1, rng.next() % 100 < 22 { g.fill(x0 + 1 + Int(rng.next() % UInt64(max(1, w - 2))), y, 1, 1, g.lit(Color(red: 1, green: 0.82, blue: 0.5), 0.5)) }
        }
        let topY = base - h, cw = g.sw(12, s, min: 7)
        g.fill(cx - cw / 2, topY - 1, cw, 1, g.dn(0xC2CEDA, 0x202838).color)
        g.fill(cx - cw / 2, topY - 1, cw, 1, g.lit(Color(red: 1, green: 0.97, blue: 0.9)))
        for dx in 0..<cw { g.fill(cx - cw / 2 + dx, topY - 2, 1, 1, g.lit(Color(red: 1, green: 0.97, blue: 0.9), 0.18)) }
        if c.dark > 0.5, Int(c.t * 1.5) % 2 == 0 { g.fill(cx, topY - 3, 1, 1, Color(red: 1, green: 0.2, blue: 0.2)) }
    }
}

// MARK: - 图层

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
        let reserved = landmark?.reserved(c) ?? []
        var rng = SeededRandom(seed: 88)
        var x = -2 + c.parallax(3)
        while x < c.cols + 2 {
            let w = 3 + Int(rng.next() % 4), h = c.tall(4 + Int(rng.next() % 8))
            if !reserved.contains(where: { $0.overlaps(x...(x + w)) }) { c.building(x: x, w: w, h: h, base: base, palette: pal, rng: &rng) }
            x += w + Int(rng.next() % 3)
        }
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

/// 刘海 = 隧道口：两侧混凝土洞口，刘海底边下方是贯穿全宽的高架桥；MRT 小列车每 50 秒穿过一次。
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
        let period = 50.0, run = 7.0
        let n = Int(c.t / period), local = c.t.truncatingRemainder(dividingBy: period)
        if local < run {
            let leftToRight = n % 2 == 0
            let cars = 3, carW = 12, gap = 1
            let trainW = cars * carW + (cars - 1) * gap
            let prog = local / run
            let x0 = leftToRight ? Int(Double(c.cols + trainW) * prog) - trainW : c.cols - Int(Double(c.cols + trainW) * prog)
            let top = trackRow - 4
            let shell = c.rgb(0xF2F4F7).mix(c.rgb(0x8A93A8), c.dark * 0.6)
            let window = c.dark > 0.5 ? Color(red: 1, green: 0.86, blue: 0.55) : c.rgb(0x2A3346).color
            for k in 0..<cars {
                let cx = x0 + k * (carW + gap)
                c.fill(cx, top, carW, 4, shell.color)
                c.fill(cx, top + 2, carW, 1, c.rgb(0xE5322D).color)
                for wx in stride(from: cx + 1, to: cx + carW - 1, by: 3) { c.fill(wx, top + 1, 2, 1, window) }
                c.fill(cx, top + 4, carW, 1, concreteDark.color)
            }
            let head = leftToRight ? x0 + trainW : x0 - 1
            c.fill(head, top + 2, 1, 1, Color(red: 1, green: 0.95, blue: 0.7).opacity(c.dark > 0.4 ? 1 : 0.7))
            if c.dark > 0.4 { c.fill(leftToRight ? head + 1 : head - 4, top + 2, 4, 1, Color(red: 1, green: 0.95, blue: 0.7).opacity(0.25)) }
        }
        for side in [nc.lowerBound - 2, nc.upperBound + 1] {
            c.fill(side, trackRow - 6, 2, 7, concrete.color)
            c.fill(side + (side < nc.lowerBound ? 1 : 0), trackRow - 5, 1, 6, concreteDark.color)
        }
        c.fill(nc.lowerBound - 3, trackRow - 7, 4, 1, concrete.color)
        c.fill(nc.upperBound, trackRow - 7, 4, 1, concrete.color)
    }
}
