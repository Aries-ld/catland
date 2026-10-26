// 事件模块：窗外按排期发生的「大事件」（流星雨、花火大会、灯光秀、樱花雨…），每次持续 10 分钟。
//   - 排期：每个事件按日期确定性地决定今天有没有、几点开始（真实的流星雨极大日、节日、周末、季节概率）。
//   - 天气门槛：开始时再看一眼天气，不满足就取消（「天公不作美，流星雨看不成了」）。
//   - 预告：开始前 6 小时起，小猫在气泡里预告；进行中显示倒计时；小猫会停下来坐着看窗外。
//   - 天气触发型（雨后彩虹、初雪）：不排期，由天气变化触发，没有预告。
// 新增事件：实现 SceneEvent，加进 Events.all。
import SwiftUI

struct EventDay {
    let day: Date
    let region: Region
    let latitude: Double
    var season: SceneSeason { SceneSeason.of(day, latitude: latitude) }
    var calendar: Calendar { .current }
    var weekday: Int { calendar.component(.weekday, from: day) }
    var isWeekend: Bool { weekday == 1 || weekday == 7 }
    var month: Int { calendar.component(.month, from: day) }
    var dayOfMonth: Int { calendar.component(.day, from: day) }

    /// 当天 hh:mm 的时刻。
    func at(_ h: Int, _ m: Int = 0) -> Date? { calendar.date(bySettingHour: h, minute: m, second: 0, of: day) }

    /// 按（事件 id, 日期）确定性的 0~1 随机数：同一天同一事件结果不变。
    func roll(_ id: String) -> Double {
        let ord = calendar.ordinality(of: .day, in: .era, for: day) ?? 0
        let h = id.unicodeScalars.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1.value)) &* 1099511628211 }
        return SceneCanvas.chance(h &+ UInt64(ord) &* 2654435761)
    }

    func isHoliday(_ id: String) -> Bool {
        guard let h = HolidayCatalog.all.first(where: { $0.id == id }), h.applies(to: region),
              let comps = h.date(calendar.component(.year, from: day)), let d = calendar.date(from: comps) else { return false }
        return calendar.isDate(d, inSameDayAs: day)
    }
}

protocol SceneEvent {
    var id: String { get }
    var name: String { get }
    var stages: Set<SceneStage> { get }
    /// 天气触发型事件：不排期、不预告。
    var triggered: Bool { get }
    /// 今天几点开始；nil 表示今天没有。
    func start(on d: EventDay) -> Date?
    /// 开始时的天气是否允许。
    func canRun(condition: String, intensity: Double) -> Bool
    /// progress 0~1：事件进行的进度。
    func draw(_ c: SceneCanvas, stage: SceneStage, progress: Double)
    /// 预告文案，`{time}` 会替换成「今晚 20:00」之类。
    var teasers: [String] { get }
    var lives: [String] { get }
    var cancelLine: String { get }
}

extension SceneEvent {
    var triggered: Bool { false }
    func start(on d: EventDay) -> Date? { nil }
}

struct EventOccurrence: Equatable {
    let eventID: String
    let start: Date
    var end: Date { start.addingTimeInterval(EventScheduler.duration) }
    var event: SceneEvent { Events.byID[eventID]! }

    static func == (a: EventOccurrence, b: EventOccurrence) -> Bool { a.eventID == b.eventID && a.start == b.start }
}

enum Events {
    static let all: [SceneEvent] = [MeteorShower(), FireworksFestival(), NewYearFireworks(), LightShow(), SakuraRain(), FireflyNight(),
                                    BalloonFestival(), FullMoonRise(), MidAutumnMoon(), RainbowAfterRain(), FirstSnow()]
    static let byID: [String: SceneEvent] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
}

enum EventScheduler {
    static let duration: TimeInterval = 10 * 60
    static let teaserWindow: TimeInterval = 6 * 3600

    /// 调试强制 / 天气触发的事件。
    nonisolated(unsafe) static var extra: [EventOccurrence] = []

    /// now 前后（昨天、今天、明天）所有排期事件 + 触发事件，按开始时间排序。
    static func occurrences(around now: Date, region: Region, latitude: Double) -> [EventOccurrence] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var out = extra
        for offset in -1...1 {
            guard let day = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            let d = EventDay(day: day, region: region, latitude: latitude)
            for e in Events.all where !e.triggered {
                if let s = e.start(on: d) { out.append(EventOccurrence(eventID: e.id, start: s)) }
            }
        }
        return out.sorted { $0.start < $1.start }
    }

    static func active(now: Date, region: Region, latitude: Double) -> EventOccurrence? {
        occurrences(around: now, region: region, latitude: latitude).first { now >= $0.start && now < $0.end }
    }

    /// 6 小时内即将开始的下一个排期事件。
    static func upcoming(now: Date, region: Region, latitude: Double) -> EventOccurrence? {
        occurrences(around: now, region: region, latitude: latitude).first { $0.start > now && $0.start.timeIntervalSince(now) <= teaserWindow }
    }

    static func trigger(_ id: String, at date: Date = Date()) {
        guard Events.byID[id] != nil else { return }
        extra.removeAll { $0.end < date }
        if !extra.contains(where: { $0.eventID == id && $0.end > date }) { extra.append(EventOccurrence(eventID: id, start: date)) }
    }

    /// 「今晚 20:00」「下午 3:00」「明天凌晨 0:00」
    static func timeLabel(_ start: Date, now: Date) -> String {
        let cal = Calendar.current
        let h = cal.component(.hour, from: start), m = cal.component(.minute, from: start)
        let hm = String(format: "%d:%02d", h, m)
        let prefix: String
        if !cal.isDate(start, inSameDayAs: now) { prefix = h < 6 ? "明天凌晨 " : "明天 " }
        else if h >= 18 { prefix = "今晚 " }
        else if h >= 12 { prefix = "今天下午 " }
        else if h >= 6 { prefix = "今天上午 " }
        else { prefix = "凌晨 " }
        return prefix + hm
    }

    static func countdown(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        if s >= 3600 { return "\(s / 3600) 小时 \((s % 3600) / 60) 分" }
        if s >= 60 { return "\(s / 60) 分钟" }
        return "\(s) 秒"
    }

    /// 气泡里的事件文案（放在轮播最前面）：预告 + 倒计时 / 进行中 + 剩余时间 / 取消。
    static func bubbleLines(now: Date, region: Region, latitude: Double, condition: String?, intensity: Double, seed: UInt64) -> [String] {
        var rng = SeededRandom(seed: seed)
        func pick(_ a: [String]) -> String { a[Int(rng.next() % UInt64(max(1, a.count)))] }
        if let a = active(now: now, region: region, latitude: latitude) {
            let e = a.event
            guard e.canRun(condition: condition ?? "partly", intensity: intensity) else { return [e.cancelLine] }
            return [pick(e.lives), "\(e.name)还剩 \(countdown(a.end.timeIntervalSince(now)))"]
        }
        if let u = upcoming(now: now, region: region, latitude: latitude) {
            let e = u.event
            return [pick(e.teasers).replacingOccurrences(of: "{time}", with: timeLabel(u.start, now: now)),
                    "距\(e.name)还有 \(countdown(u.start.timeIntervalSince(now)))"]
        }
        return []
    }
}

/// 进行中的事件绘制在它声明的各个阶段。
struct EventsLayer: SceneLayer {
    let id: String
    let stage: SceneStage
    init(stage: SceneStage) { self.stage = stage; id = "events.\(stage.rawValue)" }
    func draw(_ c: SceneCanvas) {
        let region = RestDays.region(for: c.env.location)
        guard let a = EventScheduler.active(now: c.env.date, region: region, latitude: c.env.location.latitude) else { return }
        let e = a.event
        guard e.stages.contains(stage), e.canRun(condition: c.cond, intensity: c.intensity) else { return }
        e.draw(c, stage: stage, progress: c.env.date.timeIntervalSince(a.start) / EventScheduler.duration)
    }
}

/// 事件的淡入淡出：开头 40 秒淡入、最后 40 秒淡出。
private func envelope(_ p: Double) -> Double { min(1, min(p, 1 - p) * 15) }

private func dry(_ cond: String) -> Bool { !WeatherStyle.of(cond).wet }

// MARK: - 排期事件

/// 流星雨：真实流星雨极大日（象限仪、英仙、猎户、狮子、双子）当晚 22:00 必有；秋冬晴夜另有 12% 概率。
struct MeteorShower: SceneEvent {
    let id = "meteorShower", name = "流星雨"
    let stages: Set<SceneStage> = [.skyEvents]
    static let peaks: [(Int, Int)] = [(1, 3), (1, 4), (8, 12), (8, 13), (10, 21), (11, 17), (12, 13), (12, 14)]

    func start(on d: EventDay) -> Date? {
        if Self.peaks.contains(where: { $0.0 == d.month && $0.1 == d.dayOfMonth }) { return d.at(22) }
        if [.autumn, .winter].contains(d.season), d.roll(id) < 0.12 { return d.at(21, 30) }
        return nil
    }
    func canRun(condition: String, intensity: Double) -> Bool { ["clear", "partly"].contains(condition) }
    /// 天色压暗、星星变亮；每 0.22 秒新增一颗长拖尾流星（同时 4–6 颗在天上），每 6 秒一颗彩色大火流星。
    func draw(_ c: SceneCanvas, stage: SceneStage, progress: Double) {
        let a = envelope(progress)
        let skyH = max(8, c.cityBase - c.skyTop)
        c.fill(0, c.skyTop, c.cols, skyH, Color(red: 0.02, green: 0.03, blue: 0.1).opacity(0.25 * a))
        var srng = SeededRandom(seed: 909)
        for _ in 0..<30 {
            let x = Int(srng.next() % UInt64(max(1, c.cols))), y = c.skyTop + Int(srng.next() % UInt64(skyH))
            let tw = 0.5 + 0.5 * sin(c.t * 2 + Double(x))
            c.fill(x, y, 1, 1, Color.white.opacity(0.7 * tw * a))
        }
        let slot = 0.22, life = 0.9
        for k in 0..<5 {
            let n = Int(c.t / slot) - k
            let age = c.t - Double(n) * slot
            guard age < life else { continue }
            var rng = SeededRandom(seed: UInt64(truncatingIfNeeded: n &* 7919))
            let x0 = Int(rng.next() % UInt64(max(1, c.cols + 20))), y0 = c.skyTop + Int(rng.next() % UInt64(max(1, skyH / 2)))
            let len = 10 + Int(rng.next() % 8)
            let k01 = age / life
            let hx = x0 - Int(k01 * 26), hy = y0 + Int(k01 * 13)
            streak(c, headX: hx, headY: hy, length: len, color: Color.white, alpha: a * (1 - k01 * 0.6), thick: false)
        }
        // 大火流星：更粗、带颜色、头部发光
        let big = c.t.truncatingRemainder(dividingBy: 6)
        if big < 1.2 {
            var rng = SeededRandom(seed: UInt64(Int(c.t / 6)) &+ 77)
            let x0 = c.cols / 3 + Int(rng.next() % UInt64(max(1, c.cols / 2))), y0 = c.skyTop + 1
            let k01 = big / 1.2
            let colors: [Color] = [Color(red: 0.55, green: 0.95, blue: 1), Color(red: 1, green: 0.85, blue: 0.4), Color(red: 0.75, green: 1, blue: 0.6)]
            streak(c, headX: x0 - Int(k01 * 40), headY: y0 + Int(k01 * 20), length: 22, color: colors[Int(c.t / 6) % 3], alpha: a, thick: true)
        }
    }

    /// 斜向 2:1 的流星：头亮、尾巴渐隐；thick 时 2 像素粗并带光晕。
    private func streak(_ c: SceneCanvas, headX: Int, headY: Int, length: Int, color: Color, alpha: Double, thick: Bool) {
        if thick { c.fill(headX - 2, headY - 2, 5, 5, color.opacity(0.25 * alpha)) }
        c.fill(headX - 1, headY, 2, 1, Color.white.opacity(alpha))
        for j in 0..<length {
            let fade = pow(1 - Double(j) / Double(length), 0.6)
            let x = headX + j, y = headY - j / 2
            c.fill(x, y, 1, thick ? 2 : 1, (j < 2 ? Color.white : color).opacity(alpha * fade))
        }
    }

    let teasers = ["{time} 有流星雨，记得来看哦", "{time} 流星雨！愿望清单准备好了吗", "{time} 流星雨，许个愿：准时下班"]
    let lives = ["流星雨来啦！快许愿", "许个愿：明天不加班", "一颗、两颗…数不过来了", "愿望很简单：发财、不加班"]
    let cancelLine = "天公不作美，流星雨看不成了 T_T"
}

/// 花火大会：夏天周六 30% 概率 20:00；中国国庆、新加坡国庆日当晚 20:00 必有。
struct FireworksFestival: SceneEvent {
    let id = "fireworks", name = "花火大会"
    let stages: Set<SceneStage> = [.shoreEvents] // 画在楼群前面：楼高起来后，画在后面会被挡住
    func start(on d: EventDay) -> Date? {
        if d.isHoliday("nationalDayCN") || d.isHoliday("nationalDaySG") { return d.at(20) }
        if [.summer, .tropical].contains(d.season), d.weekday == 7, d.roll(id) < 0.3 { return d.at(20) }
        return nil
    }
    func canRun(condition: String, intensity: Double) -> Bool { dry(condition) }
    func draw(_ c: SceneCanvas, stage: SceneStage, progress: Double) { Fireworks.draw(c, stage: stage, bursts: 5, alpha: envelope(progress)) }
    let teasers = ["{time} 有花火大会！占个好位置", "{time} 放烟花，下班别磨蹭", "{time} 花火大会，今晚的快乐有着落了"]
    let lives = ["花火大会开始啦！", "砰——好好看！", "这一刻，班味全无", "烟花很短，快乐很长"]
    let cancelLine = "下雨了，花火大会取消了，猫猫好失落"
}

/// 跨年烟花：12 月 31 日 23:55 开始，跨过零点。
struct NewYearFireworks: SceneEvent {
    let id = "newYearFireworks", name = "跨年烟花"
    let stages: Set<SceneStage> = [.shoreEvents]
    func start(on d: EventDay) -> Date? { d.month == 12 && d.dayOfMonth == 31 ? d.at(23, 55) : nil }
    func canRun(condition: String, intensity: Double) -> Bool { !["thunder", "hail"].contains(condition) }
    func draw(_ c: SceneCanvas, stage: SceneStage, progress: Double) { Fireworks.draw(c, stage: stage, bursts: progress > 0.5 ? 6 : 3, alpha: envelope(progress)) }
    let teasers = ["{time} 跨年烟花，一起倒数吧", "今年最后几小时，辛苦你了"]
    let lives = ["新年快乐！今年也辛苦啦", "新的一年，愿你不加班、多发财", "3、2、1——新年快乐！"]
    let cancelLine = "天气太凶，跨年烟花取消了，但新年快乐不打折"
}

enum Fireworks {
    /// 每朵烟花 2.6 秒一个周期：0–0.6 秒升空（拖着火星），0.6–2.0 秒绽放——24 道带拖尾的光线向外炸开并下坠，
    /// 内圈换一种颜色，中心一闪白光，末尾闪烁碎金；绽放时海湾泛起同色倒影。
    static func draw(_ c: SceneCanvas, stage: SceneStage, bursts: Int, alpha: Double) {
        let colors: [UInt32] = [0xFF5D7A, 0xFFD84A, 0x6DD3FF, 0xB98CFF, 0x7CF29A, 0xFF9A55]
        let skyH = max(8, c.cityBase - c.skyTop)
        for k in 0..<bursts {
            let cycle = 2.6, offset = Double(k) * cycle / Double(bursts)
            let local = (c.t + offset).truncatingRemainder(dividingBy: cycle)
            let n = Int((c.t + offset) / cycle)
            var rng = SeededRandom(seed: UInt64(truncatingIfNeeded: n &* 31 &+ k))
            let cx = 8 + Int(rng.next() % UInt64(max(1, c.cols - 16))), cy = c.skyTop + 6 + Int(rng.next() % UInt64(max(1, skyH / 3)))
            let col = c.rgb(colors[Int(rng.next() % UInt64(colors.count))]).color
            let inner = c.rgb(colors[Int(rng.next() % UInt64(colors.count))]).color
            if local < 0.6 {
                let y = c.cityBase - Int(Double(c.cityBase - cy) * local / 0.6)
                c.fill(cx, y, 1, 2, Color.white.opacity(alpha))
                c.fill(cx, y + 2, 1, 3, col.opacity(0.5 * alpha))
                continue
            }
            guard local < 2.0 else { continue }
            let k01 = (local - 0.6) / 1.4
            let r = 2 + k01 * 13, a = (1 - k01 * k01) * alpha, drop = k01 * k01 * 5
            c.fill(cx - 7, c.cityBase, 15, c.floorTop - c.cityBase, col.opacity(0.22 * a))
            if k01 < 0.12 {
                c.fill(cx - 2, cy - 2, 5, 5, Color.white.opacity(alpha))
                c.fill(cx - 6, cy - 6, 13, 13, col.opacity(0.18 * alpha))
            }
            for i in 0..<24 {
                let ang = Double(i) / 24 * 2 * .pi
                for tail in 0..<4 {
                    let rr = r - Double(tail) * 1.5
                    guard rr > 0 else { continue }
                    let x = cx + Int((cos(ang) * rr).rounded()), y = cy + Int((sin(ang) * rr * 0.85 + drop).rounded())
                    c.fill(x, y, 1, 1, (tail == 0 ? Color.white : col).opacity(a * (1 - Double(tail) * 0.22)))
                }
                if i % 2 == 0 {
                    let x = cx + Int((cos(ang) * r * 0.5).rounded()), y = cy + Int((sin(ang) * r * 0.45 + drop * 0.6).rounded())
                    c.fill(x, y, 1, 1, inner.opacity(a))
                }
            }
            if k01 > 0.55 {
                var g = SeededRandom(seed: UInt64(truncatingIfNeeded: n &* 131 &+ k))
                for _ in 0..<14 {
                    let gx = cx + Int(g.next() % 29) - 14, gy = cy + Int(g.next() % 19) - 6 + Int(drop)
                    if (Int(c.t * 14) + gx) % 3 == 0 { c.fill(gx, gy, 1, 1, Color(red: 1, green: 0.92, blue: 0.6).opacity(a)) }
                }
            }
        }
    }
}

/// 灯光秀：新加坡滨海湾每晚 20:00（Spectra）；上海周五、周六 30% 概率 19:30。
struct LightShow: SceneEvent {
    let id = "lightShow", name = "灯光秀"
    let stages: Set<SceneStage> = [.skyEvents, .shoreEvents]
    func start(on d: EventDay) -> Date? {
        switch d.region {
        case .singapore: return d.at(20)
        case .china: return [6, 7].contains(d.weekday) && d.roll(id) < 0.3 ? d.at(19, 30) : nil
        case .other: return nil
        }
    }
    func canRun(condition: String, intensity: Double) -> Bool { !["thunder", "hail"].contains(condition) }
    /// 地标楼顶射出扇形激光、同步来回扫；海湾升起一排被彩色灯光照亮的水幕；楼体泛起同色光晕。
    func draw(_ c: SceneCanvas, stage: SceneStage, progress: Double) {
        let a = envelope(progress)
        let palette: [Color] = [Color(red: 0.3, green: 1, blue: 0.6), Color(red: 0.3, green: 0.85, blue: 1), Color(red: 1, green: 0.35, blue: 0.85), Color(red: 1, green: 0.85, blue: 0.3)]
        let phase = Int(c.t / 3)
        let main = palette[phase % palette.count], second = palette[(phase + 1) % palette.count]
        if stage == .shoreEvents {
            // 水幕：一排高低起伏的水柱，被彩色灯光照亮，水面倒影泛色。
            let base = c.cityBase + 1
            c.fill(0, c.cityBase, c.cols, c.floorTop - c.cityBase, main.opacity(0.16 * a))
            for x in stride(from: 2, to: c.cols - 2, by: 3) {
                let h = Int((3 + 3 * sin(c.t * 2.2 + Double(x) * 0.35)) * a)
                guard h > 0 else { continue }
                for k in 0..<h { c.fill(x, base - k, 1, 1, (x / 3 % 2 == 0 ? main : second).opacity((0.55 - Double(k) * 0.05) * a)) }
                c.fill(x, base - h, 1, 1, Color.white.opacity(0.7 * a))
            }
            return
        }
        // 楼体泛光
        c.fill(0, c.cityBase - c.tall(12), c.cols, c.tall(12), main.opacity(0.08 * a))
        // 扇形激光：每个光源 6 束，同步摆动
        let sources = [c.landmarkLeft + 6, c.landmarkRight]
        let top = c.skyTop
        for (si, ox) in sources.enumerated() {
            let oy = c.cityBase - c.tall(14) - 2
            let sweep = sin(c.t * 0.9 + Double(si) * 0.8) * 0.35
            for beam in 0..<6 {
                let angle = -0.95 + Double(beam) * 0.38 + sweep // 弧度，0 = 竖直向上
                let color = beam % 2 == 0 ? main : second
                let length = Double(oy - top)
                guard length > 2 else { continue }
                for k in stride(from: 0.0, to: length, by: 1) {
                    let x = ox + Int((sin(angle) * k).rounded()), y = oy - Int((cos(angle) * k).rounded())
                    guard y >= top else { break }
                    let fade = 1 - k / length
                    c.fill(x, y, 1, 1, color.opacity(0.75 * fade * a))
                    if Int(k) % 2 == 0 { c.fill(x + 1, y, 1, 1, color.opacity(0.18 * fade * a)) }
                }
            }
            c.fill(ox - 1, oy - 1, 3, 3, Color.white.opacity(0.85 * a))
        }
    }

    let teasers = ["{time} 有灯光秀，城市要发光啦", "{time} 灯光秀，下班路上抬头看看"]
    let lives = ["灯光秀开始啦，城市在为你发光", "打工人也值得被照亮", "今天的城市，格外温柔"]
    let cancelLine = "雷雨太大，灯光秀暂停了"
}

/// 樱花雨：春天周末 35% 概率 15:00，工作日 10% 概率 16:00。
struct SakuraRain: SceneEvent {
    let id = "sakuraRain", name = "樱花雨"
    let stages: Set<SceneStage> = [.seasonFX]
    func start(on d: EventDay) -> Date? {
        guard d.season == .spring else { return nil }
        if d.isWeekend { return d.roll(id) < 0.35 ? d.at(15) : nil }
        return d.roll(id) < 0.1 ? d.at(16) : nil
    }
    func canRun(condition: String, intensity: Double) -> Bool { dry(condition) }
    /// 岸边的树开满樱花；空气泛一层淡粉；大片花瓣翻飞（两种朝向交替，看起来在翻转）；窗台上落满花瓣。
    func draw(_ c: SceneCanvas, stage: SceneStage, progress: Double) {
        let a = envelope(progress)
        let pinks: [Color] = [Color(red: 1, green: 0.72, blue: 0.82), Color(red: 1, green: 0.84, blue: 0.9), Color(red: 0.98, green: 0.6, blue: 0.75), .white]
        c.fill(0, c.skyTop, c.cols, c.floorTop - c.skyTop, Color(red: 1, green: 0.75, blue: 0.85).opacity(0.1 * a))
        // 满树樱花
        for (x, w) in TreesLayer.positions(c) {
            let y = c.cityBase
            c.fill(x - 1, y - 4, w + 2, 2, pinks[0].opacity(a))
            c.fill(x, y - 5, w, 1, pinks[1].opacity(a))
            c.fill(x + 1, y - 6, max(1, w - 2), 1, pinks[0].opacity(a))
            c.fill(x + w / 2, y - 5, 1, 1, Color.white.opacity(0.8 * a))
        }
        // 翻飞的花瓣
        var rng = SeededRandom(seed: 3131)
        for _ in 0..<Int(80 * a) {
            let speed = 0.05 + Double(rng.next() % 60) / 1000
            let ph = Double(rng.next() % 1000) / 1000
            let k = (ph + c.t * speed).truncatingRemainder(dividingBy: 1)
            let x0 = Int(rng.next() % UInt64(c.cols + 40))
            let x = x0 - Int(k * 40) + Int((sin(c.t * 2 + Double(x0)) * 2).rounded())
            let y = c.skyTop + Int(k * Double(c.floorTop - c.skyTop))
            let col = pinks[Int(rng.next() % 4)].opacity(0.95 * a)
            if (Int(c.t * 4) + x0) % 2 == 0 { c.fill(x, y, 2, 1, col) } else { c.fill(x, y, 1, 2, col) }
        }
        // 窗台上的落花
        var frng = SeededRandom(seed: 47)
        for _ in 0..<Int(Double(c.cols / 3) * min(1, progress * 4)) {
            c.fill(Int(frng.next() % UInt64(max(1, c.cols))), c.floorTop - 1 + Int(frng.next() % 2), 1, 1, pinks[Int(frng.next() % 3)].opacity(0.9))
        }
    }

    let teasers = ["{time} 会下一场樱花雨哦", "{time} 樱花雨，记得来窗边"]
    let lives = ["樱花雨！浪漫值拉满", "风一吹，满屏都是粉色", "春天在给你发糖"]
    let cancelLine = "下雨了，花瓣都被打湿了"
}

/// 萤火虫之夜：夏天 / 热带 18% 概率 21:00。
struct FireflyNight: SceneEvent {
    let id = "fireflyNight", name = "萤火虫之夜"
    let stages: Set<SceneStage> = [.shoreEvents]
    func start(on d: EventDay) -> Date? { [.summer, .tropical].contains(d.season) && d.roll(id) < 0.18 ? d.at(21) : nil }
    func canRun(condition: String, intensity: Double) -> Bool { dry(condition) }
    func draw(_ c: SceneCanvas, stage: SceneStage, progress: Double) {
        SeasonParticlesLayer().fireflies(c, count: Int(40 * envelope(progress)), spread: max(4, (c.cityBase - c.skyTop) / 2))
    }
    let teasers = ["{time} 萤火虫会出来哦", "今晚有萤火虫，{time} 见"]
    let lives = ["萤火虫出来啦，一闪一闪", "小时候的夏天回来了", "像不像童年的那个晚上"]
    let cancelLine = "下雨了，萤火虫都躲起来了"
}

/// 热气球节：春秋周末 25% 概率 10:00。
struct BalloonFestival: SceneEvent {
    let id = "balloonFestival", name = "热气球节"
    let stages: Set<SceneStage> = [.skyEvents]
    func start(on d: EventDay) -> Date? { [.spring, .autumn].contains(d.season) && d.isWeekend && d.roll(id) < 0.25 ? d.at(10) : nil }
    func canRun(condition: String, intensity: Double) -> Bool { dry(condition) && condition != "windy" }
    func draw(_ c: SceneCanvas, stage: SceneStage, progress: Double) {
        let palettes: [[UInt32]] = [[0xFF6B6B, 0xFFD84A, 0x5DA9FF], [0x7CF29A, 0xFFFFFF, 0x7CF29A], [0xB98CFF, 0xFF9A55, 0xB98CFF], [0x6DD3FF, 0xFF6FB5, 0x6DD3FF], [0xFFD84A, 0xE5322D, 0xFFD84A]]
        for (i, pal) in palettes.enumerated() {
            let x = Int((Double(i) * 37 + c.t * (0.3 + Double(i) * 0.07)).truncatingRemainder(dividingBy: Double(c.cols + 12))) - 6
            let rise = Int(progress * 6)
            HotAirBalloon.draw(c, x: x, y: max(c.skyTop + 1, c.cityBase - 10 - i * 2 - rise), palette: pal)
        }
    }
    let teasers = ["{time} 天上会飘满热气球", "{time} 热气球节，周末就该这么浪漫"]
    let lives = ["热气球升空啦！", "想坐上去，飞离工位", "天空好热闹"]
    let cancelLine = "风太大 / 下雨了，热气球没法升空"
}

/// 满月：月相接近满月的晚上 19:30，月亮从右翼地平线慢慢升起（中秋当天让给「中秋赏月」）。
struct FullMoonRise: SceneEvent {
    let id = "fullMoon", name = "满月"
    let stages: Set<SceneStage> = [.celestial]
    func start(on d: EventDay) -> Date? {
        guard let t = d.at(20), MoonPhase.isFull(t), !d.isHoliday("midAutumn") else { return nil }
        return d.at(19, 30)
    }
    func canRun(condition: String, intensity: Double) -> Bool { ["clear", "partly"].contains(condition) }
    func draw(_ c: SceneCanvas, stage: SceneStage, progress: Double) { BigMoon.draw(c, progress: progress, gold: false) }
    let teasers = ["{time} 满月升起，记得抬头看看", "满月之夜，{time} 一起赏月"]
    let lives = ["月亮好圆，今天也辛苦了", "月亮在陪你加班", "抬头看看，月亮替你记得你的努力"]
    let cancelLine = "云太厚，今晚的满月躲起来了"
}

/// 中秋赏月：中秋当晚 20:00，孔明灯缓缓升空（金色大月亮整晚都在）。
struct MidAutumnMoon: SceneEvent {
    let id = "midAutumnMoon", name = "中秋赏月"
    let stages: Set<SceneStage> = [.skyEvents]
    func start(on d: EventDay) -> Date? { d.isHoliday("midAutumn") ? d.at(20) : nil }
    func canRun(condition: String, intensity: Double) -> Bool { dry(condition) }
    /// 金色满月由天空模块整晚挂着（见 CelestialLayer）；这里画缓缓升空的孔明灯。
    func draw(_ c: SceneCanvas, stage: SceneStage, progress: Double) {
        var rng = SeededRandom(seed: 815)
        for _ in 0..<6 {
            let x = Int(rng.next() % UInt64(max(1, c.cols))), ph = Double(rng.next() % 1000) / 1000
            let k = (ph + progress * 2).truncatingRemainder(dividingBy: 1)
            let y = c.cityBase - Int(k * Double(c.cityBase - c.skyTop))
            c.fill(x + Int((sin(c.t + Double(x)) * 1).rounded()), y, 2, 2, Color(red: 1, green: 0.62, blue: 0.3).opacity(0.85 * (1 - k)))
        }
    }
    let teasers = ["{time} 中秋赏月，月饼准备好了吗", "{time} 一起看月亮，想家了就看看它"]
    let lives = ["中秋快乐！月亮好圆", "愿你所念皆团圆", "今天不加班，回家吃月饼"]
    let cancelLine = "下雨了，月亮没出来，但团圆不缺席"
}

enum BigMoon {
    static func draw(_ c: SceneCanvas, progress: Double, gold: Bool) {
        let mx = c.hasNotch ? min(c.cols - 8, c.notchCols.upperBound + 8) : c.cols - 10
        let rise = min(1, progress * 3)
        let my = c.cityBase - 4 - Int(rise * Double(max(4, c.cityBase - c.skyTop - 10)))
        let core = (gold ? c.rgb(0xFFE7A3) : c.rgb(0xF8F4E3)).color
        c.fill(mx - 4, my - 3, 11, 9, Color(red: 1, green: 0.9, blue: 0.6).opacity(0.12))
        c.fill(mx - 1, my - 2, 5, 7, core); c.fill(mx - 2, my - 1, 7, 5, core)
        c.fill(mx, my, 1, 1, core.opacity(0.7)); c.fill(mx + 2, my + 2, 1, 1, c.rgb(0xE8DDB8).color)
    }
}

// MARK: - 天气触发事件

/// 雨后彩虹：白天由雨转晴时触发。
struct RainbowAfterRain: SceneEvent {
    let id = "rainbowAfterRain", name = "雨后彩虹"
    let stages: Set<SceneStage> = [.seasonFX] // 画在城市前面：悬停时楼会长高，放在后面会被挡住
    let triggered = true
    func canRun(condition: String, intensity: Double) -> Bool { dry(condition) }
    func draw(_ c: SceneCanvas, stage: SceneStage, progress: Double) { RainbowArc.draw(c, center: c.wingR, alpha: 0.6 * envelope(progress)) }
    let teasers: [String] = []
    let lives = ["雨停啦，天边有彩虹！", "风雨过后，就是彩虹", "今天的坏运气，被雨带走啦"]
    let cancelLine = "又下雨了，彩虹溜走了"
}

/// 初雪：这个冬天第一次下雪时触发。
struct FirstSnow: SceneEvent {
    let id = "firstSnow", name = "初雪"
    let stages: Set<SceneStage> = [.seasonFX]
    let triggered = true
    func canRun(condition: String, intensity: Double) -> Bool { true }
    func draw(_ c: SceneCanvas, stage: SceneStage, progress: Double) {
        var rng = SeededRandom(seed: 1212)
        for _ in 0..<12 {
            let x = Int(rng.next() % UInt64(max(1, c.cols))), y = c.skyTop + Int(rng.next() % UInt64(max(1, c.floorTop - c.skyTop)))
            if (Int(c.t * 3) + x) % 4 == 0 { c.fill(x, y, 1, 1, Color(red: 0.85, green: 0.95, blue: 1).opacity(envelope(progress))) }
        }
    }
    let teasers: [String] = []
    let lives = ["初雪啦！快许个愿", "下雪了，想和你一起看", "初雪的愿望都会实现哦"]
    let cancelLine = "雪停了，初雪好短暂"
}
