// SceneSnapshot：离屏渲染表现层（README 配图 / 宣传图用）。和刘海里跑的是同一套图层代码，
// 但不截屏：没有物理刘海的黑块、尺寸和时刻完全可控，画面干净。
// 调试命令：catland-debug snapshots:<输出目录>
import AppKit
import SwiftUI

@MainActor
enum SceneSnapshot {
    struct Preset {
        let file: String
        let date: String          // yyyy-MM-dd HH:mm（本地时间）
        let condition: String
        var intensity = 0.7
        var city: SceneLocation = .shanghai
        var event: String? = nil
        var bubble: String? = nil
        var size = CGSize(width: 560, height: 110)
    }

    static let presets: [Preset] = [
        Preset(file: "hero", date: "2026-10-28 21:30", condition: "clear", bubble: "点我，本小姐今天心情好", size: CGSize(width: 720, height: 150)),
        Preset(file: "autumn-afternoon", date: "2026-10-28 15:00", condition: "partly"),
        Preset(file: "dusk", date: "2026-10-28 17:12", condition: "clear"),
        Preset(file: "beijing-day", date: "2026-10-28 14:00", condition: "clear", city: .beijing),
        Preset(file: "beijing-dusk", date: "2026-10-28 17:20", condition: "clear", city: .beijing),
        Preset(file: "beijing-night", date: "2026-10-28 21:00", condition: "clear", city: .beijing),
        Preset(file: "rain-night", date: "2026-10-28 21:00", condition: "rain", intensity: 0.85),
        Preset(file: "winter-snow", date: "2027-01-15 10:00", condition: "snow", intensity: 0.9),
        Preset(file: "event-sakura", date: "2026-04-11 15:05", condition: "partly", event: "sakuraRain"),
        Preset(file: "event-meteor", date: "2026-12-13 22:05", condition: "clear", event: "meteorShower"),
        Preset(file: "event-fireworks", date: "2026-07-11 20:05", condition: "clear", event: "fireworks"),
        Preset(file: "event-lightshow", date: "2026-10-28 20:05", condition: "clear", city: .singapore, event: "lightShow"),
    ]

    /// 宣传短片：夜里的上海窗外，四只平台小猫走动、轮流说话，逐帧渲染成 PNG（frame_000.png …），再由脚本合成 GIF / MP4。
    /// 调试命令：catland-debug film:<输出目录>
    static func film(to dir: URL, seconds: Double = 9, fps: Double = 12, scale: CGFloat = 2) -> Int {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; f.timeZone = .current
        guard let start = f.date(from: "2026-10-28 21:30") else { return 0 }
        let savedEgg = Eggs.forced, savedExtra = EventScheduler.extra
        Eggs.forced = "-"; EventScheduler.extra = []
        defer { Eggs.forced = savedEgg; EventScheduler.extra = savedExtra }
        let size = CGSize(width: 720, height: 150), notch = noNotch(size)
        let lines = ["薯薯：还不点？品味有待提高哦", "bibi：才、才不是想让你点我", "铁铁：老铁，点我，整一个！"]
        let t0 = start.timeIntervalSinceReferenceDate
        func view(_ t: TimeInterval) -> some View {
            let env = SceneEnv(date: Date(timeIntervalSinceReferenceDate: t), condition: "clear", temperature: nil, mouse: 0, location: .shanghai, intensity: 0.7)
            return ZStack {
                Canvas { ctx, sz in Presentation.render(SceneCanvas(ctx: ctx, size: sz, p: 1.5, env: env, notch: notch, t: t)) }
                CatStage(cast: [.shushu, .doudou, .bibi, .tietie], id: "film", pixel: 1.5, bubbles: lines, bubbleEpoch: t0, frozenTime: t)
            }
            .frame(width: size.width, height: size.height)
            .environment(\.displayScale, scale)
        }
        // 先让小猫们跑 4 秒，走到各自的位置
        for k in 0..<120 { _ = ImageRenderer(content: view(t0 - 4 + Double(k) / 30)).cgImage }
        var n = 0
        for i in 0..<Int(seconds * fps) {
            let r = ImageRenderer(content: view(t0 + Double(i) / fps))
            r.scale = scale
            guard let cg = r.cgImage, let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { continue }
            if (try? data.write(to: dir.appendingPathComponent(String(format: "frame_%03d.png", i)))) != nil { n += 1 }
        }
        return n
    }

    /// 渲染全部预设到目录，返回写出的文件。
    static func renderAll(to dir: URL, scale: CGFloat = 2) -> [URL] {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let saved = EventScheduler.extra, savedEgg = Eggs.forced
        Eggs.forced = "-" // 宣传图里不出随机彩蛋，画面只表达该场景本身
        defer { EventScheduler.extra = saved; Eggs.forced = savedEgg }
        return presets.compactMap { p in
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; f.timeZone = .current
            guard let date = f.date(from: p.date) else { return nil }
            EventScheduler.extra = p.event.map { [EventOccurrence(eventID: $0, start: date.addingTimeInterval(-300))] } ?? []
            let env = SceneEnv(date: date, condition: p.condition, temperature: nil, mouse: 0, location: p.city, intensity: p.intensity)
            let url = dir.appendingPathComponent("\(p.file).png")
            return render(env: env, size: p.size, bubble: p.bubble, scale: scale, pickPeak: p.event != nil, to: url) ? url : nil
        }
    }

    /// 画面里「亮而鲜艳」的像素数：用来给事件挑最好看的瞬间（烟花正盛、流星正多）。
    private static func vividness(_ cg: CGImage) -> Int {
        let w = cg.width, h = cg.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var n = 0
        for i in stride(from: 0, to: buf.count, by: 16) {
            let r = Int(buf[i]), g = Int(buf[i + 1]), b = Int(buf[i + 2])
            let mx = max(r, g, b), mn = min(r, g, b)
            if mx > 170 && (mx - mn > 70 || mn > 225) { n += 1 }
        }
        return n
    }

    static func render(env: SceneEnv, size: CGSize, bubble: String?, scale: CGFloat, pickPeak: Bool = false, to url: URL) -> Bool {
        var env = env
        if pickPeak {
            // 在事件进行中试 24 个时刻，选最「热闹」的一帧。
            var best: (Date, Int) = (env.date, -1)
            for k in 0..<24 {
                var e = env
                e.date = env.date.addingTimeInterval(Double(k) * 0.37)
                let r = ImageRenderer(content: sceneOnly(env: e, size: size, scale: scale))
                r.scale = 1
                if let cg = r.cgImage { let v = vividness(cg); if v > best.1 { best = (e.date, v) } }
            }
            env.date = best.0
        }
        return renderFrame(env: env, size: size, bubble: bubble, scale: scale, to: url)
    }

    private static func noNotch(_ size: CGSize) -> NotchGeometry {
        NotchGeometry(screenFrame: CGRect(origin: .zero, size: size), notchSize: CGSize(width: 0, height: 30), hasNotch: false)
    }

    private static func sceneOnly(env: SceneEnv, size: CGSize, scale: CGFloat) -> some View {
        let notch = noNotch(size), t = env.date.timeIntervalSinceReferenceDate
        return Canvas { ctx, sz in Presentation.render(SceneCanvas(ctx: ctx, size: sz, p: 1.5, env: env, notch: notch, t: t)) }
            .frame(width: size.width, height: size.height)
            .environment(\.displayScale, scale)
    }

    private static func renderFrame(env: SceneEnv, size: CGSize, bubble: String?, scale: CGFloat, to url: URL) -> Bool {
        // 没有刘海的几何：整面都是窗，不画横梁；收起态高度按画布算，楼高不额外放大。
        // 收起态高度取小一些：楼群按比例长高，城市成为画面主体，而不是一大片天。
        let notch = noNotch(size)
        let t = env.date.timeIntervalSinceReferenceDate
        let p: CGFloat = 1.5
        let live = EventScheduler.active(now: env.date, region: RestDays.region(for: env.location), latitude: env.location.latitude)
        CatDirector.shared.watching = live != nil
        let id = "snapshot-\(Int(t))"
        func view(catTime: TimeInterval) -> some View {
            ZStack {
                Canvas { ctx, sz in
                    Presentation.render(SceneCanvas(ctx: ctx, size: sz, p: p, env: env, notch: notch, t: t))
                }
                CatStage(cast: [.shushu, .doudou, .bibi, .tietie], id: id, pixel: p, bubbles: bubble.map { [Persona.shushu.say($0)] } ?? [], bubbleEpoch: catTime, frozenTime: catTime)
            }
            .frame(width: size.width, height: size.height)
            .environment(\.displayScale, scale)
        }

        // 先让小猫的时钟往前跑 4 秒（逐帧），走到各自的位置、摆好动作，再出最终画面。
        for k in 0..<120 { _ = ImageRenderer(content: view(catTime: t - 4 + Double(k) / 30)).cgImage }
        let renderer = ImageRenderer(content: view(catTime: t))
        renderer.scale = scale
        guard let cg = renderer.cgImage else { return false }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: url)) != nil
    }
}

