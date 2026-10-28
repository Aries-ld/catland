// 新加坡场景包：地标、动态元素、夜景配色都在这个文件里（见 CityPack.swift）。
import SwiftUI

/// 新加坡：MRT 地铁穿过刘海，偶尔有鸟群、飞机；夜里滨海湾的青色、品红霓虹。
struct SingaporePack: CityPack {
    let skyline = Skyline.singapore
    let landmark: Landmark = SingaporeLandmarks()
    let elements: [CityElement] = [MetroTrain(livery: .singaporeMRT), Birds(), Airplane()]
    let neon = NeonStyle(glow: 0x7A4FD0, signs: [0x3FE0FF, 0xFF4FC8, 0xFFE08A])
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

