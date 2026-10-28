// 搜索页（ADR 0004，线框稿 docs/design/v0.3-search.png）：
// 顶栏搜索框 → 平台筛选 → 最近搜索 / 「猫们出门帮你找了…」→ 两列封面瀑布流 → 点开进入和推荐流同一套播放卡片。
import AppKit
import SwiftUI

/// 搜索框顶栏：回车才搜，不做边打字边搜。
struct SearchHeader: View {
    let state: AppState
    @FocusState private var focused: Bool

    private var search: SearchController { state.search }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                TextField("", text: Bindable(search).query, prompt: Text("一次搜遍小红书、抖音、B 站、快手").foregroundStyle(.white.opacity(0.35)))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($focused)
                    .onSubmit { search.submit(platforms: state.searchPlatforms) }
                if !search.query.isEmpty {
                    Button { search.query = ""; focused = true } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(.white.opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(focused ? Color.pink.opacity(0.7) : .clear, lineWidth: 1))
            Button("取消") { state.closeSearch() }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .onAppear { DispatchQueue.main.async { focused = true } }
    }
}

/// 播放搜索结果时的顶栏：「< 关键词」回到瀑布流，右侧「3 / 30」。
struct SearchPlayerHeader: View {
    let state: AppState
    private var search: SearchController { state.search }

    var body: some View {
        HStack {
            Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { search.stopPlaying() } } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                    Text(search.submitted).font(.system(size: 13, weight: .medium)).lineLimit(1)
                }
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 10).frame(height: 28)
                .background(Capsule().fill(.white.opacity(0.12)))
                .contentShape(Capsule())
            }
            .buttonStyle(PressStyle())
            Spacer()
            Text("\(min(search.playIndex + 1, search.visibleHits.count)) / \(search.visibleHits.count)")
                .font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
    }
}

struct SearchView: View {
    let state: AppState
    private var search: SearchController { state.search }

    var body: some View {
        ZStack {
            Color(white: 0.04)
            if search.playing {
                FeedView(state: state, feed: search.player)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    if !search.submitted.isEmpty { chips.padding(.vertical, 10) }
                    if search.submitted.isEmpty {
                        start
                    } else if search.hits.isEmpty && search.searching {
                        ScrollView { CatsOut(state: state).padding(.horizontal, 12).padding(.top, 2) }
                    } else if search.hits.isEmpty {
                        StatusView(text: search.allUnavailable ? "猫们都在打盹" : "没找到相关内容",
                                   detail: search.allUnavailable ? "各平台刚搜得有点多，过一会儿再试试" : "换个关键词试试")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        results
                    }
                }
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.9), value: search.playing)
    }

    // MARK: - 筛选条

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(nil, label: "全部")
                ForEach(search.platforms, id: \.self) { p in
                    chip(p, label: PlatformBrand.shortName(p) + (status(p).map { " \($0)" } ?? ""))
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private func status(_ p: String) -> String? {
        guard let s = search.states[p] else { return nil }
        switch s.status {
        case .loading: return "…"
        case .ok: return "\(s.count)"
        case .resting: return "休息"
        case .auth: return "要重新登录"
        case .failed: return s.count > 0 ? "\(s.count)" : "没搜到"
        }
    }

    private func chip(_ p: String?, label: String) -> some View {
        let on = search.filter == p
        return Button { search.filter = p } label: {
            HStack(spacing: 4) {
                if let p { PlatformIcon(platform: p, size: 13) }
                Text(label).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(on ? .black : .white.opacity(0.85))
            .padding(.horizontal, 9).frame(height: 24)
            .background(Capsule().fill(on ? Color.white : .white.opacity(0.1)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 刚打开：最近搜索 + 猫们会去哪儿找

    private var start: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !search.recent.isEmpty {
                    HStack {
                        Text("最近搜索").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                        Spacer()
                        Button("清空") { search.clearRecent() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
                    }
                    FlowLayout(spacing: 8) {
                        ForEach(search.recent, id: \.self) { q in
                            Button {
                                search.useRecent(q)
                                search.submit(platforms: state.searchPlatforms)
                            } label: {
                                Text(q).font(.system(size: 12)).foregroundStyle(.white.opacity(0.85))
                                    .padding(.horizontal, 11).frame(height: 26)
                                    .background(Capsule().fill(.white.opacity(0.08)))
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Text(state.searchPlatforms.isEmpty ? "先连接一个平台，猫才能出门帮你找" : "猫们会去这些地方帮你找")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                ForEach(state.searchPlatforms, id: \.self) { p in
                    HStack(spacing: 10) {
                        if let persona = Persona.forPlatform(p) { CatSprite(skin: persona.skin, action: "idle", scale: 2.5) }
                        PlatformIcon(platform: p, size: 16)
                        Text("\(Persona.forPlatform(p)?.name ?? "") · \(PlatformBrand.shortName(p))").font(.system(size: 13))
                        Spacer()
                        if p == "kuaishou" { Text("只按关键词").font(.system(size: 10)).foregroundStyle(.white.opacity(0.35)) }
                    }
                    .padding(.horizontal, 12).frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.05)))
                }
                Text("按回车开始搜索").font(.system(size: 11)).foregroundStyle(.white.opacity(0.3))
            }
            .padding(14)
        }
    }

    // MARK: - 结果：两列瀑布流

    private var results: some View {
        let list = search.visibleHits
        let width = (NotchGeometry.expandedSize.width - 16 - 24 - 8) / 2
        let columns = Self.masonry(list, width: width)
        return ScrollView {
            VStack(spacing: 10) {
                if search.searching { CatsOut(state: state, compact: true) }
                HStack(alignment: .top, spacing: 8) {
                    ForEach(0..<2, id: \.self) { c in
                        LazyVStack(spacing: 10) {
                            ForEach(columns[c]) { hit in
                                SearchTile(hit: hit, width: width)
                                    .onTapGesture { search.play(hit) }
                            }
                        }
                        .frame(width: width)
                    }
                }
                // 滑到底才加载下一页（第一页都回来之后）
                if search.hasMore && !search.searching {
                    ProgressView().controlSize(.small).padding(.vertical, 12)
                        .onAppear { search.loadMore() }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    /// 按估算高度分到较短的一列（瀑布流）。
    static func masonry(_ hits: [SearchHit], width: CGFloat) -> [[SearchHit]] {
        var cols: [[SearchHit]] = [[], []]
        var heights: [CGFloat] = [0, 0]
        for h in hits {
            let c = heights[0] <= heights[1] ? 0 : 1
            cols[c].append(h)
            heights[c] += SearchTile.coverHeight(h, width: width) + 54
        }
        return cols
    }
}

/// 一条搜索结果：封面（左上角平台图标、视频右下角时长）+ 两行标题 + 作者与点赞。
struct SearchTile: View {
    let hit: SearchHit
    let width: CGFloat
    @State private var hovering = false

    static func coverHeight(_ h: SearchHit, width: CGFloat) -> CGFloat {
        let ratio = min(max(1 / h.aspect, 0.62), 1.34) // 横图不至于太扁，竖图不至于太长
        return (width * ratio).rounded()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RemoteImage(source: hit.cover)
                    .frame(width: width, height: Self.coverHeight(hit, width: width))
                    .clipped()
                PlatformIcon(platform: hit.platform, size: 16)
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                if let d = hit.duration, hit.kind == "video" {
                    Text(Format.clock(d))
                        .font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill(.black.opacity(0.55)))
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                } else if hit.kind == "video" {
                    Image(systemName: "play.fill").font(.system(size: 9)).foregroundStyle(.white)
                        .padding(5).background(Circle().fill(.black.opacity(0.5))).padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
            .frame(width: width, height: Self.coverHeight(hit, width: width))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.white.opacity(hovering ? 0.35 : 0), lineWidth: 1))
            Text(Format.caption(title: hit.title, text: nil).isEmpty ? "（无标题）" : Format.caption(title: hit.title, text: nil))
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.9))
                .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 4) {
                Text(hit.author?.name ?? "").lineLimit(1)
                Spacer(minLength: 4)
                if let likes = hit.stats.likes ?? hit.stats.views {
                    Image(systemName: hit.stats.likes != nil ? "heart" : "play").font(.system(size: 9))
                    Text(Format.count(likes))
                }
            }
            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
        }
        .frame(width: width)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

/// 「猫们出门帮你找了…」：每只猫去自己的平台，在找的走来走去，回来的报带回几条。
struct CatsOut: View {
    let state: AppState
    var compact = false
    private var search: SearchController { state.search }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            Text("猫们出门帮你找了…").font(.system(size: compact ? 11 : 13, weight: .medium)).foregroundStyle(.white.opacity(0.85))
            HStack(alignment: .top, spacing: 0) {
                ForEach(search.platforms, id: \.self) { p in
                    let s = search.states[p]
                    VStack(spacing: 4) {
                        if let persona = Persona.forPlatform(p) {
                            CatSprite(skin: persona.skin, action: s?.status == .loading ? "walk" : (s?.status == .resting ? "nap" : "sit"), scale: compact ? 2 : 3)
                        }
                        Text(label(s)).font(.system(size: 10)).foregroundStyle(s?.status == .ok ? Color.pink : .white.opacity(0.45))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.06)))
    }

    private func label(_ s: SearchController.PlatformState?) -> String {
        switch s?.status {
        case .loading, nil: return "在找…"
        case .ok: return "带回 \(s!.count) 条"
        case .resting: return "在打盹"
        case .auth: return "要重新登录"
        case .failed: return "没找到"
        }
    }
}

/// 手绘像素猫的一个动作（循环播放），用在搜索页这类小场合。
struct CatSprite: View {
    let skin: String
    let action: String
    var scale: CGFloat = 3

    var body: some View {
        let anim = CatAtlas.shared.cats[skin]?[action] ?? CatAtlas.shared.cats[skin]?["idle"]
        TimelineView(.animation(minimumInterval: 1.0 / 12)) { tl in
            if let a = anim, !a.frames.isEmpty {
                let i = Int(tl.date.timeIntervalSinceReferenceDate * a.fps) % a.frames.count
                Image(decorative: a.frames[i], scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .scaleEffect(x: -1, y: 1) // 美术朝左，翻成朝右
                    .frame(width: CGFloat(a.frameWidth) * scale, height: CGFloat(a.frameHeight) * scale)
            }
        }
        .frame(width: 16 * scale, height: 12 * scale)
    }
}

/// 简单的流式布局：放不下就换行（最近搜索的关键词胶囊）。
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 360
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width, x > 0 { x = 0; y += row + spacing; row = 0 }
            x += s.width + spacing
            row = max(row, s.height)
        }
        return CGSize(width: width, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += row + spacing; row = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            row = max(row, s.height)
        }
    }
}
