// 连接面板：所有平台的点亮状态，统一登录（扫码 / 内嵌官方登录页）与退出。
import SwiftUI

struct ConnectionsView: View {
    let state: AppState

    private var groups: [(String, [PlatformState])] {
        [("内容", state.platforms.filter { $0.sections.contains("content") }), ("电商 · 下个版本", state.platforms.filter { $0.sections.contains("commerce") })]
    }

    var body: some View {
        ZStack {
            Color(white: 0.07)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("连接平台").font(.system(size: 16, weight: .semibold))
                    Text("登录态只保存在这台电脑上（~/.catbus），catland 不上传任何信息。").font(.system(size: 11)).foregroundStyle(.secondary)
                    ForEach(groups, id: \.0) { title, list in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                                ForEach(list) { p in PlatformTile(state: state, platform: p) }
                            }
                        }
                    }
                }
                .padding(18)
            }
            if let qr = state.qrLogin { QRLoginView(state: state, platform: qr.platform, png: qr.png, message: qr.message) }
        }
    }
}

struct PlatformTile: View {
    let state: AppState
    let platform: PlatformState
    @State private var hovering = false

    private var commerce: Bool { platform.sections.contains("commerce") }
    private var statusText: String {
        if platform.loginInProgress { return "登录中…" }
        if !platform.connected { return platform.primaryLogin == "qrcode" ? "扫码登录" : "网页登录" }
        switch platform.health {
        case "expired": return "已失效，点击重连"
        case "risk": return "触发风控"
        default: return platform.current?.user?.name ?? "已连接"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            PlatformIcon(platform: platform.id, size: 30, dimmed: !platform.connected)
                .overlay(alignment: .bottomTrailing) {
                    if platform.connected { Circle().fill(platform.health == "expired" ? .orange : .green).frame(width: 9, height: 9).overlay(Circle().stroke(.black, lineWidth: 1.5)).offset(x: 2, y: 2) }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(platform.name).font(.system(size: 13, weight: .medium))
                Text(statusText).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if platform.connected && hovering && !commerce {
                Button("退出") { Task { await state.logout(platform.id) } }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.red.opacity(0.9))
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(hovering ? 0.09 : 0.05)))
        .opacity(commerce ? 0.45 : 1)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { connect() }
    }

    private func connect() {
        guard !commerce else { return state.showToast("电商板块下个版本上线") }
        guard !platform.connected || platform.health == "expired" else { return }
        if platform.primaryLogin == "qrcode" {
            Task { await state.loginQrcode(platform.id) }
        } else {
            WebLoginController.shared.open(state: state, platform: platform)
        }
    }
}

struct QRLoginView: View {
    let state: AppState
    let platform: String
    let png: Data?
    let message: String?

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).onTapGesture { state.cancelQrLogin() }
            VStack(spacing: 14) {
                HStack(spacing: 6) { PlatformIcon(platform: platform, size: 20); Text("用\(PlatformBrand.shortName(platform)) App 扫码").font(.system(size: 15, weight: .semibold)) }
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(.white).frame(width: 200, height: 200)
                    if let png, let img = NSImage(data: png) {
                        Image(nsImage: img).interpolation(.none).resizable().frame(width: 184, height: 184)
                    } else {
                        ProgressView().controlSize(.small).tint(.black)
                    }
                }
                Text(message ?? "").font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(height: 30)
                if platform == "xhs" {
                    Button("扫码被风控？改用网页登录") {
                        state.cancelQrLogin()
                        if let p = state.platforms.first(where: { $0.id == "xhs" }) { WebLoginController.shared.open(state: state, platform: p) }
                    }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.blue)
                }
                Button("取消") { state.cancelQrLogin() }.controlSize(.small)
            }
            .padding(22)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(white: 0.12)))
        }
    }
}
