// 内嵌官方登录页（只支持 cookie 登录的平台，以及扫码被风控时的备用方式）。
// 用户在平台官方页面完成登录；检测到登录态 cookie 后自动交给 sidecar（catbus 在线校验后保存）。
// 使用非持久化的 WKWebsiteDataStore：登录态只落在 ~/.catbus，WebView 关闭即清空。
import AppKit
import SwiftUI
import WebKit

@MainActor
final class WebLoginController: NSObject, NSWindowDelegate {
    static let shared = WebLoginController()

    private var window: NSWindow?
    private var webView: WKWebView?
    private var timer: Timer?
    private var platform: PlatformState?
    private weak var state: AppState?
    private var submitting = false

    func open(state: AppState, platform: PlatformState) {
        close()
        self.state = state
        self.platform = platform
        state.webLoginActive = true

        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: cfg)
        web.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        if let url = URL(string: platform.loginUrl) { web.load(URLRequest(url: url)) }
        webView = web

        let content = NSHostingView(rootView: WebLoginChrome(platform: platform, manual: platform.requiredCookies.isEmpty, onManual: { [weak self] in self?.submit(force: true) }, onCancel: { [weak self] in self?.close() }))
        let container = NSStackView(views: [content, web])
        container.orientation = .vertical
        container.spacing = 0
        content.heightAnchor.constraint(equalToConstant: 44).isActive = true

        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 680), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = "登录\(platform.name)"
        w.contentView = container
        w.delegate = self
        w.level = .floating
        w.isReleasedWhenClosed = false
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.submit(force: false) }
        }
    }

    /// 读取全部 cookie（含 HttpOnly）；满足任一组必需 cookie 时提交。force 用于没有判定规则的平台。
    private func submit(force: Bool) {
        guard !submitting, let platform, let store = webView?.configuration.websiteDataStore.httpCookieStore else { return }
        store.getAllCookies { [weak self] cookies in
            Task { @MainActor in
                guard let self, !self.submitting else { return }
                let names = Set(cookies.map(\.name))
                let ready = force || platform.requiredCookies.contains { group in group.allSatisfy(names.contains) }
                guard ready, !cookies.isEmpty else { return }
                self.submitting = true
                let payload: [[String: Any]] = cookies.map { c in
                    var d: [String: Any] = ["name": c.name, "value": c.value, "domain": c.domain, "path": c.path]
                    if let e = c.expiresDate { d["expires"] = e.timeIntervalSince1970 }
                    return d
                }
                do {
                    try await self.state?.loginCookie(platform.id, cookies: payload)
                    self.close()
                } catch {
                    self.submitting = false
                    // 必需 cookie 刚出现但服务端还没完成登录时校验会失败，稍后自动重试。
                    if force { self.state?.showToast("登录校验失败：\(error.localizedDescription)") }
                }
            }
        }
    }

    func close() {
        timer?.invalidate()
        timer = nil
        window?.delegate = nil
        window?.close()
        window = nil
        webView = nil
        submitting = false
        state?.webLoginActive = false
    }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
        window = nil
        webView = nil
        state?.webLoginActive = false
    }
}

private struct WebLoginChrome: View {
    let platform: PlatformState
    let manual: Bool
    let onManual: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield").foregroundStyle(.green)
            Text("在\(platform.name)官方页面登录，完成后自动连接。登录态只保存在本机。").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
            Spacer()
            if manual { Button("我已登录", action: onManual).controlSize(.small) }
            Button("取消", action: onCancel).controlSize(.small)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
