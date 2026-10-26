// PlayerPool：按卡片 key 管理 AVPlayer。窗口外的播放器释放；窗口内的提前创建并预缓冲，切换时零等待。
import AVFoundation
import Foundation
import os

@MainActor
final class PlayerPool {
    private struct Entry {
        let player: AVPlayer
        var observers: [NSObjectProtocol]
        var status: NSKeyValueObservation?
    }

    private var entries: [String: Entry] = [:]
    private var activeKey: String?
    private var muted = true
    var onFailure: ((String) -> Void)?
    private let log = Logger(subsystem: "app.catland", category: "player")

    func player(for key: String) -> AVPlayer? { entries[key]?.player }

    func prepare(_ card: FeedCard) {
        guard entries[card.key] == nil, let v = card.video, let url = URL(string: v.url) else { return }
        // 媒体 CDN 的防盗链头由 sidecar 按平台给出；不经过本地代理。
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": v.headers])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 4
        let player = AVPlayer(playerItem: item)
        player.isMuted = muted
        player.automaticallyWaitsToMinimizeStalling = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        let key = card.key
        // 抖音式循环播放。
        let end = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }
        let created = Date()
        let status = item.observe(\.status) { [weak self] item, _ in
            switch item.status {
            case .readyToPlay:
                AppLog.info("player ready", ["key": key, "ms": Int(Date().timeIntervalSince(created) * 1000)])
            case .failed:
                AppLog.error("player failed", ["key": key, "err": item.error?.localizedDescription ?? "", "url": String(v.url.prefix(100))])
                Task { @MainActor in self?.onFailure?(key) }
            default: break
            }
        }
        AppLog.debug("player prepare", ["key": key, "headers": Array(v.headers.keys)])
        // 预缓冲：item 绑定到 player 后，暂停状态下也会按 preferredForwardBufferDuration 加载。
        // 不调用 preroll：status 未就绪时调用会抛异常。
        entries[key] = Entry(player: player, observers: [end], status: status)
    }

    func activate(_ key: String) {
        for (k, e) in entries where k != key { e.player.pause() }
        activeKey = key
        entries[key]?.player.play()
    }

    func play(_ key: String) { entries[key]?.player.play() }
    func pause(_ key: String) { entries[key]?.player.pause() }

    func pauseAll() {
        entries.values.forEach { $0.player.pause() }
    }

    func setMuted(_ m: Bool) {
        muted = m
        entries.values.forEach { $0.player.isMuted = m }
    }

    /// 只保留窗口内的播放器。
    func retain(_ keys: Set<String>) {
        for k in entries.keys where !keys.contains(k) { reset(k) }
    }

    func reset(_ key: String) {
        guard let e = entries.removeValue(forKey: key) else { return }
        e.player.pause()
        e.player.replaceCurrentItem(with: nil)
        e.observers.forEach(NotificationCenter.default.removeObserver)
        e.status?.invalidate()
    }
}
