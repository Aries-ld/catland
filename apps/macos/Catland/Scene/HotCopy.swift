// HotCopy：小猫顺嘴说一句「外面大家在刷什么」。数据是各平台的实时热搜（sidecar 在后台定时取、App 已缓存在本机），
// 不新增任何联网请求。规则：
// - 每只猫用自己的口吻说自己平台的热搜（薯薯说小红书、bibi 说 B 站……）；别的平台的热搜带上平台名；没接平台时箱箱说；
// - 只说 6 小时内的热点；带灾难、伤亡、刑案等字眼的不说——小猫不拿坏消息开玩笑，也不评论严肃事件；
// - 话题太长（超过 12 个字）不说，整句不超过 22 个字（和其他语料一样）；
// - 气泡里话题用「」括起来：点刘海时如果正好显示这句，直接打开搜索搜这个词。
import Foundation

enum HotCopy {
    /// 超过这个时间的热搜不说
    static let freshFor: TimeInterval = 6 * 3600
    static let maxTopicLength = 12

    /// 不说的话题：灾难、伤亡、刑案、疾病、政治敏感等
    static let blocked = ["去世", "逝世", "死亡", "身亡", "遇难", "罹难", "丧生", "牺牲", "事故", "车祸", "坠机", "坠楼", "火灾", "爆炸", "地震", "洪水",
                          "台风", "海啸", "塌方", "溺水", "失踪", "遇害", "凶手", "杀人", "命案", "强奸", "猥亵", "性侵", "诈骗", "被捕", "判刑", "死刑",
                          "自杀", "跳楼", "疫情", "病毒", "确诊", "癌", "战争", "空袭", "袭击", "枪击", "恐袭", "冲突", "制裁", "抗议", "游行", "政府"]

    /// 能拿来说的话题
    static func usable(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces)
        return (2...maxTopicLength).contains(t.count) && !t.contains("http") && !t.contains("「") && !t.contains("」") && !blocked.contains { t.contains($0) }
    }

    /// 新鲜、能说的热搜（同一个词只留一次）
    static func topics(_ words: [HotWord], fetchedAt: Date?, now: Date = Date()) -> [HotWord] {
        guard let at = fetchedAt, now.timeIntervalSince(at) < freshFor else { return [] }
        var seen = Set<String>()
        return words.filter { usable($0.text) && seen.insert($0.text).inserted }
    }

    private static let own: [Persona: [String]] = [
        .shushu: ["小红书都在搜「{t}」，你看了吗", "姐妹们在聊「{t}」，冲浪中", "热搜上有「{t}」，先码住"],
        .doudou: ["今天大家都在刷「{t}」", "「{t}」上热搜了，懂的都懂", "「{t}」火了，刷到没"],
        .bibi: ["B站在热议「{t}」，弹幕好热闹", "「{t}」火了，三连走起", "大家在看「{t}」，你呢"],
        .tietie: ["老铁们都在唠「{t}」", "「{t}」上热门了，瞅一眼不", "「{t}」火了，整挺好"],
        .box: ["外面大家都在聊「{t}」诶", "听说「{t}」上热搜了", "「{t}」好像很火，喵"],
    ]

    private static func platformName(_ id: String) -> String {
        id == "bilibili" ? "B站" : PlatformBrand.shortName(id)
    }

    /// 这只猫能说的热点句子（不含名字）。自己平台的热搜用自己的口吻，别的平台的带上平台名。
    static func lines(for p: Persona, topics: [HotWord]) -> [String] {
        let mine = topics.filter { Persona.forPlatform($0.platform) == p || (p == .box && Persona.forPlatform($0.platform) == nil) }
        let others = topics.filter { !mine.contains($0) }
        var out: [String] = []
        for (i, w) in mine.enumerated() {
            let tpl = own[p] ?? own[.box]!
            out.append(tpl[i % tpl.count].replacingOccurrences(of: "{t}", with: w.text))
        }
        for w in others {
            out.append("\(platformName(w.platform))上在聊「\(w.text)」")
        }
        return out.filter { $0.count <= 22 }
    }

    /// 这句气泡是不是热点句：是的话返回话题（点刘海时直接搜它）
    static func topic(in line: String, topics: [HotWord]) -> String? {
        guard let m = line.firstMatch(of: /「([^」]+)」/) else { return nil }
        let t = String(m.1)
        return topics.contains { $0.text == t } ? t : nil
    }
}
