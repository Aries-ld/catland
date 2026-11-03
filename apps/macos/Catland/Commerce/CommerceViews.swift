// 电商板块（购物小助手，先只接京东）：搜索 → 京东商品 + 大家怎么说（小红书 / B 站 / 抖音的测评）→ 商品页 → 去京东买；
// 心愿单盯价、订单状态。界面组件在这里，数据接入见 docs/decisions（待写 ADR 0005）。
import AppKit
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

/// 心愿单里的一件：价格历史只存在本机。
struct WishItem: Identifiable, Hashable {
    let product: Product
    /// 最近的价格（旧 → 新）
    let history: [Double]
    var id: String { product.id }
    var current: Double { history.last ?? product.price }
    var lowest: Double { history.min() ?? current }
    /// 和加入时比：负数是降价
    var change: Double { current - (history.first ?? current) }
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
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
            Text(query.isEmpty ? "想买点什么？京东价格 + 大家的真实测评" : query)
                .font(.system(size: 13)).foregroundStyle(.white.opacity(query.isEmpty ? 0.4 : 0.92))
            Spacer()
            PlatformIcon(platform: "jd", size: 16)
        }
        .padding(.horizontal, 12).frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.08)))
    }
}

// MARK: - 首页：心愿单 + 订单

struct CommerceHome: View {
    let wishes: [WishItem]
    let orders: [OrderStatus]
    let recent: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CommerceSearchBar(query: "")
            if !recent.isEmpty {
                HStack(spacing: 6) {
                    ForEach(recent, id: \.self) { Chip(text: $0) }
                }
            }
            ForEach(orders) { OrderCard(order: $0) }
            SectionTitle(title: "心愿单", detail: "每小时帮你看一眼价格")
            VStack(spacing: 8) { ForEach(wishes) { WishRow(item: $0) } }
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
    var body: some View {
        Text(text).font(.system(size: 11, weight: active ? .semibold : .regular))
            .foregroundStyle(active ? .black : .white.opacity(0.75))
            .padding(.horizontal, 10).frame(height: 24)
            .background(Capsule().fill(active ? Color.white : .white.opacity(0.08)))
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
                    if item.current <= item.lowest && item.history.count > 3 {
                        Text("近期最低").font(.system(size: 10, weight: .medium)).foregroundStyle(dropGreen)
                    }
                }
            }
            Spacer(minLength: 4)
            Sparkline(values: item.history).frame(width: 64, height: 26)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.05)))
    }
}

/// 价格小曲线：最后一个点标出来，降价绿、涨价红。
struct Sparkline: View {
    let values: [Double]
    var body: some View {
        GeometryReader { g in
            let lo = values.min() ?? 0, hi = values.max() ?? 1, span = max(hi - lo, 1)
            let pts = values.enumerated().map { i, v in
                CGPoint(x: g.size.width * CGFloat(i) / CGFloat(max(values.count - 1, 1)), y: g.size.height * (1 - CGFloat((v - lo) / span)) * 0.8 + g.size.height * 0.1)
            }
            let color = (values.last ?? 0) < (values.first ?? 0) ? dropGreen : priceRed
            Path { p in
                guard let f = pts.first else { return }
                p.move(to: f)
                for q in pts.dropFirst() { p.addLine(to: q) }
            }
            .stroke(color.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            if let last = pts.last { Circle().fill(color).frame(width: 5, height: 5).position(last) }
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CommerceSearchBar(query: query)
            SectionTitle(title: "大家怎么说", detail: "小红书 · B 站 · 抖音的真实测评")
            ReviewStrip(reviews: Array(reviews.prefix(6)), scrollable: scrollable)
            HStack(spacing: 6) {
                SectionTitle(title: "京东")
                Spacer()
                ForEach(["综合", "销量", "价格", "评价"], id: \.self) { Chip(text: $0, active: $0 == "综合") }
            }
            VStack(spacing: 8) { ForEach(products) { ProductRow(product: $0, wished: wished.contains($0.id)) } }
        }
    }
}

/// 一排测评小卡，横向滑动。
struct ReviewStrip: View {
    let reviews: [CoverItem]
    var scrollable = true
    var body: some View {
        let row = HStack(spacing: 8) { ForEach(reviews) { ReviewTile(item: $0) } }
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
                    Text(PriceFormat.yuan(product.price)).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(priceRed)
                    if let c = PriceFormat.comments(product.comments) { Text(c).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)) }
                    Spacer()
                    Image(systemName: wished ? "heart.fill" : "heart").font(.system(size: 14))
                        .foregroundStyle(wished ? Color.pink : .white.opacity(0.6))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .topLeading) {
                RemoteImage(source: product.cover, contentMode: .fit).frame(maxWidth: .infinity).frame(height: 220).clipped().background(Color.white)
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
                    Text("结果").font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.white).padding(.horizontal, 9).frame(height: 24).background(Capsule().fill(.black.opacity(0.55))).padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(PriceFormat.yuan(product.price)).font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(priceRed)
                    if let w = wish, w.change < 0 { Text("比加入时降了 \(PriceFormat.yuan(-w.change))").font(.system(size: 11, weight: .medium)).foregroundStyle(dropGreen) }
                    Spacer()
                    if let c = PriceFormat.comments(product.comments) { Text(c).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)) }
                }
                Text(product.title).font(.system(size: 13)).foregroundStyle(.white.opacity(0.92)).lineLimit(3)
                Text(product.shop).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            }
            if let w = wish {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("价格走势").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        Text("最低 \(PriceFormat.yuan(w.lowest))").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                    }
                    Sparkline(values: w.history).frame(height: 40)
                }
                .padding(10).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.05)))
            }
            SectionTitle(title: "大家怎么说")
            ReviewStrip(reviews: Array(reviews.prefix(6)), scrollable: scrollable)
            HStack(spacing: 10) {
                Label(wish == nil ? "加入心愿单" : "已在心愿单", systemImage: wish == nil ? "heart" : "heart.fill")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 38)
                    .background(Capsule().fill(.white.opacity(0.1)))
                HStack(spacing: 6) {
                    PlatformIcon(platform: "jd", size: 16)
                    Text("去京东买").font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 38)
                .background(Capsule().fill(priceRed))
            }
        }
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
