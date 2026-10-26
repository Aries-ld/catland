// 刷刷页：上下翻页（当前条 ± 1 同时渲染，切换时整体滑动），评论抽屉。
import AVFoundation
import AppKit
import SwiftUI

struct FeedView: View {
    let state: AppState
    private var feed: FeedController { state.feed }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(white: 0.04)
                if feed.cards.isEmpty {
                    StatusView(text: feed.loading ? "小猫正在搬运内容…" : "暂时没有新内容", detail: feed.loading ? nil : "稍后再来，或在设置里多勾选几个信息源")
                }
                ForEach(visible, id: \.card.key) { entry in
                    CardView(state: state, card: entry.card, isCurrent: entry.offset == 0, size: geo.size)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .offset(y: CGFloat(entry.offset) * geo.size.height)
                        .zIndex(entry.offset == 0 ? 1 : 0)
                }
                if state.commentsOpen {
                    // 点评论区以外的地方收起评论（抖音式），不必非点关闭按钮。
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) { state.commentsOpen = false } }
                        .zIndex(1.5)
                }
                if state.commentsOpen, let c = feed.current {
                    CommentsSheet(state: state, card: c)
                        .frame(height: geo.size.height * 0.68)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .transition(.move(edge: .bottom))
                        .zIndex(2)
                }
            }
            .clipped()
        }
    }

    private var visible: [(card: FeedCard, offset: Int)] {
        let cards = feed.cards
        return (-1...1).compactMap { d in
            let i = feed.index + d
            return cards.indices.contains(i) ? (cards[i], d) : nil
        }
    }
}

struct CardView: View {
    let state: AppState
    let card: FeedCard
    let isCurrent: Bool
    let size: CGSize
    @State private var expandedText = false
    @State private var heartBurst = false

    private var feed: FeedController { state.feed }
    /// 画面比例接近面板时铺满（抖音式），否则完整显示并以模糊封面垫底。
    private var fill: Bool { abs(card.aspect - size.width / size.height) < 0.12 }

    var body: some View {
        ZStack {
            if !fill {
                RemoteImage(source: card.cover ?? card.images.first)
                    .frame(width: size.width, height: size.height)
                    .blur(radius: 36)
                    .overlay(Color.black.opacity(0.45))
                    .clipped()
            }
            media
            if heartBurst {
                Image(systemName: "heart.fill").font(.system(size: 90)).foregroundStyle(.red).shadow(radius: 10)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
            if isCurrent && feed.paused && card.isVideo {
                Image(systemName: "play.fill").font(.system(size: 46)).foregroundStyle(.white.opacity(0.75)).allowsHitTesting(false)
            }
            overlayInfo
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { doubleTapLike() }
        .onTapGesture { if card.isVideo && isCurrent { feed.togglePause() } }
    }

    @ViewBuilder private var media: some View {
        if card.isVideo {
            ZStack {
                RemoteImage(source: card.cover, contentMode: fill ? .fill : .fit)
                if let p = feed.players.player(for: card.key) {
                    VideoLayer(player: p, fill: fill)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        } else {
            ImageCarousel(images: card.images, index: isCurrent ? feed.carouselIndex : 0, fill: fill, size: size)
        }
    }

    private var overlayInfo: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom).allowsHitTesting(false)
            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        PlatformBadge(platform: card.platform)
                        if let name = card.author?.name { Text("@\(name)").font(.system(size: 13, weight: .semibold)).lineLimit(1) }
                    }
                    let body = Format.caption(title: card.title, text: card.text)
                    if !body.isEmpty {
                        Text(body)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.92))
                            .lineLimit(expandedText ? 12 : 2)
                            .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { expandedText.toggle() } }
                    }
                    if card.isVideo, isCurrent, let p = feed.players.player(for: card.key) { ProgressLine(player: p) }
                }
                Spacer(minLength: 0)
                actions
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
    }

    private var actions: some View {
        VStack(spacing: 16) {
            ActionButton(icon: card.liked == true ? "heart.fill" : "heart", tint: card.liked == true ? .red : .white, count: card.stats.likes) {
                Task { await feed.setInteract(card, kind: "like", on: !(card.liked ?? false)) }
            }
            ActionButton(icon: card.collected == true ? "star.fill" : "star", tint: card.collected == true ? .yellow : .white, count: card.stats.collects) {
                Task { await feed.setInteract(card, kind: "collect", on: !(card.collected ?? false)) }
            }
            ActionButton(icon: "ellipsis.bubble", tint: .white, count: card.stats.comments) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) { state.commentsOpen = true }
            }
            ActionButton(icon: state.settings.muted ? "speaker.slash" : "speaker.wave.2", tint: .white, count: nil) {
                state.setMuted(!state.settings.muted)
            }
            ActionButton(icon: "arrow.up.right.square", tint: .white, count: nil) {
                if let u = URL(string: card.url) { NSWorkspace.shared.open(u) }
            }
        }
    }

    private func doubleTapLike() {
        if card.liked != true { Task { await feed.setInteract(card, kind: "like", on: true) } }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { heartBurst = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { withAnimation(.easeOut(duration: 0.25)) { heartBurst = false } }
    }
}

struct ActionButton: View {
    let icon: String
    let tint: Color
    let count: Int?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 20, weight: .medium)).foregroundStyle(tint).shadow(color: .black.opacity(0.55), radius: 4).shadow(color: .black.opacity(0.25), radius: 1)
                if let c = count { Text(Format.count(c)).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.9)) }
            }
            .frame(width: 40)
        }
        .buttonStyle(PressStyle())
    }
}

/// 按下时轻微缩小，给点击反馈。
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.86 : 1).animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// 平台官方图标（圆角方形，按 App 图标比例裁切）。未连接时可显示为灰度。
struct PlatformIcon: View {
    let platform: String
    var size: CGFloat = 16
    var dimmed = false

    private static let images: [String: NSImage] = {
        guard let dir = Bundle.main.url(forResource: "PlatformIcons", withExtension: nil) else { return [:] }
        var out: [String: NSImage] = [:]
        for id in ["xhs", "douyin", "bilibili", "kuaishou", "x", "tiktok", "weibo", "jd", "taobao", "xianyu"] {
            if let img = NSImage(contentsOf: dir.appendingPathComponent("\(id).png")) { out[id] = img }
        }
        return out
    }()

    var body: some View {
        Group {
            if let img = Self.images[platform] {
                Image(nsImage: img).resizable().interpolation(.high)
            } else {
                PlatformBrand.swiftColor(platform)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 0.5))
        .saturation(dimmed ? 0 : 1)
        .opacity(dimmed ? 0.45 : 1)
    }
}

/// 内容来源标签：平台图标 + 名称。
struct PlatformBadge: View {
    let platform: String
    var body: some View {
        HStack(spacing: 4) {
            PlatformIcon(platform: platform, size: 14)
            Text(PlatformBrand.shortName(platform)).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.92))
        }
        .padding(.leading, 2).padding(.trailing, 6).padding(.vertical, 2)
        .background(Capsule().fill(.black.opacity(0.35)))
    }
}

struct ImageCarousel: View {
    let images: [ImageSource]
    let index: Int
    let fill: Bool
    let size: CGSize

    var body: some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: 0) {
                ForEach(Array(images.enumerated()), id: \.offset) { i, img in
                    RemoteImage(source: img, contentMode: fill ? .fill : .fit)
                        .frame(width: size.width, height: size.height)
                        .clipped()
                        .task(id: index) { if abs(i - index) <= 2 { ImageLoader.shared.prefetch(img) } }
                }
            }
            .frame(width: size.width, height: size.height, alignment: .leading)
            .offset(x: -CGFloat(index) * size.width)
            .animation(.spring(response: 0.32, dampingFraction: 0.88), value: index)
            if images.count > 1 {
                HStack(spacing: 4) {
                    ForEach(0..<min(images.count, 18), id: \.self) { i in
                        Circle().fill(i == index ? Color.white : .white.opacity(0.35)).frame(width: 5, height: 5)
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}

/// 视频进度条（每 0.25s 采样一次）。
struct ProgressLine: View {
    let player: AVPlayer
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let d = player.currentItem?.duration.seconds ?? 0
            let t = player.currentTime().seconds
            let p = d.isFinite && d > 0 ? min(1, max(0, t / d)) : 0
            GeometryReader { g in
                Capsule().fill(.white.opacity(0.25)).overlay(alignment: .leading) { Capsule().fill(.white.opacity(0.9)).frame(width: g.size.width * p) }
            }
            .frame(height: 2)
        }
        .frame(maxWidth: 260)
    }
}

/// AVPlayerLayer 包装；首帧就绪前透明，露出下面的封面（封面先行）。
struct VideoLayer: NSViewRepresentable {
    let player: AVPlayer
    let fill: Bool

    func makeNSView(context: Context) -> PlayerNSView { PlayerNSView() }

    func updateNSView(_ v: PlayerNSView, context: Context) {
        v.attach(player, gravity: fill ? .resizeAspectFill : .resizeAspect)
    }

    final class PlayerNSView: NSView {
        private let playerLayer = AVPlayerLayer()
        private var readyObs: NSKeyValueObservation?

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer = CALayer()
            playerLayer.opacity = 0
            layer?.addSublayer(playerLayer)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = bounds
            CATransaction.commit()
        }

        func attach(_ player: AVPlayer, gravity: AVLayerVideoGravity) {
            playerLayer.videoGravity = gravity
            guard playerLayer.player !== player else { return }
            playerLayer.player = player
            playerLayer.opacity = playerLayer.isReadyForDisplay ? 1 : 0
            readyObs = playerLayer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] l, _ in
                DispatchQueue.main.async {
                    guard l.isReadyForDisplay else { return }
                    let a = CABasicAnimation(keyPath: "opacity")
                    a.fromValue = 0
                    a.toValue = 1
                    a.duration = 0.18
                    self?.playerLayer.add(a, forKey: "fade")
                    self?.playerLayer.opacity = 1
                }
            }
        }
    }
}

enum Format {
    /// 标题 + 正文；正文以标题开头（小红书常见）时只保留正文。去掉 [话题] 等平台标记。
    static func caption(title: String?, text: String?) -> String {
        let t = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let x = (text ?? "").replacingOccurrences(of: "[话题]", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return x }
        if x.isEmpty || x.hasPrefix(t) { return x.isEmpty ? t : x }
        return "\(t)\n\(x)"
    }

    static func count(_ n: Int) -> String {
        if n >= 100_000_000 { return String(format: "%.1f亿", Double(n) / 1e8) }
        if n >= 10_000 { return String(format: "%.1f万", Double(n) / 1e4) }
        return "\(n)"
    }
}
