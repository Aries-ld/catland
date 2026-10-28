// FeedController：刷刷流的状态机——卡片队列、当前位置、预加载窗口、浏览上报、播放失败重试。
import AVFoundation
import Foundation
import Observation
import os

@MainActor
@Observable
final class FeedController {
    /// 预加载窗口：当前条之后预缓冲几条视频、预取几条图片。
    static let videoAhead = 2
    static let imageAhead = 5
    /// 剩余未看卡片少于这个数就向 sidecar 要更多。
    static let refillBelow = 4

    private(set) var cards: [FeedCard] = []
    private(set) var index = 0
    private(set) var loading = false
    private(set) var empty = false
    var muted = true { didSet { players.setMuted(muted) } }
    var paused = false
    /// 当前卡片图集的页码。
    var carouselIndex = 0

    let players = PlayerPool()
    private let sidecar: SidecarClient
    private let log = Logger(subsystem: "app.catland", category: "feed")
    private var viewStartedAt = Date()
    private var fetching = false
    private var retried = Set<String>()
    /// 自定义数据源（搜索结果）：设置后从这里取卡片，而不是推荐流 feed.next。
    private var loader: (() async -> [FeedCard])?
    private var refresher: ((String) async -> FeedCard?)?
    private var exhausted = false
    /// 推荐流暂时没货时插入的猫猫卡（PauseCard.swift）。
    private(set) var pause: PauseInfo?
    private var pauseTask: Task<Void, Never>?
    private var lastAvailability: Availability?
    private var lastSources: [String] = []
    private var pauseCount = 0

    init(sidecar: SidecarClient) {
        self.sidecar = sidecar
        players.onFailure = { [weak self] key in Task { @MainActor in await self?.playbackFailed(key) } }
    }

    var current: FeedCard? { cards.indices.contains(index) ? cards[index] : nil }

    /// 换数据源（搜索结果播放用）：清空队列和播放器，之后 prime() 从 loader 取卡片。传 nil 恢复成推荐流。
    func reset(loader: (() async -> [FeedCard])?, refresher: ((String) async -> FeedCard?)?) {
        players.retain([])
        cards = []
        index = 0
        carouselIndex = 0
        pause = nil
        pauseTask?.cancel()
        paused = false
        exhausted = false
        retried = []
        self.loader = loader
        self.refresher = refresher
    }

    /// sidecar 就绪后预热首屏，用户点开刘海时通常已经有卡片了。
    func prime() async {
        guard cards.isEmpty else { return }
        await fetchMore(wait: 15_000)
        preload()
        // 首屏只等到第一张；稍后再补一批，保证预加载窗口里有后续卡片。
        try? await Task.sleep(for: .milliseconds(1500))
        await fetchMore(wait: 3_000)
        preload()
    }

    func sourcesChanged() async {
        // 只丢弃还没看的卡片，当前这条继续播放。
        if cards.count > index + 1 { cards.removeSubrange((index + 1)...) }
        await fetchMore(wait: 3_000)
        preload()
    }

    func next() {
        // 停在猫猫卡上：新内容到了才能往下划
        if current?.isPause == true, pause?.arrived != true { return }
        guard index + 1 < cards.count else {
            Task {
                await fetchMore(wait: 1_500)
                if index + 1 < cards.count { next() } else if loader == nil { enterPause() }
            }
            return
        }
        reportView()
        index += 1
        afterMove()
    }

    func previous() {
        guard index > 0 else { return }
        reportView()
        index -= 1
        afterMove()
    }

    func carousel(_ dir: Int) {
        guard let c = current, c.images.count > 1 else { return }
        carouselIndex = min(max(carouselIndex + dir, 0), c.images.count - 1)
    }

    private func afterMove() {
        // 划过了猫猫卡（只有就绪后才划得过去）：把它从队列里拿掉，往上滑也回不到它
        if let pi = cards.firstIndex(where: \.isPause), pi < index {
            cards.remove(at: pi)
            index -= 1
            pause = nil
            pauseTask?.cancel()
        }
        viewStartedAt = Date()
        paused = false
        carouselIndex = 0
        preload()
        if cards.count - index - 1 < Self.refillBelow { Task { await fetchMore(wait: 0) } }
    }

    func togglePause() {
        paused.toggle()
        if let c = current { paused ? players.pause(c.key) : players.play(c.key) }
    }

    func pauseAll() {
        paused = true
        players.pauseAll()
    }

    /// 面板展开时恢复当前条。
    func resume() {
        guard let c = current else { return }
        paused = false
        players.activate(c.key)
    }

    func setInteract(_ card: FeedCard, kind: String, on: Bool) async {
        guard !card.isPause else { return }
        AppLog.info("interact", ["key": card.key, "kind": kind, "on": on, "video": card.isVideo])
        guard let i = cards.firstIndex(where: { $0.key == card.key }) else { return }
        if kind == "like" { cards[i].liked = on } else { cards[i].collected = on }
        do {
            let s: InteractState = try await sidecar.call("interact.set", ["key": card.key, "kind": kind, "on": on])
            cards[i].liked = s.liked
            cards[i].collected = s.collected
        } catch {
            if kind == "like" { cards[i].liked = !on } else { cards[i].collected = !on }
        }
    }

    // MARK: - 内部

    private func fetchMore(wait: Int) async {
        guard !fetching else { return }
        if loader == nil, let p = pause, !p.arrived { return } // 猫猫卡在等：由它自己去取，别抢它的卡
        fetching = true
        loading = cards.count <= index + 1
        defer { fetching = false; loading = false }
        if let loader {
            guard !exhausted else { return }
            let got = await loader()
            exhausted = got.isEmpty
            let known = Set(cards.map(\.key))
            cards.append(contentsOf: got.filter { !known.contains($0.key) })
            empty = cards.isEmpty
            return
        }
        do {
            let t0 = Date()
            let r: FeedNext = try await sidecar.call("feed.next", ["count": 6, "waitMs": wait])
            lastAvailability = r.availability
            lastSources = r.sources
            let known = Set(cards.map(\.key))
            cards.append(contentsOf: r.cards.filter { !known.contains($0.key) })
            AppLog.info("feed.next", ["got": r.cards.count, "total": cards.count, "index": index, "ms": Int(Date().timeIntervalSince(t0) * 1000), "kinds": r.cards.map { "\($0.platform):\($0.kind):\($0.cover != nil)" }])
            empty = cards.isEmpty && r.sources.isEmpty
            trimHistory()
        } catch {
            log.error("feed.next failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 没货了：在队尾插一张猫猫卡并停在上面，后台继续等新内容（按限速规则，不额外加请求）。
    private func enterPause() {
        guard current?.isPause != true, !cards.contains(where: \.isPause) else { return }
        let cats = lastSources.compactMap(Persona.forPlatform)
        pauseCount += 1
        pause = PauseInfo(mode: lastAvailability?.state == "resting" ? .resting : .waiting,
                          resumeAt: lastAvailability?.resumeAt.map { Date(timeIntervalSince1970: $0 / 1000) },
                          batch: Self.releaseBatch,
                          speaker: cats.isEmpty ? .box : cats[pauseCount % cats.count], cats: cats.isEmpty ? [.box] : cats,
                          single: lastSources.count == 1, line: pauseCount)
        AppLog.info("feed pause", ["mode": lastAvailability?.state ?? "waiting", "sources": lastSources])
        reportView()
        cards.append(.pause())
        index = cards.count - 1
        viewStartedAt = Date()
        players.pauseAll()
        pauseTask?.cancel()
        pauseTask = Task { [weak self] in await self?.waitForContent() }
    }

    /// 调试：立刻插一张猫猫卡（catland-debug feed:pause），验证新内容到了会提示往下滑。
    func debugPause() {
        lastAvailability = Availability(state: "waiting", resumeAt: nil)
        enterPause()
    }

    /// 猫猫卡后面已经排着的卡片数。
    private var queuedAfterPause: Int {
        guard let pi = cards.firstIndex(where: \.isPause) else { return 0 }
        return cards.count - 1 - pi
    }

    /// 一次放行至少攒几张：只等到 1 张就放行的话，看完这张马上又是猫猫卡，一触发就停不下来。
    static let releaseBatch = 3
    static let releaseAfter: TimeInterval = 20

    /// 停在猫猫卡上时：一直等新内容（sidecar 那边按平台预算排队），攒够一批（或等了 20 秒）再提示往下滑。
    private func waitForContent() async {
        let started = Date()
        var got = queuedAfterPause
        pause?.progress = min(got, Self.releaseBatch)
        while !Task.isCancelled, pause != nil, pause?.arrived == false {
            if got >= Self.releaseBatch { break }
            guard let r: FeedNext = try? await sidecar.call("feed.next", ["count": Self.releaseBatch - got, "waitMs": 12_000]) else {
                try? await Task.sleep(for: .seconds(5)); continue
            }
            if !r.cards.isEmpty {
                let known = Set(cards.map(\.key))
                cards.append(contentsOf: r.cards.filter { !known.contains($0.key) })
                preload()
            }
            // 进度 = 猫猫卡后面已经排着几张（不管卡是从哪条路径进来的）
            got = queuedAfterPause
            pause?.progress = min(got, Self.releaseBatch)
            if got >= Self.releaseBatch || (got > 0 && Date().timeIntervalSince(started) >= Self.releaseAfter) { break }
            if !r.cards.isEmpty { continue }
            if let a = r.availability {
                pause?.mode = a.state == "resting" ? .resting : .waiting
                pause?.resumeAt = a.resumeAt.map { Date(timeIntervalSince1970: $0 / 1000) }
            }
            if pause?.mode == .resting { try? await Task.sleep(for: .seconds(10)) }
        }
        if pause != nil, queuedAfterPause > 0 {
            pause?.progress = min(queuedAfterPause, Self.releaseBatch)
            pause?.arrived = true // 不自动跳走：停在这张卡上提示「往下滑」，收起再打开也一样
            AppLog.info("feed pause: content arrived", ["got": queuedAfterPause, "waitedS": Int(Date().timeIntervalSince(started))])
        }
    }

    /// 只保留当前位置前 20 条，避免长时间刷导致内存增长。
    private func trimHistory() {
        let drop = index - 20
        guard drop > 0 else { return }
        cards.removeFirst(drop)
        index -= drop
    }

    /// 预加载：当前条播放，后 2 条预缓冲；上 1 条保留，其余释放；后 5 条的封面和图集前 3 张预取。
    private func preload() {
        guard let cur = current else { return }
        let keep = max(0, index - 1)...min(cards.count - 1, index + Self.videoAhead)
        let window = cards[keep].filter(\.isVideo)
        players.retain(Set(window.map(\.key)))
        for c in window { players.prepare(c) }
        if !paused { players.activate(cur.key) }
        let upcoming = cards[index..<min(cards.count, index + 1 + Self.imageAhead)]
        for c in upcoming {
            if let cover = c.cover { ImageLoader.shared.prefetch(cover) }
            c.images.prefix(3).forEach { ImageLoader.shared.prefetch($0) }
        }
    }

    private func reportView() {
        guard let c = current, !c.isPause else { return }
        let dwell = Int(Date().timeIntervalSince(viewStartedAt) * 1000)
        Task { _ = try? await sidecar.callRaw("feed.view", ["key": c.key, "dwellMs": dwell]) }
    }

    /// 播放失败（地址过期 / 403）：换新地址重试一次，仍失败就跳过。
    private func playbackFailed(_ key: String) async {
        guard let i = cards.firstIndex(where: { $0.key == key }) else { return }
        log.error("playback failed \(key, privacy: .public)")
        let fresh: FeedCard? = retried.contains(key) ? nil
            : (refresher != nil ? await refresher!(key) : try? await sidecar.call("feed.refresh", ["key": key]))
        if let fresh {
            retried.insert(key)
            var card = fresh
            card.liked = cards[i].liked
            card.collected = cards[i].collected
            cards[i] = card
            players.reset(key)
            preload()
        } else if i == index {
            next()
        }
    }
}
