// CatStage：小猫的随机行为引擎 + 绘制。
// 每只猫是一个「演员」：在自己的活动区间里随机选动作（发呆、舔毛、打盹、伸懒腰、蹦一下、走几步），
// 节奏和停顿随机；偶尔有猫走出画面「下班」，换一只随机形象的新猫走进来。
import SwiftUI

struct CatStage: View {
    /// 同时在场的猫数量。
    let cats: Int
    var id = "notch"
    /// 中间被物理刘海挡住的宽度：有刘海时每只猫固定在一侧翅膀活动。
    var hiddenWidth: CGFloat = 0
    /// 一个美术像素对应多少 pt；默认一个物理像素（Retina 上 0.5pt），保证像素锐利。
    var pixel: CGFloat = 0
    /// 悬停 / 点开时让猫开心地蹦一下。
    var excited = false

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        if CatAtlas.shared.isEmpty {
            CatStrip(cats: cats, id: id, hiddenWidth: hiddenWidth)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
                Canvas { ctx, size in
                    let px = pixel > 0 ? pixel : 1 / max(displayScale, 1)
                    let t = tl.date.timeIntervalSinceReferenceDate
                    for i in 0..<cats {
                        let lane = CatDirector.shared.lane(for: i, count: cats, width: size.width, hidden: hiddenWidth)
                        let snap = CatDirector.shared.tick(actor: "\(id)#\(i)", lane: lane, pixel: px, time: t, excited: excited)
                        draw(snap, in: &ctx, size: size, px: px)
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func draw(_ s: CatDirector.Snapshot, in ctx: inout GraphicsContext, size: CGSize, px: CGFloat) {
        let a = s.animation
        let frame = a.frames[s.frame % a.frames.count]
        let w = CGFloat(a.frameWidth) * px, h = CGFloat(a.frameHeight) * px
        let src = CGFloat(CatAtlas.shared.sourceSize) * px
        // 源图底边对齐地面、源图水平中心对齐角色位置。
        let originX = CGFloat(a.originX) * px, originY = CGFloat(a.originY) * px
        let ground = size.height - 1
        var rect = CGRect(x: s.x - src / 2 - originX, y: ground - src - originY, width: w, height: h)
        rect = rect.integral(scale: 1 / px)
        var c = ctx
        c.opacity = s.opacity
        if s.facingLeft {
            c.translateBy(x: rect.midX * 2, y: 0)
            c.scaleBy(x: -1, y: 1)
        }
        // 刘海是纯黑底：先画一圈 1 像素的浅色剪影描边，黑猫、奶牛猫也能看清轮廓。
        var rim = c.resolve(Image(decorative: frame, scale: 1).renderingMode(.template).interpolation(.none))
        rim.shading = .color(Color(white: 0.62, opacity: 0.55))
        for (dx, dy) in [(px, 0), (-px, 0), (0, px), (0, -px)] {
            c.draw(rim, in: rect.offsetBy(dx: dx, dy: dy))
        }
        let img = c.resolve(Image(decorative: frame, scale: 1).interpolation(.none))
        c.draw(img, in: rect)
    }
}

private extension CGRect {
    /// 对齐到像素网格，避免半像素采样发糊。
    func integral(scale: CGFloat) -> CGRect {
        CGRect(x: (minX * scale).rounded() / scale, y: (minY * scale).rounded() / scale, width: width, height: height)
    }
}

/// 所有猫演员的状态与随机决策。
final class CatDirector {
    static let shared = CatDirector()

    struct Lane { let min: CGFloat; let max: CGFloat; let exitLeft: Bool }

    struct Snapshot {
        let animation: CatAnimation
        let frame: Int
        let x: CGFloat
        let facingLeft: Bool
        let opacity: Double
    }

    private enum Phase { case acting, walking(to: CGFloat), entering, leaving }

    private struct Actor {
        var skin: String
        var x: CGFloat
        var facingLeft = false
        var action = "idle"
        var phase: Phase = .acting
        var started: TimeInterval = 0
        var until: TimeInterval = 0
        var lastTick: TimeInterval = 0
        var nextSwap: TimeInterval = 0
        var wasExcited = false
        /// 打盹时中段（睡着）循环几遍。
        var sleepLoops = 0
    }

    /// 打盹动画分三段：躺下（前 4 帧）→ 睡着（中间循环）→ 起身（后 4 帧）。
    private static let napIntro = 4, napOutro = 4

    private func frameIndex(_ a: Actor, raw f: Int, count n: Int) -> Int {
        guard a.action == "nap", n > Self.napIntro + Self.napOutro else { return f }
        let mid = n - Self.napIntro - Self.napOutro
        if f < Self.napIntro { return f }
        let slept = f - Self.napIntro
        if slept < mid * a.sleepLoops { return Self.napIntro + slept % mid }
        return min(n - 1, Self.napIntro + mid + (slept - mid * a.sleepLoops))
    }

    private var actors: [String: Actor] = [:]
    private var onStage: Set<String> { Set(actors.values.map(\.skin)) }

    /// 每只猫的活动区间。有刘海时左右翅膀各一只；否则平分整条。
    func lane(for i: Int, count: Int, width: CGFloat, hidden: CGFloat) -> Lane {
        let margin: CGFloat = 8
        if hidden > 0, width - hidden > margin * 4 {
            let wing = (width - hidden) / 2
            return i % 2 == 0 ? Lane(min: margin, max: wing - 4, exitLeft: true) : Lane(min: width - wing + 4, max: width - margin, exitLeft: false)
        }
        let seg = width / CGFloat(max(count, 1))
        return Lane(min: seg * CGFloat(i) + margin, max: seg * CGFloat(i + 1) - margin, exitLeft: i == 0)
    }

    func tick(actor id: String, lane: Lane, pixel: CGFloat, time t: TimeInterval, excited: Bool) -> Snapshot {
        let atlas = CatAtlas.shared
        var a = actors[id] ?? newActor(lane: lane, time: t)
        let dt = a.lastTick == 0 ? 0 : min(0.1, t - a.lastTick)
        a.lastTick = t
        let speed = 26 * pixel // 约每秒 26 个美术像素
        let anim = { (name: String) in atlas.cats[a.skin]?[name] ?? atlas.cats[a.skin]?["idle"] ?? atlas.cats[a.skin]!.values.first! }

        if excited && !a.wasExcited, case .acting = a.phase, atlas.cats[a.skin]?["hop"] != nil {
            start(&a, action: "hop", time: t)
        }
        a.wasExcited = excited

        switch a.phase {
        case .walking(let goal):
            moveToward(&a, goal: goal, step: speed * CGFloat(dt))
            if abs(a.x - goal) < 0.5 { decide(&a, lane: lane, time: t) }
        case .entering:
            let goal = lane.exitLeft ? lane.min + 6 : lane.max - 6
            moveToward(&a, goal: goal, step: speed * CGFloat(dt))
            if abs(a.x - goal) < 0.5 { start(&a, action: "idle", time: t) }
        case .leaving:
            let exit = lane.exitLeft ? lane.min - 24 : lane.max + 24
            moveToward(&a, goal: exit, step: speed * CGFloat(dt))
            if abs(a.x - exit) < 0.5 { a = newActor(lane: lane, time: t, entering: true, excluding: onStage) }
        case .acting:
            if t >= a.until { decide(&a, lane: lane, time: t) }
        }
        actors[id] = a

        let animation = anim(a.action)
        let fps: Double = a.action == "walk" ? 10 : (a.action == "nap" ? 5 : 8)
        let elapsed = t - a.started
        let frame = frameIndex(a, raw: Int(elapsed * fps), count: animation.frames.count)
        // 离场 / 入场时在翅膀外沿淡出淡入，不突兀地「消失」。
        let edge = lane.exitLeft ? a.x - (lane.min - 24) : (lane.max + 24) - a.x
        let opacity = min(1, max(0, Double(edge) / 20))
        return Snapshot(animation: animation, frame: frame, x: a.x, facingLeft: a.facingLeft, opacity: opacity)
    }

    private func newActor(lane: Lane, time t: TimeInterval, entering: Bool = false, excluding: Set<String> = []) -> Actor {
        let skins = CatAtlas.shared.skins
        let pool = skins.filter { !excluding.contains($0) }
        let skin = (pool.isEmpty ? skins : pool).randomElement() ?? "orange"
        var a = Actor(skin: skin, x: entering ? (lane.exitLeft ? lane.min - 24 : lane.max + 24) : CGFloat.random(in: lane.min...max(lane.min + 1, lane.max)))
        a.nextSwap = t + Double.random(in: 120...300)
        if entering {
            a.phase = .entering
            a.action = "walk"
            a.facingLeft = !lane.exitLeft
            a.started = t
        } else {
            start(&a, action: "idle", time: t)
        }
        return a
    }

    /// 随机选下一个动作。没有的动作自动跳过（部分形象只有走路和发呆）。
    private func decide(_ a: inout Actor, lane: Lane, time t: TimeInterval) {
        if t >= a.nextSwap {
            a.phase = .leaving
            a.action = "walk"
            a.facingLeft = lane.exitLeft
            a.started = t
            return
        }
        let have = CatAtlas.shared.cats[a.skin] ?? [:]
        let weights: [(String, Double)] = [("idle", 3), ("walk", 2.5), ("groom", 1.5), ("nap", 1.2), ("stretch", 1), ("hop", 0.6)]
        let options = weights.filter { have[$0.0] != nil }
        var r = Double.random(in: 0..<options.map(\.1).reduce(0, +))
        var pick = "idle"
        for (name, w) in options {
            if r < w { pick = name; break }
            r -= w
        }
        if pick == "walk" {
            let target = CGFloat.random(in: lane.min...max(lane.min + 1, lane.max))
            a.facingLeft = target < a.x
            a.phase = .walking(to: target)
            a.action = "walk"
            a.started = t
        } else {
            start(&a, action: pick, time: t)
        }
    }

    private func start(_ a: inout Actor, action: String, time t: TimeInterval) {
        let frames = CatAtlas.shared.cats[a.skin]?[action]?.frames.count ?? 8
        let fps: Double = action == "nap" ? 5 : 8
        a.phase = .acting
        a.action = action
        a.started = t
        if action == "nap" {
            // 睡 4~10 轮呼吸（每轮约 1.6s），醒来再起身。
            a.sleepLoops = Int.random(in: 4...10)
            let mid = max(0, frames - Self.napIntro - Self.napOutro)
            a.until = t + Double(Self.napIntro + mid * a.sleepLoops + Self.napOutro) / fps
            return
        }
        // 发呆多循环几遍；其余动作做一遍就回到站姿。
        let loops: Double = action == "idle" ? Double(Int.random(in: 2...5)) : 1
        a.until = t + Double(frames) / fps * loops + Double.random(in: 0...0.6)
        if Bool.random() && action != "nap" { a.facingLeft.toggle() }
    }

    private func moveToward(_ a: inout Actor, goal: CGFloat, step: CGFloat) {
        guard abs(goal - a.x) > step else { a.x = goal; return }
        a.facingLeft = goal < a.x
        a.x += goal > a.x ? step : -step
    }
}
