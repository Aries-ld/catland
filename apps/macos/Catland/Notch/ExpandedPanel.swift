// 展开面板：顶部板块切换（视频 / 电商）+ 右上角入口（搜索、收藏、连接、设置），下面是当前板块内容与浮层。
// 打开搜索后顶栏变成搜索框、内容区变成搜索页（ADR 0004）。
import SwiftUI

struct ExpandedPanel: View {
    let state: AppState
    /// 搜索功能的一次性提示气泡（升级后第一次展开时出现）。
    @AppStorage("searchTipShown") private var searchTipShown = false
    @State private var showSearchTip = false

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if state.search.active {
                    if state.search.playing { SearchPlayerHeader(state: state) } else { SearchHeader(state: state) }
                } else {
                    header
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
        .onAppear {
            guard !searchTipShown, !state.searchPlatforms.isEmpty else { return }
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
                    state.section = s
                    state.overlay = .none
                } label: {
                    VStack(spacing: 4) {
                        Text(s.rawValue)
                            .font(.system(size: 14, weight: state.section == s ? .semibold : .regular))
                            .foregroundStyle(s == .commerce ? .white.opacity(0.3) : (state.section == s ? .white : .white.opacity(0.55)))
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
            iconButton("heart.text.square", active: state.overlay == .saved) { toggleOverlay(.saved) }
            // 连接平台：和收藏、设置一样的图标按钮，不抢视觉；悬停显示已连接几个
            iconButton("person.crop.circle.badge.plus", active: state.overlay == .connections) { toggleOverlay(.connections) }
                .help("连接平台（已连接 \(state.connectedContentPlatforms.count) 个）")
            iconButton("slider.horizontal.3", active: state.overlay == .settings) { toggleOverlay(.settings) }
        }
        .padding(.horizontal, 18)
        .frame(height: 40)
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
                StatusView(text: "还没有连接任何平台", detail: "连接小红书、B 站、X 等账号后就能开刷", action: ("连接平台", { state.overlay = .connections }))
            } else {
                FeedView(state: state, feed: state.feed)
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
