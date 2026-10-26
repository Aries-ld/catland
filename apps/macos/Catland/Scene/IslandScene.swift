// IslandScene：把刘海收起态本身画成一面小落地窗（手绘像素，与小猫同一像素网格 1.5pt）。
// 刘海很长但很矮，所以不放家具，只靠分层营造都市景深：
//   天空（按太阳高度）→ 日月星 → 云 → 远景楼群（雾化）→ 近景楼群 + 地标（左翼金沙、右翼摩天轮）→ 海湾水面
//   → 雨 / 雾霾 / 闪电 / 夜航飞机 / 白天飞鸟 / 节日烟花 → 窗框（物理刘海当作窗上横梁）→ 玻璃反光 → 地板（小猫在上面）
// 时间、天气与所在地一致：太阳位置按新加坡经纬度本地计算，天气来自 NEA；鼠标移动时远近两层有轻微视差。
import SwiftUI

struct IslandScene: View {
    let state: AppState

    /// 地板厚度（美术像素）。小猫站在地板上，CatStage 底部留出这么多空间。
    static let floorRows = 3
    static var floorInset: CGFloat { 0 }

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15)) { tl in
            Canvas { ctx, size in
                let p = max(1, (1.5 * displayScale).rounded()) / max(displayScale, 1)
                var r = IslandRenderer(ctx: ctx, size: size, p: p, env: state.sceneEnv(now: tl.date),
                                       notch: state.notch, t: tl.date.timeIntervalSinceReferenceDate)
                r.draw()
            }
        }
        .allowsHitTesting(false)
    }

    static func weatherName(_ c: String) -> String {
        ["clear": "晴", "partly": "少云", "cloudy": "多云", "haze": "霾", "rain": "雨", "thunder": "雷雨", "windy": "有风"][c] ?? c
    }
}

/// 逐「美术像素」绘制。坐标单位都是像素格，(0,0) 为左上角。
struct IslandRenderer {
    var ctx: GraphicsContext
    let size: CGSize
    let p: CGFloat
    let env: SceneEnv
    let notch: NotchGeometry
    let t: TimeInterval

    // 画布尺寸（像素格）
    var cols: Int { Int(size.width / p) }
    var rows: Int { Int(size.height / p) }
    var floorTop: Int { rows - IslandScene.floorRows }
    /// 物理刘海在画布里占的列与行（看不见的区域）。
    var notchCols: ClosedRange<Int> {
        let w = Int((notch.notchSize.width / p).rounded())
        let left = (cols - w) / 2
        return left...(left + w - 1)
    }
    var notchRows: Int { notch.hasNotch ? Int((notch.notchSize.height / p).rounded()) : 0 }
    /// 天花板模式：顶部整条与刘海同为黑色天花板，刘海「融进」天花板；窗户从天花板下沿开始。
    var ceilingMode: Bool { notch.ceiling && notchRows > 0 }
    /// 窗户可见区域的最上一行。
    var skyTop: Int { ceilingMode ? notchRows + 1 : 0 }

    // 场景参数
    private var sun: SunPosition { SceneClock.sun(at: env.date) }
    private var dark: Double { SceneClock.darkness(sun) }
    private var dusk: Double { SceneClock.twilight(sun) }
    private var cond: String { env.condition }
    private var overcast: Double { ["cloudy": 0.55, "rain": 0.8, "thunder": 0.95, "haze": 0.45, "partly": 0.15, "windy": 0.2][cond] ?? 0 }
    private var raining: Bool { cond == "rain" || cond == "thunder" }

    mutating func draw() {
        let sky = SkyPalette.stops(darkness: dark, twilight: dusk, overcast: overcast)
        drawSky(sky)
        drawCelestial(sky)
        drawClouds()
        drawFlyers()
        drawFireworks()
        drawFarCity(sky)
        drawNearCity()
        drawWater(sky)
        drawMetro()
        drawWeather()
        drawFrame()
        drawCeiling()
        drawFloor()
    }

    // MARK: - 基础

    private func fill(_ x: Int, _ y: Int, _ w: Int = 1, _ h: Int = 1, _ c: Color) {
        ctx.fill(Path(CGRect(x: CGFloat(x) * p, y: CGFloat(y) * p, width: CGFloat(w) * p, height: CGFloat(h) * p)), with: .color(c))
    }

    private func rgb(_ hex: UInt32) -> SkyPalette.RGB { .hex(hex) }

    /// 视差：远景层随鼠标移动 depth 个像素。
    private func parallax(_ depth: Double) -> Int { Int((Double(env.mouse) * -depth).rounded()) }

    // MARK: - 天空

    private func drawSky(_ s: SkyPalette.Stops) {
        let horizon = floorTop - 2
        for y in 0..<horizon {
            let k = Double(y) / Double(max(1, horizon - 1))
            fill(0, y, cols, 1, s.top.mix(s.horizon, k * k).color)
        }
    }

    private func drawCelestial(_ s: SkyPalette.Stops) {
        let horizon = floorTop - 2
        if dark < 0.85, overcast < 0.85 {
            // 太阳：东升（左）西落（右），高度映射到天空纵向；晨昏变橙。
            let x = Int(Double(cols) * min(1, max(0, (sun.azimuth - 60) / 240)))
            let y = horizon - 3 - Int(Double(max(1, horizon - skyTop - 6)) * min(1, max(0, sun.altitude / 50)))
            let core = rgb(0xFFF1B8).mix(rgb(0xFF9A55), dusk).color.opacity(1 - overcast * 0.7)
            fill(x - 1, y - 2, 3, 5, core); fill(x - 2, y - 1, 5, 3, core)
            fill(x - 3, y - 3, 7, 7, core.opacity(0.18))
        }
        if dark > 0.55 {
            let a = (dark - 0.55) / 0.45 * (1 - overcast)
            var rng = SeededRandom(seed: 7)
            for _ in 0..<40 {
                let x = Int(rng.next() % UInt64(max(1, cols))), y = skyTop + Int(rng.next() % UInt64(max(1, horizon - skyTop - 8)))
                let tw = 0.5 + 0.5 * sin(t * (0.8 + Double(rng.next() % 7) * 0.3) + Double(x))
                fill(x, y, 1, 1, Color.white.opacity(a * tw))
            }
            // 月亮（新月形），夜里从左慢慢移到右。
            let h = Double(Calendar.current.component(.hour, from: env.date)) + Double(Calendar.current.component(.minute, from: env.date)) / 60
            let prog = min(1, max(0, ((h - 19 + 24).truncatingRemainder(dividingBy: 24)) / 11))
            let mx = Int(Double(cols - 6) * prog) + 2, my = skyTop + 2
            let moon = rgb(0xF4F1DE).color.opacity(min(1, a + 0.3))
            fill(mx, my, 3, 4, moon); fill(mx - 1, my + 1, 1, 2, moon); fill(mx + 3, my + 1, 1, 2, moon)
            fill(mx + 1, my, 3, 3, s.top.color.opacity(min(1, a + 0.3)))
        }
    }

    private func drawClouds() {
        let count = ["clear": 1, "partly": 3, "windy": 4, "cloudy": 5, "haze": 3, "rain": 6, "thunder": 6][cond] ?? 2
        let tone = rgb(0xFFFFFF).mix(rgb(0x5C6475), overcast).mix(rgb(0x1E2742), dark * 0.85).mix(rgb(0xF6A27C), dusk * 0.4)
        var rng = SeededRandom(seed: 42)
        let speed = cond == "windy" ? 3.0 : 0.6
        for i in 0..<count {
            let w = 10 + Int(rng.next() % 12), y = skyTop + 1 + Int(rng.next() % UInt64(max(1, (floorTop - skyTop) / 3)))
            let span = Double(cols + w * 2)
            let x = Int((Double(rng.next() % 500) + t * speed * (0.6 + Double(i % 3) * 0.35)).truncatingRemainder(dividingBy: span)) - w
            let c = tone.color.opacity(0.55 + overcast * 0.4)
            fill(x, y + 2, w, 2, c); fill(x + w / 5, y + 1, w / 2, 1, c); fill(x + w / 3, y, w / 3, 1, c); fill(x + w * 3 / 5, y + 1, w / 3, 1, c)
        }
    }

    /// 白天偶尔飞过一只鸟，夜里飞机闪着红灯划过（约每 40 秒一次）。
    private func drawFlyers() {
        let period = 40.0, phase = t.truncatingRemainder(dividingBy: period) / 12
        guard phase < 1, !raining else { return }
        let x = Int(Double(cols + 10) * phase) - 5, y = skyTop + 2 + Int(t / period) % 4
        if dark > 0.5 {
            fill(x, y, 3, 1, Color(white: 0.55))
            if Int(t * 2) % 2 == 0 { fill(x + 3, y, 1, 1, .red) }
        } else {
            let flap = Int(t * 6) % 2 == 0
            let c = Color(white: 0.2).opacity(0.8)
            fill(x, y + (flap ? 0 : 1), 1, 1, c); fill(x + 1, y + 1, 1, 1, c); fill(x + 2, y + (flap ? 0 : 1), 1, 1, c)
        }
    }

    /// 彩蛋：元旦、国庆（8/9）夜里窗外放烟花。
    private func drawFireworks() {
        let cal = Calendar.current
        let m = cal.component(.month, from: env.date), d = cal.component(.day, from: env.date)
        guard dark > 0.7, !raining, (m == 1 && d == 1) || (m == 8 && d == 9) || (m == 12 && d == 31) else { return }
        for k in 0..<2 {
            let cycle = 3.2, local = (t + Double(k) * 1.6).truncatingRemainder(dividingBy: cycle)
            let n = Int((t + Double(k) * 1.6) / cycle)
            var rng = SeededRandom(seed: UInt64(n * 31 + k))
            let cx = 6 + Int(rng.next() % UInt64(max(1, cols - 12))), cy = skyTop + 3 + Int(rng.next() % 4)
            let colors: [UInt32] = [0xFF5D7A, 0xFFD84A, 0x6DD3FF, 0xB98CFF]
            let c = rgb(colors[Int(rng.next() % 4)]).color
            if local < 0.6 { fill(cx, floorTop - 3 - Int(Double(floorTop - 3 - cy) * local / 0.6), 1, 1, c) }
            else if local < 2.2 {
                let r = Int((local - 0.6) * 4) + 1, a = 1 - (local - 0.6) / 1.6
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)] {
                    fill(cx + dx * r, cy + dy * r, 1, 1, c.opacity(a))
                }
            }
        }
    }

    // MARK: - 城市

    private func drawFarCity(_ s: SkyPalette.Stops) {
        let base = floorTop - 2
        let tone = s.horizon.mix(rgb(0x6F7FA0), 0.45).mix(rgb(0x18203C), dark * 0.85).grey(overcast * 0.35)
        var rng = SeededRandom(seed: 2026)
        var x = -4 + parallax(1)
        while x < cols + 4 {
            let w = 3 + Int(rng.next() % 5), h = 5 + Int(rng.next() % 9)
            fill(x, base - h, w, h, tone.color)
            if dark > 0.5 {
                for wy in stride(from: base - h + 1, to: base - 1, by: 2) {
                    for wx in x..<(x + w) where rng.next() % 6 == 0 { fill(wx, wy, 1, 1, Color(red: 1, green: 0.86, blue: 0.6).opacity(0.45 * dark)) }
                }
            }
            x += w + Int(rng.next() % 2)
        }
    }

    private func drawNearCity() {
        let base = floorTop - 2
        let body = rgb(0x8EA4BC).mix(rgb(0x26304F), dark).mix(rgb(0xC98A6E), dusk * 0.25).grey(overcast * 0.25)
        let shade = body.mix(rgb(0x0E1426), 0.25)
        let windowDay = body.mix(rgb(0xE6F0FA), 0.35)
        let off = parallax(3)
        let nc = notchCols
        let leftWing = 0..<nc.lowerBound, rightWing = (nc.upperBound + 1)..<cols

        // 普通高楼：避开地标所在位置，两翼与刘海下方都铺满。
        var rng = SeededRandom(seed: 88)
        var x = -2 + off
        let mbsX = leftWing.lowerBound + max(1, leftWing.count / 2 - 6) + off
        let flyerX = rightWing.lowerBound + rightWing.count / 2 + off
        while x < cols + 2 {
            let w = 3 + Int(rng.next() % 4), h = 4 + Int(rng.next() % 8)
            let skip = (x + w > mbsX - 1 && x < mbsX + 13) || (x + w > flyerX - 9 && x < flyerX + 9)
            if !skip { building(x: x, w: w, h: h, base: base, body: body, shade: shade, windowDay: windowDay, rng: &rng) }
            x += w + Int(rng.next() % 3)
        }

        // 金沙酒店（左翼）：三栋塔楼 + 顶上的「船」。
        let mbsH = min(14, base - skyTop - 3)
        for i in 0..<3 {
            let tx = mbsX + i * 4
            fill(tx, base - mbsH, 3, mbsH, body.color); fill(tx + 2, base - mbsH, 1, mbsH, shade.color)
            litWindows(x: tx, w: 3, top: base - mbsH + 2, bottom: base, seed: UInt64(500 + i), windowDay: windowDay)
        }
        let deck = (body.mix(rgb(0xFFFFFF), 0.2)).color
        fill(mbsX - 1, base - mbsH - 1, 14, 1, deck); fill(mbsX + 11, base - mbsH - 2, 3, 1, deck)
        if dark > 0.5 { fill(mbsX, base - mbsH - 1, 12, 1, Color(red: 0.6, green: 0.8, blue: 1).opacity(0.6 * dark)) }

        // 摩天轮（右翼）：像素圆环 + 辐条 + 支架；夜里灯光沿圆环流动变色。
        let r = min(6, max(3, (base - skyTop - 4) / 3))
        let cy = base - r - 3
        let ring = rgb(0xE8EDF2).mix(rgb(0x6A7798), dark * 0.6).color
        let points = ringPoints(r)
        let cycleShift = Int(t * 4)
        for (i, pt) in points.enumerated() {
            var c = ring
            if dark > 0.5 {
                let palette: [UInt32] = [0xFF6FB5, 0x6DD3FF, 0xB98CFF, 0xFFD84A]
                c = rgb(palette[((i + cycleShift) / 3) % palette.count]).color.opacity(0.6 + 0.4 * dark)
            }
            fill(flyerX + pt.0, cy + pt.1, 1, 1, c)
        }
        let spoke = ring.opacity(0.45)
        for k in 1..<r { fill(flyerX + k, cy, 1, 1, spoke); fill(flyerX - k, cy, 1, 1, spoke); fill(flyerX, cy + k, 1, 1, spoke); fill(flyerX, cy - k, 1, 1, spoke) }
        for k in 0..<(base - cy) { fill(flyerX - 1 - k / 2, cy + k, 1, 1, shade.color); fill(flyerX + 1 + k / 2, cy + k, 1, 1, shade.color) }
    }

    private func building(x: Int, w: Int, h: Int, base: Int, body: SkyPalette.RGB, shade: SkyPalette.RGB, windowDay: SkyPalette.RGB, rng: inout SeededRandom) {
        fill(x, base - h, w, h, body.color)
        fill(x + w - 1, base - h, 1, h, shade.color)
        if rng.next() % 3 == 0 { fill(x + w / 2, base - h - 1, 1, 1, body.color) } // 天线
        litWindows(x: x, w: w - 1, top: base - h + 1, bottom: base, seed: rng.next(), windowDay: windowDay)
    }

    /// 窗格：白天浅色格子，夜里随机亮起暖灯并偶尔闪烁。
    private func litWindows(x: Int, w: Int, top: Int, bottom: Int, seed: UInt64, windowDay: SkyPalette.RGB) {
        var rng = SeededRandom(seed: seed)
        for wy in stride(from: top, to: bottom - 1, by: 2) {
            for wx in stride(from: x, to: x + w, by: 2) {
                let roll = rng.next()
                if dark > 0.5 {
                    guard roll % 3 != 0 else { continue }
                    let flicker = roll % 37 == 0 && Int(t / 3) % 2 == 0
                    if !flicker { fill(wx, wy, 1, 1, (roll % 5 == 0 ? Color(red: 0.75, green: 0.9, blue: 1) : Color(red: 1, green: 0.84, blue: 0.5)).opacity(0.85 * dark)) }
                } else if roll % 2 == 0 {
                    fill(wx, wy, 1, 1, windowDay.color.opacity(0.7))
                }
            }
        }
    }

    private func ringPoints(_ r: Int) -> [(Int, Int)] {
        var pts: [(Int, Int)] = []
        let n = r * 8
        for i in 0..<n {
            let a = Double(i) / Double(n) * 2 * .pi
            let pt = (Int((cos(a) * Double(r)).rounded()), Int((sin(a) * Double(r)).rounded()))
            if !pts.contains(where: { $0 == pt }) { pts.append(pt) }
        }
        return pts
    }

    private func drawWater(_ s: SkyPalette.Stops) {
        let y = floorTop - 2
        let water = s.horizon.mix(rgb(0x2E5C7A), 0.5).mix(rgb(0x0B1530), dark * 0.8)
        fill(0, y, cols, 2, water.color)
        var rng = SeededRandom(seed: 13)
        for _ in 0..<(cols / 6) {
            let x = Int(rng.next() % UInt64(max(1, cols)))
            let on = (Int(t * 2) + x) % 5 != 0
            if on { fill(x, y + Int(rng.next() % 2), 2, 1, (dark > 0.5 ? Color(red: 1, green: 0.85, blue: 0.5) : Color.white).opacity(0.35)) }
        }
    }

    // MARK: - 天气

    private func drawWeather() {
        if cond == "haze" { fill(0, 0, cols, floorTop, Color(red: 0.86, green: 0.82, blue: 0.74).opacity(0.32)) }
        guard raining else { return }
        fill(0, 0, cols, floorTop, Color(red: 0.5, green: 0.56, blue: 0.68).opacity(0.16))
        var rng = SeededRandom(seed: 99)
        let n = cond == "thunder" ? cols / 2 : cols / 3
        for _ in 0..<n {
            let x0 = Int(rng.next() % UInt64(cols + 8))
            let ph = Double(rng.next() % 1000) / 1000
            let y = Int((ph + t * 1.4).truncatingRemainder(dividingBy: 1) * Double(floorTop + 2)) - 1
            fill(x0 - y / 3, y, 1, 2, Color(red: 0.82, green: 0.88, blue: 0.96).opacity(0.5))
        }
        if cond == "thunder" {
            let c = t.truncatingRemainder(dividingBy: 9)
            if c < 0.16 {
                fill(0, 0, cols, floorTop, Color.white.opacity(c < 0.05 ? 0.5 : 0.22))
                var b = SeededRandom(seed: UInt64(Int(t / 9) & 0xFFFF) + 3)
                var x = Int(b.next() % UInt64(max(1, cols)))
                for y in 0..<(floorTop - 4) { x += Int(b.next() % 3) - 1; fill(x, y, 1, 1, .white) }
            }
        }
    }

    // MARK: - 窗框与地板

    private func drawFrame() {
        let frame = Color(red: 0.12, green: 0.13, blue: 0.17)
        let edge = Color(red: 0.26, green: 0.27, blue: 0.33)
        let nc = notchCols
        if notchRows > 0 && !ceilingMode {
            // 物理刘海 = 窗上的黑色横梁；沿刘海外沿描一圈窗框，让它看起来是有意的结构。
            // 隧道模式下，刘海两侧窗框在列车高度处让位给隧道口。
            let barTop = notch.tunnel ? notchRows + 1 : 0
            fill(nc.lowerBound - 2, barTop, 2, floorTop - barTop, frame)
            fill(nc.upperBound + 1, barTop, 2, floorTop - barTop, frame)
            if notch.den {
                // 猫洞模式：洞口一圈木质边框（外沿深、内沿浅），像天花板上开的猫洞。
                let woodDark = rgb(0x5A3A26).mix(rgb(0x1E140F), dark * 0.6).color
                let woodLight = rgb(0xA8744A).mix(rgb(0x3A271B), dark * 0.6).color
                fill(nc.lowerBound - 2, notchRows, nc.count + 4, 1, woodLight)
                fill(nc.lowerBound - 1, notchRows + 1, nc.count + 2, 1, woodDark)
            } else {
                fill(nc.lowerBound - 2, notchRows, nc.count + 4, 1, frame)
                fill(nc.lowerBound - 1, notchRows + 1, nc.count + 2, 1, edge.opacity(0.6))
            }
            fill(0, 0, nc.lowerBound, 1, frame)
            fill(nc.upperBound + 1, 0, cols, 1, frame)
        }
        // 玻璃反光：每块玻璃一道淡淡的斜线。
        let panes: [ClosedRange<Int>] = notchRows > 0 && !ceilingMode ? [0...(nc.lowerBound - 3), (nc.upperBound + 3)...(cols - 1), (nc.lowerBound)...(nc.upperBound)] : [0...(cols - 1)]
        for pane in panes where pane.count > 6 {
            let top = pane == nc ? notchRows + 2 : 1
            for k in 0..<(floorTop - top) {
                let x = pane.lowerBound + 4 + (floorTop - top - k) / 2
                if pane.contains(x) { fill(x, top + k, 1, 1, Color.white.opacity(0.06 + dark * 0.03)) }
            }
        }
    }

    // MARK: - 地铁隧道

    /// 列车行驶的轨面行：刚好在刘海底边之上，车身在两翼完整可见、经过刘海时整列「钻进隧道」。
    private var trackRow: Int { notchRows - 1 }

    /// 刘海 = 隧道口：两侧画混凝土洞口，刘海底边下方是贯穿全宽的高架桥；MRT 小列车每隔一阵从左右随机方向穿过。
    private func drawMetro() {
        guard notch.tunnel, notchRows > 6 else { return }
        let nc = notchCols
        let concrete = rgb(0xB9BEC7).mix(rgb(0x3A4054), dark * 0.75)
        let concreteDark = concrete.mix(rgb(0x10131C), 0.35)
        let bridgeY = notchRows
        // 高架桥：桥面 + 桥墩
        fill(0, bridgeY, cols, 1, concrete.color)
        fill(0, bridgeY + 1, cols, 1, concreteDark.color.opacity(0.8))
        for x in stride(from: 6 + parallax(3), to: cols, by: 22) where !nc.contains(x) {
            fill(x, bridgeY + 2, 2, max(0, floorTop - 2 - bridgeY - 2), concreteDark.color.opacity(0.85))
        }
        // 列车：每 50 秒一班，方向随班次交替；穿越全程约 7 秒
        let period = 50.0, run = 7.0
        let n = Int(t / period), local = t.truncatingRemainder(dividingBy: period)
        if local < run {
            let leftToRight = n % 2 == 0
            let cars = 3, carW = 12, gap = 1
            let trainW = cars * carW + (cars - 1) * gap
            let prog = local / run
            let x0 = leftToRight ? Int(Double(cols + trainW) * prog) - trainW : cols - Int(Double(cols + trainW) * prog)
            let top = trackRow - 4
            let shell = rgb(0xF2F4F7).mix(rgb(0x8A93A8), dark * 0.6)
            let stripe = rgb(0xE5322D)
            let window = dark > 0.5 ? Color(red: 1, green: 0.86, blue: 0.55) : rgb(0x2A3346).color
            for c in 0..<cars {
                let cx = x0 + c * (carW + gap)
                fill(cx, top, carW, 4, shell.color)
                fill(cx, top + 2, carW, 1, stripe.color)
                for wx in stride(from: cx + 1, to: cx + carW - 1, by: 3) { fill(wx, top + 1, 2, 1, window) }
                fill(cx, top + 4, carW, 1, concreteDark.color) // 转向架阴影
            }
            // 车头灯
            let head = leftToRight ? x0 + trainW : x0 - 1
            fill(head, top + 2, 1, 1, Color(red: 1, green: 0.95, blue: 0.7).opacity(dark > 0.4 ? 1 : 0.7))
            if dark > 0.4 { fill(leftToRight ? head + 1 : head - 4, top + 2, 4, 1, Color(red: 1, green: 0.95, blue: 0.7).opacity(0.25)) }
        }
        // 隧道口：刘海左右两侧的混凝土洞框（画在列车之上，列车像是钻进去）
        for side in [nc.lowerBound - 2, nc.upperBound + 1] {
            fill(side, trackRow - 6, 2, 7, concrete.color)
            fill(side + (side < nc.lowerBound ? 1 : 0), trackRow - 5, 1, 6, concreteDark.color)
        }
        fill(nc.lowerBound - 3, trackRow - 7, 4, 1, concrete.color)
        fill(nc.upperBound, trackRow - 7, 4, 1, concrete.color)
    }

    /// 天花板（仅天花板模式）：纯黑与刘海融为一体，下沿一道暗边，夜里亮起一排暖色筒灯。
    private func drawCeiling() {
        guard ceilingMode else { return }
        fill(0, 0, cols, notchRows + 1, .black)
        fill(0, notchRows + 1, cols, 1, Color(red: 0.12, green: 0.13, blue: 0.17))
        let lamps = max(3, cols / 28)
        for i in 0..<lamps {
            let x = cols * (2 * i + 1) / (2 * lamps)
            if notchCols.contains(x) { continue }
            fill(x - 1, notchRows, 3, 1, Color(red: 1, green: 0.84, blue: 0.58).opacity(0.25 + 0.6 * dark))
        }
    }

    /// 地面：都市感的深色抛光地面，颜色取自窗外天色；窗台一条细高光过渡。
    /// 白天映出天空的亮带，夜里映出城市灯光的竖向倒影。
    private func drawFloor() {
        let y = floorTop
        let sky = SkyPalette.stops(darkness: dark, twilight: dusk, overcast: overcast)
        let sill = sky.horizon.mix(rgb(0xFFFFFF), 0.35).mix(rgb(0x2A3045), dark * 0.7)
        fill(0, y, cols, 1, sill.color.opacity(0.9))
        let floorTone = sky.horizon.mix(rgb(0x151A26), 0.72 + dark * 0.18)
        for k in 1..<IslandScene.floorRows {
            fill(0, y + k, cols, 1, floorTone.mix(rgb(0x0B0E15), Double(k) / Double(IslandScene.floorRows) * 0.5).color)
        }
        var lr = SeededRandom(seed: 17)
        if dark > 0.45 {
            for _ in 0..<(cols / 5) {
                let lx = Int(lr.next() % UInt64(max(1, cols)))
                let warm = lr.next() % 3 != 0
                fill(lx, y + 1, 1, IslandScene.floorRows - 1, (warm ? Color(red: 1, green: 0.82, blue: 0.5) : Color(red: 0.6, green: 0.8, blue: 1)).opacity(0.28 * dark))
            }
        } else {
            fill(0, y + 1, cols, 1, sky.horizon.mix(rgb(0xFFFFFF), 0.3).color.opacity(0.22 * (1 - overcast * 0.6)))
        }
    }
}
