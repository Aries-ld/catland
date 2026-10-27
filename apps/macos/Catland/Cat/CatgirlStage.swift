// CatgirlStage：刘海里的猫娘（人设见 docs/design/catgirls.md）。
// 接入了哪个平台，对应的猫娘就住进来；什么都没接入时只有纸箱猫娘箱箱。第一次接入平台时，
// 箱箱从纸箱里跳出来欢呼，然后猫娘们登场。
// 每位猫娘是一个演员：待机 → 走几步 → 待机……隔一阵做一次招牌动作（薯薯转伞、抖抖跳舞、bibi 比耶、铁铁叉腰大笑）；
// 悬停时一起做招牌动作；有事件时停下来抬头看。
// 收起态只在刘海两侧看得见的地方活动；悬停时窗户变大，可以走到刘海下方。
import AppKit
import SwiftUI

/// 猫娘图集：scripts/build_catgirls.py 生成的 Resources/Catgirls/<角色>.png（每行一个动作）+ catgirls.json。
final class CatgirlAtlas {
    static let shared = CatgirlAtlas()

    struct Anim { let row: Int; let frames: Int }
    private(set) var cell = 64
    private var anims: [String: [String: Anim]] = [:]
    private var sheets: [String: CGImage] = [:]
    private var cache: [String: Image] = [:]

    private init() {
        guard let url = Bundle.main.url(forResource: "catgirls", withExtension: "json", subdirectory: "Catgirls"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        cell = json["cell"] as? Int ?? 64
        for (name, v) in json["characters"] as? [String: [String: [String: Int]]] ?? [:] {
            anims[name] = v.compactMapValues { d in d["row"].flatMap { r in d["frames"].map { Anim(row: r, frames: $0) } } }
            if let u = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Catgirls"),
               let src = CGImageSourceCreateWithURL(u as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                sheets[name] = img
            }
        }
    }

    func anim(_ persona: Persona, _ action: String) -> Anim? { anims[persona.rawValue]?[action] }

    func frame(_ persona: Persona, _ action: String, _ index: Int) -> Image? {
        guard let a = anim(persona, action), let sheet = sheets[persona.rawValue] else { return nil }
        let i = index % max(1, a.frames)
        let key = "\(persona.rawValue)/\(action)/\(i)"
        if let img = cache[key] { return img }
        guard let cg = sheet.cropping(to: CGRect(x: i * cell, y: a.row * cell, width: cell, height: cell)) else { return nil }
        let img = Image(decorative: cg, scale: 1).interpolation(.none)
        cache[key] = img
        return img
    }
}

/// 猫娘们的行为状态（跨帧保存）。
final class CatgirlDirector {
    static let shared = CatgirlDirector()
    /// 有事件进行时，大家停下来看窗外。
    var watching = false

    struct Actor {
        var x: CGFloat
        var target: CGFloat
        var facingLeft = false
        var action = "idle"
        var actionStart: TimeInterval
        var until: TimeInterval
        var nextSign: TimeInterval
        var wasExcited = false
    }

    struct Snapshot { let persona: Persona; let x: CGFloat; let action: String; let frame: Int; let facingLeft: Bool }

    private var actors: [Persona: Actor] = [:]
    private var lastTick: TimeInterval = 0
    /// 上一帧在场的是不是只有箱箱：从箱箱切到猫娘时先播「跳出纸箱」。
    private var wasBoxOnly = true
    private var popUntil: TimeInterval = 0
    static let fps = 8.0

    func tick(cast: [Persona], lanes: [Persona: ClosedRange<CGFloat>], time t: TimeInterval, excited: Bool) -> [Snapshot] {
        let dt = min(0.2, max(0, t - lastTick))
        lastTick = t
        let boxOnly = cast == [.box]
        if wasBoxOnly && !boxOnly && actors[.box] != nil { popUntil = t + 1.6 }
        wasBoxOnly = boxOnly
        // 箱箱跳出纸箱的这 1.6 秒：只演箱箱
        if t < popUntil, let box = actors[.box] {
            let f = Int((t - (popUntil - 1.6)) * Self.fps)
            return [Snapshot(persona: .box, x: box.x, action: "pop", frame: f, facingLeft: false)]
        }
        for p in actors.keys where !cast.contains(p) { actors[p] = nil }

        var out: [Snapshot] = []
        for p in cast {
            guard let lane = lanes[p] else { continue }
            var a = actors[p] ?? Actor(x: .random(in: lane), target: .random(in: lane), actionStart: t, until: t + .random(in: 1...4),
                                       nextSign: t + .random(in: 12...30))
            a.x = min(max(a.x, lane.lowerBound), lane.upperBound)
            let hasWalk = CatgirlAtlas.shared.anim(p, "walk") != nil, hasSign = CatgirlAtlas.shared.anim(p, "sign") != nil
            if excited && !a.wasExcited && hasSign { start(&a, "sign", t, duration: 2.0) }
            a.wasExcited = excited
            if watching && a.action != "idle" { start(&a, "idle", t, duration: 2) }

            switch a.action {
            case "walk":
                let speed: CGFloat = 10 // pt/s，慢悠悠地走
                let step = speed * CGFloat(dt)
                if abs(a.target - a.x) <= step { a.x = a.target; start(&a, "idle", t, duration: .random(in: 3...7)) }
                else { a.facingLeft = a.target < a.x; a.x += a.target < a.x ? -step : step }
            default:
                if t >= a.until {
                    if !watching && hasSign && t >= a.nextSign {
                        start(&a, "sign", t, duration: 2.0)
                        a.nextSign = t + .random(in: 25...50)
                    } else if !watching && hasWalk && Double.random(in: 0..<1) < 0.55 {
                        a.target = .random(in: lane)
                        if abs(a.target - a.x) > 3 { start(&a, "walk", t, duration: 60) } else { start(&a, "idle", t, duration: .random(in: 2...5)) }
                    } else {
                        start(&a, "idle", t, duration: .random(in: 3...7))
                    }
                }
            }
            actors[p] = a
            out.append(Snapshot(persona: p, x: a.x, action: a.action, frame: Int((t - a.actionStart) * Self.fps), facingLeft: a.facingLeft))
        }
        return out
    }

    private func start(_ a: inout Actor, _ action: String, _ t: TimeInterval, duration: TimeInterval) {
        a.action = action
        a.actionStart = t
        a.until = t + duration
    }
}

struct CatgirlStage: View {
    let cast: [Persona]
    /// 物理刘海的左右边界（pt，本视图坐标）；nil 表示没有刘海或可以走到刘海下方。
    var notchSpan: ClosedRange<CGFloat>?
    /// 一个美术像素对应多少 pt：0.5pt = Retina 上 1 个物理像素，保证锐利。
    var pixel: CGFloat = 0.5
    var excited = false
    var bubbles: [String] = []
    var bubbleEpoch: TimeInterval = 0
    /// 离屏渲染（宣传图）用：固定在某一时刻、不跑动画。
    var frozenTime: TimeInterval? = nil

    var body: some View {
        if let ft = frozenTime { canvas(t: ft) } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in canvas(t: tl.date.timeIntervalSinceReferenceDate) }
        }
    }

    private func canvas(t: TimeInterval) -> some View {
        Canvas { ctx, size in
            let cell = CGFloat(CatgirlAtlas.shared.cell) * pixel
            let snaps = CatgirlDirector.shared.tick(cast: cast, lanes: lanes(width: size.width, spriteWidth: cell * 0.5), time: t, excited: excited)
            let ground = size.height - pixel * 2
            for s in snaps.sorted(by: { $0.x < $1.x }) {
                guard let img = CatgirlAtlas.shared.frame(s.persona, s.action, s.frame) else { continue }
                var c = ctx
                let rect = CGRect(x: (s.x / pixel).rounded() * pixel - cell / 2, y: ground - cell, width: cell, height: cell)
                if s.facingLeft {
                    c.translateBy(x: rect.midX, y: 0)
                    c.scaleBy(x: -1, y: 1)
                    c.translateBy(x: -rect.midX, y: 0)
                }
                c.draw(img, in: rect)
            }
            // 气泡：由报名字的那位猫娘说；她不在场就由第一位说
            if !bubbles.isEmpty, !snaps.isEmpty {
                let text = bubbles[max(0, Int((t - bubbleEpoch) / 3)) % bubbles.count]
                let speaker = snaps.first { text.hasPrefix("\($0.persona.name)：") } ?? snaps[0]
                drawBubble(text, at: speaker.x, top: ground - cell * 0.78, in: &ctx, size: size)
            }
        }
        .allowsHitTesting(false)
    }

    /// 每位猫娘的活动区间：收起态在刘海两侧（偶数位左侧、奇数位右侧，同侧的两位各占一半）；悬停时整条都能走。
    private func lanes(width: CGFloat, spriteWidth: CGFloat) -> [Persona: ClosedRange<CGFloat>] {
        let half = spriteWidth / 2 + 2
        var out: [Persona: ClosedRange<CGFloat>] = [:]
        guard let span = notchSpan else {
            let n = CGFloat(max(1, cast.count)), w = (width - 2 * half) / n
            for (i, p) in cast.enumerated() { out[p] = (half + CGFloat(i) * w)...(half + CGFloat(i + 1) * w) }
            return out
        }
        let sides = [(half...max(half, span.lowerBound - half)), (min(width - half, span.upperBound + half)...(width - half))]
        let groups = [cast.enumerated().filter { $0.offset % 2 == 0 }.map(\.element), cast.enumerated().filter { $0.offset % 2 == 1 }.map(\.element)]
        // 同一侧有两位时各占一半，并在中间留出一个身位，避免叠在一起
        let gap = spriteWidth / 2
        for (side, members) in zip(sides, groups) where !members.isEmpty {
            let w = (side.upperBound - side.lowerBound) / CGFloat(members.count)
            for (i, p) in members.enumerated() {
                let lo = side.lowerBound + CGFloat(i) * w + (i > 0 ? gap : 0)
                let hi = side.lowerBound + CGFloat(i + 1) * w - (i < members.count - 1 ? gap : 0)
                out[p] = lo <= hi ? lo...hi : ((lo + hi) / 2)...((lo + hi) / 2)
            }
        }
        return out
    }

    private func drawBubble(_ text: String, at cx: CGFloat, top: CGFloat, in ctx: inout GraphicsContext, size: CGSize) {
        let px: CGFloat = 1.5
        let label = ctx.resolve(Text(text).font(.system(size: 9, weight: .bold, design: .rounded)).foregroundColor(Color(red: 0.16, green: 0.14, blue: 0.2)))
        let ts = label.measure(in: CGSize(width: max(60, size.width - 8), height: 40))
        let w = ((ts.width + 8 * px) / px).rounded(.up) * px, h = ((ts.height + 3 * px) / px).rounded(.up) * px
        let x = min(max(px, ((cx - w / 2) / px).rounded() * px), size.width - w - px)
        let y = max(px, top - h - 3 * px)
        let border = Color(red: 0.16, green: 0.14, blue: 0.2)
        ctx.fill(Path(CGRect(x: x - px, y: y, width: w + 2 * px, height: h)), with: .color(border))
        ctx.fill(Path(CGRect(x: x, y: y - px, width: w, height: h + 2 * px)), with: .color(border))
        ctx.fill(Path(CGRect(x: x, y: y, width: w, height: h)), with: .color(.white.opacity(0.96)))
        let tx = min(max(x + 2 * px, ((cx - px) / px).rounded() * px), x + w - 3 * px)
        ctx.fill(Path(CGRect(x: tx, y: y + h, width: 2 * px, height: px)), with: .color(.white.opacity(0.96)))
        ctx.fill(Path(CGRect(x: tx, y: y + h + px, width: px, height: px)), with: .color(border))
        ctx.fill(Path(CGRect(x: tx + 2 * px, y: y + h, width: px, height: px)), with: .color(border))
        ctx.draw(label, at: CGPoint(x: x + w / 2, y: y + h / 2), anchor: .center)
    }
}
