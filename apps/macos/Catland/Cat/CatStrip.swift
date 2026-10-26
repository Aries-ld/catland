// 收起态的小猫散步（占位实现）：像素小猫随机走走停停、偶尔坐下，穿过刘海时「躲到后面」。
// 正式美术素材（多套形象 × 多套动作，随机组合）就绪后替换 PixelCat 的绘制即可，行为逻辑保留。
import SwiftUI

struct CatStrip: View {
    let cats: Int
    /// 每条小猫带独立的行为状态，避免多处同时显示时互相干扰。
    var id = "notch"
    /// 中间被物理刘海挡住的宽度；小猫主要在两侧活动，偶尔从刘海「后面」穿过。
    var hiddenWidth: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
                Canvas { ctx, size in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    for i in 0..<cats {
                        let cat = CatBrain.shared.state(for: "\(id)#\(i)", width: size.width, hidden: hiddenWidth, side: i % 2, time: t)
                        PixelCat.draw(in: &ctx, at: CGPoint(x: cat.x, y: size.height - 3), frame: cat.frame, facingLeft: cat.facingLeft, palette: PixelCat.palettes[i % PixelCat.palettes.count], pose: cat.pose)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)
    }
}

/// 每只猫一个简单的随机行为状态机：走 → 停 → 坐 → 走……
final class CatBrain {
    static let shared = CatBrain()

    enum Pose { case walk, stand, sit }
    struct Snapshot { let x: CGFloat; let frame: Int; let facingLeft: Bool; let pose: Pose }

    private struct Cat {
        var x: CGFloat
        var target: CGFloat
        var pose: Pose = .stand
        var until: TimeInterval = 0
        var last: TimeInterval = 0
        var speed: CGFloat
    }

    private var cats: [String: Cat] = [:]

    /// 在可见区域里随机取落脚点。有刘海时每只猫固定在一侧翅膀，不穿过刘海（物理刘海处没有像素，会像「消失」）。
    private func pickTarget(width: CGFloat, hidden: CGFloat, side: Int) -> CGFloat {
        let margin: CGFloat = 9
        guard hidden > 0, width - hidden > margin * 4 else { return CGFloat.random(in: margin...max(margin + 1, width - margin)) }
        let wing = (width - hidden) / 2
        return side == 0 ? CGFloat.random(in: margin...max(margin + 1, wing - margin / 2)) : CGFloat.random(in: min(width - margin - 1, width - wing + margin / 2)...(width - margin))
    }

    func state(for i: String, width: CGFloat, hidden: CGFloat = 0, side: Int = 0, time t: TimeInterval) -> Snapshot {
        var c = cats[i] ?? Cat(x: 0, target: 0, speed: CGFloat.random(in: 12...20))
        if c.last == 0 { c.x = pickTarget(width: width, hidden: hidden, side: side) }
        let dt = c.last == 0 ? 0 : min(0.1, t - c.last)
        c.last = t
        if t >= c.until {
            switch Int.random(in: 0..<10) {
            case 0..<6:
                c.pose = .walk
                c.target = pickTarget(width: width, hidden: hidden, side: side)
                c.until = t + 20
            case 6..<8:
                c.pose = .stand
                c.until = t + Double.random(in: 1...3)
            default:
                c.pose = .sit
                c.until = t + Double.random(in: 3...7)
            }
        }
        var facingLeft = c.target < c.x
        if c.pose == .walk {
            let step = c.speed * CGFloat(dt)
            if abs(c.target - c.x) <= step {
                c.x = c.target
                c.pose = .stand
                c.until = t + Double.random(in: 0.5...2)
            } else {
                c.x += c.target > c.x ? step : -step
            }
            facingLeft = c.target < c.x
        }
        cats[i] = c
        let frame = c.pose == .walk ? Int(t * 8) % 4 : 0
        return Snapshot(x: c.x, frame: frame, facingLeft: facingLeft, pose: c.pose)
    }
}

/// 极简 10×8 像素小猫（2pt 一个像素），四帧走路 + 站 + 坐。
enum PixelCat {
    struct Palette { let body: Color; let dark: Color }
    static let palettes = [
        Palette(body: Color(red: 0.98, green: 0.70, blue: 0.40), dark: Color(red: 0.80, green: 0.45, blue: 0.20)), // 橘猫
        Palette(body: Color(red: 0.92, green: 0.92, blue: 0.92), dark: Color(red: 0.55, green: 0.55, blue: 0.6)),   // 白猫
        Palette(body: Color(red: 0.35, green: 0.35, blue: 0.40), dark: Color(red: 0.15, green: 0.15, blue: 0.18)),  // 黑猫
    ]

    // 行从上到下；B = 身体，D = 深色（耳尖 / 尾巴），E = 眼睛，. = 透明
    private static let head = [
        "D.D.......",
        "BBB.......",
        "BEB.......",
    ]
    private static let bodyWalk = [
        [".BBBBBBBD.", ".BBBBBBB.D", ".B.B..B.B."],
        [".BBBBBBBD.", ".BBBBBBB.D", "..B.BB.B.."],
        [".BBBBBBBD.", ".BBBBBBB.D", ".B..B..B.B"],
        [".BBBBBBBD.", ".BBBBBBB.D", "..BB..BB.."],
    ]
    private static let bodySit = [".BBBBBB...", ".BBBBBBD..", ".BB.BBBDD."]

    static func draw(in ctx: inout GraphicsContext, at p: CGPoint, frame: Int, facingLeft: Bool, palette: Palette, pose: CatBrain.Pose) {
        let px: CGFloat = 2
        let rows = head + (pose == .sit ? bodySit : bodyWalk[pose == .walk ? frame : 0])
        let w = CGFloat(rows[0].count) * px
        let h = CGFloat(rows.count) * px
        let origin = CGPoint(x: p.x - w / 2, y: p.y - h)
        for (r, row) in rows.enumerated() {
            for (c, ch) in row.enumerated() where ch != "." {
                let col = facingLeft ? c : row.count - 1 - c
                let rect = CGRect(x: origin.x + CGFloat(col) * px, y: origin.y + CGFloat(r) * px, width: px, height: px)
                let color: Color = ch == "E" ? .black : (ch == "D" ? palette.dark : palette.body)
                ctx.fill(Path(rect), with: .color(color))
            }
        }
    }
}
