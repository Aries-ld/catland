// BubbleCopy：悬停时气泡的轮播语料。受众是可怜的打工人，我们做的是陪伴：
// 不说教、不打鸡血，站在打工人这边，顺手逗你笑一下。
// 每句话由一只平台小猫用自己的口吻说（PersonaCopy），格式「名字：内容」；正常连接的平台由对应的小猫轮流说，
// 被风控暂停、正在打盹的小猫只说「我累了，休息一会儿再来」这类话。
// 分四类，按情境筛选后交错轮播：
//   a. 闲聊语：天气、季节、时段、星期几、打工共鸣（泛化，避免每句都「看穿你」显得刻意）
//   b. 时间语：距下班 / 节假日 / 发薪，今日 / 本周 / 今年进度
//   c. 戳我语：俏皮地邀请点一下（不直说「开刷」）
//   d. 情境语：此刻最贴切的话。强情境（凌晨还亮着屏、工作日晚上加班、雷雨暴雪、极端冷热）每次悬停的第一句必定是它；
//      普通情境（周一早上、周五下午、早起、下雨、时段、季节）约一半悬停排第一句，之后和泛化语料按较低比例交错。
// 事件预告 / 倒计时由 EventScheduler.bubbleLines 提供，排在轮播最前面（由第一只小猫说）。
// 内容单句不超过 22 个字（不含名字）。
import Foundation

enum BubbleCopy {
    struct Context {
        var now: Date
        var region: RestDays.Region
        var city: String
        var condition: String?
        var temperature: Double?
        var season: SceneSeason
        /// 说话的小猫（正常连接的平台对应的小猫；都没接入时是箱箱）。
        var speakers: [Persona]
        /// 正在打盹（平台被风控暂停）的小猫。
        var sleeping: Set<Persona> = []
        var calendar: Calendar = .current
    }

    // MARK: - a. 闲聊语

    static func chat(_ c: Context, as p: Persona) -> [String] {
        let l = p.lines
        var out: [String] = []
        let cal = c.calendar
        let hm = Double(cal.component(.hour, from: c.now)) + Double(cal.component(.minute, from: c.now)) / 60
        let weekday = cal.component(.weekday, from: c.now)

        if let cond = c.condition {
            if let t = c.temperature.map({ Int($0.rounded()) }) {
                out.append("\(c.city) \(t)°，\(IslandScene.weatherName(cond))")
                if t >= 32 { out += l.weather["hot"] ?? [] } else if t <= 8 { out += l.weather["cold"] ?? [] }
            }
            out += l.weather[cond] ?? []
        }
        out += l.season[c.season] ?? []
        out += l.daypart[daypart(hm)] ?? []
        out += l.weekday[weekday == 1 ? 7 : weekday] ?? []
        out += l.mood
        return out
    }

    static func daypart(_ hm: Double) -> String {
        switch hm {
        case 5..<9.5: return "morning"
        case 9.5..<11.5: return "forenoon"
        case 11.5..<13.5: return "lunch"
        case 13.5..<17: return "afternoon"
        case 17..<18: return "lastHour"
        case 18..<21: return "evening"
        case 21..<23: return "night"
        default: return "late"
        }
    }

    // MARK: - d. 情境语

    /// 此刻的情境语：strong 是特别值得说的（凌晨、加班、雷雨暴雪、极端冷热），mild 是普通的（周一、周五、早起、下雨、时段、季节）。
    static func moments(_ c: Context, as p: Persona) -> (strong: [String], mild: [String]) {
        let l = p.lines, m = l.moments
        let cal = c.calendar
        let hm = Double(cal.component(.hour, from: c.now)) + Double(cal.component(.minute, from: c.now)) / 60
        let weekday = cal.component(.weekday, from: c.now) // 1 = 周日 … 7 = 周六
        let workday = (2...6).contains(weekday)
        var strong: [String] = [], mild: [String] = []
        if hm < 5 { strong += m["lateNight"] ?? [] }
        if workday && hm >= 19 { strong += m["overtime"] ?? [] }
        if let cond = c.condition {
            if ["thunder", "snow", "sleet"].contains(cond) { strong += l.weather[cond] ?? [] }
            else if ["rain", "drizzle", "fog", "haze", "windy"].contains(cond) { mild += l.weather[cond] ?? [] }
        }
        if let t = c.temperature {
            if t >= 33 { strong += l.weather["hot"] ?? [] } else if t <= 3 { strong += l.weather["cold"] ?? [] }
        }
        if hm >= 5 && hm < 7 { mild += m["earlyBird"] ?? [] }
        if weekday == 2 && hm >= 8 && hm < 11.5 { mild += m["mondayMorning"] ?? [] }
        if weekday == 6 && hm >= 14 && hm < 18.5 { mild += m["fridayAfternoon"] ?? [] }
        if !workday && hm >= 9 && hm < 18 { mild += m["weekendWork"] ?? [] }
        if hm >= 5 { mild += l.daypart[daypart(hm)] ?? [] }
        mild += l.season[c.season] ?? []
        return (strong, mild)
    }

    // MARK: - b. 时间语

    static func time(_ c: Context, as p: Persona) -> [String] {
        let l = p.lines
        var out: [String] = []
        let cal = c.calendar
        let hour = cal.component(.hour, from: c.now), minute = cal.component(.minute, from: c.now)
        let weekday = cal.component(.weekday, from: c.now) // 1 = 周日 … 7 = 周六
        let nowMin = hour * 60 + minute

        // 下班 + 今日 / 本周进度（按 9:00–18:00 算）
        if (2...6).contains(weekday) {
            let start = 9 * 60, off = 18 * 60
            if nowMin >= start && nowMin < 12 * 60 || nowMin >= 13 * 60 + 30 && nowMin < off {
                let left = off - nowMin
                out.append(left >= 60 ? l.offWork(left / 60, left % 60) : l.offSoon(left))
                out.append(l.dayProgress((nowMin - start) * 100 / (off - start)))
            }
            let weekProgress = min(100, ((weekday - 2) * (off - start) + max(0, min(off, nowMin) - start)) * 100 / (5 * (off - start)))
            out.append(l.weekProgress(weekProgress))
        }

        // 节假日
        if let (h, d) = RestDays.nextHoliday(from: c.now, region: c.region, calendar: cal) {
            switch d {
            case 0: out.append(l.holidayToday(h.name))
            case 1: out.append(l.holidayTomorrow(h.name))
            case 2...7: out.append(l.holidayNear(h.name, d))
            default: out.append(l.holidayFar(h.name, d))
            }
        }

        // 月底 / 年度进度
        let day = cal.component(.day, from: c.now)
        let daysInMonth = cal.range(of: .day, in: .month, for: c.now)?.count ?? 30
        if day >= 25 { out.append(l.monthEnd(daysInMonth - day)) }
        if let doy = cal.ordinality(of: .day, in: .year, for: c.now), let total = cal.range(of: .day, in: .year, for: c.now)?.count {
            out.append(l.yearProgress(cal.component(.year, from: c.now), doy * 100 / total))
        }
        return out
    }

    // MARK: - 组合

    /// 第一句：有强情境时必定是情境语，普通情境约一半是；之后四类交错：戳我 → 情境 → 闲聊 → 时间 → 闲聊 → …
    /// 说话的小猫轮流来；同一次悬停内不重复。
    static func rotation(_ c: Context, seed: UInt64, count: Int = 12) -> [String] {
        var rng = SeededRandom(seed: seed)
        func shuffled(_ a: [String]) -> [String] {
            var a = a
            for i in stride(from: a.count - 1, to: 0, by: -1) { a.swapAt(i, Int(rng.next() % UInt64(i + 1))) }
            return a
        }
        let speakers = c.speakers.isEmpty ? [Persona.box] : shuffledPersonas(c.speakers, &rng)
        var pools: [Persona: [String: [String]]] = [:]
        var hasStrong = false
        for p in speakers {
            if c.sleeping.contains(p) {
                // 打盹的小猫：轮到它时不管哪一类，都只说累了、待会儿再来
                let tired = shuffled(p.lines.tired)
                pools[p] = ["tap": tired, "moment": tired, "chat": tired, "time": tired]
            } else {
                let mo = moments(c, as: p)
                hasStrong = hasStrong || !mo.strong.isEmpty
                // popLast 先取末尾：强情境排在后面，先被说到
                pools[p] = ["tap": shuffled(p.lines.tap), "time": shuffled(time(c, as: p)), "chat": shuffled(chat(c, as: p)),
                            "moment": shuffled(mo.mild) + shuffled(mo.strong)]
            }
        }
        let pattern = ["tap", "moment", "chat", "time", "chat"]
        var out: [String] = []
        var seen = Set<String>()
        // 第一句：由第一只醒着的小猫说情境语（强情境必定，普通情境约一半）
        if hasStrong || rng.next() % 2 == 0, let first = speakers.first(where: { !c.sleeping.contains($0) }),
           let line = pools[first]?["moment"]?.popLast() {
            seen.insert(line)
            out.append(first.say(line))
        }
        var i = 0
        while out.count < count, i < count * 12 {
            let p = speakers[i % speakers.count], kind = pattern[(i / speakers.count + i) % pattern.count]
            if let line = pools[p]?[kind]?.popLast(), seen.insert(line).inserted { out.append(p.say(line)) }
            i += 1
        }
        return out
    }

    private static func shuffledPersonas(_ a: [Persona], _ rng: inout SeededRandom) -> [Persona] {
        var a = a
        for i in stride(from: a.count - 1, to: 0, by: -1) { a.swapAt(i, Int(rng.next() % UInt64(i + 1))) }
        return a
    }
}
