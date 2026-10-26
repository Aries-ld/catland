// CatStage：小猫的随机行为引擎 + 绘制。
// 每只猫是一个「演员」：在自己的活动区间里按权重随机选动作（发呆、东张西望、坐下、舔爪、打哈欠、打盹、
// 趴成面包、伸懒腰、追蝴蝶、翻肚皮、走几步），节奏和停顿随机；悬停时开心地蹦一下冒爱心；
// 每隔几分钟有一只猫走出画面「下班」，换一只随机花色的新猫走进来。
import SwiftUI

struct CatStage: View {
    /// 同时在场的猫数量。
    let cats: Int
    var id = "notch"
    /// 中间被物理刘海挡住、看不见的宽度：此时每只猫固定在一侧活动。0 表示整条都可见（含刘海下方步道）。
    var hiddenWidth: CGFloat = 0
    /// 一个美术像素对应多少 pt；0 表示默认：Retina 上 1.5pt（3 个物理像素，整数倍保证锐利）。
    var pixel: CGFloat = 0
    /// 悬停 / 点开时让猫开心地蹦一下。
    var excited = false

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
            Canvas { ctx, size in
                let px = pixel > 0 ? pixel : max(1, (1.5 * displayScale).rounded()) / max(displayScale, 1)
                let t = tl.date.timeIntervalSinceReferenceDate
                for i in 0..<cats {
                    let lane = CatDirector.shared.lane(for: i, count: cats, width: size.width, hidden: hiddenWidth, catWidth: CGFloat(PixelCatArt.width) * px)
                    let snap = CatDirector.shared.tick(actor: "\(id)#\(i)", lane: lane, pixel: px, time: t, excited: excited)
                    draw(snap, in: &ctx, size: size, px: px)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func draw(_ s: CatDirector.Snapshot, in ctx: inout GraphicsContext, size: CGSize, px: CGFloat) {
        let a = s.animation
        let frame = a.frames[min(max(s.frame, 0), a.frames.count - 1)]
        let w = CGFloat(a.frameWidth) * px, h = CGFloat(a.frameHeight) * px
        var rect = CGRect(x: s.x - w / 2, y: size.height - h, width: w, height: h)
        rect.origin.x = (rect.origin.x / px).rounded() * px // 对齐像素网格，避免发糊
        var c = ctx
        c.opacity = s.opacity
        // 美术朝左绘制；朝右时水平翻转。
        if s.facingLeft != CatAtlas.shared.facesLeft {
            c.translateBy(x: rect.midX * 2, y: 0)
            c.scaleBy(x: -1, y: 1)
        }
        if s.rim {
            var rim = c.resolve(Image(decorative: frame, scale: 1).renderingMode(.template).interpolation(.none))
            rim.shading = .color(Color(white: 0.6, opacity: 0.6))
            for (dx, dy) in [(px, 0), (-px, 0), (0, px), (0, -px)] { c.draw(rim, in: rect.offsetBy(dx: dx, dy: dy)) }
        }
        c.draw(c.resolve(Image(decorative: frame, scale: 1).interpolation(.none)), in: rect)
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
        let rim: Bool
    }

    private enum Phase { case acting, walking(to: CGFloat), entering, leaving }

    private struct Actor {
        var skin: String
        var x: CGFloat
        var facingLeft = true
        var action = "idle"
        var phase: Phase = .acting
        var started: TimeInterval = 0
        var until: TimeInterval = 0
        var lastTick: TimeInterval = 0
        var nextSwap: TimeInterval = 0
        var wasExcited = false
        var loops = 1
    }

    private var actors: [String: Actor] = [:]
    private var onStage: Set<String> { Set(actors.values.map(\.skin)) }
    /// 走路速度：每秒多少个美术像素。
    private let walkSpeed: CGFloat = 9
    /// 离场 / 入场时走到区间外多远。
    private let offstage: CGFloat = 26

    /// 每只猫的活动区间（猫的中心点范围）。
    func lane(for i: Int, count: Int, width: CGFloat, hidden: CGFloat, catWidth: CGFloat) -> Lane {
        let half = catWidth / 2 + 2
        if hidden > 0, (width - hidden) / 2 > catWidth {
            let wing = (width - hidden) / 2
            return i % 2 == 0 ? Lane(min: half, max: max(half + 1, wing - half), exitLeft: true)
                              : Lane(min: min(width - half - 1, width - wing + half), max: width - half, exitLeft: false)
        }
        let seg = width / CGFloat(max(count, 1))
        return Lane(min: seg * CGFloat(i) + half, max: max(seg * CGFloat(i) + half + 1, seg * CGFloat(i + 1) - half), exitLeft: i % 2 == 0)
    }

    func tick(actor id: String, lane: Lane, pixel: CGFloat, time t: TimeInterval, excited: Bool) -> Snapshot {
        let atlas = CatAtlas.shared
        var a = actors[id] ?? newActor(lane: lane, time: t)
        let dt = a.lastTick == 0 ? 0 : min(0.1, t - a.lastTick)
        a.lastTick = t
        let step = walkSpeed * pixel * CGFloat(dt)

        if excited && !a.wasExcited, case .acting = a.phase { start(&a, action: "hop", time: t) }
        a.wasExcited = excited

        switch a.phase {
        case .walking(let goal):
            moveToward(&a, goal: goal, step: step)
            if abs(a.x - goal) < 0.5 { decide(&a, lane: lane, time: t) }
        case .entering:
            let goal = lane.exitLeft ? lane.min + 4 : lane.max - 4
            moveToward(&a, goal: goal, step: step)
            if abs(a.x - goal) < 0.5 { start(&a, action: "look", time: t) }
        case .leaving:
            let exit = lane.exitLeft ? lane.min - offstage : lane.max + offstage
            moveToward(&a, goal: exit, step: step)
            if abs(a.x - exit) < 0.5 { a = newActor(lane: lane, time: t, entering: true, excluding: onStage) }
        case .acting:
            if t >= a.until { decide(&a, lane: lane, time: t) }
        }
        actors[id] = a

        let anim = atlas.cats[a.skin]?[a.action] ?? atlas.cats[a.skin]!["idle"]!
        let raw = Int((t - a.started) * anim.fps)
        let edge = lane.exitLeft ? a.x - (lane.min - offstage) : (lane.max + offstage) - a.x
        return Snapshot(animation: anim, frame: Self.frameIndex(raw: raw, anim: anim, loops: a.loops), x: a.x, facingLeft: a.facingLeft,
                        opacity: min(1, max(0, Double(edge) / 16)), rim: atlas.rimmed.contains(a.skin))
    }

    /// 分段播放：intro 一次 → 中段循环 loops 次 → outro 一次（停在最后一帧直到动作结束）。
    static func frameIndex(raw f: Int, anim: CatAnimation, loops: Int) -> Int {
        let n = anim.frames.count
        let mid = n - anim.intro - anim.outro
        guard mid > 0 else { return f % max(n, 1) }
        if anim.intro == 0 && anim.outro == 0 { return f % n }
        if f < anim.intro { return f }
        let inMid = f - anim.intro
        if inMid < mid * loops { return anim.intro + inMid % mid }
        return min(n - 1, anim.intro + mid + (inMid - mid * loops))
    }

    static func duration(_ anim: CatAnimation, loops: Int) -> TimeInterval {
        let n = anim.frames.count
        let mid = n - anim.intro - anim.outro
        let frames = (anim.intro == 0 && anim.outro == 0) ? n * loops : anim.intro + max(0, mid) * loops + anim.outro
        return Double(frames) / anim.fps
    }

    private func newActor(lane: Lane, time t: TimeInterval, entering: Bool = false, excluding: Set<String> = []) -> Actor {
        let skins = CatAtlas.shared.skins
        let pool = skins.filter { !excluding.contains($0) }
        let skin = (pool.isEmpty ? skins : pool).randomElement() ?? "orange"
        var a = Actor(skin: skin, x: entering ? (lane.exitLeft ? lane.min - offstage : lane.max + offstage) : CGFloat.random(in: lane.min...max(lane.min + 1, lane.max)))
        a.nextSwap = t + Double.random(in: 150...360)
        if entering {
            a.phase = .entering
            a.action = "walk"
            a.facingLeft = !lane.exitLeft
            a.started = t
        } else {
            a.facingLeft = Bool.random()
            start(&a, action: "idle", time: t)
        }
        return a
    }

    /// 按动作权重随机选下一个动作；刚做完的动作降低权重，避免连续重复。
    private func decide(_ a: inout Actor, lane: Lane, time t: TimeInterval) {
        if t >= a.nextSwap {
            a.phase = .leaving
            a.action = "walk"
            a.facingLeft = lane.exitLeft
            a.started = t
            return
        }
        let have = CatAtlas.shared.cats[a.skin] ?? [:]
        let options = have.filter { $0.key != "hop" }.map { ($0.key, $0.key == a.action ? $0.value.weight * 0.3 : $0.value.weight) }
        var r = Double.random(in: 0..<max(options.map(\.1).reduce(0, +), 0.001))
        var pick = "idle"
        for (name, w) in options.sorted(by: { $0.0 < $1.0 }) {
            if r < w { pick = name; break }
            r -= w
        }
        if pick == "walk" {
            // 走到区间里另一个随机点；距离太近就换个方向多走一点。
            var target = CGFloat.random(in: lane.min...max(lane.min + 1, lane.max))
            if abs(target - a.x) < 6 { target = a.x < (lane.min + lane.max) / 2 ? lane.max : lane.min }
            a.facingLeft = target < a.x
            a.phase = .walking(to: target)
            a.action = "walk"
            a.started = t
        } else {
            start(&a, action: pick, time: t)
        }
    }

    private func start(_ a: inout Actor, action: String, time t: TimeInterval) {
        guard let anim = CatAtlas.shared.cats[a.skin]?[action] else { return }
        a.phase = .acting
        a.action = action
        a.started = t
        a.loops = Int.random(in: anim.loops)
        a.until = t + Self.duration(anim, loops: a.loops) + Double.random(in: 0.2...1.5)
        // 原地动作偶尔转个身，更像真猫。
        if ["idle", "look", "sit"].contains(action), Double.random(in: 0..<1) < 0.3 { a.facingLeft.toggle() }
    }

    private func moveToward(_ a: inout Actor, goal: CGFloat, step: CGFloat) {
        guard abs(goal - a.x) > step else { a.x = goal; return }
        a.facingLeft = goal < a.x
        a.x += goal > a.x ? step : -step
    }
}
