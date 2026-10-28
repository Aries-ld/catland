// 城市场景包：一个城市的地标、动态元素、夜景霓虹放在同一个文件里（Cities/<城市>.swift），按所在地整包加载。
// 新增城市 = 新写一个 CityPack 并登记到 CityPacks.all；图层只读场景包，不写死任何城市。
import SwiftUI

protocol CityPack {
    var skyline: Skyline { get }
    /// 左右两翼的地标（刘海挡住中间，地标只放在两侧看得见的地方）。
    var landmark: Landmark { get }
    /// 动态元素：各自声明画在哪一层（天空 / 水面 / 高架桥）。
    var elements: [CityElement] { get }
    /// 夜景：地平线光晕、霓虹招牌、水面倒影的配色。
    var neon: NeonStyle { get }
}

/// 城市里会动的东西（地铁、游船、车流、风筝、飞机、鸟群）。
protocol CityElement {
    var stage: SceneStage { get }
    func draw(_ c: SceneCanvas)
}

struct NeonStyle {
    /// 地平线上的城市光晕。
    let glow: UInt32
    /// 霓虹招牌 / 水面倒影的颜色。
    let signs: [UInt32]
}

enum CityPacks {
    static let all: [CityPack] = [SingaporePack(), ShanghaiPack(), BeijingPack()]
    static func of(_ s: Skyline) -> CityPack? { all.first { $0.skyline == s } }
    static func current(_ c: SceneCanvas) -> CityPack? { of(c.env.location.skyline) }
}

/// 把场景包里属于某一层的动态元素画出来（高架桥上的车辆由 MetroLayer 在桥和隧道口之间调用）。
struct CityElementsLayer: SceneLayer {
    let stage: SceneStage
    var id: String { "cityElements-\(stage.rawValue)" }
    func draw(_ c: SceneCanvas) {
        CityPacks.current(c)?.elements.filter { $0.stage == stage }.forEach { $0.draw(c) }
    }
}

extension SceneCanvas {
    /// 夜里的灯光强度：天黑过半后淡入。
    var nightGlow: Double { min(1, max(0, (dark - 0.35) / 0.35)) }
    /// 一个周期里出场的进度（0…1），不在出场时间内返回 nil。
    func appearance(period: Double, run: Double, offset: Double = 0) -> (progress: Double, round: Int)? {
        let tt = t + offset
        let local = tt.truncatingRemainder(dividingBy: period)
        return local < run ? (local / run, Int(tt / period)) : nil
    }
}

// MARK: - 夜景霓虹

/// 地平线上的城市光晕：天黑后楼群背后泛起一层暖 / 紫色的光（画在远景楼群之前）。
struct HorizonGlowLayer: SceneLayer {
    let id = "horizonGlow"
    let stage = SceneStage.farCity
    func draw(_ c: SceneCanvas) {
        guard let pack = CityPacks.current(c), c.nightGlow > 0 else { return }
        let glow = c.rgb(pack.neon.glow).color
        let span = c.tall(10)
        for k in 0..<span {
            let a = 0.45 * pow(1 - Double(k) / Double(span), 1.4) * c.nightGlow * (1 - c.overcast * 0.4)
            c.fill(0, c.cityBase - 1 - k, c.cols, 1, glow.opacity(a))
        }
    }
}

/// 近景楼上的霓虹招牌：楼侧竖招牌、楼顶横招牌，偶尔有一块轻轻闪一下（只在夜里）。
struct NeonSignsLayer: SceneLayer {
    let id = "neonSigns"
    let stage = SceneStage.nearCity
    func draw(_ c: SceneCanvas) {
        guard let pack = CityPacks.current(c), c.nightGlow > 0 else { return }
        let base = c.cityBase
        for (i, b) in c.nearBuildings.enumerated() where b.h >= 5 && (i * 7 + 3) % 3 == 0 {
            let col = c.rgb(pack.neon.signs[i % pack.neon.signs.count]).color
            // 每块招牌各自的节奏：大多数常亮，少数偶尔闪一下
            let flicker = (i % 5 == 0) && sin(c.t * 3.1 + Double(i)) > 0.92
            let a = (flicker ? 0.25 : 1) * c.nightGlow
            if i % 2 == 0 { // 楼侧竖招牌 + 一圈光晕
                let len = min(5, b.h - 2), y = base - b.h + 1
                c.fill(b.x, y, 1, len, col.opacity(a))
                c.fill(b.x - 1, y - 1, 1, len + 2, col.opacity(0.22 * a)); c.fill(b.x + 1, y - 1, 1, len + 2, col.opacity(0.22 * a))
                c.fill(b.x, y - 1, 1, 1, col.opacity(0.22 * a)); c.fill(b.x, y + len, 1, 1, col.opacity(0.22 * a))
            } else { // 楼顶横招牌 + 往上的光晕
                c.fill(b.x + 1, base - b.h - 1, max(1, b.w - 2), 1, col.opacity(a))
                c.fill(b.x, base - b.h - 2, b.w, 1, col.opacity(0.2 * a))
                c.fill(b.x + 1, base - b.h - 3, max(1, b.w - 2), 1, col.opacity(0.08 * a))
            }
        }
    }
}

/// 水面倒影：夜里地标和霓虹在水里拖出一条条晃动的彩色光（画在水面之上、岸边之前）。
struct WaterReflectionLayer: SceneLayer {
    let id = "waterReflection"
    let stage = SceneStage.water
    func draw(_ c: SceneCanvas) {
        guard let pack = CityPacks.current(c), c.nightGlow > 0 else { return }
        let y0 = c.cityBase, h = max(2, c.floorTop - c.cityBase)
        // 地标正下方：明亮的倒影
        let marks: [(Int, UInt32)] = [(c.markL, pack.neon.signs[0]), (c.markR - 4, pack.neon.signs[min(3, pack.neon.signs.count - 1)]), (c.markR + 4, pack.neon.signs[1])]
        for (x, hex) in marks {
            for k in 0..<h {
                let wob = Int((sin(c.t * 2.4 + Double(k) * 1.7 + Double(x)) * 1.2).rounded())
                c.fill(x + wob, y0 + k, 1 + (k % 2), 1, c.rgb(hex).color.opacity((0.55 - Double(k) * 0.12) * c.nightGlow))
            }
        }
        // 霓虹招牌的倒影：淡一些
        for (i, b) in c.nearBuildings.enumerated() where b.h >= 5 && (i * 7 + 3) % 3 == 0 {
            let hex = pack.neon.signs[i % pack.neon.signs.count]
            for k in 0..<h where (Int(c.t * 3) + k + i) % 3 != 0 {
                c.fill(b.x + (k % 2), y0 + k, 1, 1, c.rgb(hex).color.opacity((0.3 - Double(k) * 0.08) * c.nightGlow))
            }
        }
    }
}

// MARK: - 动态元素

/// 高架上的地铁：每 50 秒穿过刘海一次，车身涂装按城市（上海地铁的绿色腰带、新加坡 MRT 的红色腰带）。
struct MetroTrain: CityElement {
    enum Livery {
        case shanghaiMetro, singaporeMRT
        var stripe: UInt32 { self == .shanghaiMetro ? 0x3BB54A : 0xE5322D }
        var stripe2: UInt32? { self == .shanghaiMetro ? 0x8BC34A : nil }
    }
    let livery: Livery
    let stage = SceneStage.transit

    func draw(_ c: SceneCanvas) {
        guard let (prog, n) = c.appearance(period: 50, run: 7) else { return }
        let trackRow = c.notchRows - 1
        let leftToRight = n % 2 == 0
        let cars = 3, carW = 12, gap = 1
        let trainW = cars * carW + (cars - 1) * gap
        let x0 = leftToRight ? Int(Double(c.cols + trainW) * prog) - trainW : c.cols - Int(Double(c.cols + trainW) * prog)
        let top = trackRow - 4
        let shell = c.rgb(0xF2F4F7).mix(c.rgb(0x8A93A8), c.dark * 0.6)
        let under = c.rgb(0x7A808C).mix(c.rgb(0x10131C), c.dark * 0.6)
        let window = c.dark > 0.5 ? Color(red: 1, green: 0.86, blue: 0.55) : c.rgb(0x2A3346).color
        for k in 0..<cars {
            let cx = x0 + k * (carW + gap)
            c.fill(cx, top, carW, 4, shell.color)
            c.fill(cx, top + 2, carW, 1, c.rgb(livery.stripe).color)
            if let s2 = livery.stripe2 { c.fill(cx, top + 3, carW, 1, c.rgb(s2).color.opacity(0.7)) }
            for wx in stride(from: cx + 1, to: cx + carW - 1, by: 3) { c.fill(wx, top + 1, 2, 1, window) }
            c.fill(cx, top + 4, carW, 1, under.color)
        }
        let head = leftToRight ? x0 + trainW : x0 - 1
        c.fill(head, top + 2, 1, 1, Color(red: 1, green: 0.95, blue: 0.7).opacity(c.dark > 0.4 ? 1 : 0.7))
        if c.dark > 0.4 { c.fill(leftToRight ? head + 1 : head - 4, top + 2, 4, 1, Color(red: 1, green: 0.95, blue: 0.7).opacity(0.25)) }
    }
}

/// 长安街车流：高架上两条车道对向行驶，小汽车、出租车、红色公交车；夜里车身压暗，只看到白色车头灯和红色尾灯拖出的光。
struct ChangAnTraffic: CityElement {
    let stage = SceneStage.transit

    private struct Vehicle { let w: Int; let h: Int; let body: UInt32; let bus: Bool }
    private static let fleet: [Vehicle] = [
        Vehicle(w: 4, h: 2, body: 0xE8E8EC, bus: false), Vehicle(w: 4, h: 2, body: 0x2E3440, bus: false),
        Vehicle(w: 9, h: 3, body: 0xD0453A, bus: true), Vehicle(w: 4, h: 2, body: 0xF2C94C, bus: false),
        Vehicle(w: 4, h: 2, body: 0x9AA4B2, bus: false), Vehicle(w: 5, h: 2, body: 0x1F3A5F, bus: false),
    ]

    func draw(_ c: SceneCanvas) {
        let trackRow = c.notchRows - 1
        let night = c.dark > 0.45
        // 两条车道：远车道往左（稍暗、高一格），近车道往右
        for lane in 0..<2 {
            let dir = lane == 0 ? -1 : 1
            let speed = lane == 0 ? 9.0 : 12.0
            let spacing = 17, span = c.cols + 40
            let shift = Int(c.t * speed) % span
            let bottom = trackRow - (lane == 0 ? 1 : 0)
            for i in 0..<(span / spacing) {
                let v = Self.fleet[(i * 5 + lane * 3) % Self.fleet.count]
                guard (i * 7 + lane) % 5 != 0 else { continue } // 车流有疏有密
                var x = (i * spacing + (dir > 0 ? shift : -shift)) % span
                if x < 0 { x += span }
                x -= 20
                let top = bottom - v.h + 1
                let dim = lane == 0 ? 0.25 : 0
                let body = c.rgb(v.body).mix(c.rgb(0x10131C), max(dim, c.dark * 0.8))
                c.fill(x, top, v.w, v.h, body.color)
                if v.bus { // 公交车窗：白天深色，夜里亮暖光
                    for wx in stride(from: x + 1, to: x + v.w - 1, by: 2) { c.fill(wx, top, 1, 1, night ? Color(red: 1, green: 0.86, blue: 0.55).opacity(0.9) : c.rgb(0x2A3346).color) }
                } else if !night {
                    c.fill(x + 1, top, v.w - 2, 1, c.rgb(0x2A3346).color.opacity(0.7))
                }
                let front = dir > 0 ? x + v.w - 1 : x, back = dir > 0 ? x : x + v.w - 1
                if night {
                    c.fill(front, bottom, 1, 1, Color(red: 1, green: 0.97, blue: 0.85))
                    c.fill(front + dir, bottom, 1, 1, Color(red: 1, green: 0.97, blue: 0.85).opacity(0.5))
                    c.fill(front + 2 * dir, bottom, 2, 1, Color(red: 1, green: 0.97, blue: 0.85).opacity(0.18))
                    c.fill(back, bottom, 1, 1, Color(red: 1, green: 0.15, blue: 0.15))
                    c.fill(back - dir, bottom, 2, 1, Color(red: 1, green: 0.15, blue: 0.15).opacity(0.3))
                }
            }
        }
    }
}

/// 黄浦江上的船：白天是红白相间的渡轮，夜里是亮着彩灯的夜游船，水里拖着彩色倒影；大约每 80 秒漂过一次。
struct RiverBoat: CityElement {
    let stage = SceneStage.water

    func draw(_ c: SceneCanvas) {
        guard let (prog, n) = c.appearance(period: 80, run: 40, offset: 23) else { return }
        let night = c.dark > 0.45
        let w = 11, waterline = c.cityBase + 1
        let leftToRight = n % 2 == 1
        let x = leftToRight ? Int(Double(c.cols + w) * prog) - w : c.cols - Int(Double(c.cols + w) * prog)
        let hull = night ? c.rgb(0x1A1E2C) : c.rgb(0xF4F4F0)
        c.fill(x, waterline, w, 1, hull.color)
        c.fill(x + 1, waterline + 1, w - 2, 1, hull.mix(c.rgb(0x0A0C14), 0.3).color)
        if !night { c.fill(x, waterline, w, 1, c.rgb(0xD0453A).color.opacity(0.0)); c.fill(x + 1, waterline + 1, w - 2, 1, c.rgb(0xD0453A).color) }
        // 船舱
        let cabin = night ? c.rgb(0x22283A) : c.rgb(0xE8ECF2)
        c.fill(x + 2, waterline - 2, w - 4, 2, cabin.color)
        if night {
            let colors: [UInt32] = [0xFF4FA3, 0x48D6FF, 0xFFD27A, 0xC86BFF]
            for i in 0..<(w - 4) {
                let col = c.rgb(colors[(i + Int(c.t * 4)) % colors.count]).color
                c.fill(x + 2 + i, waterline - 2, 1, 1, col)
                c.fill(x + 2 + i, waterline + 2, 1, 1, col.opacity(0.35)) // 倒影
            }
            c.fill(x + 2, waterline - 1, w - 4, 1, Color(red: 1, green: 0.88, blue: 0.6).opacity(0.8))
        } else {
            for i in stride(from: 3, to: w - 3, by: 2) { c.fill(x + i, waterline - 1, 1, 1, c.rgb(0x5A6E8A).color) }
            c.fill(x + w / 2, waterline - 3, 1, 1, c.rgb(0xD0453A).color) // 小旗
        }
    }
}

/// 风筝：春秋天的白天、不下雨时，天坛上空飘着一只菱形风筝和一只沙燕风筝，随风轻轻摆动，细线垂向地面。
struct Kites: CityElement {
    let stage = SceneStage.flyers

    func draw(_ c: SceneCanvas) {
        guard c.dark < 0.4, !c.raining, [.spring, .autumn].contains(c.season) else { return }
        let line = Color(white: 1).opacity(0.35)
        // 菱形风筝：左翼天坛上空
        let x1 = c.markL + 5 + Int((sin(c.t * 0.7) * 1.5).rounded()), y1 = c.skyTop + 3 + Int((sin(c.t * 1.3) * 1).rounded())
        let red = c.rgb(0xE0453A).color, yellow = c.rgb(0xF2C94C).color
        c.fill(x1, y1 - 1, 1, 1, red); c.fill(x1 - 1, y1, 3, 1, red); c.fill(x1, y1, 1, 1, yellow); c.fill(x1, y1 + 1, 1, 1, red)
        for k in 0..<3 { c.fill(x1 + (k % 2 == 0 ? 0 : -1) + Int((sin(c.t * 4 + Double(k)) * 0.6).rounded()), y1 + 2 + k, 1, 1, yellow.opacity(0.9)) }
        for k in stride(from: 2, to: c.cityBase - y1, by: 2) { c.fill(x1 + 1 + k / 3, y1 + k, 1, 1, line) }
        // 沙燕风筝：右翼更高处（展开时看得到）
        let x2 = c.markR - 6 + Int((sin(c.t * 0.5 + 1) * 2).rounded()), y2 = c.skyTop + 2 + Int((sin(c.t * 1.1 + 2) * 1).rounded())
        let ink = c.rgb(0x2A2A35).color, white = c.rgb(0xF4F1E8).color
        c.fill(x2 - 2, y2, 5, 1, ink); c.fill(x2 - 1, y2 - 1, 3, 1, white); c.fill(x2, y2 + 1, 1, 1, ink)
        c.fill(x2 - 1, y2 + 2, 1, 1, ink); c.fill(x2 + 1, y2 + 2, 1, 1, ink) // 燕尾
        for k in stride(from: 3, to: c.cityBase - y2, by: 2) { c.fill(x2 - k / 4, y2 + k, 1, 1, line) }
    }
}

/// 鸟群：白天偶尔有一小群鸟排成松散的人字飞过（下雨不飞），翅膀上下扇动。
struct Birds: CityElement {
    let stage = SceneStage.flyers

    func draw(_ c: SceneCanvas) {
        guard c.dark < 0.55, !c.raining, let (prog, n) = c.appearance(period: 75, run: 14, offset: 31) else { return }
        let leftToRight = n % 2 == 0
        let lead = leftToRight ? Int(Double(c.cols + 30) * prog) - 15 : c.cols + 15 - Int(Double(c.cols + 30) * prog)
        let baseY = c.skyTop + 4 + n % 3
        let col = c.rgb(0x2A2E3A).color.opacity(0.75)
        let flock: [(Int, Int)] = [(0, 0), (-4, 2), (-8, 3), (-3, -2), (-7, -3), (-11, 1)]
        for (i, (dx, dy)) in flock.enumerated() {
            let x = lead + (leftToRight ? dx : -dx), y = baseY + dy + Int((sin(c.t * 2 + Double(i)) * 0.7).rounded())
            let up = (Int(c.t * 6) + i) % 2 == 0
            c.fill(x - 1, y + (up ? -1 : 0), 1, 1, col); c.fill(x, y, 1, 1, col); c.fill(x + 1, y + (up ? -1 : 0), 1, 1, col)
        }
    }
}

/// 飞机：大约每分钟从高空飞过一架。白天白色机身拖一道淡淡的尾迹；夜里只看得到闪烁的白色频闪灯和红绿航行灯。
struct Airplane: CityElement {
    let stage = SceneStage.flyers

    func draw(_ c: SceneCanvas) {
        guard let (prog, n) = c.appearance(period: 60, run: 18, offset: 7) else { return }
        let leftToRight = n % 2 == 1
        let x = leftToRight ? Int(Double(c.cols + 20) * prog) - 10 : c.cols + 10 - Int(Double(c.cols + 20) * prog)
        let y = c.skyTop + 2 + n % 2
        let dir = leftToRight ? 1 : -1
        if c.dark > 0.45 {
            c.fill(x, y, 4, 1, Color(white: 0.35))
            if Int(c.t * 2.5) % 3 == 0 { c.fill(x + (dir > 0 ? 4 : -1), y, 1, 1, .white) }
            c.fill(x + 1, y + 1, 1, 1, dir > 0 ? .red : .green)
            c.fill(x + 2, y - 1, 1, 1, dir > 0 ? .green : .red)
        } else {
            let body = c.rgb(0xF4F6F8).color
            c.fill(x, y, 5, 1, body)
            c.fill(dir > 0 ? x : x + 4, y - 1, 1, 1, body)   // 垂尾
            c.fill(x + 2, y + 1, 1, 1, body.opacity(0.8))     // 机翼
            if !c.raining && c.overcast < 0.6 { // 尾迹
                for k in 1...10 { c.fill(dir > 0 ? x - k : x + 4 + k, y, 1, 1, Color.white.opacity(0.4 * (1 - Double(k) / 11))) }
            }
        }
    }
}
