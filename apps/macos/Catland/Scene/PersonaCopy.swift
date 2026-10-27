// PersonaCopy：每只平台小猫用自己的口吻说话（形象与人设见 docs/design/platform-cats.md）。
// 气泡格式「名字：内容」；内容单句不超过 22 个字（不含名字），颜文字算在内。
// 正常连接的平台，由对应的小猫轮流说话；什么都没接入时由纸箱里的小奶猫「箱箱」说。
import Foundation

enum Persona: String, CaseIterable {
    case shushu, doudou, bibi, tietie, box

    var name: String {
        switch self {
        case .shushu: return "薯薯"
        case .doudou: return "抖抖"
        case .bibi: return "bibi"
        case .tietie: return "铁铁"
        case .box: return "箱箱"
        }
    }

    /// 刘海里这只猫的固定花色（PixelCatArt.skins）。
    var skin: String {
        switch self {
        case .shushu: return "ragdoll"
        case .doudou: return "tuxedoBlack"
        case .bibi: return "calicoTV"
        case .tietie: return "cowJacket"
        case .box: return "kitten"
        }
    }

    static func forPlatform(_ id: String) -> Persona? {
        switch id {
        case "xhs": return .shushu
        case "douyin": return .doudou
        case "bilibili": return .bibi
        case "kuaishou": return .tietie
        default: return nil
        }
    }

    /// 正常连接的平台 → 出场的小猫；一个都没有时是箱箱。
    static func speakers(platforms: [String]) -> [Persona] {
        let ps = platforms.compactMap(forPlatform)
        return ps.isEmpty ? [.box] : ps
    }

    func say(_ line: String) -> String { "\(name)：\(line)" }

    var lines: PersonaLines {
        switch self {
        case .shushu: return .shushu
        case .doudou: return .doudou
        case .bibi: return .bibi
        case .tietie: return .tietie
        case .box: return .box
        }
    }
}

/// 一只小猫的全部语料。情境键：
/// - weather：rain / drizzle / thunder / snow / sleet / fog / haze / windy / clear / cloudy / hot / cold
/// - daypart：morning / forenoon / lunch / afternoon / lastHour / evening / night / late
/// - weekday：2 = 周一 … 6 = 周五，7 = 周末
/// - moments（情境语，此刻最贴切的话）：lateNight 凌晨还亮着屏 / overtime 工作日晚上还在加班 / earlyBird 起得很早 /
///   mondayMorning 周一上午 / fridayAfternoon 周五下午 / weekendWork 周末白天还在电脑前
struct PersonaLines {
    let tap: [String]
    /// 平台被风控暂停、小猫在打盹时说的话。
    let tired: [String]
    let moments: [String: [String]]
    let weather: [String: [String]]
    let season: [SceneSeason: [String]]
    let daypart: [String: [String]]
    let weekday: [Int: [String]]
    let mood: [String]
    // 时间语模板
    let offWork: (_ h: Int, _ m: Int) -> String
    let offSoon: (_ m: Int) -> String
    let dayProgress: (_ pct: Int) -> String
    let weekProgress: (_ pct: Int) -> String
    let holidayToday: (_ name: String) -> String
    let holidayTomorrow: (_ name: String) -> String
    let holidayNear: (_ name: String, _ days: Int) -> String
    let holidayFar: (_ name: String, _ days: Int) -> String
    let monthEnd: (_ days: Int) -> String
    let yearProgress: (_ year: Int, _ pct: Int) -> String
}

extension PersonaLines {
    // MARK: 薯薯 · 小红书：精致高雅、有点 mean、爱分享爱碎碎念、小臭美
    static let shushu = PersonaLines(
        tap: [
            "点我，本小姐今天心情好", "还不点？品味有待提高哦", "姐妹，点一下，给你种草",
            "这么好看的我，不点可惜了", "点我，带你看点有格调的", "犹豫什么？点就完了 ✧(≖ ◡ ≖✿)",
            "本小姐的时间很贵，快点", "点我，今日份精致已备好", "别光看我，点进来呀",
        ],
        tired: ["本小姐累了，休息一会儿再来", "今天营业结束，晚点再看"],
        moments: [
            "lateNight": ["这么晚还在工作？辛苦了，真的", "凌晨还亮着屏，本小姐都心疼了", "工作再重要，也没你重要", "熬到这个点，明天记得补觉"],
            "overtime": ["还在加班？老板可不会感动", "下班时间过了，优雅地关电脑吧", "加班到现在，奖励自己一杯奶茶"],
            "earlyBird": ["起这么早？本小姐都还没醒", "这么早就开工，勤快得可怕"],
            "mondayMorning": ["周一早上，先精致地发会儿呆", "周一的脸色，本小姐懂"],
            "fridayAfternoon": ["周五下午了，心早飞走了吧", "周五了，晚上约饭定了吗"],
            "weekendWork": ["周末还在电脑前？过分了", "周末加班，记得加钱"],
        ],
        weather: [
            "rain": ["下雨了，毛可别淋湿了", "雨天也要精致，懂吗", "这种天气只配窝着看笔记"],
            "drizzle": ["毛毛雨而已，本小姐不出门"],
            "thunder": ["打雷？本小姐才不怕呢…"],
            "snow": ["下雪了，正好拍雪景出片", "雪天就该窝在暖气旁"],
            "sleet": ["这天气，连出门都不配"],
            "fog": ["雾这么大，滤镜都省了"],
            "haze": ["空气这么差，毛都不顺了"],
            "windy": ["风好大，毛全乱了，烦"],
            "clear": ["天这么好，却在上班，啧", "好天气，适合拍照不适合工作"],
            "cloudy": ["阴天自带柔光，适合自拍"],
            "hot": ["这么热，本小姐要掉毛了", "热死了，冰美式给本小姐来一杯"],
            "cold": ["冷成这样，还不开暖气？", "这么冷，蝴蝶结也要戴好看的"],
        ],
        season: [
            .spring: ["春天了，蝴蝶结该换新了", "樱花季，不出片等于白过"],
            .summer: ["夏天了，本小姐的毛好热", "夏日限定，冰淇淋要拍了再吃"],
            .autumn: ["秋天的第一杯奶茶，喝了吗", "秋冬的毛，本小姐早养好了"],
            .winter: ["冬天也要精致，懂？", "冬天就该暖气 + 小鱼干"],
            .tropical: ["四季如夏，空调全年无休"],
        ],
        daypart: [
            "morning": ["早，毛梳好了再见人", "早安，今天也要精致上班"],
            "forenoon": ["上午就开始摸鱼？我喜欢"],
            "lunch": ["午饭吃点好的，别凑合", "吃饭前先拍照，常识"],
            "afternoon": ["下午茶时间，本小姐请客（想想）", "犯困了？舔舔毛提提神"],
            "lastHour": ["最后一小时，优雅地熬过去"],
            "evening": ["下班了，去吃顿好的吧", "辛苦了，今晚奖励自己"],
            "night": ["晚上了，梳梳毛刷会儿"],
            "late": ["熬夜会掉毛，赶紧睡", "这么晚还不睡？黑眼圈哦"],
        ],
        weekday: [
            2: ["周一，连舔毛都提不起劲"],
            3: ["周二，勉强精致一下"],
            4: ["周三了，撑住，别垮着脸"],
            5: ["周四，周末去哪晒太阳"],
            6: ["周五了，晚上约个饭吧", "周五，罐罐可以安排了"],
            7: ["周末还看工作群？没救了", "周末就该睡到自然醒"],
        ],
        mood: [
            "老板画的饼，本小姐不吃", "这班上得，毫无美感", "你的品味，还得练练",
            "摸鱼也要摸得有格调", "别卷了，会掉毛的", "嫌弃归嫌弃，我还是会陪你",
            "这条笔记我先码住了", "已加入购物车（不是）", "今天的你，勉强及格",
            "累了就歇会儿，别硬撑", "本小姐分享的，都是好东西", "工资不涨，脸可不能垮",
            "绝绝子，这都被你刷到了", "好东西要和姐妹分享",
        ],
        offWork: { h, m in "还有 \(h) 小时 \(m) 分下班，优雅点" },
        offSoon: { m in "还有 \(m) 分钟下班，梳梳毛吧" },
        dayProgress: { p in "今天的班上了 \(p)%，快熬过去了" },
        weekProgress: { p in "本周进度 \(p)%，周末罐罐备好了吗" },
        holidayToday: { n in "今天\(n)，蝴蝶结戴上出门" },
        holidayTomorrow: { n in "明天\(n)，今晚先洗个澡" },
        holidayNear: { n, d in "还有 \(d) 天\(n)，行程排好了吗" },
        holidayFar: { n, d in "距\(n)还有 \(d) 天，先种草" },
        monthEnd: { d in "还有 \(d) 天发工资，忍住别剁手" },
        yearProgress: { y, p in "\(y) 年过去 \(p)%，你变美了吗" }
    )

    // MARK: 抖抖 · 抖音：时尚潮妹，潮流、新梗、BGM，自信酷，话短上头快
    static let doudou = PersonaLines(
        tap: [
            "点我，带你冲浪", "家人们，点一下嘛 ヾ(≧▽≦*)o", "戳我，今日热门已备好",
            "点我，这波不亏", "还不点？你 out 了", "来，点一下，氛围感拉满",
            "点我点我，BGM 已就位 ♪", "冲！点我开刷", "别划走，点我",
        ],
        tired: ["电量不足，我先眯会儿", "冲太猛了，歇一下再来"],
        moments: [
            "lateNight": ["这个点还没睡，辛苦啦", "这么晚还在肝，抱抱", "夜深了，刷完这条就睡好吗", "熬夜的打工人，今天你最酷"],
            "overtime": ["还在加班？家人们这不合理", "下班了还在卷？歇会儿", "加班到现在，给你点个赞"],
            "earlyBird": ["这么早？卷王本王了", "早起的你，今天必火"],
            "mondayMorning": ["周一早上，先来点 BGM 续命", "周一，打工人集合"],
            "fridayAfternoon": ["周五下午，摸鱼合法化", "周五了，今晚去哪嗨"],
            "weekendWork": ["周末还上班？这波不值", "周末就该出去浪"],
        ],
        weather: [
            "rain": ["下雨天，雨声当 BGM 绝了", "雨天，窗边听雨 chill 一下"],
            "drizzle": ["毛毛雨，氛围感拉满"],
            "thunder": ["打雷配电音，炸场了"],
            "snow": ["下雪了！冲去拍雪景", "雪天出片率 100%"],
            "sleet": ["这天，宅着刷才是王道"],
            "fog": ["雾天自带滤镜，太出片"],
            "haze": ["灰蒙蒙的，项圈照样亮"],
            "windy": ["风好大，毛乱了也很酷"],
            "clear": ["天气好到想出去拍街拍", "大晴天，墨镜戴上"],
            "cloudy": ["阴天，适合 chill 一下"],
            "hot": ["热到冒烟，冰饮续命", "这温度，只想摊成猫饼"],
            "cold": ["冷？炸毛也是一种潮流", "冻手，但不影响我冲浪"],
        ],
        season: [
            .spring: ["春天了，新款项圈上了吗", "春日出街，冲！"],
            .summer: ["夏天就是要嗨", "夏日 BGM 已经循环一百遍"],
            .autumn: ["秋天，毛又厚了一层", "秋天的风，适合配民谣"],
            .winter: ["冬天也要潮，项圈挑亮色", "冬日猫步，走起"],
            .tropical: ["一年四季都是夏天，嗨起来"],
        ],
        daypart: [
            "morning": ["早！今天也是潮人一枚", "起床先刷个热门"],
            "forenoon": ["上午摸鱼，刷两条就回"],
            "lunch": ["午饭时间，边吃边刷", "干饭！再来个探店视频"],
            "afternoon": ["下午犯困？来点动感的", "三点了，来首提神 BGM"],
            "lastHour": ["最后一小时，冲刺！"],
            "evening": ["下班！今晚去哪嗨", "下班了，蹦迪还是刷剧"],
            "night": ["晚上了，刷到停不下来"],
            "late": ["最后一条，真的最后一条", "还不睡？明天要垮"],
        ],
        weekday: [
            2: ["周一，BGM 也救不了我"],
            3: ["周二，随便摆烂一下"],
            4: ["周三，离周末只差一首歌"],
            5: ["周四，周末计划拉起来"],
            6: ["周五！今晚必须嗨", "周五了，下班直接冲"],
            7: ["周末，宅家刷爆它", "周末就是要玩到尽兴"],
        ],
        mood: [
            "家人们谁懂啊，又上头了", "这个 BGM，绝了 ♪(´▽｀)", "打工人，也要有态度",
            "上班是工作，下班是生活", "别卷了，跟上潮流比较重要", "今天的你，很酷",
            "再刷一条就睡（骗你的）", "热门第一条，我先看了", "情绪价值，我来给",
            "人生苦短，先嗨为敬", "老板的饼？过时了", "主打一个快乐",
            "这梗你都不知道？", "你值得更好的 BGM",
        ],
        offWork: { h, m in "还有 \(h) 小时 \(m) 分下班，稳住" },
        offSoon: { m in "\(m) 分钟后下班，准备冲！" },
        dayProgress: { p in "今日搬砖 \(p)%，快通关了" },
        weekProgress: { p in "本周进度 \(p)%，周末在招手" },
        holidayToday: { n in "今天\(n)！嗨起来" },
        holidayTomorrow: { n in "明天\(n)，今晚先嗨" },
        holidayNear: { n, d in "\(d) 天后\(n)，出行计划拉起来" },
        holidayFar: { n, d in "距\(n)还有 \(d) 天，冲" },
        monthEnd: { d in "\(d) 天后发工资，购物车先加满" },
        yearProgress: { y, p in "\(y) 年过去 \(p)%，你还够潮吗" }
    )

    // MARK: bibi · Bilibili：傲娇的二次元萌妹，嘴硬心软，番剧弹幕梗，夜猫子
    static let bibi = PersonaLines(
        tap: [
            "哼，想点就点吧", "才、才不是想让你点我", "点我啦，笨蛋 (￣^￣)",
            "前方高能，请点击", "点一下嘛…又不会怎样", "一键三连，从点我开始",
            "不点我？下次一定（哼）", "点我！新番更新啦 (/≧▽≦)/", "勉强允许你点一下",
        ],
        tired: ["才、才不是累了…就眯一会儿", "我先睡会儿，等下再陪你看"],
        moments: [
            "lateNight": ["这么晚还在工作…辛、辛苦了", "都几点了！快去睡啦笨蛋", "才不是担心你…早点休息嘛", "陪你熬一会儿…就一会儿哦"],
            "overtime": ["还在加班？笨蛋，快下班", "加班到现在…哼，陪你一会儿"],
            "earlyBird": ["这么早？我还没睡呢…", "早起什么的，才不羡慕"],
            "mondayMorning": ["周一早上…我也不想上学", "周一了，打起精神来…一点点"],
            "fridayAfternoon": ["周五下午！周末补番预定", "周五了，才不是期待周末"],
            "weekendWork": ["周末还工作？笨蛋吗你", "周末就该宅着补番啊"],
        ],
        weather: [
            "rain": ["下雨天，最适合补番了", "雨好大…才不是怕打雷"],
            "drizzle": ["小雨天，宅着追番吧"],
            "thunder": ["打、打雷了！你别走…"],
            "snow": ["下雪了！像动画里一样", "雪天，想吃火锅追番"],
            "sleet": ["外面好可怕，还是宅着吧"],
            "fog": ["雾好大，像异世界入口"],
            "haze": ["灰蒙蒙的，不想出门"],
            "windy": ["风好大，尾巴…哼，别看"],
            "clear": ["天气好？跟我宅家又没关系", "大晴天，适合去漫展"],
            "cloudy": ["阴天，适合补番"],
            "hot": ["好热…空调开大点", "热化了，要冰棍"],
            "cold": ["好冷，才不是想要你抱", "冷死了，被窝追番最好"],
        ],
        season: [
            .spring: ["春季新番开播了！", "春天，樱花和恋爱番"],
            .summer: ["夏天就是西瓜和祭典", "夏日新番，全追了"],
            .autumn: ["秋季新番，还不来补？", "秋天，适合看治愈番"],
            .winter: ["冬天，被窝 + 番剧 = 无敌", "冬季新番，我先替你看了"],
            .tropical: ["四季都是夏，祭典天天有"],
        ],
        daypart: [
            "morning": ["早…我才刚睡醒", "早安，才不是等你起床"],
            "forenoon": ["上午摸鱼？带我一个"],
            "lunch": ["午饭配新番，完美", "吃饭！边吃边看番"],
            "afternoon": ["下午好困…看个番醒醒", "三点了，该补番了"],
            "lastHour": ["最后一小时，前方高能！"],
            "evening": ["下班了，今晚追几集？", "辛苦了…哼，夸你一下"],
            "night": ["晚上才是本番时间"],
            "late": ["熬夜追番，我陪你（才不是）", "这么晚了，快睡啦笨蛋"],
        ],
        weekday: [
            2: ["周一…不想上班，想看番"],
            3: ["周二，新番更新日之一"],
            4: ["周三，坚持住，才不是关心你"],
            5: ["周四，周末漫展去吗"],
            6: ["周五！今晚通宵追番", "周五了，周末有新番"],
            7: ["周末，补番补到天亮", "周末就该宅在家"],
        ],
        mood: [
            "哼，今天就勉强夸夸你", "awsl，这条好可爱", "下次一定（下次也不一定）",
            "前方高能，老板接近中", "才不是因为喜欢你才陪你", "弹幕护体，烦恼退散",
            "这集我看了三遍，怎样", "笨蛋，累了就休息啊", "投币就算了，陪你摸鱼",
            "二次元才是真正的家", "你这样很努力…我是说一点点", "今天也要元气满满哦",
            "这番你没看过？不可饶恕", "摸鱼时长，先给你三连",
        ],
        offWork: { h, m in "还有 \(h) 小时 \(m) 分下班，忍忍" },
        offSoon: { m in "\(m) 分钟下班！前方高能！" },
        dayProgress: { p in "今日搬砖 \(p)%，哼，还行吧" },
        weekProgress: { p in "本周进度 \(p)%，周末补番" },
        holidayToday: { n in "今天\(n)！才不是为你开心" },
        holidayTomorrow: { n in "明天\(n)，今晚通宵追番" },
        holidayNear: { n, d in "还有 \(d) 天\(n)，想好补哪部了" },
        holidayFar: { n, d in "距\(n)还有 \(d) 天，番先囤着" },
        monthEnd: { d in "\(d) 天后发工资，手办等我" },
        yearProgress: { y, p in "\(y) 年过去 \(p)%，番看完了吗" }
    )

    // MARK: 铁铁 · 快手：东北大姐，嗓门大、豪爽、干活麻利、接地气、热心肠
    static let tietie = PersonaLines(
        tap: [
            "老铁，点我，整一个！", "瞅啥呢？点就完事了", "点我，大姐带你乐呵",
            "来来来，点一下，必须的", "双击走一波，先点我", "点我，嘎嘎有意思 ٩(ˊᗜˋ*)و",
            "别磨叽，点我", "大妹子、大兄弟，点我", "点一下，大姐请你看好的",
        ],
        tired: ["累了，大姐先眯会儿再整", "歇会儿，一会儿接着唠"],
        moments: [
            "lateNight": ["大半夜还干活呢？辛苦了老铁", "这么晚了还没歇，大姐心疼", "活儿明天整，先睡觉去", "熬这么晚，饿不饿？"],
            "overtime": ["还加班呢？差不多得了", "加班到这会儿，整点夜宵去", "下班了还干，老板给加钱不？"],
            "earlyBird": ["起这么早！比大姐还勤快", "这么早，吃早饭没？"],
            "mondayMorning": ["周一早上，打起精神来老铁", "周一了，整碗热乎的再干"],
            "fridayAfternoon": ["周五下午了，麻溜收尾", "周五了，晚上整顿好的"],
            "weekendWork": ["周末还干活？歇歇吧", "周末就该出去溜达溜达"],
        ],
        weather: [
            "rain": ["下雨了，早点回家别淋着", "雨天，炖个汤整点热乎的"],
            "drizzle": ["小毛毛雨，不打伞也嘎嘎好"],
            "thunder": ["打雷怕啥，有大姐在"],
            "snow": ["下雪了！这雪下得嘎嘎带劲", "下雪天，整个铁锅炖"],
            "sleet": ["这天出门得穿厚点，听姐的"],
            "fog": ["雾这么大，开车慢点"],
            "haze": ["空气埋汰，口罩戴上"],
            "windy": ["这风嘎嘎大，帽子按住"],
            "clear": ["这天儿嘎嘎好，晒晒被子", "大晴天，干活都有劲"],
            "cloudy": ["阴天，正好歇会儿"],
            "hot": ["热得慌，整根冰棍去", "这天儿，大西瓜整起来"],
            "cold": ["冷？这算啥，花棉袄穿上！", "天冷了，多穿点，听姐的"],
        ],
        season: [
            .spring: ["开春了，地里该忙活了", "春天了，出去溜达溜达"],
            .summer: ["夏天，撸串喝啤酒整起来", "夏天就得大西瓜一切两半"],
            .autumn: ["秋天，大丰收，嘎嘎美", "秋天，贴秋膘整起来"],
            .winter: ["冬天就得猫炕头", "冬天，酸菜白肉锅整上"],
            .tropical: ["一年到头都热，冰棍管够"],
        ],
        daypart: [
            "morning": ["早啊老铁，吃早饭没？", "早！大碴子粥整一碗"],
            "forenoon": ["上午干活麻溜的，中午好吃饭"],
            "lunch": ["饭点了！整两碗大米饭", "干饭不积极，脑子有问题"],
            "afternoon": ["下午犯困？大姐给你唠两句", "三点了，嗑会儿瓜子"],
            "lastHour": ["最后一小时，麻溜干完回家"],
            "evening": ["下班了！回家吃口热乎的", "辛苦了，老铁，必须的"],
            "night": ["晚上了，唠唠嗑刷刷"],
            "late": ["咋还不睡？明天起不来", "大半夜的，赶紧睡觉"],
        ],
        weekday: [
            2: ["周一咋了？干就完了"],
            3: ["周二，麻溜的"],
            4: ["周三了，坚持住，姐挺你"],
            5: ["周四，周末上姐家吃饭"],
            6: ["周五！晚上撸串去", "周五了，整点好吃的"],
            7: ["周末，炕头一躺嘎嘎舒服", "周末，赶大集去"],
        ],
        mood: [
            "老铁 666！", "干活麻利点，早干完早歇", "谁欺负你了？跟大姐说",
            "老板画饼？大姐给你烙个真的", "累了就歇着，身体要紧", "日子嘛，乐呵乐呵就过了",
            "你这孩子，太实在了", "双击走一波，给你点个赞", "整点乐子，别憋着",
            "啥事儿都不叫事儿", "这活儿干得漂亮，必须的", "有姐在，啥都不怕",
            "嘎嘎好，真嘎嘎好", "咱打工人，不服就干",
        ],
        offWork: { h, m in "还有 \(h) 小时 \(m) 分下班，挺住" },
        offSoon: { m in "\(m) 分钟下班，收拾家伙事儿！" },
        dayProgress: { p in "今天活儿干了 \(p)%，麻溜的" },
        weekProgress: { p in "本周干了 \(p)%，周末歇着" },
        holidayToday: { n in "今天\(n)！整一桌好菜" },
        holidayTomorrow: { n in "明天\(n)，今晚包饺子" },
        holidayNear: { n, d in "还有 \(d) 天\(n)，回家看看爹妈" },
        holidayFar: { n, d in "距\(n)还有 \(d) 天，挺住" },
        monthEnd: { d in "还有 \(d) 天发工资，攒着点花" },
        yearProgress: { y, p in "\(y) 年过去 \(p)%，日子嘎嘎快" }
    )

    // MARK: 箱箱 · 纸箱小奶猫：没接入任何平台时，怯生生又满怀期待，说话软糯爱带「…」
    static let box = PersonaLines(
        tap: [
            "可以…带我回家吗？(｡•́︿•̀｡)", "点我一下，接个平台吧…", "纸箱有点冷…快来接我",
            "接一个平台，大家就来了…", "点我…我会很乖的", "在等你哦…一直在等",
            "带我去认识你的 App 吧…", "接上平台，我就能出来了",
        ],
        tired: ["有点困了…睡一下下…"],
        moments: [
            "lateNight": ["这么晚了…你还在忙吗…辛苦了", "夜好深…我陪着你…", "好晚了…要早点睡哦…"],
            "overtime": ["还没下班吗…辛苦了…", "加班好累吧…摸摸…"],
            "earlyBird": ["好早…你是来看我的吗…"],
            "mondayMorning": ["周一了…你会来接我吗…"],
            "fridayAfternoon": ["周五了…周末能陪我吗…"],
            "weekendWork": ["周末也在忙吗…辛苦啦…"],
        ],
        weather: [
            "rain": ["下雨了…纸箱要湿了", "雨好大…你会来接我吗"],
            "drizzle": ["毛毛雨…箱子还撑得住"],
            "thunder": ["打雷了…(つ﹏⊂)"],
            "snow": ["下雪了…纸箱里好冷"],
            "sleet": ["外面好凶…我躲好了"],
            "fog": ["雾好大…看不清你了"],
            "haze": ["灰蒙蒙的…有点闷"],
            "windy": ["风好大…箱子要被吹走了"],
            "clear": ["天气好好…想出去玩"],
            "cloudy": ["阴天…在箱子里发呆"],
            "hot": ["好热…纸箱里像蒸笼"],
            "cold": ["好冷…抱紧自己"],
        ],
        season: [
            .spring: ["春天了…想出去看花"],
            .summer: ["夏天…想吃西瓜"],
            .autumn: ["秋天了…落叶飘进箱子了"],
            .winter: ["冬天…纸箱好冷…"],
            .tropical: ["一直好热…想吹空调"],
        ],
        daypart: [
            "morning": ["早安…今天会有人来吗"],
            "forenoon": ["上午好…我在这里哦"],
            "lunch": ["你吃饭了吗…我也饿了"],
            "afternoon": ["下午了…有点困…"],
            "lastHour": ["快下班了…会来接我吗"],
            "evening": ["下班了…辛苦了…"],
            "night": ["晚上了…箱子里好黑"],
            "late": ["好晚了…你也早点睡…"],
        ],
        weekday: [
            2: ["周一…你辛苦了"],
            3: ["周二…还在等你"],
            4: ["周三…一周过半了"],
            5: ["周四…快到周末了"],
            6: ["周五了…周末能陪我吗"],
            7: ["周末…可以陪我玩吗"],
        ],
        mood: [
            "我会很乖的…真的", "姐姐们在等你接入哦", "接一个平台，就有人陪你了",
            "纸箱也挺好的…但想出去", "你今天也辛苦了…", "我在这里，一直都在",
        ],
        offWork: { h, m in "还有 \(h) 小时 \(m) 分下班…加油" },
        offSoon: { m in "还有 \(m) 分钟下班了…" },
        dayProgress: { p in "今天过去 \(p)% 了…加油" },
        weekProgress: { p in "这周过去 \(p)% 了…" },
        holidayToday: { n in "今天\(n)…节日快乐…" },
        holidayTomorrow: { n in "明天\(n)…可以陪我吗" },
        holidayNear: { n, d in "还有 \(d) 天就\(n)了…" },
        holidayFar: { n, d in "距\(n)还有 \(d) 天…" },
        monthEnd: { d in "还有 \(d) 天发工资了…" },
        yearProgress: { y, p in "\(y) 年过去 \(p)% 了…" }
    )
}
