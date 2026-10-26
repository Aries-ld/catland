// AppState：全局状态（连接、设置、通知分发），视图只读它、调它的方法。
import AppKit
import Foundation
import Observation
import os

@MainActor
@Observable
final class AppState {
    enum Phase: Equatable { case starting, ready, failed(String) }
    enum Section: String, CaseIterable { case content = "视频", commerce = "电商" }
    enum Overlay: String, Equatable { case none, connections, settings, saved }

    let sidecar = SidecarClient()
    let feed: FeedController
    private let log = Logger(subsystem: "app.catland", category: "app")

    var phase: Phase = .starting
    var platforms: [PlatformState] = []
    var settings = Settings(muted: true, sources: [:])
    var section: Section = .content
    var overlay: Overlay = .none
    var expanded = false
    var hovering = false
    var commentsOpen = false
    /// 内嵌网页登录窗口打开时，点击面板外不收起。
    var webLoginActive = false
    var notch = NotchGeometry(screenFrame: .zero, notchSize: CGSize(width: 180, height: 32), hasNotch: false)
    /// 扫码登录进行中：平台 → 二维码 PNG 与最新进度。
    var qrLogin: (platform: String, png: Data?, message: String?)?
    var toast: String?
    private var toastTask: Task<Void, Never>?

    init() {
        feed = FeedController(sidecar: sidecar)
    }

    var connectedContentPlatforms: [PlatformState] {
        platforms.filter { $0.connected && $0.sections.contains("content") }
    }

    func start() async {
        sidecar.setNotificationHandler { [weak self] method, params in
            Task { @MainActor in self?.onNotification(method, params) }
        }
        do {
            try sidecar.start()
            let hello: HelloResult = try await sidecar.call("app.hello")
            settings = hello.settings
            feed.muted = settings.muted
            phase = .ready
        } catch {
            log.error("start failed: \(error.localizedDescription, privacy: .public)")
            phase = .failed(error.localizedDescription)
        }
    }

    func stop() {
        sidecar.stop()
    }

    private func onNotification(_ method: String, _ params: Data) {
        let dec = JSONDecoder()
        switch method {
        case "app.ready", "accounts.changed":
            struct P: Decodable { let platforms: [PlatformState] }
            if let p = try? dec.decode(P.self, from: params) { platforms = p.platforms }
            if method == "app.ready" { Task { await feed.prime() } }
        case "accounts.login":
            if let e = try? dec.decode(LoginEvent.self, from: params), qrLogin?.platform == e.platform {
                if e.type == "qrcode", let b64 = e.png { qrLogin?.png = Data(base64Encoded: b64) }
                if e.type == "progress" { qrLogin?.message = e.message }
            }
        case "feed.source":
            if let s = try? dec.decode(SourceState.self, from: params) {
                let name = PlatformBrand.shortName(s.platform)
                if s.status == "cooldown" { showToast("\(name) 触发风控，先歇 10 分钟") }
                if s.status == "auth" { showToast("\(name) 登录已失效，请重新连接") }
            }
        default: break
        }
    }

    // MARK: - 账号

    func refreshAccounts() async {
        if let list: [PlatformState] = try? await sidecar.call("accounts.list") { platforms = list }
    }

    func loginQrcode(_ platform: String) async {
        qrLogin = (platform, nil, "正在获取二维码…")
        do {
            let _: Account = try await sidecar.call("accounts.loginQrcode", ["platform": platform])
            showToast("已连接 \(PlatformBrand.shortName(platform))")
            qrLogin = nil
        } catch let e as RPCError where e.appCode == "ABORTED" {
            qrLogin = nil
        } catch {
            qrLogin?.message = "登录失败：\(error.localizedDescription)"
        }
        await refreshAccounts()
    }

    func cancelQrLogin() {
        guard let p = qrLogin?.platform else { return }
        qrLogin = nil
        Task { _ = try? await sidecar.callRaw("accounts.cancelLogin", ["platform": p]) }
    }

    func loginCookie(_ platform: String, cookies: [[String: Any]]) async throws {
        let _: Account = try await sidecar.call("accounts.loginCookie", ["platform": platform, "cookies": cookies])
        showToast("已连接 \(PlatformBrand.shortName(platform))")
        await refreshAccounts()
    }

    func logout(_ platform: String) async {
        do {
            platforms = try await sidecar.call("accounts.logout", ["platform": platform])
        } catch {
            showToast("退出失败：\(error.localizedDescription)")
        }
    }

    // MARK: - 设置

    func setMuted(_ muted: Bool) {
        settings.muted = muted
        feed.muted = muted
        Task { let _: Settings? = try? await sidecar.call("settings.update", ["muted": muted]) }
    }

    /// 勾选 / 取消某个信息源；nil 表示全部已登录平台。
    func toggleSource(_ platform: String) {
        let all = connectedContentPlatforms.map(\.id)
        var chosen = settings.sources["content"] ?? all
        if chosen.contains(platform) { chosen.removeAll { $0 == platform } } else { chosen.append(platform) }
        if chosen.isEmpty { return showToast("至少保留一个信息源") }
        settings.sources["content"] = chosen
        Task {
            let _: Settings? = try? await sidecar.call("settings.update", ["sources": ["content": chosen]])
            await feed.sourcesChanged()
        }
    }

    func isSourceEnabled(_ platform: String) -> Bool {
        settings.sources["content"].map { $0.contains(platform) } ?? true
    }

    func showToast(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            if !Task.isCancelled { toast = nil }
        }
    }

    /// 老板键：立刻收起、暂停、静音。
    func bossKey() {
        expanded = false
        overlay = .none
        feed.pauseAll()
    }
}
