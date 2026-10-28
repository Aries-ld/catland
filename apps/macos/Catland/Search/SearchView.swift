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
                    // 关键词删光：回到搜索首页（结果丢掉）
                    .onChange(of: search.query) { _, q in
                        if q.trimmingCharacters(in: .whitespaces).isEmpty && !search.submitted.isEmpty { search.clearResults() }
                    }
                if !search.query.isEmpty {
                    Button { search.query = ""; search.clearResults(); focused = true } label: {
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
                    } else if let f = search.filter, search.visibleHits.isEmpty {
                        filteredEmpty(f)
                    } else {
                        results
                    }
                }
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.9), value: search.playing)
    }

    /// 筛选到某个平台、它一条都没有：说清楚是还在找、没找到、在打盹还是要重新登录，不要一直转圈。
    private func filteredEmpty(_ p: String) -> some View {
        let cat = Persona.forPlatform(p)?.name ?? "猫"
        let (title, detail): (String, String?) = switch search.states[p]?.status {
        case .loading, nil: ("\(cat)还在找…", nil)
        case .resting: ("\(cat)在打盹", "\(PlatformBrand.shortName(p))刚搜得有点多，过一会儿再试试")
        case .auth: ("\(cat)出不了门", "\(PlatformBrand.shortName(p))的登录过期了，去「连接」里重新登录")
        default: ("\(cat)在\(PlatformBrand.shortName(p))没找到", "看看别的平台，或换个关键词")
        }
        return StatusView(text: title, detail: detail).frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private var start: some View {
        ScrollView { SearchHome(state: state) }
    }

    // MARK: - 结果：两列瀑布流

    private var results: some View {
        let list = search.visibleHits
        let width = (NotchGeometry.expandedSize.width - 16 - 24 - 8) / 2
        return ScrollView {
            // 外层也要惰性：普通 VStack 里底部的「加载更多」一创建就会 onAppear，没滑到底就开始翻页
            LazyVStack(spacing: 10) {
                if search.searching { CatsOut(state: state, compact: true) }
                CoverMasonry(items: list.map(CoverItem.init), columnWidth: width) { item in
                    if let hit = list.first(where: { $0.key == item.id }) { search.play(hit) }
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

/// 搜索首页（没输入关键词时）：历史记录 + 猜你想搜 + 猫们会去哪儿找；和小红书的搜索首页一致。
struct SearchHome: View {
    let state: AppState
    private var search: SearchController { state.search }

    // MARK: - 搜索首页：历史记录 + 猜你想搜 + 猫们会去哪儿找（和小红书一致）

    var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                if !search.recent.isEmpty { history }
                suggestions
                if state.searchPlatforms.isEmpty {
                    VStack(spacing: 10) {
                        Text("先连接一个平台，猫才能出门帮你找").font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                        Button {
                            state.closeSearch()
                            state.overlay = .connections
                        } label: {
                            Text("去连接平台").font(.system(size: 13, weight: .semibold)).foregroundStyle(.black)
                                .padding(.horizontal, 18).frame(height: 32)
                                .background(Capsule().fill(.white))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(PressStyle())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                } else {
                    sectionTitle("猫们会去这些地方帮你找")
                    ForEach(state.searchPlatforms, id: \.self) { p in
                        HStack(spacing: 10) {
                            if let persona = Persona.forPlatform(p) { CatSprite(skin: persona.skin, action: "idle", scale: 2.5) }
                            PlatformIcon(platform: p, size: 16)
                            Text("\(Persona.forPlatform(p)?.name ?? "") · \(PlatformBrand.shortName(p))").font(.system(size: 13))
                            Spacer()
                        }
                        .padding(.horizontal, 12).frame(height: 46)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.05)))
                    }
                }
            }
            .padding(14)
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
    }

    /// 历史记录：点词直接搜；垃圾桶进入编辑（每个词出现 ×、可「全部删除」，点「完成」退出）；也可以右键删除单个。
    private var history: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("历史记录")
                Spacer()
                if search.editingRecent {
                    Button("全部删除") { search.clearRecent() }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                    Text("|").font(.system(size: 11)).foregroundStyle(.white.opacity(0.2))
                    Button("完成") { search.editingRecent = false }.buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(.pink)
                } else {
                    Button { search.editingRecent = true } label: {
                        Image(systemName: "trash").font(.system(size: 12)).foregroundStyle(.white.opacity(0.45))
                            .frame(width: 24, height: 24).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("编辑历史记录")
                }
            }
            FlowLayout(spacing: 8) {
                ForEach(search.recent, id: \.self) { q in
                    Button {
                        if search.editingRecent { search.removeRecent(q) } else {
                            search.useRecent(q)
                            search.submit(platforms: state.searchPlatforms)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(q).lineLimit(1)
                            if search.editingRecent { Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.5)) }
                        }
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 11).frame(height: 26)
                        .background(Capsule().fill(.white.opacity(0.08)))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .contextMenu { Button("删除") { search.removeRecent(q) } }
                }
            }
        }
    }

    /// 猜你想搜：有实时热搜只显示热搜（来自各平台、等比例混合），没有时才用本地示例词；「换一换」翻下一组。
    private var suggestions: some View {
        let words = search.currentSuggestions(season: SceneSeason.of(Date(), latitude: state.location.latitude))
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                sectionTitle("猜你想搜")
                Spacer()
                if search.canShuffleSuggestions { Button { search.suggestionRound += 1 } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 10))
                        Text("换一换").font(.system(size: 12))
                    }
                    .foregroundStyle(.white.opacity(0.45))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain) }
            }
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 12) {
                ForEach(words, id: \.self) { w in
                    Button {
                        search.query = w
                        search.submit(platforms: state.searchPlatforms)
                    } label: {
                        Text(w).font(.system(size: 13)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(state.searchPlatforms.isEmpty)
                }
            }
        }
    }

}
