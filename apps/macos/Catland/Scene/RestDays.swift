// RestDays：离最近的休息日 / 节日还有几天，给打工人一句鼓励。悬停时小猫的气泡轮播这些话。
// 节日按所在地区：中国大陆用法定节假日（按节日当天计，不含调休安排），新加坡用公共假期；其他地区只算周末和通用节日。
// 农历节日写死近几年的公历日期。
import Foundation

enum RestDays {
    enum Region { case china, singapore, other }

    struct Holiday {
        let name: String
        let date: DateComponents
        /// 是否放假（法定 / 公共假期）；否则只是「节日」。
        let off: Bool
    }

    static func region(for loc: SceneLocation, timeZone: TimeZone = .current) -> Region {
        if loc.skyline == .singapore || timeZone.identifier == "Asia/Singapore" { return .singapore }
        if loc.skyline == .shanghai || ["Asia/Shanghai", "Asia/Chongqing", "Asia/Urumqi", "Asia/Harbin"].contains(timeZone.identifier) { return .china }
        return .other
    }

    private static func d(_ y: Int, _ m: Int, _ day: Int) -> DateComponents { DateComponents(year: y, month: m, day: day) }

    static func holidays(_ region: Region) -> [Holiday] {
        var out: [Holiday] = []
        for y in 2026...2031 {
            out.append(Holiday(name: "元旦", date: d(y, 1, 1), off: true))
            out.append(Holiday(name: "圣诞节", date: d(y, 12, 25), off: region == .singapore))
            out.append(Holiday(name: "万圣节", date: d(y, 10, 31), off: false))
            out.append(Holiday(name: "情人节", date: d(y, 2, 14), off: false))
        }
        let spring: [Int: (Int, Int)] = [2026: (2, 17), 2027: (2, 6), 2028: (1, 26), 2029: (2, 13), 2030: (2, 3), 2031: (1, 23)]
        switch region {
        case .china:
            let qingming: [Int: (Int, Int)] = [2026: (4, 5), 2027: (4, 5), 2028: (4, 4), 2029: (4, 4), 2030: (4, 5), 2031: (4, 5)]
            let dragon: [Int: (Int, Int)] = [2026: (6, 19), 2027: (6, 9), 2028: (5, 28), 2029: (6, 16), 2030: (6, 5), 2031: (6, 24)]
            let mid: [Int: (Int, Int)] = [2026: (9, 25), 2027: (9, 15), 2028: (10, 3), 2029: (9, 22), 2030: (9, 12), 2031: (10, 1)]
            for y in 2026...2031 {
                if let v = spring[y] { out.append(Holiday(name: "春节", date: d(y, v.0, v.1), off: true)) }
                if let v = qingming[y] { out.append(Holiday(name: "清明", date: d(y, v.0, v.1), off: true)) }
                out.append(Holiday(name: "劳动节", date: d(y, 5, 1), off: true))
                if let v = dragon[y] { out.append(Holiday(name: "端午", date: d(y, v.0, v.1), off: true)) }
                if let v = mid[y] { out.append(Holiday(name: "中秋", date: d(y, v.0, v.1), off: true)) }
                out.append(Holiday(name: "国庆", date: d(y, 10, 1), off: true))
            }
        case .singapore:
            let goodFriday: [Int: (Int, Int)] = [2026: (4, 3), 2027: (3, 26), 2028: (4, 14), 2029: (3, 30), 2030: (4, 19), 2031: (4, 11)]
            for y in 2026...2031 {
                if let v = spring[y] { out.append(Holiday(name: "农历新年", date: d(y, v.0, v.1), off: true)) }
                if let v = goodFriday[y] { out.append(Holiday(name: "耶稣受难日", date: d(y, v.0, v.1), off: true)) }
                out.append(Holiday(name: "劳动节", date: d(y, 5, 1), off: true))
                out.append(Holiday(name: "国庆日", date: d(y, 8, 9), off: true))
            }
        case .other:
            break
        }
        return out
    }

    /// 下一个节日（含今天）及距今天数。
    static func nextHoliday(from now: Date, region: Region, calendar cal: Calendar = .current) -> (Holiday, Int)? {
        let today = cal.startOfDay(for: now)
        return holidays(region)
            .compactMap { h -> (Holiday, Int)? in
                guard let date = cal.date(from: h.date) else { return nil }
                let days = cal.dateComponents([.day], from: today, to: date).day ?? -1
                return days >= 0 ? (h, days) : nil
            }
            .min { $0.1 < $1.1 }
    }

    /// 气泡轮播的几句话：开刷提示 + 天气、周末、节日（按距离给出不同语气的鼓励）。
    static func messages(now: Date, region: Region, weather: String?, connected: Bool, calendar cal: Calendar = .current) -> [String] {
        var out = [connected ? "点我开刷" + (weather.map { " · \($0)" } ?? "") : "点我连接平台"]
        let hour = cal.component(.hour, from: now)
        let weekday = cal.component(.weekday, from: now) // 1 = 周日 … 7 = 周六
        if hour >= 23 || hour < 5 {
            out.append("夜深了，刷完这条就睡吧")
        } else {
            switch weekday {
            case 7, 1: out.append(["周末愉快，好好休息～", "周末就该躺平刷刷刷"][(hour / 6) % 2])
            case 6: out.append(hour >= 17 ? "下班就是周末！冲！" : "明天周末！再撑一下")
            case 2: out.append("周一而已，摸会儿鱼回回血")
            default: out.append("距周末还有 \(7 - weekday) 天，加油打工人")
            }
        }
        if let (h, days) = nextHoliday(from: now, region: region, calendar: cal) {
            let name = h.name
            switch days {
            case 0: out.append("今天是\(name)，节日快乐！")
            case 1: out.append(h.off ? "明天就放\(name)假啦！" : "明天就是\(name)啦")
            case 2...3: out.append("还有 \(days) 天就\(name)啦，冲！")
            case 4...14: out.append("距\(name)还有 \(days) 天")
            default: out.append("距\(name)还有 \(days) 天，先摸会儿鱼")
            }
        }
        return out
    }
}
