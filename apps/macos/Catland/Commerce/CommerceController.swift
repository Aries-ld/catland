// 购物小助手的状态：京东搜索（经 sidecar 的京东总闸，见 ADR 0005）、同屏的测评搜索、商品页、心愿单、京东歇着时的兜底。
import AppKit
import Foundation
import Observation

/// sidecar 的商品快照（commerce.search / wish.list）。
struct ProductDTO: Codable, Hashable {
    let sku: String
    let title: String
    let price: Double?
    let shop: String?
    let cover: String?
    let url: String
    let comments: Int?
    let wished: Bool?

    var product: Product {
        Product(id: sku, title: title, price: price ?? 0, shop: shop ?? "", cover: cover.map { ImageSource(url: $0, headers: [:], width: nil, height: nil) },
                url: url, comments: comments)
    }

    init(_ p: Product) {
        sku = p.id; title = p.title; price = p.price > 0 ? p.price : nil; shop = p.shop.isEmpty ? nil : p.shop
        cover = p.cover?.url; url = p.url; comments = p.comments; wished = nil
    }
}

struct RestDTO: Codable, Hashable {
    let kind: String
    let resumeAt: Double

    var rest: JDRest { JDRest(kind: kind == "verify" ? .verify : .resting, resumeAt: Date(timeIntervalSince1970: resumeAt / 1000)) }
}

struct ProductPageDTO: Codable {
    let products: [ProductDTO]
    let cursor: String?
    let hasMore: Bool
    let rest: RestDTO?
    let cachedAt: Double?
    let auth: Bool
}

struct WishListDTO: Codable {
    struct Entry: Codable { let product: ProductDTO; let at: String; let history: [Point] }
    struct Point: Codable { let at: String; let price: Double }
    let entries: [Entry]
    let rest: RestDTO?
}

@MainActor
@Observable
final class CommerceController {
    var query = ""
    private(set) var submitted = ""
    private(set) var sort = "general"
    private(set) var products: [Product] = []
    private(set) var loading = false
    private(set) var loadingMore = false
    private(set) var cursor: String?
    private(set) var hasMore = false
    private(set) var rest: JDRest?
    private(set) var cachedAt: Date?
    private(set) var needsLogin = false
    /// 打开的商品页
    var detail: Product?
    private(set) var wishes: [WishItem] = []
    private(set) var recent: [String]
    /// 「大家怎么说」：在内容平台上搜同一个词，用和搜索页同一套播放
    let reviews: SearchController

    private let sidecar: SidecarClient
    private var generation = 0
    private static let recentKey = "commerceRecent"
    /// 测评只去这几个平台（快手的测评少、噪音多）
    static let reviewPlatforms = ["xhs", "bilibili", "douyin"]

    init(sidecar: SidecarClient) {
        self.sidecar = sidecar
        reviews = SearchController(sidecar: sidecar, recentKey: "commerceReviewSearches")
        recent = UserDefaults.standard.stringArray(forKey: Self.recentKey) ?? []
    }

    var wishedIDs: Set<String> { Set(wishes.map(\.id)) }

    func wish(for p: Product) -> WishItem? { wishes.first { $0.id == p.id } }

    /// 回车：京东搜一次 + 内容平台搜一次测评。
    func submit(contentPlatforms: [String]) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        query = q
        submitted = q
        detail = nil
        remember(q)
        reviews.query = q
        let targets = contentPlatforms.filter { Self.reviewPlatforms.contains($0) }
        if targets.isEmpty { reviews.clearResults() } else { reviews.submit(platforms: targets) }
        Task { await fetch(reset: true) }
    }

    func setSort(_ s: String) {
        guard s != sort, !submitted.isEmpty else { return }
        sort = s
        Task { await fetch(reset: true) }
    }

    func loadMore() {
        guard hasMore, !loadingMore, !loading, cursor != nil else { return }
        Task { await fetch(reset: false) }
    }

    /// 搜索框清空 / 返回首页
    func clear() {
        generation += 1
        submitted = ""
        products = []
        cursor = nil
        hasMore = false
        cachedAt = nil
        detail = nil
        sort = "general"
        reviews.stopPlaying()
        reviews.clearResults()
    }

    private func fetch(reset: Bool) async {
        generation += reset ? 1 : 0
        let gen = generation
        if reset { loading = true; products = []; cursor = nil; hasMore = false } else { loadingMore = true }
        defer { if gen == generation { loading = false; loadingMore = false } }
        var params: [String: Any] = ["query": submitted, "sort": sort]
        if !reset, let c = cursor { params["cursor"] = c }
        do {
            let page: ProductPageDTO = try await sidecar.call("commerce.search", params)
            guard gen == generation else { return }
            needsLogin = page.auth
            rest = page.rest?.rest
            cachedAt = page.cachedAt.map { Date(timeIntervalSince1970: $0 / 1000) }
            let known = Set(products.map(\.id))
            products += page.products.map(\.product).filter { !known.contains($0.id) }
            cursor = page.cursor
            hasMore = page.hasMore
        } catch {
            AppLog.warn("commerce search failed", ["err": error.localizedDescription])
        }
    }

    // MARK: - 心愿单

    func refreshWishes() async {
        guard let list: WishListDTO = try? await sidecar.call("wish.list") else { return }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        wishes = list.entries.map { e in
            WishItem(product: e.product.product, history: e.history.compactMap { h in iso.date(from: h.at).map { PricePoint(date: $0, price: h.price) } })
        }
        rest = list.rest?.rest ?? (submitted.isEmpty ? nil : rest)
    }

    /// 返回 nil 表示成功；否则是给用户看的提示。
    func toggleWish(_ p: Product) async -> String? {
        do {
            if wishedIDs.contains(p.id) {
                _ = try await sidecar.callRaw("wish.remove", ["sku": p.id])
            } else {
                let dto = ProductDTO(p)
                var product: [String: Any] = ["sku": dto.sku, "title": dto.title, "url": dto.url]
                if let v = dto.price { product["price"] = v }
                if let v = dto.shop { product["shop"] = v }
                if let v = dto.cover { product["cover"] = v }
                if let v = dto.comments { product["comments"] = v }
                _ = try await sidecar.callRaw("wish.add", ["product": product])
            }
            await refreshWishes()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - 去京东（浏览器打开，不经 catbus）

    func openInJD(_ p: Product) {
        if let u = URL(string: p.url) { NSWorkspace.shared.open(u) }
    }

    func searchInJD(_ q: String) {
        var c = URLComponents(string: "https://search.jd.com/Search")!
        c.queryItems = [URLQueryItem(name: "keyword", value: q), URLQueryItem(name: "enc", value: "utf-8")]
        if let u = c.url { NSWorkspace.shared.open(u) }
    }

    /// 京东歇完了（收到恢复或到点）：清掉兜底状态
    func noteRest(_ r: JDRest?) {
        rest = r
    }

    private func remember(_ q: String) {
        recent = Array(([q] + recent.filter { $0 != q }).prefix(10))
        UserDefaults.standard.set(recent, forKey: Self.recentKey)
    }

    func removeRecent(_ q: String) {
        recent.removeAll { $0 == q }
        UserDefaults.standard.set(recent, forKey: Self.recentKey)
    }
}
