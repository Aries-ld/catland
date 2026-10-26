// 展开面板：顶部板块切换（视频 / 电商）+ 右上角入口（收藏、连接、设置），下面是当前板块内容与浮层。
import SwiftUI

struct ExpandedPanel: View {
    let state: AppState

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack {
                content
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
                }
                .buttonStyle(.plain)
            }
            Spacer()
            iconButton("heart.text.square", active: state.overlay == .saved) { toggleOverlay(.saved) }
            iconButton("link", active: state.overlay == .connections, badge: state.connectedContentPlatforms.count) { toggleOverlay(.connections) }
            iconButton("slider.horizontal.3", active: state.overlay == .settings) { toggleOverlay(.settings) }
        }
        .padding(.horizontal, 18)
        .frame(height: 40)
    }

    private func toggleOverlay(_ o: AppState.Overlay) {
        state.overlay = state.overlay == o ? .none : o
        state.overlay == .none ? state.feed.resume() : state.feed.pauseAll()
    }

    private func iconButton(_ name: String, active: Bool, badge: Int = 0, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(active ? .white : .white.opacity(0.6))
                .frame(width: 26, height: 26)
                .background(Circle().fill(.white.opacity(active ? 0.16 : 0)))
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
                StatusView(text: "还没有连接任何平台", detail: "连接小红书、B 站、X 等账号后就能开刷", action: ("去连接", { state.overlay = .connections }))
            } else {
                FeedView(state: state)
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
            CatStrip(cats: 1, id: "status").frame(width: 120, height: 30)
            Text(text).font(.system(size: 14, weight: .semibold))
            if let d = detail { Text(d).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 30) }
            if let a = action {
                Button(a.0, action: a.1).buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.07))
    }
}
