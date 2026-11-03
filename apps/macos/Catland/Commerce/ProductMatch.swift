// 商品页的测评要对上这一款（SKU），不能是搜索词那么宽：从京东标题里认出品牌和型号，
// 用「品牌 型号」去内容平台搜，再只留下标题里带这个型号的结果。
import Foundation

struct ProductMatch: Equatable {
    /// 品牌及别名：罗技 / Logitech，雷蛇 / Razer，Apple / 苹果
    let brands: [String]
    /// 型号：G316、JZ990Pro、K845、黑寡妇蜘蛛V3……（字母和数字混合的那一段，太短时带上前面的系列名）
    let model: String?
    /// 没有型号时的系列名：黑寡妇蜘蛛……
    let series: String?
    /// 型号、系列都认不出时的品类（只能按品牌 + 品类找，结果不一定是这一款）
    let category: String?

    var brand: String? { brands.first }

    /// 去内容平台搜测评用的词
    var query: String { [brand, model ?? series ?? category].compactMap { $0 }.joined(separator: " ") }

    /// 能精确对上这一款（有型号或系列）
    var specific: Bool { model != nil || series != nil }

    /// 内容平台的这条结果说的是不是这一款
    func matches(_ title: String?) -> Bool {
        guard let title else { return false }
        let t = Self.normalize(title)
        let hasBrand = brands.contains { t.contains(Self.normalize($0)) }
        if let m = model {
            // 只认型号里字母数字那一段（「黑寡妇蜘蛛V3」也要能匹配「Razer 黑寡妇 V3」）
            let core = Self.normalize(m.replacingOccurrences(of: "^\\p{Han}+", with: "", options: .regularExpression))
            // 型号后面不能紧跟字母数字：G316 不算 G316X，JZ990Pro 不算 JZ990ProV2（那是另一款）
            guard Self.containsWhole(t, core) else { return false }
            // 型号太短（M3、V3、K8）容易撞车：还要求品牌出现
            return core.count > 3 || hasBrand
        }
        if let s = series { return t.contains(Self.normalize(s)) }
        if let c = category { return hasBrand && t.contains(Self.normalize(c)) }
        return false
    }

    /// t 里有 key，且 key 前后都不是字母或数字
    static func containsWhole(_ t: String, _ key: String) -> Bool {
        var from = t.startIndex
        while let r = t.range(of: key, range: from..<t.endIndex) {
            let before = r.lowerBound > t.startIndex ? t[t.index(before: r.lowerBound)] : " "
            let after = r.upperBound < t.endIndex ? t[r.upperBound] : " "
            let alnum: (Character) -> Bool = { $0.isASCII && ($0.isLetter || $0.isNumber) }
            if !alnum(before) && !alnum(after) { return true }
            from = t.index(after: r.lowerBound)
        }
        return false
    }

    static func normalize(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: "[\\s\\-_·/]", with: "", options: .regularExpression)
    }

    /// 常见品类词：系列名如果只是品类（「机械键盘」），不能当系列
    private static let categories = ["机械键盘", "键盘", "鼠标", "耳机", "音箱", "手机", "平板", "笔记本", "电脑", "显示器", "充电器", "充电宝", "手表", "手环",
                                     "相机", "路由器", "猫砂", "猫粮", "狗粮", "洗面奶", "面霜", "精华", "口红", "咖啡", "牛奶", "电动牙刷", "吹风机", "空气炸锅"]

    /// 从京东商品标题认出品牌、型号、系列。
    static func parse(_ title: String) -> ProductMatch {
        var rest = title.trimmingCharacters(in: .whitespaces)
        // 开头的营销前缀：【万人购】、[自营]
        rest = rest.replacingOccurrences(of: "^[【\\[][^】\\]]*[】\\]]\\s*", with: "", options: .regularExpression)

        var brands: [String] = []
        if let m = rest.firstMatch(of: /^([\p{Han}A-Za-z]{1,12}?)\s*[（(]([^）)]{1,20})[）)]\s*/) {
            // 「罗技（Logitech）」「雷蛇（Razer）」：括号里的英文名也算品牌（太短的如「G」不算）
            brands.append(String(m.1))
            let alias = String(m.2).trimmingCharacters(in: .whitespaces)
            if alias.count >= 2 { brands.append(alias) }
            rest = String(rest[m.range.upperBound...])
        } else if let m = rest.firstMatch(of: /^([\p{Han}A-Za-z]{1,12})\/([\p{Han}A-Za-z]{1,12})\s*/) {
            // 「Apple/苹果」
            brands += [String(m.1), String(m.2)]
            rest = String(rest[m.range.upperBound...])
        } else if let m = rest.firstMatch(of: /^(\p{Han}{2,4})(?=[A-Za-z0-9])/) {
            // 「京东京造JZ990Pro……」：中文品牌后面紧跟型号
            brands.append(String(m.1))
            rest = String(rest[m.range.upperBound...])
        } else if let m = rest.firstMatch(of: /^(\p{Han}{2,4}|[A-Za-z]{2,12})\s/) {
            brands.append(String(m.1))
            rest = String(rest[m.range.upperBound...])
        }

        // 型号：字母和数字都有的一段（G316、JZ990Pro、WH-1000XM5、M3）；跳过规格（8K、16GB、2.4G、13.6英寸）
        var model: String?
        for m in rest.matches(of: /[A-Za-z0-9][A-Za-z0-9\-]*/) {
            let s = String(m.0).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            guard s.contains(where: \.isLetter), s.contains(where: \.isNumber), !isSpec(s) else { continue }
            model = s
            // 型号太短（V3）：带上紧挨着的中文系列名（「黑寡妇蜘蛛V3」）
            if s.count <= 3, let pre = rest[..<m.range.lowerBound].firstMatch(of: /(\p{Han}{2,6})$/) {
                model = cleanSeries(String(pre.1)).map { $0 + s } ?? s
            }
            break
        }

        var series: String?, category: String?
        if model == nil, let m = rest.firstMatch(of: /^\s*(\p{Han}{2,8})/) {
            let head = String(m.1)
            if let c = categories.first(where: { head.hasPrefix($0) }) { category = c } else { series = cleanSeries(head) }
        }
        if model == nil && series == nil && category == nil {
            category = categories.first { rest.contains($0) }
        }
        return ProductMatch(brands: brands, model: model, series: series, category: category)
    }

    /// 「黑寡妇蜘蛛标准版」→「黑寡妇蜘蛛」
    private static func cleanSeries(_ s: String) -> String? {
        let v = s.replacingOccurrences(of: "(标准版|旗舰版|竞技版|专业版|升级版|电竞版|新款|官方|正品)$", with: "", options: .regularExpression)
        return v.count >= 2 && !categories.contains(v) ? v : nil
    }

    private static func isSpec(_ s: String) -> Bool {
        s.range(of: "^[0-9.]+(k|g|gb|tb|mb|hz|khz|mm|cm|w|mah|v|p|m)?$", options: [.regularExpression, .caseInsensitive]) != nil
    }
}
