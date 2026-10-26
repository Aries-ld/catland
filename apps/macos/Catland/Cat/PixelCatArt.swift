// 手绘像素小猫：部件化（头 + 身体姿势 + 腿 + 尾巴 + 粒子）组合出逐帧图像，花色由「涂装」规则自动上色。
// 画布 16×12 像素，角色朝左绘制（头在左），地面是最后一行。
//
// 部件编码：A 耳  H 头  E 眼  C 闭眼线  N 鼻  M 口鼻  P 粉色（舌头 / 腮红）
//          B 身体  W 胸腹  L 腿  T 尾巴  Z 睡觉的 z  V 爱心  Y 蝴蝶  . 透明
import CoreGraphics
import Foundation

enum PixelCatArt {
    static let width = 16
    static let height = 12

    // MARK: - 头部（6×5）

    enum Head: CaseIterable {
        case normal, blink, happy, yawn, lick, lookAhead, lookBack, lookUp

        var rows: [String] {
            let ears = ["A....A", "AA..AA"]
            switch self {
            case .normal: return ears + ["HHHHHH", "HEHHEH", "HMNNMH"]
            case .blink: return ears + ["HHHHHH", "HCHHCH", "HMNNMH"]
            case .happy: return ears + ["HHHHHH", "HCHHCH", "PMNNMP"]
            case .yawn: return ears + ["HHHHHH", "HCHHCH", "HPPPPH"]
            case .lick: return ears + ["HHHHHH", "HCHHCH", "HMPPMH"]
            case .lookAhead: return ears + ["HHHHHH", "EHHEHH", "HMNNMH"]
            case .lookBack: return ears + ["HHHHHH", "HHEHHE", "HMNNMH"]
            case .lookUp: return ears + ["HEHHEH", "HHHHHH", "HMNNMH"]
            }
        }
    }

    // MARK: - 身体姿势（16×12，不含头；head 为头部左上角位置）

    struct Pose {
        let rows: [String]
        let head: (x: Int, y: Int)
    }

    static let stand = Pose(rows: [
        "................",
        "................",
        "................",
        "................",
        "................",
        "................",
        "......BBBBBBB...",
        "......BBBBBBBB..",
        ".WWWBBBBBBBBBB..",
        "..BBBBBBBBBBB...",
        "..L.L.....L.L...",
        "..L.L.....L.L...",
    ], head: (0, 3))

    static let sit = Pose(rows: [
        "................",
        "................",
        "................",
        "................",
        "................",
        "................",
        "................",
        ".......BB.......",
        "..WWWWBBBB......",
        "..WWWWBBBBB.....",
        "..WLWLBBBBB.....",
        "..LLLLBBBBB.....",
    ], head: (1, 3))

    static let loaf = Pose(rows: [
        "................",
        "................",
        "................",
        "................",
        "................",
        "................",
        "................",
        "................",
        "......BBBBBBB...",
        "......BBBBBBBB..",
        "......BBBBBBBB..",
        "......WWBBBBBB..",
    ], head: (0, 7))

    static let stretch = Pose(rows: [
        "................",
        "................",
        "................",
        "................",
        "................",
        "................",
        ".........BBB....",
        "......BBBBBBB...",
        "......BBBBBBBB..",
        "......BBB..BBB..",
        "..........L..L..",
        "LLLL......L..L..",
    ], head: (0, 6))

    static let back = Pose(rows: [
        "................",
        "................",
        "................",
        "................",
        "................",
        "................",
        "................",
        ".......L.L..L.L.",
        "......WWWWWWWW..",
        "......BBBBBBBB..",
        "......BBBBBBBB..",
        ".......BBBBBB...",
    ], head: (0, 7))

    // MARK: - 尾巴（像素坐标）

    enum Tail {
        case up, flick, curl, low, sitFlat, sitTip, loafTuck, stretchUp, backFlop

        var pixels: [(Int, Int)] {
            switch self {
            case .up: return [(13, 6), (14, 5), (14, 4)]
            case .flick: return [(13, 6), (14, 5), (15, 4), (15, 3)]
            case .curl: return [(13, 6), (14, 5), (14, 4), (13, 3)]
            case .low: return [(14, 7), (15, 8), (15, 9)]
            case .sitFlat: return [(11, 11), (12, 11), (13, 11), (13, 10)]
            case .sitTip: return [(11, 11), (12, 11), (13, 10), (13, 9)]
            case .loafTuck: return [(14, 10), (14, 11), (13, 11)]
            case .stretchUp: return [(12, 6), (12, 5), (12, 4), (11, 3)]
            case .backFlop: return [(14, 10), (15, 10), (15, 11)]
            }
        }
    }

    // MARK: - 组合一帧

    struct Frame {
        var pose: Pose
        var head: Head = .normal
        var tail: Tail? = nil
        /// 腿部替换：键为行号，值为整行（只替换 L 与空位）。
        var legs: [Int: String] = [:]
        /// 头部额外偏移（低头舔毛、抬头等）。
        var headOffset: (Int, Int) = (0, 0)
        /// 整帧上下平移（跳跃，负数向上）。
        var lift = 0
        /// 额外像素（抬起的爪子、粒子）。
        var extra: [(Int, Int, Character)] = []
        /// 去掉的像素（抬爪后原来的腿）。
        var erase: [(Int, Int)] = []
    }

    /// 组合成 12 行 × 16 列的部件编码网格。
    static func compose(_ f: Frame) -> [[Character]] {
        var g = f.pose.rows.map { Array($0) }
        for (row, line) in f.legs { g[row] = Array(line) }
        for (x, y) in f.erase where inBounds(x, y) { g[y][x] = "." }
        for (x, y) in f.tail?.pixels ?? [] where inBounds(x, y) { g[y][x] = "T" }
        let hx = f.pose.head.x + f.headOffset.0, hy = f.pose.head.y + f.headOffset.1
        for (r, line) in f.head.rows.enumerated() {
            for (c, ch) in line.enumerated() where ch != "." && inBounds(hx + c, hy + r) { g[hy + r][hx + c] = ch }
        }
        // 身体部件随跳跃平移；粒子（z、爱心、蝴蝶）固定在画布位置，最后再画。
        let isParticle = { (ch: Character) in ch == "Z" || ch == "V" || ch == "Y" }
        for (x, y, ch) in f.extra where !isParticle(ch) && inBounds(x, y) { g[y][x] = ch }
        if f.lift != 0 {
            let empty = Array(repeating: Character("."), count: width)
            var shifted = Array(repeating: empty, count: height)
            for y in 0..<height where inBounds(0, y + f.lift) { shifted[y + f.lift] = g[y] }
            g = shifted
        }
        for (x, y, ch) in f.extra where isParticle(ch) && inBounds(x, y) { g[y][x] = ch }
        return g
    }

    private static func inBounds(_ x: Int, _ y: Int) -> Bool { x >= 0 && x < width && y >= 0 && y < height }

    // MARK: - 动作

    struct Action {
        let name: String
        let frames: [Frame]
        let fps: Double
        /// 前 intro 帧只播一次，后 outro 帧只播一次，中间按 loops 循环（打盹、坐着等）。
        var intro = 0
        var outro = 0
        var loops: ClosedRange<Int> = 1...1
        var weight: Double = 1
    }

    // 走路腿型
    private static let legsDown = [10: "..L.L.....L.L...", 11: "..L.L.....L.L..."]
    private static let stride = [10: "..L.L.....L.L...", 11: ".L...L...L...L.."]
    private static let cross = [10: "..L.L.....L.L...", 11: "...LL......LL..."]
    private static let crouchLegs = [10: "..L.L.....L.L...", 11: "................"]
    private static let tucked = [10: ".LL.......LL....", 11: "................"]

    /// 蝴蝶的飞行轨迹（在猫前上方飞来飞去）。
    private static let butterflyPath: [(Int, Int)] = [(7, 0), (5, 1), (3, 0), (2, 1), (4, 2), (6, 1), (8, 0), (10, 1)]

    static let actions: [Action] = {
        var a: [Action] = []
        let s = stand, si = sit

        a.append(Action(name: "idle", frames: [
            Frame(pose: s, tail: .up), Frame(pose: s, tail: .flick), Frame(pose: s, tail: .up), Frame(pose: s, tail: .curl),
            Frame(pose: s, tail: .up), Frame(pose: s, head: .blink, tail: .up),
        ], fps: 3, loops: 2...4, weight: 3))

        a.append(Action(name: "walk", frames: [
            Frame(pose: s, tail: .up, legs: stride), Frame(pose: s, tail: .curl, legs: legsDown, lift: -1),
            Frame(pose: s, tail: .up, legs: cross), Frame(pose: s, tail: .flick, legs: legsDown, lift: -1),
        ], fps: 7, weight: 2.5))

        a.append(Action(name: "look", frames: [
            Frame(pose: s, head: .lookAhead, tail: .up), Frame(pose: s, head: .lookAhead, tail: .up),
            Frame(pose: s, head: .normal, tail: .flick), Frame(pose: s, head: .lookBack, tail: .up),
            Frame(pose: s, head: .lookBack, tail: .curl), Frame(pose: s, head: .blink, tail: .up),
        ], fps: 2.5, weight: 1))

        a.append(Action(name: "sit", frames: [
            Frame(pose: s, tail: .up, legs: crouchLegs, lift: 1),
            Frame(pose: si, tail: .sitFlat), Frame(pose: si, tail: .sitTip), Frame(pose: si, tail: .sitFlat),
            Frame(pose: si, head: .blink, tail: .sitFlat), Frame(pose: si, tail: .sitTip),
            Frame(pose: s, tail: .up, legs: crouchLegs, lift: 1),
        ], fps: 2.5, intro: 1, outro: 1, loops: 2...5, weight: 2))

        // 坐下舔爪：抬起前爪凑到嘴边，低头舔两下。
        let paw: [(Int, Int, Character)] = [(1, 8, "L"), (1, 9, "L")]
        a.append(Action(name: "groom", frames: [
            Frame(pose: si, tail: .sitFlat),
            Frame(pose: si, tail: .sitFlat, extra: paw, erase: [(3, 10), (2, 11), (3, 11)]),
            Frame(pose: si, head: .lick, tail: .sitTip, headOffset: (0, 1), extra: paw, erase: [(3, 10), (2, 11), (3, 11)]),
            Frame(pose: si, head: .lick, tail: .sitFlat, extra: paw, erase: [(3, 10), (2, 11), (3, 11)]),
            Frame(pose: si, head: .lick, tail: .sitTip, headOffset: (0, 1), extra: paw, erase: [(3, 10), (2, 11), (3, 11)]),
            Frame(pose: si, head: .blink, tail: .sitFlat),
        ], fps: 4, intro: 1, outro: 1, loops: 2...4, weight: 1.2))

        a.append(Action(name: "yawn", frames: [
            Frame(pose: si, tail: .sitFlat), Frame(pose: si, head: .blink, tail: .sitFlat),
            Frame(pose: si, head: .yawn, tail: .sitTip, headOffset: (0, -1)), Frame(pose: si, head: .yawn, tail: .sitTip, headOffset: (0, -1)),
            Frame(pose: si, head: .yawn, tail: .sitFlat, headOffset: (0, -1)), Frame(pose: si, head: .blink, tail: .sitFlat),
            Frame(pose: si, tail: .sitFlat),
        ], fps: 3, weight: 0.6))

        // 打盹：趴下 → 呼吸起伏 + 冒 z → 醒来起身。
        let z1: [(Int, Int, Character)] = [(6, 6, "Z")]
        let z2: [(Int, Int, Character)] = [(7, 4, "Z"), (6, 6, "Z")]
        let z3: [(Int, Int, Character)] = [(8, 2, "Z"), (7, 4, "Z")]
        let breatheOut = [8: "......BBBBBB...."]
        a.append(Action(name: "nap", frames: [
            Frame(pose: si, tail: .sitFlat), Frame(pose: loaf, head: .blink, tail: .loafTuck),
            Frame(pose: loaf, head: .blink, tail: .loafTuck, extra: z1),
            Frame(pose: loaf, head: .blink, tail: .loafTuck, legs: breatheOut, extra: z2),
            Frame(pose: loaf, head: .blink, tail: .loafTuck, extra: z3),
            Frame(pose: loaf, head: .blink, tail: .loafTuck, legs: breatheOut),
            Frame(pose: loaf, head: .normal, tail: .loafTuck), Frame(pose: si, head: .yawn, tail: .sitTip, headOffset: (0, -1)),
            Frame(pose: si, tail: .sitFlat),
        ], fps: 1.6, intro: 2, outro: 3, loops: 4...10, weight: 1))

        // 趴着当「猫猫面包」，偶尔眨眼。
        a.append(Action(name: "loaf", frames: [
            Frame(pose: si, tail: .sitFlat),
            Frame(pose: loaf, tail: .loafTuck), Frame(pose: loaf, tail: .loafTuck), Frame(pose: loaf, head: .blink, tail: .loafTuck),
            Frame(pose: loaf, tail: .loafTuck),
            Frame(pose: si, tail: .sitFlat),
        ], fps: 2, intro: 1, outro: 1, loops: 2...5, weight: 1))

        a.append(Action(name: "stretch", frames: [
            Frame(pose: s, tail: .up), Frame(pose: stretch, head: .normal, tail: .stretchUp),
            Frame(pose: stretch, head: .yawn, tail: .stretchUp), Frame(pose: stretch, head: .yawn, tail: .stretchUp),
            Frame(pose: stretch, head: .blink, tail: .stretchUp), Frame(pose: s, head: .happy, tail: .flick),
            Frame(pose: s, tail: .up),
        ], fps: 3.5, weight: 0.8))

        // 开心蹦一下，头顶冒爱心（悬停时触发）。
        let heart: [(Int, Int, Character)] = [(2, 0, "V"), (4, 0, "V"), (3, 1, "V")]
        a.append(Action(name: "hop", frames: [
            Frame(pose: s, tail: .up, legs: crouchLegs, lift: 1),
            Frame(pose: s, head: .happy, tail: .flick, legs: tucked, lift: -2),
            Frame(pose: s, head: .happy, tail: .flick, legs: tucked, lift: -3, extra: heart),
            Frame(pose: s, head: .happy, tail: .up, legs: tucked, lift: -2, extra: heart),
            Frame(pose: s, head: .happy, tail: .up, legs: crouchLegs, lift: 1, extra: heart),
            Frame(pose: s, head: .happy, tail: .curl),
        ], fps: 9, weight: 0.3))

        // 追蝴蝶：抬头盯着，伸爪去够。
        var play: [Frame] = []
        for (i, p) in butterflyPath.enumerated() {
            let wing: Character = "Y"
            let bf: [(Int, Int, Character)] = i % 2 == 0 ? [(p.0, p.1, wing), (p.0 + 1, p.1, wing)] : [(p.0, p.1, wing)]
            let swipe = i == 3 || i == 4
            play.append(Frame(pose: s, head: .lookUp, tail: i % 2 == 0 ? .flick : .curl,
                              legs: swipe ? [10: "....L.....L.L...", 11: "....L.....L.L..."] : [:],
                              extra: bf + (swipe ? [(1, 7, "L"), (0, 6, "L")] : [])))
        }
        a.append(Action(name: "play", frames: play, fps: 5, loops: 1...2, weight: 0.5))

        // 翻肚皮打滚。
        let wiggle = [6: "........L.....L.", 7: "......L...L.L..."]
        a.append(Action(name: "roll", frames: [
            Frame(pose: si, tail: .sitFlat), Frame(pose: loaf, tail: .loafTuck),
            Frame(pose: back, head: .happy, tail: .backFlop), Frame(pose: back, head: .happy, tail: .backFlop, legs: wiggle),
            Frame(pose: back, head: .happy, tail: .backFlop), Frame(pose: back, head: .happy, tail: .backFlop, legs: wiggle),
            Frame(pose: loaf, tail: .loafTuck), Frame(pose: si, tail: .sitFlat),
        ], fps: 4, intro: 2, outro: 2, loops: 2...4, weight: 0.5))

        return a
    }()

    // MARK: - 花色

    struct Skin {
        let name: String
        let base: UInt32
        var stripe: UInt32? = nil
        var belly: UInt32? = nil
        var point: UInt32? = nil
        var patchA: UInt32? = nil
        var patchB: UInt32? = nil
        var eye: UInt32 = 0x2A2A33
        var line: UInt32 = 0x3A3340
        /// 白袜子（奶牛猫、橘白）。
        var socks = false
        /// 深色猫在黑色刘海上需要浅色描边。
        var rim = false
    }

    static let skins: [Skin] = [
        Skin(name: "orange", base: 0xF6A75C, stripe: 0xDB7B3C, belly: 0xFCE2C2),
        Skin(name: "white", base: 0xF4F4F6, belly: 0xFFFFFF, eye: 0x5B8DEF, line: 0x8A8A99),
        Skin(name: "black", base: 0x2C2C35, eye: 0xF2C14E, line: 0x7A7A8C, rim: true),
        Skin(name: "gray", base: 0x8E9AB0, stripe: 0x7D899E, belly: 0xB9C2D2, eye: 0xF0A04B),
        Skin(name: "cream", base: 0xF7D9A8, belly: 0xFDF0DA, eye: 0x6B4A2A),
        Skin(name: "tabby", base: 0xAE916F, stripe: 0x6E5843, belly: 0xD9C7AE, eye: 0x6DBE5A),
        Skin(name: "calico", base: 0xF4F1EC, belly: 0xFFFFFF, patchA: 0xEB8C3B, patchB: 0x3A3340),
        Skin(name: "siamese", base: 0xF1E5D2, belly: 0xF8F0E4, point: 0x5C4234, eye: 0x4F8FE6),
        Skin(name: "tuxedo", base: 0x2C2C35, belly: 0xF4F4F6, eye: 0x8BD46A, line: 0x7A7A8C, socks: true, rim: true),
        Skin(name: "gingerWhite", base: 0xF6A75C, stripe: 0xDB7B3C, belly: 0xFFFFFF, socks: true),
    ]

    private static let pink: UInt32 = 0xF49AB0
    private static let zColor: UInt32 = 0xC9D6FF
    private static let heartColor: UInt32 = 0xFF5D7A
    private static let butterflyColor: UInt32 = 0xFFD84A

    /// 部件编码 + 坐标 → 颜色（nil 为透明）。
    static func color(_ ch: Character, x: Int, y: Int, skin s: Skin) -> UInt32? {
        let belly = s.belly ?? s.base
        switch ch {
        case "Z": return zColor
        case "V": return heartColor
        case "Y": return butterflyColor
        case "E": return s.eye
        case "C": return s.line
        case "N", "P": return pink
        case "M": return s.point ?? belly
        case "W": return belly
        case "L":
            if s.point != nil { return s.point }
            if s.socks && y >= 10 { return belly }
            return s.base
        case "A":
            if let p = s.point { return p }
            return patch(x, y, s) ?? (s.stripe ?? s.base)
        case "T":
            if let p = s.point { return p }
            if let st = s.stripe, x % 2 == 0 { return st }
            return patch(x, y, s) ?? s.base
        case "H", "B":
            if let p = patch(x, y, s) { return p }
            if let st = s.stripe, ch == "B", x % 3 == 0 { return st }
            return s.base
        default: return nil
        }
    }

    /// 三花的色块：按 4×3 网格的确定性哈希分出大块橘色和黑色，避免碎成噪点。
    private static func patch(_ x: Int, _ y: Int, _ s: Skin) -> UInt32? {
        guard let a = s.patchA, let b = s.patchB else { return nil }
        let h = ((x / 4) &* 73 &+ (y / 3) &* 151) % 5
        return h == 0 ? a : (h == 2 ? b : nil)
    }

    // MARK: - 渲染

    static func render(_ grid: [[Character]], skin: Skin) -> CGImage? {
        var pixels = [UInt32](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                guard let rgb = color(grid[y][x], x: x, y: y, skin: skin) else { continue }
                // RGBA（premultipliedLast，大端序）
                pixels[y * width + x] = (rgb << 8 | 0xFF).bigEndian
            }
        }
        let data = pixels.withUnsafeBytes { Data($0) }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
