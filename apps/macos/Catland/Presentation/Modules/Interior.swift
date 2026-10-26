// 室内模块：窗框（物理刘海 = 横梁 / 猫洞口 / 隧道口）、玻璃反光、天花板（天花板模式）、地面。
import SwiftUI

struct FrameLayer: SceneLayer {
    let id = "frame"
    let stage = SceneStage.frame
    func draw(_ c: SceneCanvas) {
        let frame = Color(red: 0.12, green: 0.13, blue: 0.17)
        let edge = Color(red: 0.26, green: 0.27, blue: 0.33)
        let nc = c.notchCols
        if c.hasNotch && !c.ceilingMode {
            // 物理刘海 = 窗上的黑色横梁；隧道模式下，刘海两侧窗框在列车高度处让位给隧道口。
            let barTop = c.notch.tunnel ? c.notchRows + 1 : 0
            c.fill(nc.lowerBound - 2, barTop, 2, c.floorTop - barTop, frame)
            c.fill(nc.upperBound + 1, barTop, 2, c.floorTop - barTop, frame)
            if c.notch.den {
                // 猫洞模式：洞口一圈木质边框。
                c.fill(nc.lowerBound - 2, c.notchRows, nc.count + 4, 1, c.rgb(0xA8744A).mix(c.rgb(0x3A271B), c.dark * 0.6).color)
                c.fill(nc.lowerBound - 1, c.notchRows + 1, nc.count + 2, 1, c.rgb(0x5A3A26).mix(c.rgb(0x1E140F), c.dark * 0.6).color)
            } else {
                c.fill(nc.lowerBound - 2, c.notchRows, nc.count + 4, 1, frame)
                c.fill(nc.lowerBound - 1, c.notchRows + 1, nc.count + 2, 1, edge.opacity(0.6))
            }
            c.fill(0, 0, nc.lowerBound, 1, frame)
            c.fill(nc.upperBound + 1, 0, c.cols, 1, frame)
        }
        // 玻璃反光：每块玻璃一道淡淡的斜线。
        let panes: [ClosedRange<Int>] = c.hasNotch && !c.ceilingMode
            ? [0...(nc.lowerBound - 3), (nc.upperBound + 3)...(c.cols - 1), nc.lowerBound...nc.upperBound] : [0...(c.cols - 1)]
        for pane in panes where pane.count > 6 {
            let top = pane == nc ? c.notchRows + 2 : 1
            for k in 0..<max(0, c.floorTop - top) {
                let x = pane.lowerBound + 4 + (c.floorTop - top - k) / 2
                if pane.contains(x) { c.fill(x, top + k, 1, 1, Color.white.opacity(0.06 + c.dark * 0.03)) }
            }
        }
    }
}

/// 天花板（仅天花板模式）：纯黑与刘海融为一体，下沿一道暗边，夜里亮起一排暖色筒灯。
struct CeilingLayer: SceneLayer {
    let id = "ceiling"
    let stage = SceneStage.ceiling
    func draw(_ c: SceneCanvas) {
        guard c.ceilingMode else { return }
        c.fill(0, 0, c.cols, c.notchRows + 1, .black)
        c.fill(0, c.notchRows + 1, c.cols, 1, Color(red: 0.12, green: 0.13, blue: 0.17))
        let lamps = max(3, c.cols / 28)
        for i in 0..<lamps {
            let x = c.cols * (2 * i + 1) / (2 * lamps)
            if c.notchCols.contains(x) { continue }
            c.fill(x - 1, c.notchRows, 3, 1, Color(red: 1, green: 0.84, blue: 0.58).opacity(0.25 + 0.6 * c.dark))
        }
    }
}

/// 地面：深色抛光地面，颜色取自窗外天色；窗台一条细高光过渡；白天映天光、夜里映城市灯。
struct FloorLayer: SceneLayer {
    let id = "floor"
    let stage = SceneStage.floor
    func draw(_ c: SceneCanvas) {
        let y = c.floorTop
        let sky = SkyPalette.stops(darkness: c.dark, twilight: c.dusk, overcast: c.overcast)
        c.fill(0, y, c.cols, 1, sky.horizon.mix(c.rgb(0xFFFFFF), 0.35).mix(c.rgb(0x2A3045), c.dark * 0.7).color.opacity(0.9))
        let tone = sky.horizon.mix(c.rgb(0x151A26), 0.72 + c.dark * 0.18)
        for k in 1..<SceneCanvas.floorRows {
            c.fill(0, y + k, c.cols, 1, tone.mix(c.rgb(0x0B0E15), Double(k) / Double(SceneCanvas.floorRows) * 0.5).color)
        }
        var lr = SeededRandom(seed: 17)
        if c.dark > 0.45 {
            for _ in 0..<(c.cols / 5) {
                let lx = Int(lr.next() % UInt64(max(1, c.cols)))
                let warm = lr.next() % 3 != 0
                c.fill(lx, y + 1, 1, SceneCanvas.floorRows - 1, (warm ? Color(red: 1, green: 0.82, blue: 0.5) : Color(red: 0.6, green: 0.8, blue: 1)).opacity(0.28 * c.dark))
            }
        } else {
            c.fill(0, y + 1, c.cols, 1, sky.horizon.mix(c.rgb(0xFFFFFF), 0.3).color.opacity(0.22 * (1 - c.overcast * 0.6)))
        }
    }
}
