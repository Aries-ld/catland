// 连接面板：所有平台的点亮状态，统一登录（扫码 / 内嵌官方登录页）与退出。
import SwiftUI

struct ConnectionsView: View {
    let state: AppState

    private var groups: [(String, [PlatformState])] {
        // 暂未开放的平台排在分组最后，不夹在可用平台中间。
        let content = state.platforms.filter { $0.sections.contains("content") }
        return [("内容", content.filter { $0.unavailable == nil } + content.filter { $0.unavailable != nil }),
                ("电商 · 下个版本", state.platforms.filter { $0.sections.contains("commerce") })]
    }

    var body: some View {
        ZStack {
            Color(white: 0.07)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("连接平台").font(.system(size: 16, weight: .semibold))
                    Text("登录状态只保存在这台 Mac 上，删掉或重装 catland 也不用重新登录；catland 不上传任何信息。").font(.system(size: 11)).foregroundStyle(.secondary)
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
    /// 电商（下个版本）与暂未开放的平台都置灰、不能连接。
    private var disabled: Bool { commerce || platform.unavailable != nil }
    private var statusText: String {
        if platform.unavailable != nil { return "暂未开放" }
        if platform.loginInProgress { return "登录中…" }
        if platform.connected, state.sourceStatus[platform.id] == "cooldown" { return "休息中 · 稍后自动恢复" }
        if !platform.connected { return platform.primaryLogin == "qrcode" ? "扫码登录" : "网页登录" }
        switch platform.health {
        case "expired": return "已失效，点击重连"
        case "risk": return "触发风控"
        default: return platform.current?.user?.name ?? "已连接"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            PlatformIcon(platform: platform.id, size: 30, dimmed: !platform.connected || disabled)
                .overlay(alignment: .bottomTrailing) {
                    if platform.connected && !disabled { Circle().fill(platform.health == "expired" ? .orange : .green).frame(width: 9, height: 9).overlay(Circle().stroke(.black, lineWidth: 1.5)).offset(x: 2, y: 2) }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(platform.name).font(.system(size: 13, weight: .medium))
                Text(statusText).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if platform.connected && hovering && !disabled {
                Button("退出") { Task { await state.logout(platform.id) } }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.red.opacity(0.9))
            } else if platform.connected && !disabled && platform.sections.contains("content") {
                // 「刷它」：这个平台出不出现在推荐里（和「视频」标签下的平台开关是同一份设置）
                let on = state.isSourceEnabled(platform.id)
                Button { withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) { state.toggleSource(platform.id) } } label: {
                    Text(on ? "刷它" : "不刷").font(.system(size: 10, weight: .medium))
                        .foregroundStyle(on ? .black : .white.opacity(0.6))
                        .padding(.horizontal, 7).frame(height: 18)
                        .background(Capsule().fill(on ? Color.pink : .white.opacity(0.12)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(on ? "推荐里会刷到它，点一下关掉" : "推荐里不刷它，点一下打开")
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(hovering ? 0.09 : 0.05)))
        .opacity(disabled ? 0.45 : 1)
        .help(platform.unavailable ?? "")
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { connect() }
    }

    private func connect() {
        guard !commerce else { return state.showToast("电商板块下个版本上线") }
        if let reason = platform.unavailable { return state.showToast(reason) }
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
                Text(message ?? "").font(.system(size: 11)).foregroundStyle(state.qrRiskBlocked ? .orange : .secondary)
                    .multilineTextAlignment(.center).frame(width: 240).fixedSize(horizontal: false, vertical: true)
                if state.qrRiskBlocked {
                    // 被风控时把浏览器登录作为主操作：真实浏览器里扫码几乎不会被拦，登录后把登录态导入即可。
                    Button { useBrowser() } label: {
                        Label("改用浏览器登录（推荐）", systemImage: "safari")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 16).frame(height: 30)
                            .background(Capsule().fill(Color.accentColor)).contentShape(Capsule())
                    }
                    .buttonStyle(PressStyle())
                } else {
                    Button("扫不了或被拦？改用浏览器登录", action: useBrowser)
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.blue)
                }
                Button("取消") { state.cancelQrLogin() }.controlSize(.small)
            }
            .padding(22)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(white: 0.12)))
        }
    }

    private func useBrowser() {
        state.cancelQrLogin()
        guard let p = state.platforms.first(where: { $0.id == platform }) else { return }
        WebLoginController.shared.open(state: state, platform: p, browserImport: true,
                                       reason: state.qrRiskBlocked ? "\(PlatformBrand.shortName(platform))拦下了扫码登录。在浏览器里登录（真实浏览器几乎不会被拦），再把登录态导入进来。" : nil)
    }
}
