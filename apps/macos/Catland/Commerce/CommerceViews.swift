// 电商板块（购物小助手，先只接京东）：搜索 → 京东商品 + 大家怎么说（小红书 / B 站 / 抖音的测评）→ 商品页 → 去京东买；
// 心愿单盯价、订单状态。界面组件在这里，数据接入见 docs/decisions（待写 ADR 0005）。
import AppKit
import Charts
import SwiftUI

/// 京东商品（来自 catbus jd item search / get）。
struct Product: Identifiable, Hashable {
    let id: String
    let title: String
    let price: Double
    let shop: String
    let cover: ImageSource?
    let url: String
    /// 评价数：京东只给量级（5 万+），这里存下限。
    let comments: Int?

    var selfOperated: Bool { shop.contains("自营") }
}

struct PricePoint: Hashable {
    let date: Date
    let price: Double
}

/// 心愿单里的一件：价格历史只存在本机。
struct WishItem: Identifiable, Hashable {
    let product: Product
    /// 价格历史（旧 → 新）
    let history: [PricePoint]
    var id: String { product.id }
    var current: Double { history.last?.price ?? product.price }
    var lowest: Double { history.map(\.price).min() ?? current }
    var highest: Double { history.map(\.price).max() ?? current }
    /// 和加入时比：负数是降价
    var change: Double { current - (history.first?.price ?? current) }
    /// 加入心愿单的时间（第一个价格点）
    var added: Date { history.first?.date ?? Date() }
    /// 记录了多少天
    var days: Int {
        guard let a = history.first?.date else { return 0 }
        return max(1, Calendar.current.dateComponents([.day], from: a, to: Date()).day ?? 0)
    }
    /// 画图用：最后一个价格一直延续到现在（价格没变时也能看到一条线，而不是一个点）
    var chartPoints: [PricePoint] {
        guard let last = history.last else { return [] }
        return last.date < Date().addingTimeInterval(-60) || history.count == 1 ? history + [PricePoint(date: max(Date(), last.date.addingTimeInterval(3600)), price: last.price)] : history
    }
}

/// 订单的履约状态（catbus jd order list）。
struct OrderStatus: Identifiable, Hashable {
    let id: String
    let title: String
    let cover: ImageSource?
    let status: String
    let detail: String
    /// 0…1：下单 → 出库 → 运输 → 派送 → 签收
    let progress: Double
}

enum PriceFormat {
    static func yuan(_ v: Double) -> String {
        v.rounded() == v ? "¥\(Int(v))" : String(format: "¥%.2f", v).replacingOccurrences(of: "0$", with: "", options: .regularExpression)
    }

    static func comments(_ n: Int?) -> String? {
        guard let n, n > 0 else { return nil }
        return n >= 10_000 ? "\(n / 10_000)万+ 评价" : "\(n)+ 评价"
    }
}

private let priceRed = Color(red: 1, green: 0.27, blue: 0.27)
private let dropGreen = Color(red: 0.25, green: 0.85, blue: 0.55)

// MARK: - 搜索框

struct CommerceSearchBar: View {
    let query: String
    /// 给了就是可输入的搜索框（回车才搜）；离屏渲染设计稿时为 nil，只显示文字
    var text: Binding<String>? = nil
    var onSubmit: () -> Void = {}
    var onClear: () -> Void = {}
    @FocusState private var focused: Bool
    private static let prompt = "想买点什么？京东价格 + 大家的真实测评"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
            if let text {
                TextField("", text: text, prompt: Text(Self.prompt).foregroundStyle(.white.opacity(0.4)))
                    .textFieldStyle(.plain).font(.system(size: 13))
                    .focused($focused)
                    .onSubmit(onSubmit)
                if !text.wrappedValue.isEmpty {
                    Button { onClear(); focused = true } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text(query.isEmpty ? Self.prompt : query)
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(query.isEmpty ? 0.4 : 0.92))
            }
            Spacer(minLength: 0)
            PlatformIcon(platform: "jd", size: 16)
        }
        .padding(.horizontal, 12).frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(focused ? Color.pink.opacity(0.6) : .clear, lineWidth: 1))
    }
}

// MARK: - 首页：心愿单 + 订单

struct CommerceHome: View {
    let wishes: [WishItem]
    let orders: [OrderStatus]
    let recent: [String]
    var rest: JDRest? = nil
    var onRecent: (String) -> Void = { _ in }
    var onOpenWish: (WishItem) -> Void = { _ in }
    var onRemoveWish: (WishItem) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !recent.isEmpty {
                HStack(spacing: 6) {
                    ForEach(recent.prefix(5), id: \.self) { q in Chip(text: q) { onRecent(q) } }
                }
            }
            ForEach(orders) { OrderCard(order: $0) }
            SectionTitle(title: "心愿单", detail: wishes.isEmpty ? nil : "每小时帮你看一眼价格")
            if let rest, !wishes.isEmpty { WishPausedBanner(rest: rest) }
            if wishes.isEmpty {
                Text("搜到喜欢的点一下 ♡ 就放进来，箱箱帮你盯着价格；降价了会在刘海里告诉你。")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.04)))
            }
            VStack(spacing: 8) {
                ForEach(wishes) { w in
                    WishRow(item: w)
                        .contentShape(Rectangle())
                        .onTapGesture { onOpenWish(w) }
                        .contextMenu {
                            if let u = URL(string: w.product.url) { Button("在京东打开") { NSWorkspace.shared.open(u) } }
                            Button("移出心愿单", role: .destructive) { onRemoveWish(w) }
                        }
                }
            }
        }
    }
}

struct SectionTitle: View {
    let title: String
    var detail: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title).font(.system(size: 13, weight: .semibold))
            if let detail { Text(detail).font(.system(size: 10)).foregroundStyle(.white.opacity(0.4)) }
            Spacer()
        }
    }
}

struct Chip: View {
    let text: String
    var active = false
    var action: (() -> Void)? = nil

    init(text: String, active: Bool = false, action: (() -> Void)? = nil) {
        self.text = text
        self.active = active
        self.action = action
    }

    var body: some View {
        let label = Text(text).font(.system(size: 11, weight: active ? .semibold : .regular))
            .foregroundStyle(active ? .black : .white.opacity(0.75))
            .padding(.horizontal, 10).frame(height: 24)
            .background(Capsule().fill(active ? Color.white : .white.opacity(0.08)))
            .contentShape(Capsule())
        if let action { Button(action: action) { label }.buttonStyle(PressStyle()) } else { label }
    }
}

/// 心愿单一行：封面、标题、现价、和加入时比涨跌、价格小曲线。
struct WishRow: View {
    let item: WishItem
    var body: some View {
        HStack(spacing: 10) {
            ProductThumb(source: item.product.cover, size: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.product.title).font(.system(size: 12)).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
                HStack(spacing: 6) {
                    Text(PriceFormat.yuan(item.current)).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(priceRed)
                    if item.change < 0 {
                        Text("降 \(PriceFormat.yuan(-item.change))").font(.system(size: 10, weight: .semibold)).foregroundStyle(.black)
                            .padding(.horizontal, 5).frame(height: 16).background(Capsule().fill(dropGreen))
                    }
                    if item.current <= item.lowest && item.history.count > 3 && item.highest > item.lowest {
                        Text("近期最低").font(.system(size: 10, weight: .medium)).foregroundStyle(dropGreen)
                    }
                }
            }
            Spacer(minLength: 4)
            PriceChart(item: item, compact: true).frame(width: 96, height: 44)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.05)))
    }
}

/// 价格走势（Swift Charts）。
/// 完整版：纵轴价格刻度、横轴日期，标出最高、最低和现在；缩略版（心愿单）：只标最低点和现在，下面一行写「N 天最低」。
struct PriceChart: View {
    let item: WishItem
    var compact = false

    private var points: [PricePoint] { item.chartPoints }
    private var lowPoint: PricePoint? { points.min { $0.price < $1.price } }
    private var highPoint: PricePoint? { points.max { $0.price < $1.price } }
    private var shortSpan: Bool {
        guard let a = points.first?.date, let b = points.last?.date else { return true }
        return b.timeIntervalSince(a) < 2 * 86400
    }
    private var trend: Color { item.change < 0 ? dropGreen : (item.change > 0 ? priceRed : .white.opacity(0.7)) }
    /// 纵轴留白：曲线不贴边，标注放得下
    private var domain: ClosedRange<Double> {
        let lo = item.lowest, hi = item.highest, pad = max((hi - lo) * 0.35, hi * 0.02, 1)
        return (lo - pad)...(hi + pad)
    }

    var body: some View {
        if compact { compactBody } else { fullBody }
    }

    private var fullBody: some View {
        Chart {
            ForEach(points, id: \.date) { p in
                AreaMark(x: .value("日期", p.date), yStart: .value("下限", domain.lowerBound), yEnd: .value("价格", p.price))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(LinearGradient(colors: [trend.opacity(0.25), trend.opacity(0)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("日期", p.date), y: .value("价格", p.price))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(trend)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            if let h = highPoint, item.highest > item.lowest {
                PointMark(x: .value("日期", h.date), y: .value("价格", h.price)).foregroundStyle(priceRed).symbolSize(30)
                    .annotation(position: .top, spacing: 3) { label("最高 \(PriceFormat.yuan(h.price))", priceRed) }
            }
            // 现在就是最低价：合成一个标注，不叠在一起
            let nowIsLow = item.current <= item.lowest
            if let l = lowPoint, item.highest > item.lowest, !nowIsLow {
                PointMark(x: .value("日期", l.date), y: .value("价格", l.price)).foregroundStyle(dropGreen).symbolSize(30)
                    .annotation(position: .bottom, spacing: 3) { label("最低 \(PriceFormat.yuan(l.price))", dropGreen) }
            }
            if let c = points.last {
                PointMark(x: .value("日期", c.date), y: .value("价格", c.price)).foregroundStyle(.white).symbolSize(40)
                    .annotation(position: nowIsLow ? .bottomLeading : .topLeading, spacing: 3) {
                        label(nowIsLow ? "现在 \(PriceFormat.yuan(c.price)) · 最低" : "现在 \(PriceFormat.yuan(c.price))", nowIsLow ? dropGreen : .white.opacity(0.85))
                    }
            }
        }
        .chartYScale(domain: domain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(.white.opacity(0.06))
                // 记录还不到两天：横轴标几点，不然会是一排一样的日期
                if shortSpan {
                    AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute(), centered: false).foregroundStyle(.white.opacity(0.45)).font(.system(size: 9))
                } else {
                    AxisValueLabel(format: .dateTime.month(.defaultDigits).day(), centered: false).foregroundStyle(.white.opacity(0.45)).font(.system(size: 9))
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { v in
                AxisGridLine().foregroundStyle(.white.opacity(0.08))
                AxisValueLabel { if let d = v.as(Double.self) { Text(PriceFormat.yuan(d.rounded())) } }.foregroundStyle(.white.opacity(0.45)).font(.system(size: 9))
            }
        }
    }

    private var compactBody: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Chart {
                ForEach(points, id: \.date) { p in
                    LineMark(x: .value("日期", p.date), y: .value("价格", p.price))
                        .interpolationMethod(.stepEnd)
                        .foregroundStyle(trend)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
                if let l = lowPoint, item.highest > item.lowest, l != points.last {
                    PointMark(x: .value("日期", l.date), y: .value("价格", l.price)).foregroundStyle(dropGreen).symbolSize(14)
                }
                if let c = points.last { PointMark(x: .value("日期", c.date), y: .value("价格", c.price)).foregroundStyle(.white).symbolSize(18) }
            }
            .chartYScale(domain: domain)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            Text(item.history.count < 2 ? "刚开始盯" : "\(item.days) 天最低 \(PriceFormat.yuan(item.lowest))")
                .font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
        }
    }

    private func label(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 9, weight: .semibold)).foregroundStyle(color)
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(Capsule().fill(Color(white: 0.1).opacity(0.85)))
    }
}

/// 订单履约：箱箱抱着纸箱在进度条上走。
struct OrderCard: View {
    let order: OrderStatus
    var body: some View {
        HStack(spacing: 10) {
            ProductThumb(source: order.cover, size: 44)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(order.status).font(.system(size: 12, weight: .semibold))
                    Text(order.detail).font(.system(size: 10)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.12)).frame(height: 3)
                        Capsule().fill(Color(red: 1, green: 0.55, blue: 0.35)).frame(width: g.size.width * order.progress, height: 3)
                        CatSprite(skin: "kitten", action: "walk", scale: 1.5)
                            .offset(x: g.size.width * order.progress - 14, y: -9)
                    }
                    .frame(maxHeight: .infinity)
                }
                .frame(height: 18)
                Text(order.title).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 1, green: 0.55, blue: 0.3).opacity(0.18), .white.opacity(0.04)], startPoint: .leading, endPoint: .trailing)))
    }
}

struct ProductThumb: View {
    let source: ImageSource?
    let size: CGFloat
    var body: some View {
        RemoteImage(source: source, contentMode: .fit)
            .frame(width: size, height: size)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - 搜索结果：大家怎么说 + 京东商品

struct CommerceResults: View {
    let query: String
    let reviews: [CoverItem]
    let products: [Product]
    let wished: Set<String>
    /// 离屏渲染（设计稿）时不能用 ScrollView：ImageRenderer 画不出它的内容
    var scrollable = true
    /// 京东歇着时：顶上放说明卡，下面是上次的结果
    var rest: JDRest? = nil
    var cachedAt: Date? = nil
    var sort = "general"
    var loading = false
    var reviewsLoading = false
    var hasMore = false
    var failed = false
    var onRetry: () -> Void = {}
    var onSort: (String) -> Void = { _ in }
    var onOpen: (Product) -> Void = { _ in }
    var onWish: (Product) -> Void = { _ in }
    var onReview: (CoverItem) -> Void = { _ in }
    var onSearchInJD: () -> Void = {}
    var onLoadMore: () -> Void = {}

    static let sorts: [(String, String)] = [("general", "综合"), ("sales", "销量"), ("price_asc", "价格"), ("comments", "评价")]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "大家怎么说", detail: "小红书 · B 站 · 抖音的真实测评")
            if reviews.isEmpty {
                Text(reviewsLoading ? "小猫们正在找测评…" : "没找到相关测评").font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ReviewStrip(reviews: Array(reviews.prefix(10)), scrollable: scrollable, onTap: onReview)
            }
            HStack(spacing: 6) {
                SectionTitle(title: "京东")
                Spacer()
                ForEach(Self.sorts, id: \.0) { key, name in
                    // 「价格」再点一下切换升降序
                    let on = sort == key || (key == "price_asc" && sort == "price_desc")
                    Chip(text: key == "price_asc" && sort == "price_desc" ? "价格↓" : (key == "price_asc" && on ? "价格↑" : name), active: on) {
                        onSort(key == "price_asc" && sort == "price_asc" ? "price_desc" : key)
                    }
                }
            }
            .opacity(rest == nil ? 1 : 0.4)
            .allowsHitTesting(rest == nil)
            if let rest { JDRestCard(rest: rest, query: query, cachedAt: cachedAt, onSearchInJD: onSearchInJD) }
            if loading && products.isEmpty {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 80)
            } else if failed && rest == nil {
                HStack(spacing: 10) {
                    Text("京东这次没响应").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Chip(text: "重试", action: onRetry)
                    Chip(text: "在京东里搜", action: onSearchInJD)
                }
                .padding(10).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.05)))
            } else if products.isEmpty && rest == nil {
                Text("京东上没搜到「\(query)」，换个说法试试").font(.system(size: 11)).foregroundStyle(.white.opacity(0.45)).frame(maxWidth: .infinity, minHeight: 60)
            }
            VStack(spacing: 8) {
                ForEach(products) { p in
                    ProductRow(product: p, wished: wished.contains(p.id), onWish: { onWish(p) })
                        .contentShape(Rectangle())
                        .onTapGesture { onOpen(p) }
                }
            }
            .opacity(rest == nil ? 1 : 0.75)
            if hasMore && rest == nil {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(.vertical, 6).onAppear(perform: onLoadMore)
            }
        }
    }
}

/// 一排测评小卡，横向滑动。
struct ReviewStrip: View {
    let reviews: [CoverItem]
    var scrollable = true
    var onTap: (CoverItem) -> Void = { _ in }
    var body: some View {
        let row = HStack(spacing: 8) { ForEach(reviews) { r in ReviewTile(item: r).contentShape(Rectangle()).onTapGesture { onTap(r) } } }
        if scrollable { ScrollView(.horizontal, showsIndicators: false) { row } } else {
            // 不让超宽的一排把父视图撑宽：放进固定高度的容器里，靠左、裁掉右边
            Color.clear.frame(height: 172).overlay(alignment: .topLeading) { row.fixedSize() }.clipped()
        }
    }
}

/// 测评小卡：竖版封面 + 平台图标 + 一行标题。
struct ReviewTile: View {
    let item: CoverItem
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .topLeading) {
                RemoteImage(source: item.cover).frame(width: 104, height: 138).clipped()
                PlatformIcon(platform: item.platform, size: 14).padding(5)
                if item.isVideo {
                    Image(systemName: "play.fill").font(.system(size: 8)).foregroundStyle(.white)
                        .padding(4).background(Circle().fill(.black.opacity(0.5)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(5)
                }
            }
            .frame(width: 104, height: 138)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text(Format.caption(title: item.title, text: nil)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.8)).lineLimit(2)
                .frame(width: 104, alignment: .leading)
        }
    }
}

/// 京东商品一行：白底商品图、两行标题、价格、店铺（自营标签）、评价量级、加心愿单。
struct ProductRow: View {
    let product: Product
    let wished: Bool
    var onWish: () -> Void = {}
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ProductThumb(source: product.cover, size: 84)
            VStack(alignment: .leading, spacing: 5) {
                Text(product.title).font(.system(size: 12)).foregroundStyle(.white.opacity(0.92)).lineLimit(2)
                HStack(spacing: 5) {
                    if product.selfOperated {
                        Text("自营").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 4).frame(height: 14).background(RoundedRectangle(cornerRadius: 3).fill(priceRed))
                    }
                    Text(product.shop.replacingOccurrences(of: "京东自营旗舰店", with: "").replacingOccurrences(of: "自营旗舰店", with: ""))
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                }
                Spacer(minLength: 0)
                HStack(alignment: .lastTextBaseline) {
                    Text(product.price > 0 ? PriceFormat.yuan(product.price) : "看价格").font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(priceRed)
                    if let c = PriceFormat.comments(product.comments) { Text(c).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)) }
                    Spacer()
                    Button(action: onWish) {
                        Image(systemName: wished ? "heart.fill" : "heart").font(.system(size: 14))
                            .foregroundStyle(wished ? Color.pink : .white.opacity(0.6))
                            .symbolEffect(.bounce, value: wished)
                            .frame(width: 30, height: 30).contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .help(wished ? "移出心愿单" : "加入心愿单，帮你盯价格")
                }
            }
            .frame(height: 84)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.05)))
    }
}

// MARK: - 商品页

struct ProductDetailView: View {
    let product: Product
    let reviews: [CoverItem]
    let wish: WishItem?
    var scrollable = true
    /// 价格来自多久之前的搜索结果（京东歇着时显示「更新于」）
    var priceAt: Date? = nil
    var reviewsTitle = "大家怎么说"
    var reviewsNote: String? = nil
    var onBack: () -> Void = {}
    var onWish: () -> Void = {}
    var onBuy: () -> Void = {}
    var onReview: (CoverItem) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .topLeading) {
                RemoteImage(source: product.cover, contentMode: .fit).frame(maxWidth: .infinity).frame(height: 220).clipped().background(Color.white)
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
                        Text("返回").font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.white).padding(.horizontal, 9).frame(height: 24).background(Capsule().fill(.black.opacity(0.55))).contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(product.price > 0 ? PriceFormat.yuan(product.price) : "去京东看价格").font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(priceRed)
                    if let w = wish, w.change < 0 { Text("比加入时降了 \(PriceFormat.yuan(-w.change))").font(.system(size: 11, weight: .medium)).foregroundStyle(dropGreen) }
                    Spacer()
                    if let c = PriceFormat.comments(product.comments) { Text(c).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)) }
                }
                if let priceAt { Text("价格更新于 \(JDRestCard.ago(priceAt))，以京东页面为准").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)) }
                Text(product.title).font(.system(size: 13)).foregroundStyle(.white.opacity(0.92)).lineLimit(3)
                Text(product.shop).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            }
            if wish == nil {
                HStack(spacing: 10) {
                    Image(systemName: "chart.line.downtrend.xyaxis").font(.system(size: 16)).foregroundStyle(.white.opacity(0.5))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("价格走势").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                        Text("加入心愿单后，箱箱从今天开始记这件商品的价格，降价了告诉你").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                    }
                    Spacer(minLength: 0)
                }
                .padding(10).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.05)))
            }
            if let w = wish {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("价格走势").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        Text(w.history.count < 2 ? "\(Self.since(w.added)) 开始记录 · 加入时 \(PriceFormat.yuan(w.current))" : "近 \(w.days) 天 · 最高 \(PriceFormat.yuan(w.highest)) · 最低 \(PriceFormat.yuan(w.lowest))")
                            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                    }
                    PriceChart(item: w).frame(height: 150)
                }
                .padding(10).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.05)))
            }
            SectionTitle(title: reviewsTitle, detail: "小红书 · B 站 · 抖音")
            if let reviewsNote {
                Text(reviewsNote).font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
            }
            if !reviews.isEmpty {
                ReviewStrip(reviews: Array(reviews.prefix(10)), scrollable: scrollable, onTap: onReview)
            }
            HStack(spacing: 10) {
                Button(action: onWish) {
                    Label(wish == nil ? "加入心愿单" : "已在心愿单", systemImage: wish == nil ? "heart" : "heart.fill")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 38)
                        .background(Capsule().fill(.white.opacity(0.1))).contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                Button(action: onBuy) {
                    HStack(spacing: 6) {
                        PlatformIcon(platform: "jd", size: 16)
                        Text("去京东买").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 38)
                    .background(Capsule().fill(priceRed)).contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
            }
        }
    }
}

extension ProductDetailView {
    static func since(_ d: Date) -> String {
        Calendar.current.isDateInToday(d) ? "今天" : d.formatted(.dateTime.month(.defaultDigits).day())
    }
}

// MARK: - 降价提醒（刘海里的气泡）

struct PriceDropBubble: View {
    let item: WishItem
    var body: some View {
        HStack(spacing: 10) {
            CatSprite(skin: "kitten", action: "hop", scale: 2.5)
            VStack(alignment: .leading, spacing: 3) {
                Text("箱箱：你看中的东西降价啦").font(.system(size: 12, weight: .semibold))
                HStack(spacing: 6) {
                    Text(item.product.title).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    Text("降 \(PriceFormat.yuan(-item.change))").font(.system(size: 10, weight: .bold)).foregroundStyle(dropGreen)
                }
            }
            Spacer(minLength: 0)
            ProductThumb(source: item.product.cover, size: 36)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Capsule().fill(.black))
        .overlay(Capsule().stroke(.white.opacity(0.1)))
    }
}

// MARK: - 京东被风控时的兜底

/// 京东暂时不能用（限流 / 风控）的状态。
struct JDRest: Hashable {
    enum Kind: Hashable {
        /// 限流：到点自动恢复
        case resting
        /// 京东要求人机验证：需要用户在浏览器里正常逛一下京东
        case verify
    }
    let kind: Kind
    let resumeAt: Date?
}

/// 搜索结果里京东那一栏的替身：说明在歇、几点回来，给一个「在京东里搜」的出口；下面接着放上次的结果（标注更新时间）。
struct JDRestCard: View {
    let rest: JDRest
    let query: String
    var cachedAt: Date? = nil
    var onSearchInJD: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            CatSprite(skin: "kitten", action: "nap", scale: 2.2)
            VStack(alignment: .leading, spacing: 4) {
                Text(rest.kind == .resting ? "京东让箱箱歇会儿" : "京东想确认你是真人")
                    .font(.system(size: 12, weight: .semibold))
                Text(detail).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Button(action: onSearchInJD) {
                        Label("在京东里搜「\(query)」", systemImage: "arrow.up.right")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 9).frame(height: 22).background(Capsule().fill(priceRed.opacity(0.85))).contentShape(Capsule())
                    }
                    .buttonStyle(PressStyle())
                    if let cachedAt {
                        Text("下面是 \(Self.ago(cachedAt))的结果").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                    }
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.08)))
    }

    private var detail: String {
        switch rest.kind {
        case .resting:
            let t = rest.resumeAt.map { $0.formatted(date: .omitted, time: .shortened) } ?? "稍后"
            return "刚才问得有点多，\(t)左右自动回来。测评照常看，价格可以先去京东瞄一眼。"
        case .verify:
            return "在浏览器里打开京东随便逛两下就好，箱箱会过一阵再来试；不用重新登录。"
        }
    }

    static func ago(_ d: Date) -> String {
        let m = Int(Date().timeIntervalSince(d) / 60)
        return m < 60 ? "\(max(m, 1)) 分钟前" : (m < 24 * 60 ? "\(m / 60) 小时前" : "\(m / 1440) 天前")
    }
}

/// 心愿单顶上的一条：盯价暂停中，几点继续；价格显示的是最后一次看到的。
struct WishPausedBanner: View {
    let rest: JDRest
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "moon.zzz.fill").font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
            Text("盯价暂停中，\(rest.resumeAt.map { $0.formatted(date: .omitted, time: .shortened) } ?? "稍后")后接着盯 · 下面是最后一次看到的价格")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.65)).lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.06)))
    }
}
