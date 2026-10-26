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
    func draw(_ c: SceneCanvas, stage: SceneStage, progress: Double) {
        let a = envelope(progress)
        let slot = 0.18
        for k in 0..<5 {
            let n = Int(c.t / slot) - k
            let age = c.t - Double(n) * slot
            var rng = SeededRandom(seed: UInt64(truncatingIfNeeded: n &* 7919))
            let x0 = Int(rng.next() % UInt64(max(1, c.cols))) + 8, y0 = c.skyTop + Int(rng.next() % UInt64(max(1, (c.cityBase - c.skyTop) / 2)))
            let life = 0.8
            guard age < life else { continue }
            let travel = Int(age / life * 16)
            Meteor.draw(c, x: x0 - travel, y: y0 + travel / 2, length: 8, alpha: a * (1 - age / life * 0.7))
        }
    }
    let teasers = ["{time} 有流星雨，记得来看哦", "{time} 流星雨！愿望清单准备好了吗", "{time} 流星雨，许个愿：准时下班"]
    let lives = ["流星雨来啦！快许愿", "许个愿：明天不加班", "一颗、两颗…数不过来了", "愿望很简单：发财、不加班"]
    let cancelLine = "天公不作美，流星雨看不成了 T_T"
}

/// 花火大会：夏天周六 30% 概率 20:00；中国国庆、新加坡国庆日当晚 20:00 必有。
struct FireworksFestival: SceneEvent {
    let id = "fireworks", name = "花火大会"
    let stages: Set<SceneStage> = [.skyEvents, .shoreEvents]
    func start(on d: EventDay) -> Date? {
        if d.isHoliday("nationalDayCN") || d.isHoliday("nationalDaySG") { return d.at(20) }
        if [.summer, .tropical].contains(d.season), d.weekday == 7, d.roll(id) < 0.3 { return d.at(20) }
        return nil
    }
    func canRun(condition: String, intensity: Double) -> Bool { dry(condition) }
    func draw(_ c: SceneCanvas, stage: SceneStage, progress: Double) { Fireworks.draw(c, stage: stage, bursts: 4, alpha: envelope(progress)) }
    let teasers = ["{time} 有花火大会！占个好位置", "{time} 放烟花，下班别磨蹭", "{time} 花火大会，今晚的快乐有着落了"]
    let lives = ["花火大会开始啦！", "砰——好好看！", "这一刻，班味全无", "烟花很短，快乐很长"]
    let cancelLine = "下雨了，花火大会取消了，猫猫好失落"
}

/// 跨年烟花：12 月 31 日 23:55 开始，跨过零点。
struct NewYearFireworks: SceneEvent {
    let id = "newYearFireworks", name = "跨年烟花"
    let stages: Set<SceneStage> = [.skyEvents, .shoreEvents]
    func start(on d: EventDay) -> Date? { d.month == 12 && d.dayOfMonth == 31 ? d.at(23, 55) : nil }
    func canRun(condition: String, intensity: Double) -> Bool { !["thunder", "hail"].contains(condition) }
    func draw(_ c: SceneCanvas, stage: SceneStage, progress: Double) { Fireworks.draw(c, stage: stage, bursts: progress > 0.5 ? 6 : 3, alpha: envelope(progress)) }
    let teasers = ["{time} 跨年烟花，一起倒数吧", "今年最后几小时，辛苦你了"]
    let lives = ["新年快乐！今年也辛苦啦", "新的一年，愿你不加班、多发财", "3、2、1——新年快乐！"]
    let cancelLine = "天气太凶，跨年烟花取消了，但新年快乐不打折"
}

enum Fireworks {
    static func draw(_ c: SceneCanvas, stage: SceneStage, bursts: Int, alpha: Double) {
        let colors: [UInt32] = [0xFF5D7A, 0xFFD84A, 0x6DD3FF, 0xB98CFF, 0x7CF29A, 0xFF9A55]
        for k in 0..<bursts {
            let cycle = 2.6, offset = Double(k) * cycle / Double(bursts)
            let local = (c.t + offset).truncatingRemainder(dividingBy: cycle)
            let n = Int((c.t + offset) / cycle)
            var rng = SeededRandom(seed: UInt64(truncatingIfNeeded: n &* 31 &+ k))
            let cx = 6 + Int(rng.next() % UInt64(max(1, c.cols - 12))), cy = c.skyTop + 3 + Int(rng.next() % UInt64(max(1, (c.cityBase - c.skyTop) / 3)))
            let col = c.rgb(colors[Int(rng.next() % UInt64(colors.count))]).color
            if stage == .shoreEvents {
                // 水面倒影：爆开时海湾泛起同色的光。
                if local > 0.6 && local < 1.8 { c.fill(cx - 4, c.cityBase, 9, c.floorTop - c.cityBase, col.opacity(0.18 * alpha)) }
                continue
            }
            if local < 0.6 { c.fill(cx, c.cityBase - Int(Double(c.cityBase - cy) * local / 0.6), 1, 1, col.opacity(alpha)) }
            else if local < 2.0 {
                let r = Int((local - 0.6) * 5) + 1, a = (1 - (local - 0.6) / 1.4) * alpha
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)] { c.fill(cx + dx * r, cy + dy * r, 1, 1, col.opacity(a)) }
                if r > 2 { for (dx, dy) in [(2, 1), (-2, 1), (1, 2), (-1, 2)] { c.fill(cx + dx * r / 2, cy + dy * r / 2 + 1, 1, 1, col.opacity(a * 0.6)) } }
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
    func draw(_ c: SceneCanvas, stage: SceneStage, progress: Double) {
        let a = envelope(progress)
        let colors: [UInt32] = [0x6DD3FF, 0xFF6FB5, 0xB98CFF, 0x7CF29A]
        let col = c.rgb(colors[Int(c.t / 2.5) % colors.count]).color
        if stage == .shoreEvents {
            c.fill(0, c.cityBase, c.cols, c.floorTop - c.cityBase, col.opacity(0.14 * a))
            return
        }
        for (i, ox) in [c.landmarkLeft + 6, c.landmarkRight].enumerated() {
            let base = c.cityBase - c.tall(12)
            for beam in 0..<3 {
                let angle = sin(c.t * 0.7 + Double(beam) * 1.3 + Double(i)) * 0.9
                for k in 0..<max(1, base - c.skyTop) {
                    let x = ox + Int((Double(k) * angle).rounded())
                    c.fill(x, base - k, 1, 1, col.opacity(a * 0.5 * (1 - Double(k) / Double(max(1, base - c.skyTop)))))
                }
            }
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
    func draw(_ c: SceneCanvas, stage: SceneStage, progress: Double) {
        SeasonParticlesLayer().drift(c, colors: [0xF7A8C4, 0xFFD1E0, 0xFFFFFF, 0xF48FB1], count: Int(60 * envelope(progress)), seed: 3131)
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
