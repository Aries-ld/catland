// 上海场景包：地标、动态元素、夜景配色都在这个文件里（见 CityPack.swift）。
import SwiftUI

/// 上海：地铁在高架上驶过刘海，黄浦江上的渡轮 / 夜游船，偶尔飞机和鸟群；夜里陆家嘴一带粉紫色的霓虹和江面倒影。
struct ShanghaiPack: CityPack {
    let skyline = Skyline.shanghai
    let landmark: Landmark = ShanghaiLandmarks()
    let elements: [CityElement] = [MetroTrain(livery: .shanghaiMetro), RiverBoat(), Airplane(), Birds()]
    let neon = NeonStyle(glow: 0xA0448C, signs: [0xFF4FA3, 0x48D6FF, 0xC86BFF, 0xFFD27A])
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

