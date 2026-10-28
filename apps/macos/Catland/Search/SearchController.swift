// SearchController：跨平台搜索（ADR 0004）。对每个已连接平台分别请求，谁先回来谁先显示；
// 结果按平台轮流混排（append 式：已经显示的不重排）；点开结果后交给 searchFeed，用和推荐流同一套卡片播放。
import Foundation
import Observation

@MainActor
@Observable
final class SearchController {
    enum Status: Equatable { case loading, ok, resting, auth, failed }

    struct PlatformState: Equatable {
        var status: Status = .loading
        var count = 0
        var cursor: String?
        var hasMore = false
        var loadingMore = false
    }

    /// 搜索页是否打开（顶栏变成搜索框，推荐流暂停）。
    var active = false
    var query = ""
    private(set) var submitted = ""
    /// 平台筛选：nil = 全部。
    var filter: String?
    private(set) var platforms: [String] = []
    private(set) var states: [String: PlatformState] = [:]
    private(set) var hits: [SearchHit] = []
    private(set) var recent: [String]
    /// 正在播放搜索结果（和推荐流同一套卡片）。
    private(set) var playing = false
    /// 点开时在当前筛选结果里的位置，供顶栏显示「3 / 30」。
    var playIndex: Int { player.index + playOffset }

    let player: FeedController
    private let sidecar: SidecarClient
    private var generation = 0
    /// 各平台已返回、还没并入 hits 的结果（按平台排队，轮流取出）。
    private var queues: [String: [SearchHit]] = [:]
    /// 后台按游标预取好的下一页（还没显示）：滑到底时直接放进来，不用等。
    private var reserve: [String: [SearchHit]] = [:]
    /// 正在预取下一页的平台；waiting 里的平台预取一回来就直接显示（用户已经滑到底了）。
    private var prefetching: Set<String> = []
    private var wantMore: Set<String> = []
    private var lastPlatform: String?
    private var run = 0
    private var playOffset = 0
    private static let recentKey = "recentSearches"
    static let maxRun = 3
    /// 第一屏（两列各两张）：先回来的平台可以先把它铺满，让结果「一下子就出来」。
    static let firstScreen = 4

    init(sidecar: SidecarClient) {
        self.sidecar = sidecar
        recent = UserDefaults.standard.stringArray(forKey: Self.recentKey) ?? []
        player = FeedController(sidecar: sidecar)
    }

    var searching: Bool { states.values.contains { $0.status == .loading } }
    var visibleHits: [SearchHit] { filter.map { f in hits.filter { $0.platform == f } } ?? hits }
    /// 当前筛选下还有没有下一页（含已预取、还没显示的）。
    var hasMore: Bool {
        let ps = filter.map { [$0] } ?? platforms
        return ps.contains { states[$0]?.hasMore == true || !(reserve[$0]?.isEmpty ?? true) || !(queues[$0]?.isEmpty ?? true) }
    }
    var allUnavailable: Bool { !states.isEmpty && states.values.allSatisfy { $0.status == .resting || $0.status == .auth || $0.status == .failed } }

    func open() {
        active = true
    }

    func close() {
        stopPlaying()
        active = false
    }

    /// 回车：对每个已连接平台各发一次搜索（只取第一页）。
    func submit(platforms ids: [String]) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !ids.isEmpty else { return }
        generation += 1
        let gen = generation
        submitted = q
        query = q
        platforms = ids
        filter = filter.flatMap { ids.contains($0) ? $0 : nil }
        hits = []
        queues = [:]
        reserve = [:]
        prefetching = []
        wantMore = []
        lastPlatform = nil
        run = 0
        states = Dictionary(uniqueKeysWithValues: ids.map { ($0, PlatformState()) })
        remember(q)
        AppLog.info("search", ["platforms": ids, "len": q.count])
        for p in ids { Task { await fetch(p, cursor: nil, gen: gen) } }
    }

    /// 滑到底：把后台预取好的下一页直接放进来，并接着预取再下一页；还没预取到的，等它回来就直接显示。
    func loadMore() {
        guard !searching else { return } // 第一页还没都回来时不翻页，免得快的平台挤占结果
        for p in filter.map({ [$0] }) ?? platforms {
            if let r = reserve[p], !r.isEmpty {
                queues[p, default: []] += r
                reserve[p] = []
            } else if prefetching.contains(p) {
                wantMore.insert(p)
            }
            prefetch(p)
        }
        drain()
    }

    /// 后台按游标取下一页，先放在 reserve 里不显示。
    private func prefetch(_ p: String) {
        guard let s = states[p], s.status == .ok, s.hasMore, let c = s.cursor, !prefetching.contains(p), reserve[p]?.isEmpty ?? true else { return }
        prefetching.insert(p)
        let gen = generation
        Task { await fetch(p, cursor: c, gen: gen, intoReserve: true) }
    }

    func useRecent(_ q: String) {
        query = q
    }

    func clearRecent() {
        recent = []
        UserDefaults.standard.removeObject(forKey: Self.recentKey)
    }

    /// 点开一条结果：从它开始，在当前筛选结果里上下划着看。
    func play(_ hit: SearchHit) {
        guard let start = visibleHits.firstIndex(of: hit) else { return }
        playOffset = start
        var next = start
        let sidecar = self.sidecar
        player.reset { [weak self] in
            // 每次解析接下来的 2 条（第一次从点开的那条开始），解析不出来的跳过；
            // 刷到结果末尾时加载下一页，在搜索词下一直刷下去
            var out: [FeedCard] = []
            while out.count < 2 {
                guard let self else { break }
                if next >= self.visibleHits.count {
                    guard self.hasMore else { break }
                    self.loadMore()
                    for _ in 0..<30 where next >= self.visibleHits.count { try? await Task.sleep(for: .milliseconds(200)) }
                    if next >= self.visibleHits.count { break }
                }
                let h = self.visibleHits[next]
                next += 1
                if let card: FeedCard = try? await sidecar.call("search.resolve", ["key": h.key]) { out.append(card) }
            }
            return out
        } refresher: { key in
            try? await sidecar.call("search.resolve", ["key": key, "fresh": true])
        }
        playing = true
        Task { await player.prime() }
    }

    func stopPlaying() {
        guard playing else { return }
        player.pauseAll()
        player.reset(loader: nil, refresher: nil)
        playing = false
    }

    // MARK: - 内部

    private func fetch(_ p: String, cursor: String?, gen: Int, intoReserve: Bool = false) async {
        var params: [String: Any] = ["platform": p, "query": submitted]
        if let cursor { params["cursor"] = cursor }
        let result: SearchResult? = try? await sidecar.call("search.query", params)
        guard gen == generation, var s = states[p] else { return } // 已经换了关键词：丢弃旧结果
        s.loadingMore = false
        if intoReserve { prefetching.remove(p) }
        guard let r = result else {
            if s.count == 0 { s.status = .failed }
            states[p] = s
            return
        }
        switch r.status {
        case "ok": s.status = .ok
        case "resting": s.status = .resting
        case "auth": s.status = .auth
        default: s.status = .failed
        }
        let known = Set(hits.map(\.key)).union((queues[p] ?? []).map(\.key)).union((reserve[p] ?? []).map(\.key))
        let fresh = r.hits.filter { !known.contains($0.key) }
        s.count += fresh.count
        s.cursor = r.cursor
        s.hasMore = r.status == "ok" && r.hasMore
        states[p] = s
        if intoReserve && !wantMore.contains(p) {
            reserve[p, default: []] += fresh
        } else {
            wantMore.remove(p)
            queues[p, default: []] += fresh
        }
        drain()
        // 第一页都回来后，各平台在后台预取下一页，滑到底时直接显示
        if !searching { for q in platforms { prefetch(q) } }
        AppLog.info("search.result", ["platform": p, "status": r.status, "got": fresh.count, "page": cursor == nil ? "first" : "more"])
    }

    /// 把各平台排队的结果轮流并入 hits：同一平台最多连着 maxRun 条（只剩它有货时例外）。只追加，不重排已显示的结果。
    private func drain() {
        while true {
            let available = platforms.filter { !(queues[$0]?.isEmpty ?? true) }
            guard !available.isEmpty else { return }
            // 还有平台在搜第一页时先别把一个平台的结果全倒出来，留位置给它
            let waiting = platforms.contains { states[$0]?.status == .loading }
            let others = available.filter { $0 != lastPlatform }
            let pick: String
            if let o = others.min(by: { (queues[$0]?.count ?? 0) > (queues[$1]?.count ?? 0) }) {
                pick = o
            } else if let only = available.first, run < (hits.count < Self.firstScreen ? Self.firstScreen : Self.maxRun) || !waiting {
                pick = only
            } else {
                return
            }
            hits.append(queues[pick]!.removeFirst())
            run = pick == lastPlatform ? run + 1 : 1
            lastPlatform = pick
        }
    }

    private func remember(_ q: String) {
        recent = [q] + recent.filter { $0 != q }
        recent = Array(recent.prefix(10))
        UserDefaults.standard.set(recent, forKey: Self.recentKey)
    }
}
