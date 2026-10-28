// 展开面板：顶部板块切换（视频 / 电商）+ 右上角入口（搜索、收藏、连接、设置），下面是当前板块内容与浮层。
// 打开搜索后顶栏变成搜索框、内容区变成搜索页（ADR 0004）。
import SwiftUI

struct ExpandedPanel: View {
    let state: AppState
    /// 搜索功能的一次性提示气泡（升级后第一次展开时出现）。
    @AppStorage("searchTipShown") private var searchTipShown = false
    @State private var showSearchTip = false
    /// 再点一下「视频」标签：弹出刷哪些平台的开关。
    @State private var showSources = false

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if state.search.active {
                    if state.search.playing { SearchPlayerHeader(state: state) } else { SearchHeader(state: state) }
                } else {
                    header
                }
            }
            .overlay(alignment: .topLeading) {
                if showSources && !state.search.active && state.overlay == .none {
                    SourcePicker(state: state) { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { showSources = false } }
                        .offset(x: 12, y: 44)
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .topLeading)))
                }
            }
            .overlay(alignment: .topTrailing) {
                if showSearchTip && !state.search.active {
                    Text("新：一次搜遍四个平台")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.black)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(Capsule().fill(.white))
                        .offset(x: -96, y: 38)
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
                        .allowsHitTesting(false)
                }
            }
            .zIndex(1)
            ZStack {
                if state.search.active {
                    SearchView(state: state).transition(.opacity)
                } else {
                    content
                }
                // 平台开关弹层打开时：点内容区任意位置关掉它
                if showSources {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { showSources = false } }
                        .zIndex(5)
                }
                switch state.overlay {
                case .none: EmptyView()
                case .connections: ConnectionsView(state: state).transition(.move(edge: .bottom).combined(with: .opacity))
                case .settings: SettingsView(state: state).transition(.move(edge: .bottom).combined(with: .opacity))
                case .saved: SavedView(state: state).transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding([.horizontal, .bottom], 8)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.88), value: state.overlay)
        .animation(.spring(response: 0.3, dampingFraction: 0.9), value: state.search.active)
        // 新手引导：开刷且有内容时开始讲；高亮的目标位置由 coachAnchor 标出
        .overlayPreferenceValue(CoachAnchorKey.self) { anchors in
            if state.onboarding.step != nil && state.overlay == .none && !state.search.active {
                CoachMarksOverlay(state: state, anchors: anchors)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: state.onboarding.step)
        .onAppear(perform: startOnboarding)
        .onChange(of: state.feed.cards.count) { _, _ in startOnboarding() }
        .onChange(of: state.feed.index) { _, _ in state.onboarding.advance(from: 0) }
        .onAppear {
            guard !searchTipShown, !state.searchPlatforms.isEmpty, state.onboarding.done else { return }
            searchTipShown = true
            withAnimation { showSearchTip = true }
            Task { try? await Task.sleep(for: .seconds(6)); withAnimation { showSearchTip = false } }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ForEach(AppState.Section.allCases, id: \.self) { s in
                Button {
                    if s == .commerce { return state.showToast("电商板块下个版本上线") }
                    // 已经在「视频」上再点一下：弹出 / 收起平台开关
                    if state.section == s && state.overlay == .none && s == .content {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { showSources.toggle() }
                        return
                    }
                    state.section = s
                    state.overlay = .none
                } label: {
                    VStack(spacing: 4) {
                        HStack(spacing: 2) {
                            Text(s.rawValue)
                                .font(.system(size: 14, weight: state.section == s ? .semibold : .regular))
                                .foregroundStyle(s == .commerce ? .white.opacity(0.3) : (state.section == s ? .white : .white.opacity(0.55)))
                            if s == .content && state.section == s {
                                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.5))
                                    .rotationEffect(.degrees(showSources ? 180 : 0))
                            }
                        }
                        Capsule().fill(state.section == s ? Color.white : .clear).frame(width: 14, height: 2)
                    }
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            iconButton("magnifyingglass", active: false) {
                showSearchTip = false
                state.openSearch()
            }
            .help("一次搜遍几个平台（⌘F）")
            .coachAnchor(.search)
            iconButton("heart.text.square", active: state.overlay == .saved) { toggleOverlay(.saved) }
            // 连接平台：和收藏、设置一样的图标按钮，不抢视觉；悬停显示已连接几个
            iconButton("person.crop.circle.badge.plus", active: state.overlay == .connections) { toggleOverlay(.connections) }
                .help("连接平台（已连接 \(state.connectedContentPlatforms.count) 个）")
            iconButton("slider.horizontal.3", active: state.overlay == .settings) { toggleOverlay(.settings) }
        }
        .padding(.horizontal, 18)
        .frame(height: 40)
    }

    private func startOnboarding() {
        guard !state.feed.cards.isEmpty, state.overlay == .none, !state.search.active, !state.connectedContentPlatforms.isEmpty else { return }
        state.onboarding.startIfNeeded()
    }

    private func toggleOverlay(_ o: AppState.Overlay) {
        state.stopSaved()
        state.overlay = state.overlay == o ? .none : o
        state.overlay == .none ? state.feed.resume() : state.feed.pauseAll()
    }

    private func iconButton(_ name: String, active: Bool, badge: Int = 0, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(active ? .white : .white.opacity(0.6))
                .frame(width: 28, height: 28)
                .background(Circle().fill(.white.opacity(active ? 0.16 : 0)))
                .contentShape(Circle())
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Text("\(badge)").font(.system(size: 8, weight: .bold)).padding(2).background(Circle().fill(.green)).offset(x: 3, y: -3)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var content: some View {
        switch state.phase {
        case .starting:
            StatusView(text: "小猫正在发动巴士…")
        case .failed(let msg):
            StatusView(text: "本地服务启动失败", detail: msg)
        case .ready:
            if state.connectedContentPlatforms.isEmpty && !state.platforms.isEmpty {
                if state.onboarding.done {
                    StatusView(text: "还没有连接任何平台", detail: "连接小红书、B 站、快手等账号后就能开刷", action: ("连接平台", { state.overlay = .connections }))
                } else {
                    OnboardingWelcome(state: state)
                }
            } else {
                FeedView(state: state, feed: state.feed).coachAnchor(.card)
            }
        }
    }
}

struct StatusView: View {
    let text: String
    var detail: String? = nil
    var action: (String, () -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            CatStage(cast: [.box], id: "status", pixel: 1).frame(width: 140, height: 44)
            Text(text).font(.system(size: 14, weight: .semibold))
            if let d = detail { Text(d).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 30) }
            if let a = action {
                Button(action: a.1) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 14, weight: .semibold))
                        Text(a.0).font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 26).frame(height: 38)
                    .background(Capsule().fill(LinearGradient(colors: [Color(red: 1, green: 0.48, blue: 0.35), Color(red: 1, green: 0.3, blue: 0.55)],
                                                              startPoint: .leading, endPoint: .trailing)))
                    .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 0.5))
                    .shadow(color: Color(red: 1, green: 0.35, blue: 0.45).opacity(0.45), radius: 10, y: 4)
                    .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.07))
    }
}

/// 刷哪些平台：一排平台小猫，点一下开关（和「连接」页的「刷它」开关是同一份设置，任意一处改都行）。
struct SourcePicker: View {
    let state: AppState
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("刷哪些平台").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                Spacer()
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.4)) }
                    .buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                ForEach(state.connectedContentPlatforms) { p in
                    let on = state.isSourceEnabled(p.id)
                    Button { withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) { state.toggleSource(p.id) } } label: {
                        VStack(spacing: 4) {
                            if let persona = Persona.forPlatform(p.id) {
                                CatSprite(skin: persona.skin, action: on ? "idle" : "nap", scale: 2.5)
                            }
                            HStack(spacing: 3) {
                                PlatformIcon(platform: p.id, size: 12, dimmed: !on)
                                Text(PlatformBrand.shortName(p.id)).font(.system(size: 11)).foregroundStyle(.white.opacity(on ? 0.9 : 0.4))
                            }
                        }
                        .frame(width: 76, height: 70)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(on ? 0.1 : 0.03)))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(on ? Color.pink.opacity(0.7) : .clear, lineWidth: 1))
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(PressStyle())
                }
            }
            Text(state.connectedContentPlatforms.filter { state.isSourceEnabled($0.id) }.count == 1
                 ? "只刷一个平台时，猫猫会比较辛苦，搬得慢一点"
                 : "关掉的平台不会出现在推荐里；也可以在「连接」页里开关")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
        }
        .padding(12)
        .frame(width: 360, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(white: 0.1)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.5), radius: 16, y: 6)
    }
}
