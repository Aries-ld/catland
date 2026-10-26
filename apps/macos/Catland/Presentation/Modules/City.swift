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
    static let all: [Landmark] = [SingaporeLandmarks(), ShanghaiLandmarks()]
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

/// 上海：左翼东方明珠（两颗球 + 天线），右翼上海中心（扭转的高塔）与环球金融中心（「开瓶器」）。
struct ShanghaiLandmarks: Landmark {
    let skyline = Skyline.shanghai
    func reserved(_ c: SceneCanvas) -> [ClosedRange<Int>] { [(c.landmarkLeft + 2)...(c.landmarkLeft + 10), (c.landmarkRight - 4)...(c.landmarkRight + 9)] }

    func draw(_ c: SceneCanvas, base: Int, palette pal: CityPalette) {
        let pink = c.rgb(0xE0607E).mix(c.rgb(0x7A2E52), c.dark * 0.5)
        let glow = Color(red: 1, green: 0.45, blue: 0.7).opacity(0.85)
        let h = min(c.tall(18), base - c.skyTop - 2)
        let cx = c.landmarkLeft + 6
        c.fill(cx - 2, base - 3, 1, 3, pal.shade.color); c.fill(cx + 2, base - 3, 1, 3, pal.shade.color)
        c.fill(cx, base - h + 2, 1, h - 2, pal.body.color)
        let ball = c.dark > 0.5 ? glow : pink.color
        let top = base - h * 3 / 4
        c.fill(cx - 1, top - 2, 3, 1, ball); c.fill(cx - 2, top - 1, 5, 3, ball); c.fill(cx - 1, top + 2, 3, 1, ball)
        if c.dark <= 0.5 { c.fill(cx - 1, top - 1, 1, 1, pink.mix(c.rgb(0xFFFFFF), 0.35).color) }
        let low = base - h * 2 / 5
        c.fill(cx, low - 1, 1, 1, ball); c.fill(cx - 1, low, 3, 1, ball); c.fill(cx, low + 1, 1, 1, ball)
        c.fill(cx, base - h - 2, 1, 4, pal.body.mix(c.rgb(0xFFFFFF), 0.3).color)
        if c.dark > 0.5, Int(c.t * 2) % 2 == 0 { c.fill(cx, base - h - 2, 1, 1, .red) }

        let sx = c.landmarkRight - 3
        let th = min(c.tall(20), base - c.skyTop - 1)
        for k in 0..<th {
            let w = k < th / 3 ? 5 : (k < th * 2 / 3 ? 4 : 3)
            let y = base - 1 - k
            c.fill(sx + (5 - w) / 2, y, w, 1, pal.body.color)
            c.fill(sx + (5 - w) / 2 + (k / 3) % w, y, 1, 1, pal.windowDay.color.opacity(c.dark > 0.5 ? 0 : 0.8))
        }
        if c.dark > 0.5 { for k in stride(from: 1, to: th, by: 2) { c.fill(sx + 2, base - 1 - k, 1, 1, Color(red: 0.7, green: 0.9, blue: 1).opacity(0.7)) } }
        let wx = c.landmarkRight + 4, wh = min(16, th - 3)
        c.fill(wx, base - wh, 4, wh, pal.shade.mix(pal.body, 0.5).color)
        c.fill(wx + 1, base - wh + 1, 2, 2, c.dark > 0.5 ? Color(red: 0.6, green: 0.8, blue: 1).opacity(0.7) : c.rgb(0xBFD3E6).color)
        c.litWindows(x: wx, w: 4, top: base - wh + 4, bottom: base, seed: 777, palette: pal)
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
