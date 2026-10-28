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
    private var lastPlatform: String?
    private var run = 0
    private var playOffset = 0
    private static let recentKey = "recentSearches"
    static let maxRun = 3

    init(sidecar: SidecarClient) {
        self.sidecar = sidecar
        recent = UserDefaults.standard.stringArray(forKey: Self.recentKey) ?? []
        player = FeedController(sidecar: sidecar)
    }

    var searching: Bool { states.values.contains { $0.status == .loading } }
    var visibleHits: [SearchHit] { filter.map { f in hits.filter { $0.platform == f } } ?? hits }
    var hasMore: Bool { states.values.contains { $0.hasMore } }
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
        lastPlatform = nil
        run = 0
        states = Dictionary(uniqueKeysWithValues: ids.map { ($0, PlatformState()) })
        remember(q)
        AppLog.info("search", ["platforms": ids, "len": q.count])
        for p in ids { Task { await fetch(p, cursor: nil, gen: gen) } }
    }

    /// 滑到底：还有下一页的平台各再取一页。
    func loadMore() {
        guard !searching else { return } // 第一页还没都回来时不翻页，免得快的平台挤占结果
        let gen = generation
        for p in platforms {
            guard var s = states[p], s.status == .ok, s.hasMore, !s.loadingMore, let c = s.cursor else { continue }
            s.loadingMore = true
            states[p] = s
            Task { await fetch(p, cursor: c, gen: gen) }
        }
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
        let list = visibleHits
        guard let start = list.firstIndex(of: hit) else { return }
        playOffset = start
        var next = start
        let sidecar = self.sidecar
        player.reset {
            // 每次解析接下来的 2 条（第一次从点开的那条开始），解析不出来的跳过
            var out: [FeedCard] = []
            while out.count < 2, next < list.count {
                let h = list[next]
                next += 1
                if let card: FeedCard = try? await sidecar.call("search.resolve", ["key": h.key]) { out.append(card) }
            }
            return out
        } refresher: { key in
            try? await sidecar.call("search.resolve", ["key": key])
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

    private func fetch(_ p: String, cursor: String?, gen: Int) async {
        var params: [String: Any] = ["platform": p, "query": submitted]
        if let cursor { params["cursor"] = cursor }
        let result: SearchResult? = try? await sidecar.call("search.query", params)
        guard gen == generation, var s = states[p] else { return } // 已经换了关键词：丢弃旧结果
        s.loadingMore = false
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
        let known = Set(hits.map(\.key))
        let fresh = r.hits.filter { !known.contains($0.key) }
        s.count += fresh.count
        s.cursor = r.cursor
        s.hasMore = r.status == "ok" && r.hasMore
        states[p] = s
        queues[p, default: []] += fresh
        drain()
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
            } else if let only = available.first, run < Self.maxRun || !waiting {
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
