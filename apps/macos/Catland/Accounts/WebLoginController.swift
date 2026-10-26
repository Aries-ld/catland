// 内嵌官方登录页（只支持 cookie 登录的平台，以及扫码被风控时的备用方式）。
// 用户在平台官方页面完成登录；检测到登录态 cookie 后自动交给 sidecar（catbus 在线校验后保存）。
// 使用非持久化的 WKWebsiteDataStore：登录态只落在 ~/.catbus，窗口关闭即清空。
// 外观做成一个迷你浏览器：前进 / 后退 / 刷新、带锁的地址栏（一眼看出是官方域名）、加载进度条。
import AppKit
import SwiftUI
import WebKit

/// 浏览器顶栏要显示的状态（KVO 自 WKWebView）。
@MainActor
@Observable
final class WebLoginModel {
    var url: URL?
    var title = ""
    var progress: Double = 0
    var loading = false
    var canGoBack = false
    var canGoForward = false
}

@MainActor
final class WebLoginController: NSObject, NSWindowDelegate, WKUIDelegate {
    static let shared = WebLoginController()

    private var window: NSWindow?
    private var webView: WKWebView?
    private var timer: Timer?
    private var platform: PlatformState?
    private weak var state: AppState?
    private var submitting = false
    private var observers: [NSKeyValueObservation] = []
    private let model = WebLoginModel()

    func open(state: AppState, platform: PlatformState) {
        close()
        self.state = state
        self.platform = platform
        state.webLoginActive = true

        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .nonPersistent()
        cfg.preferences.javaScriptCanOpenWindowsAutomatically = true
        let web = WKWebView(frame: .zero, configuration: cfg)
        // 与 Safari 一致的 UA：部分平台会对内嵌 WebView 降级或提示「浏览器不受支持」。
        web.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        web.allowsBackForwardNavigationGestures = true
        web.uiDelegate = self
        if let url = URL(string: platform.loginUrl) { web.load(URLRequest(url: url)) }
        webView = web
        observe(web)

        let chrome = NSHostingView(rootView: WebLoginChrome(
            model: model, platform: platform, manual: platform.requiredCookies.isEmpty,
            onBack: { [weak web] in web?.goBack() }, onForward: { [weak web] in web?.goForward() },
            onReload: { [weak web] in web?.reload() },
            onManual: { [weak self] in self?.submit(force: true) }, onCancel: { [weak self] in self?.close() }))
        let container = NSStackView(views: [chrome, web])
        container.orientation = .vertical
        container.spacing = 0
        chrome.heightAnchor.constraint(equalToConstant: 84).isActive = true

        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 760), styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = "登录\(platform.name)"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.contentView = container
        w.delegate = self
        w.level = .floating
        w.isReleasedWhenClosed = false
        w.minSize = NSSize(width: 420, height: 560)
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.submit(force: false) }
        }
    }

    private func observe(_ web: WKWebView) {
        let m = model
        observers = [
            web.observe(\.url, options: [.initial, .new]) { w, _ in Task { @MainActor in m.url = w.url } },
            web.observe(\.title, options: [.initial, .new]) { w, _ in Task { @MainActor in m.title = w.title ?? "" } },
            web.observe(\.estimatedProgress, options: [.initial, .new]) { w, _ in Task { @MainActor in m.progress = w.estimatedProgress } },
            web.observe(\.isLoading, options: [.initial, .new]) { w, _ in Task { @MainActor in m.loading = w.isLoading } },
            web.observe(\.canGoBack, options: [.initial, .new]) { w, _ in Task { @MainActor in m.canGoBack = w.canGoBack } },
            web.observe(\.canGoForward, options: [.initial, .new]) { w, _ in Task { @MainActor in m.canGoForward = w.canGoForward } },
        ]
    }

    /// 「用 Apple / Google 登录」等会开新窗口：在当前窗口里打开，避免点了没反应。
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { webView.load(URLRequest(url: url)) }
        return nil
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
        observers = []
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
        observers = []
        window = nil
        webView = nil
        state?.webLoginActive = false
    }
}

/// 迷你浏览器顶栏：第一行是导航按钮 + 地址栏，第二行是登录说明与操作，底部一条加载进度。
private struct WebLoginChrome: View {
    let model: WebLoginModel
    let platform: PlatformState
    let manual: Bool
    let onBack: () -> Void
    let onForward: () -> Void
    let onReload: () -> Void
    let onManual: () -> Void
    let onCancel: () -> Void

    private var secure: Bool { model.url?.scheme == "https" }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Spacer().frame(width: 64) // 给左上角的红绿灯留位置
                navButton("chevron.left", enabled: model.canGoBack, action: onBack)
                navButton("chevron.right", enabled: model.canGoForward, action: onForward)
                HStack(spacing: 6) {
                    Image(systemName: secure ? "lock.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(secure ? .green : .orange)
                    Text(model.url?.host() ?? "正在打开…").font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Text(model.url.map { $0.path() == "/" ? "" : $0.path() } ?? "").font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10).frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.07)))
                navButton(model.loading ? "xmark" : "arrow.clockwise", enabled: true, action: onReload)
            }
            .padding(.horizontal, 10).frame(height: 42)

            HStack(spacing: 8) {
                PlatformIcon(platform: platform.id, size: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text("在\(platform.name)官方页面登录").font(.system(size: 12, weight: .semibold))
                    Text("登录完成后自动连接并关闭窗口 · 登录态只保存在这台 Mac").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                if manual { Button("我已登录", action: onManual).controlSize(.small) }
                Button("取消", action: onCancel).controlSize(.small)
            }
            .padding(.horizontal, 12).frame(height: 40)

            GeometryReader { g in
                Rectangle().fill(Color.accentColor)
                    .frame(width: g.size.width * (model.loading ? max(0.05, model.progress) : 0), height: 2)
                    .animation(.easeOut(duration: 0.2), value: model.progress)
            }
            .frame(height: 2)
        }
        .background(.bar)
    }

    private func navButton(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold)).frame(width: 26, height: 26).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.4))
        .disabled(!enabled)
    }
}
