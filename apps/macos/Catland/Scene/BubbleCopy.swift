// BubbleCopy：悬停时小猫气泡的轮播语料（小红书风：可爱、有梗、轻松）。分三类：
//   a. 闲聊语：天气、季节、一天里的时段、星期几、给打工人的鼓励
//   b. 时间语：距周末 / 下班 / 节假日 / 月底的提醒
//   c. 戳我语：俏皮地邀请用户点一下猫（不直说「开刷」）
// 按当下情境筛出可用的句子，三类交错排列；每次悬停换一个随机种子，轮播顺序不重复。
import Foundation

enum BubbleCopy {
    struct Context {
        var now: Date
        var region: RestDays.Region
        var city: String
        var condition: String?
        var temperature: Double?
        var season: SceneSeason
        var connected: Bool
        var calendar: Calendar = .current
    }

    // MARK: - c. 戳我语

    static let tap = [
        "点我点我～(๑•̀ㅂ•́)و✧", "戳我一下，有好事花生", "摸摸猫猫头，烦恼都溜走", "偷偷点一下，老板看不见",
        "喵～要不要一起摸鱼", "点我！今日份快乐已到货", "听说点我的人今天会暴富", "猫猫已就位，就差你了",
        "来都来了，点一下嘛", "戳一戳，解锁电子榨菜", "主打一个点了就开心", "别犹豫啦，点我有惊喜",
        "喵呜～陪我玩会儿嘛", "今天的快乐，从戳我开始", "宝，点一下嘛～", "芜湖～点我起飞",
        "点我领取今日份摸鱼许可", "猫猫营业中，欢迎光临", "尊嘟假嘟？你还没点我", "按一下，快乐加载中…",
        "我数到三，你就点我哦", "猫猫的肚皮给你摸～",
    ]

    static let tapUnconnected = ["带我认识你的 App 呗～", "点我，把小猫们接回家", "还没连接平台，猫猫好无聊"]

    // MARK: - a. 闲聊语

    static func chat(_ c: Context) -> [String] {
        var out: [String] = []
        let cal = c.calendar
        let hour = cal.component(.hour, from: c.now), minute = cal.component(.minute, from: c.now)
        let hm = Double(hour) + Double(minute) / 60
        let weekday = cal.component(.weekday, from: c.now)
        let temp = c.temperature.map { Int($0.rounded()) }

        // 天气
        if let cond = c.condition {
            if let t = temp { out.append("\(c.city) \(t)°，\(IslandScene.weatherName(cond))") }
            switch cond {
            case "rain": out += ["下雨啦，记得早点下班", "雨天适合窝着刷视频", "外面在下雨，猫猫不想出门", "听着雨声摸鱼，绝绝子"]
            case "drizzle": out += ["毛毛雨～出门记得带伞", "小雨淅淅沥沥，适合发呆"]
            case "thunder": out += ["打雷了！猫猫躲进洞里了", "雷雨天，乖乖待在室内吧", "轰隆隆…猫猫吓得炸毛了"]
            case "snow": out += ["下雪啦！好想去踩雪", "雪天限定：热可可 + 猫猫", "窗外白茫茫，心里暖洋洋"]
            case "sleet", "hail": out += ["外面在下冰粒子，别乱跑", "天气有点凶，猫猫陪你待着"]
            case "fog": out += ["雾蒙蒙的，出门慢慢走", "今天的城市像加了柔光滤镜"]
            case "haze": out += ["空气不太好，记得戴口罩", "灰蒙蒙的天，开个电子窗看看"]
            case "windy": out += ["风好大，猫毛都吹乱了", "大风天，帽子要抓紧哦"]
            case "clear": out += ["天气真好，晒晒太阳吧", "晴天！心情也跟着放晴"]
            case "cloudy": out += ["多云的天，适合放空", "云朵慢慢飘，你也慢慢来"]
            default: break
            }
            if let t = temp {
                if t >= 32 { out += ["\(t)°，热到融化 orz", "这么热，冰美式安排上"] }
                else if t <= 8 { out += ["\(t)°，好冷，抱紧猫猫取暖", "天冷了，多穿一件哦"] }
            }
        }

        // 季节
        switch c.season {
        case .spring: out += ["春天来了，猫猫开始掉毛了", "春困秋乏，摸鱼有理", "春天的风都是甜的"]
        case .summer: out += ["夏天就是空调西瓜和猫猫", "夏日限定：躺平不被打扰", "夏天的晚风最温柔"]
        case .autumn: out += ["秋天的第一杯奶茶喝了吗", "落叶好好看，猫猫想去追", "秋高气爽，适合偷懒"]
        case .winter: out += ["冬天就想缩在被窝里", "冬天的猫猫是液体做的", "手冷就揣兜里，猫猫也想揣"]
        case .tropical: out += ["四季都是夏天的城市", "热带的猫猫天天想吹空调"]
        }

        // 时段
        switch hm {
        case 5..<7: out += ["这么早就起来啦，你好棒"]
        case 7..<10: out += ["早安打工人，元气满满", "早上好！先摸会儿鱼开开机"]
        case 11.5..<13.5: out += ["干饭时间到！", "吃饱了才有力气摸鱼"]
        case 14..<16.5: out += ["下午犯困？看个视频醒醒神", "三点几嚟，饮茶先啦"]
        case 18..<21: out += ["辛苦啦，今天也很棒", "晚上好，奖励自己一下"]
        case 21..<23: out += ["晚上的时间是自己的", "洗完澡刷会儿，美滋滋"]
        case 23..<24, 0..<5: out += ["夜深了，刷完这条就睡吧", "熬夜伤身，猫猫监督你睡觉"]
        default: break
        }

        // 星期几
        switch weekday {
        case 2: out += ["周一啦，摸摸鱼恢复元气", "周一综合症？猫猫抱抱"]
        case 4: out += ["周三了，给自己打打气"]
        case 6: out += ["周五了，班味逐渐消散"]
        case 7, 1: out += ["周末也要好好吃饭哦", "周末的快乐是双倍的"]
        default: break
        }

        // 通用鼓励
        out += ["打工人打工魂，摸鱼才是人上人", "今天也辛苦啦，抱抱", "累了就歇会儿，猫猫陪你",
                "你已经很努力啦", "电子榨菜已备好，请慢用", "允许自己偶尔摆烂一下"]
        return out
    }

    // MARK: - b. 时间语

    static func time(_ c: Context) -> [String] {
        var out: [String] = []
        let cal = c.calendar
        let hour = cal.component(.hour, from: c.now), minute = cal.component(.minute, from: c.now)
        let weekday = cal.component(.weekday, from: c.now) // 1 = 周日 … 7 = 周六
        let workday = (2...6).contains(weekday)

        // 周末
        switch weekday {
        case 2: out.append("距周末还有 5 天，稳住我们能赢")
        case 3: out.append("周二了！离周末又近了一步")
        case 4: out.append("周三过半，距周末只剩 3 天")
        case 5: out.append("周四了，明天就是快乐周五")
        case 6: out.append(hour >= 17 ? "下班就是周末，冲鸭！" : "周五！今天的班味淡淡的")
        case 7: out.append("周六，主打一个躺平")
        default: out.append(hour >= 18 ? "周日晚上的 emo 也是周末的一部分" : "周日，珍惜周末的余额")
        }

        // 下班
        if workday {
            let offWork = 18 * 60, nowMin = hour * 60 + minute
            if nowMin >= 9 * 60 && nowMin < 12 * 60 || nowMin >= 13 * 60 + 30 && nowMin < offWork {
                let left = offWork - nowMin
                out.append(left >= 60 ? "距下班还有 \(left / 60) 小时 \(left % 60) 分" : "还有 \(left) 分钟下班！收拾收拾")
            } else if nowMin >= 12 * 60 && nowMin < 13 * 60 + 30 {
                out.append("午休时间，饭饭最大")
            } else if nowMin >= offWork && nowMin < 19 * 60 {
                out.append("下班时间到！快跑！")
            }
        }

        // 节假日
        if let (h, d) = RestDays.nextHoliday(from: c.now, region: c.region, calendar: cal) {
            let n = h.name
            switch d {
            case 0: out.append("今天\(n)！节日快乐呀～")
            case 1: out.append(h.off ? "明天放\(n)假！今晚就开始快乐" : "明天就是\(n)啦")
            case 2...3: out.append("还有 \(d) 天就\(n)啦，狠狠期待住了")
            case 4...14: out.append("距\(n)还有 \(d) 天，数着日子摸鱼")
            default: out.append("距\(n)还有 \(d) 天，先把电子榨菜吃上")
            }
        }

        // 月底 / 月初
        let day = cal.component(.day, from: c.now)
        let daysInMonth = cal.range(of: .day, in: .month, for: c.now)?.count ?? 30
        if day >= 25 { out.append("离月底还有 \(daysInMonth - day) 天，工资在路上了") }
        if day <= 3 { out.append("新的一个月，钱包也要鼓鼓的") }

        // 年度进度
        if let doy = cal.ordinality(of: .day, in: .year, for: c.now), let total = cal.range(of: .day, in: .year, for: c.now)?.count {
            out.append("\(cal.component(.year, from: c.now)) 年已经过去 \(doy * 100 / total)%，你超棒的")
        }
        return out
    }

    // MARK: - 组合

    /// 三类交错：戳我 → 时间 → 闲聊 → 闲聊 → 戳我 → 时间 → 闲聊 …；同一次悬停内不重复。
    static func rotation(_ c: Context, seed: UInt64, count: Int = 12) -> [String] {
        var rng = SeededRandom(seed: seed)
        func shuffled(_ a: [String]) -> [String] {
            var a = a
            for i in stride(from: a.count - 1, to: 0, by: -1) { a.swapAt(i, Int(rng.next() % UInt64(i + 1))) }
            return a
        }
        var pools: [String: [String]] = [
            "tap": shuffled(c.connected ? tap : tapUnconnected + tap.prefix(6)),
            "time": shuffled(time(c)),
            "chat": shuffled(chat(c)),
        ]
        let pattern = ["tap", "time", "chat", "chat"]
        var out: [String] = []
        var i = 0
        while out.count < count, pools.values.contains(where: { !$0.isEmpty }) {
            let kind = pattern[i % pattern.count]
            if let line = pools[kind]?.popLast() { out.append(line) }
            i += 1
            if i > count * 8 { break }
        }
        return out
    }
}
