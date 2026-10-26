// CatStage：小猫的随机行为引擎 + 绘制。
// 每只猫是一个「演员」：在自己的活动区间里按权重随机选动作（发呆、东张西望、坐下、舔爪、打哈欠、打盹、
// 趴成面包、伸懒腰、追蝴蝶、翻肚皮、走几步），节奏和停顿随机；悬停时开心地蹦一下冒爱心；
// 每隔几分钟有一只猫走出画面「下班」，换一只随机花色的新猫走进来。
// 猫洞（刘海 = 天花板上的猫洞）：猫会走到刘海下方跳进洞里「消失」，在洞里时洞口会垂下尾巴、
// 伸出爪子或飘出 z，过一阵再跳下来。
import SwiftUI

/// 猫洞位置（CatStage 坐标，pt）：刘海的左右边界与底边。
struct CatDen: Equatable {
    let minX: CGFloat
    let maxX: CGFloat
    let bottom: CGFloat
}

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
    var den: CatDen? = nil
    /// 悬停时某只猫头顶冒出的像素对话气泡，多句时每 3.5 秒轮换一句（第一句通常是「点我开刷 · 21°晴」）。
    var bubbles: [String] = []
    /// 轮播起点（悬停开始的时刻），保证每次都从第一句开始。
    var bubbleEpoch: TimeInterval = 0
    /// 离屏渲染（宣传图）用：固定在某一时刻、不跑动画。
    var frozenTime: TimeInterval? = nil

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        if let ft = frozenTime {
            canvas(t: ft)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in canvas(t: tl.date.timeIntervalSinceReferenceDate) }
        }
    }

    private func canvas(t: TimeInterval) -> some View {
            Canvas { ctx, size in
                let px = pixel > 0 ? pixel : max(1, (1.5 * displayScale).rounded()) / max(displayScale, 1)
                var speaker: CatDirector.Snapshot?
                for i in 0..<cats {
                    let lane = CatDirector.shared.lane(for: i, count: cats, width: size.width, hidden: hiddenWidth, catWidth: CGFloat(PixelCatArt.width) * px)
                    let snap = CatDirector.shared.tick(actor: "\(id)#\(i)", lane: lane, pixel: px, time: t, excited: excited,
                                                       den: den, groundToDen: den.map { size.height - px - $0.bottom } ?? 0)
                    if let effect = snap.denEffect, let den { drawDenEffect(effect, skin: snap.skin, den: den, in: &ctx, px: px, t: t) }
                    if snap.opacity > 0 { draw(snap, in: &ctx, size: size, px: px) }
                    // 说话的猫：选第一只不在刘海下方（头不会被刘海挡住）的猫。
                    let catTop = size.height - px - CGFloat(PixelCatArt.height - 3) * px
                    let hidden = den.map { snap.x > $0.minX && snap.x < $0.maxX && catTop - 14 * px < $0.bottom } ?? false
                    if speaker == nil, snap.opacity > 0.9, snap.lift == 0, !hidden { speaker = snap }
                }
                if !bubbles.isEmpty, let s = speaker {
                    // 每句停留 3 秒。
                    let text = bubbles[max(0, Int((t - bubbleEpoch) / 3)) % bubbles.count]
                    drawBubble(text, above: s, in: &ctx, size: size, px: px)
                }
            }
            .allowsHitTesting(false)
    }

    private func draw(_ s: CatDirector.Snapshot, in ctx: inout GraphicsContext, size: CGSize, px: CGFloat) {
        let a = s.animation
        let frame = a.frames[min(max(s.frame, 0), a.frames.count - 1)]
        let w = CGFloat(a.frameWidth) * px, h = CGFloat(a.frameHeight) * px
        // 脚踩在倒数第二行，最后一行留给影子；lift 为跳进 / 跳出猫洞时的离地高度。
        var rect = CGRect(x: s.x - w / 2, y: size.height - h - px - s.lift, width: w, height: h)
        rect.origin.x = (rect.origin.x / px).rounded() * px // 对齐像素网格，避免发糊
        rect.origin.y = (rect.origin.y / px).rounded() * px
        var c = ctx
        c.opacity = s.opacity
        // 脚下的影子：离地越高越淡。
        let shadowW = CGFloat(PixelCatArt.width - 5) * px
        let shadowA = 0.28 * max(0, 1 - Double(s.lift / (12 * px)))
        if shadowA > 0.02 {
            c.fill(Path(CGRect(x: ((s.x - shadowW / 2) / px).rounded() * px, y: size.height - px, width: shadowW, height: px)), with: .color(.black.opacity(shadowA)))
        }
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

    /// 像素风对话气泡：白底、1 像素深色描边、方角，带一个指向猫头的小尾巴。
    private func drawBubble(_ text: String, above s: CatDirector.Snapshot, in ctx: inout GraphicsContext, size: CGSize, px: CGFloat) {
        let label = ctx.resolve(Text(text).font(.system(size: 9, weight: .bold, design: .rounded)).foregroundColor(Color(red: 0.16, green: 0.14, blue: 0.2)))
        let ts = label.measure(in: CGSize(width: 300, height: 40))
        let w = ((ts.width + 8 * px) / px).rounded(.up) * px, h = ((ts.height + 3 * px) / px).rounded(.up) * px
        let catTop = size.height - px - CGFloat(PixelCatArt.height - 3) * px
        var x = ((s.x - w / 2) / px).rounded() * px
        x = min(max(px, x), size.width - w - px)
        let y = max(px, catTop - h - 3 * px)
        let border = Color(red: 0.16, green: 0.14, blue: 0.2)
        ctx.fill(Path(CGRect(x: x - px, y: y, width: w + 2 * px, height: h)), with: .color(border))
        ctx.fill(Path(CGRect(x: x, y: y - px, width: w, height: h + 2 * px)), with: .color(border))
        ctx.fill(Path(CGRect(x: x, y: y, width: w, height: h)), with: .color(.white.opacity(0.96)))
        // 尾巴：两格台阶
        let tx = min(max(x + 2 * px, ((s.x - px) / px).rounded() * px), x + w - 3 * px)
        ctx.fill(Path(CGRect(x: tx, y: y + h, width: 2 * px, height: px)), with: .color(.white.opacity(0.96)))
        ctx.fill(Path(CGRect(x: tx, y: y + h + px, width: px, height: px)), with: .color(border))
        ctx.fill(Path(CGRect(x: tx + 2 * px, y: y + h, width: px, height: px)), with: .color(border))
        ctx.draw(label, at: CGPoint(x: x + w / 2, y: y + h / 2), anchor: .center)
    }

    /// 猫在洞里时，洞口（刘海底边）露出来的小动作。
    private func drawDenEffect(_ e: CatDirector.DenEffect, skin name: String, den: CatDen, in ctx: inout GraphicsContext, px: CGFloat, t: TimeInterval) {
        guard let skin = PixelCatArt.skins.first(where: { $0.name == name }) else { return }
        let base = PixelCatArt.color("B", x: 0, y: 0, skin: skin).map(Self.color) ?? .orange
        let tail = PixelCatArt.color("T", x: 1, y: 0, skin: skin).map(Self.color) ?? base
        let paw = PixelCatArt.color("L", x: 0, y: 11, skin: skin).map(Self.color) ?? base
        let x0 = (e.x / px).rounded() * px, y0 = (den.bottom / px).rounded() * px
        func dot(_ dx: Int, _ dy: Int, _ c: Color) { ctx.fill(Path(CGRect(x: x0 + CGFloat(dx) * px, y: y0 + CGFloat(dy) * px, width: px, height: px)), with: .color(c)) }
        switch e.kind {
        case .tail:
            // 垂下的尾巴，末端左右摆动。
            let len = 5
            for k in 0..<len {
                let sway = k >= 2 ? Int((sin(t * 2.2 + Double(k) * 0.6) * Double(k - 1) * 0.6).rounded()) : 0
                dot(sway, k, k % 2 == 0 ? tail : base)
            }
        case .paws:
            // 两只前爪扒着洞口边，偶尔动一下。
            let wiggle = Int(t * 1.5) % 5 == 0 ? 1 : 0
            dot(-2, 0, paw); dot(-2, 1 + wiggle, paw); dot(-1, 1 + wiggle, paw)
            dot(2, 0, paw); dot(2, 1, paw); dot(3, 1, paw)
        case .sleep:
            // 洞里在睡觉：飘出 z。
            let phase = t.truncatingRemainder(dividingBy: 3) / 3
            let z = Color(red: 0.8, green: 0.85, blue: 1).opacity(1 - phase)
            dot(1 + Int(phase * 3), 1 + Int(phase * 4), z)
            if phase > 0.4 { dot(3 + Int(phase * 2), 2 + Int(phase * 5), z.opacity(0.6)) }
        }
    }

    private static func color(_ rgb: UInt32) -> Color {
        Color(red: Double(rgb >> 16 & 0xFF) / 255, green: Double(rgb >> 8 & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
    }
}

/// 所有猫演员的状态与随机决策。
final class CatDirector {
    static let shared = CatDirector()

    struct Lane { let min: CGFloat; let max: CGFloat; let exitLeft: Bool }

    struct DenEffect {
        enum Kind: CaseIterable { case tail, paws, sleep }
        let kind: Kind
        let x: CGFloat
    }

    struct Snapshot {
        let animation: CatAnimation
        let frame: Int
        let x: CGFloat
        let lift: CGFloat
        let facingLeft: Bool
        let opacity: Double
        let rim: Bool
        let skin: String
        let denEffect: DenEffect?
        var action: String = ""
    }

    private enum Phase {
        case acting, walking(to: CGFloat), entering, leaving
        /// 走到洞口下方 → 起跳钻进洞 → 在洞里 → 跳下来
        case toDen(x: CGFloat), climbing(from: TimeInterval), inDen(until: TimeInterval, effect: DenEffect.Kind), dropping(from: TimeInterval)
    }

    private struct Actor {
        var skin: String
        var x: CGFloat
        var lift: CGFloat = 0
        var facingLeft = true
        var action = "idle"
        var phase: Phase = .acting
        var started: TimeInterval = 0
        var until: TimeInterval = 0
        var lastTick: TimeInterval = 0
        var nextSwap: TimeInterval = 0
        var wasExcited = false
        var loops = 1
        var effectChange: TimeInterval = 0
    }

    private var actors: [String: Actor] = [:]
    /// 调试：下一次决策时强制去猫洞。
    var forceDen = false
    /// 窗外有事件（流星雨、烟花…）正在进行：所有猫停下来坐着抬头看。
    var watching = false
    private var onStage: Set<String> { Set(actors.values.map(\.skin)) }
    /// 同一时刻只允许一只猫在洞里（洞口小，效果更清楚）。
    private var denOccupied: Bool { actors.values.contains { if case .inDen = $0.phase { return true }; if case .climbing = $0.phase { return true }; return false } }
    /// 走路速度：每秒多少个美术像素。
    private let walkSpeed: CGFloat = 9
    /// 离场 / 入场时走到区间外多远。
    private let offstage: CGFloat = 26
    private let jumpTime: TimeInterval = 0.45

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

    func tick(actor id: String, lane: Lane, pixel: CGFloat, time t: TimeInterval, excited: Bool, den: CatDen? = nil, groundToDen: CGFloat = 0) -> Snapshot {
        let atlas = CatAtlas.shared
        var a = actors[id] ?? newActor(lane: lane, time: t)
        let dt = a.lastTick == 0 ? 0 : min(0.1, t - a.lastTick)
        a.lastTick = t
        let step = walkSpeed * pixel * CGFloat(dt)
        // 跳进洞需要的高度：整只猫越过刘海底边。
        let denLift = groundToDen + CGFloat(PixelCatArt.height) * pixel

        // 事件开始：正在发呆 / 散步的猫原地坐下看窗外；事件结束：起身继续自己的事。
        if watching, a.action != "watch" {
            switch a.phase {
            case .acting, .walking: start(&a, action: "watch", time: t)
            default: break
            }
        } else if !watching, a.action == "watch", case .acting = a.phase, a.until > t + 1 {
            a.until = t
        }
        if excited && !a.wasExcited, case .acting = a.phase, a.action != "watch" { start(&a, action: "hop", time: t) }
        a.wasExcited = excited
        var effect: DenEffect?

        switch a.phase {
        case .walking(let goal):
            moveToward(&a, goal: goal, step: step)
            if abs(a.x - goal) < 0.5 { decide(&a, lane: lane, time: t, den: den) }
        case .entering:
            let goal = lane.exitLeft ? lane.min + 4 : lane.max - 4
            moveToward(&a, goal: goal, step: step)
            if abs(a.x - goal) < 0.5 { start(&a, action: "look", time: t) }
        case .leaving:
            let exit = lane.exitLeft ? lane.min - offstage : lane.max + offstage
            moveToward(&a, goal: exit, step: step)
            if abs(a.x - exit) < 0.5 { a = newActor(lane: lane, time: t, entering: true, excluding: onStage) }
        case .acting:
            if t >= a.until { decide(&a, lane: lane, time: t, den: den) }
        case .toDen(let goal):
            moveToward(&a, goal: goal, step: step)
            if abs(a.x - goal) < 0.5 {
                a.phase = .climbing(from: t)
                a.action = "hop"
                a.started = t
            }
        case .climbing(let from):
            let k = min(1, (t - from) / jumpTime)
            a.lift = denLift * CGFloat(1 - pow(1 - k, 2)) // 先快后慢的起跳
            if k >= 1 {
                a.phase = .inDen(until: t + Double.random(in: 18...50), effect: DenEffect.Kind.allCases.randomElement()!)
                a.effectChange = t + Double.random(in: 5...10)
            }
        case .inDen(let until, var kind):
            if t >= a.effectChange {
                kind = DenEffect.Kind.allCases.randomElement()!
                a.effectChange = t + Double.random(in: 5...10)
                a.phase = .inDen(until: until, effect: kind)
            }
            effect = DenEffect(kind: kind, x: a.x)
            if t >= until {
                a.phase = .dropping(from: t)
                a.action = "hop"
                a.started = t
            }
        case .dropping(let from):
            let k = min(1, (t - from) / (jumpTime * 0.8))
            a.lift = denLift * CGFloat(1 - k * k) // 自由落体般加速落地
            if k >= 1 {
                a.lift = 0
                start(&a, action: "look", time: t)
            }
        }
        actors[id] = a

        let anim = atlas.cats[a.skin]?[a.action] ?? atlas.cats[a.skin]!["idle"]!
        let raw = Int((t - a.started) * anim.fps)
        let edge = lane.exitLeft ? a.x - (lane.min - offstage) : (lane.max + offstage) - a.x
        var opacity = min(1, max(0, Double(edge) / 16))
        if case .inDen = a.phase { opacity = 0 }
        return Snapshot(animation: anim, frame: Self.frameIndex(raw: raw, anim: anim, loops: a.loops), x: a.x, lift: a.lift, facingLeft: a.facingLeft,
                        opacity: opacity, rim: atlas.rimmed.contains(a.skin), skin: a.skin, denEffect: effect, action: a.action)
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
    private func decide(_ a: inout Actor, lane: Lane, time t: TimeInterval, den: CatDen?) {
        if t >= a.nextSwap {
            a.phase = .leaving
            a.action = "walk"
            a.facingLeft = lane.exitLeft
            a.started = t
            return
        }
        // 去猫洞：洞没人占、并且这只猫离洞不太远时才考虑。
        if let den, !denOccupied, forceDen || Double.random(in: 0..<1) < 0.14 {
            forceDen = false
            let margin = CGFloat(PixelCatArt.width)
            let target = CGFloat.random(in: (den.minX + margin)...max(den.minX + margin + 1, den.maxX - margin))
            a.facingLeft = target < a.x
            a.phase = .toDen(x: target)
            a.action = "walk"
            a.started = t
            return
        }
        let have = CatAtlas.shared.cats[a.skin] ?? [:]
        let season = SceneSeason.current
        let options = have.filter { $0.key != "hop" }.map { ($0.key, ($0.key == a.action ? $0.value.weight * 0.3 : $0.value.weight) * season.catWeight($0.key)) }
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
