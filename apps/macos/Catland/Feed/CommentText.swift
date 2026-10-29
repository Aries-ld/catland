// 评论正文：平台的表情代码（[doge]、[笑哭R]、[赞]…）换成 emoji，不认识的显示成淡色小字；时间显示成「3 天前」。
import SwiftUI

enum CommentText {
    /// 常见表情代码 → emoji。小红书的代码带 R / H 后缀（[笑哭R]），比较时先去掉。
    static let emoji: [String: String] = [
        "赞": "👍", "强": "👍", "点赞": "👍", "弱": "👎", "doge": "🐶", "狗头": "🐶", "笑哭": "😂", "破涕为笑": "😂", "偷笑": "🤭", "捂嘴笑": "🤭",
        "害羞": "😳", "哭惹": "😭", "大哭": "😭", "流泪": "😢", "哭": "😢", "捂脸": "🤦", "呲牙": "😁", "嘿嘿": "😁", "微笑": "🙂", "哈哈": "😄",
        "大笑": "😄", "色": "😍", "喜欢": "😍", "爱心": "❤️", "心": "❤️", "比心": "🫶", "鼓掌": "👏", "拍手": "👏", "机智": "😏", "坏笑": "😏",
        "吃瓜": "🍉", "加油": "💪", "奋斗": "💪", "发呆": "😶", "生气": "😠", "发怒": "😠", "抓狂": "😫", "晕": "😵", "惊讶": "😮", "吃惊": "😮",
        "疑问": "🤔", "思考": "🤔", "无语": "😑", "白眼": "🙄", "皱眉": "😟", "酷": "😎", "墨镜": "😎", "再见": "👋", "拜拜": "👋", "OK": "👌",
        "握手": "🤝", "抱拳": "🙏", "祈祷": "🙏", "合十": "🙏", "玫瑰": "🌹", "星星眼": "🤩", "飞吻": "😘", "亲亲": "😘", "可怜": "🥺", "委屈": "🥺",
        "喝奶茶": "🧋", "奶茶": "🧋", "扯脸": "😜", "鬼脸": "😜", "打call": "📣", "红包": "🧧", "庆祝": "🎉", "火": "🔥", "汗": "😅", "尴尬": "😅",
        "失望": "😞", "叹气": "😮‍💨", "生病": "🤒", "睡": "😴", "睡觉": "😴", "困": "😪", "打脸": "🤕", "666": "6️⃣6️⃣6️⃣", "牛": "🐮", "牛哇": "🐮",
        "绝绝子": "✨", "awsl": "🥰", "爱了": "🥰", "笑": "😆", "开心": "😆", "难过": "😔", "心碎": "💔", "大佬": "🙇", "跪了": "🧎", "呆": "😶",
    ]

    /// 把正文切成「文字 / emoji / 不认识的表情」三种片段，拼成一个 Text。
    static func render(_ s: String) -> Text {
        var out = Text("")
        var rest = Substring(s)
        while let open = rest.firstIndex(of: "[") {
            guard let close = rest[open...].firstIndex(of: "]"), rest.distance(from: open, to: close) <= 10 else { break }
            out = out + Text(String(rest[..<open]))
            let code = String(rest[rest.index(after: open)..<close])
            if let e = lookup(code) { out = out + Text(e) } else { out = out + Text("[\(code)]").foregroundColor(.white.opacity(0.4)) }
            rest = rest[rest.index(after: close)...]
        }
        return out + Text(String(rest))
    }

    static func lookup(_ code: String) -> String? {
        if let e = emoji[code] { return e }
        // B 站的系列表情：[doge_金箍]、[热词系列_xx] → 取下划线前面的名字
        if let us = code.firstIndex(of: "_"), let e = emoji[String(code[..<us])] { return e }
        if let last = code.last, last == "R" || last == "H", code.count > 1 { return emoji[String(code.dropLast())] }
        return nil
    }

    /// B 站等平台在回复正文前面带「回复 @某某 :」，已经显示了「▸ 某某」时去掉这段。
    static func stripReplyPrefix(_ s: String) -> String {
        guard let r = s.range(of: #"^回复\s*@[^:：]{1,30}[:：]\s*"#, options: .regularExpression) else { return s }
        return String(s[r.upperBound...])
    }

    /// 「刚刚 / 5 分钟前 / 3 小时前 / 2 天前 / 10-21 / 2025-10-21」
    static func relative(_ iso: String?, now: Date = Date()) -> String? {
        guard let iso, let d = parse(iso) else { return nil }
        let s = now.timeIntervalSince(d)
        if s < 60 { return "刚刚" }
        if s < 3600 { return "\(Int(s / 60)) 分钟前" }
        if s < 86_400 { return "\(Int(s / 3600)) 小时前" }
        if s < 7 * 86_400 { return "\(Int(s / 86_400)) 天前" }
        let f = DateFormatter()
        f.dateFormat = Calendar.current.isDate(d, equalTo: now, toGranularity: .year) ? "MM-dd" : "yyyy-MM-dd"
        return f.string(from: d)
    }

    private static func parse(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }
}
