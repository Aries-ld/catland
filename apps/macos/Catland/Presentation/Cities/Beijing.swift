// 北京场景包：地标、动态元素、夜景配色都在这个文件里（见 CityPack.swift）。
import SwiftUI

/// 北京：长安街的车流从刘海下方的高架驶过（白天公交和小汽车，夜里红白两色的车灯），春秋天天坛上空放风筝，偶尔鸟群；
/// 夜里是暖金色的城市光（长安街路灯、祈年殿泛光）配一点冷色的 CBD 霓虹。
struct BeijingPack: CityPack {
    let skyline = Skyline.beijing
    let landmark: Landmark = BeijingLandmarks()
    let elements: [CityElement] = [ChangAnTraffic(), Kites(), Birds()]
    let neon = NeonStyle(glow: 0xB0743A, signs: [0xFFC86A, 0xFF5A4A, 0x7FD8FF])
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

