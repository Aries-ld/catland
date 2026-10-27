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
    enum Mode { case web, browserImport }
    var mode: Mode = .web
    /// 为什么切到「浏览器登录后导入」（比如 Google 不允许内嵌登录）。
    var notice: String?
    var url: URL?
    var title = ""
    var progress: Double = 0
    var loading = false
    var canGoBack = false
    var canGoForward = false
}

@MainActor
final class WebLoginController: NSObject, NSWindowDelegate, WKUIDelegate, WKNavigationDelegate {
    static let shared = WebLoginController()

    private var window: NSWindow?
    private var webView: WKWebView?
    private var timer: Timer?
    private var platform: PlatformState?
    private weak var state: AppState?
    private var submitting = false
    private var observers: [NSKeyValueObservation] = []
    private let model = WebLoginModel()
    private var importHost: NSView?

    /// browserImport：直接进入「在浏览器里登录后导入」并打开默认浏览器（扫码被风控时用）。
    func open(state: AppState, platform: PlatformState, browserImport: Bool = false, reason: String? = nil) {
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
        web.navigationDelegate = self
        model.mode = .web
        model.notice = nil
        if let url = URL(string: platform.loginUrl) { web.load(URLRequest(url: url)) }
        webView = web
        observe(web)

        let chrome = NSHostingView(rootView: WebLoginChrome(
            model: model, platform: platform, manual: platform.requiredCookies.isEmpty,
            onBack: { [weak web] in web?.goBack() }, onForward: { [weak web] in web?.goForward() },
            onReload: { [weak web] in web?.reload() },
            onBrowser: { [weak self] in self?.switchToBrowser(reason: nil) },
            onManual: { [weak self] in self?.submit(force: true) }, onCancel: { [weak self] in self?.close() }))
        let importView = NSHostingView(rootView: BrowserImportView(
            model: model, platform: platform,
            onOpenBrowser: { [weak self] in self?.openInBrowser() },
            onBackToWindow: { [weak self] in self?.showWeb() },
            onSubmit: { [weak self] header in await self?.submitHeader(header) ?? "窗口已关闭" }))
        importView.isHidden = true
        importHost = importView
        let container = NSStackView(views: [chrome, web, importView])
        container.orientation = .vertical
        container.spacing = 0
        // NSStackView 默认按子视图的固有宽度居中摆放：顶栏、网页、导入页都要撑满整个窗口宽度。
        container.alignment = .leading
        container.distribution = .fill
        for v in [chrome, web, importView] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false }
        chrome.heightAnchor.constraint(equalToConstant: 90).isActive = true

        // 各平台官网都是桌面宽屏布局：给一个正常浏览器大小的窗口（按屏幕可用区域收缩），登录入口和弹窗才完整可见。
        let visible = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        let ww = min(1180, visible.width - 120), wh = min(820, visible.height - 80)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: ww, height: wh), styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = "登录\(platform.name)"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.contentView = container
        for v in [chrome, web, importView] as [NSView] { v.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true }
        w.delegate = self
        w.level = .floating
        w.isReleasedWhenClosed = false
        w.minSize = NSSize(width: 720, height: 560)
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.submit(force: false) }
        }
        if browserImport {
            switchToBrowser(reason: reason)
            openInBrowser()
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

    /// Google / Apple 明确禁止在 App 内嵌网页里登录账号（会卡住或报「浏览器不安全」）。
    private static let embeddedBlockedHosts = ["accounts.google.com", "appleid.apple.com"]

    private func isBlockedSSO(_ url: URL?) -> Bool {
        guard let host = url?.host() else { return false }
        return Self.embeddedBlockedHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// 「用 Apple / Google 登录」等会开新窗口：SSO 直接引导去浏览器；其他在当前窗口里打开。
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if isBlockedSSO(navigationAction.request.url) {
            switchToBrowser(reason: "Google / Apple 不允许在 App 内嵌窗口里登录。请在浏览器里登录后，把登录态导入进来。")
        } else if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard isBlockedSSO(navigationAction.request.url) else { return .allow }
        switchToBrowser(reason: "Google / Apple 不允许在 App 内嵌窗口里登录。请在浏览器里登录后，把登录态导入进来。")
        return .cancel
    }

    // MARK: - 在浏览器里登录后导入

    private func switchToBrowser(reason: String?) {
        model.notice = reason
        model.mode = .browserImport
        webView?.isHidden = true
        importHost?.isHidden = false
        AppLog.info("web login: browser import", ["platform": platform?.id ?? "", "reason": reason ?? "user"])
    }

    private func showWeb() {
        model.mode = .web
        model.notice = nil
        importHost?.isHidden = true
        webView?.isHidden = false
    }

    /// 在用户的默认浏览器（如 Chrome）里打开官方登录页：可以直接复用浏览器里已有的账号。
    private func openInBrowser() {
        guard let platform, let url = URL(string: platform.loginUrl) else { return }
        NSWorkspace.shared.open(url)
    }

    /// 提交用户从浏览器复制的 Cookie 请求头；返回错误信息（nil 表示成功）。
    private func submitHeader(_ raw: String) async -> String? {
        guard let platform else { return "窗口已关闭" }
        var header = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if header.lowercased().hasPrefix("cookie:") { header = String(header.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
        let names = Set(header.split(separator: ";").compactMap { $0.split(separator: "=", maxSplits: 1).first.map { $0.trimmingCharacters(in: .whitespaces) } })
        if !platform.requiredCookies.isEmpty, !platform.requiredCookies.contains(where: { $0.allSatisfy(names.contains) }) {
            let need = platform.requiredCookies.first?.joined(separator: "、") ?? ""
            return "没找到登录态（需要包含 \(need)）。请确认已经登录，并复制的是完整的 Cookie 那一行。"
        }
        do {
            try await state?.loginCookie(platform.id, header: header)
            close()
            return nil
        } catch {
            return "校验没通过：\(error.localizedDescription)"
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
        observers = []
        window?.delegate = nil
        window?.close()
        window = nil
        webView = nil
        importHost = nil
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
    let onBrowser: () -> Void
    let onManual: () -> Void
    let onCancel: () -> Void

    private var secure: Bool { model.url?.scheme == "https" }

    /// 各平台官方页面上「登录」入口的位置提示。
    static let hint: [String: String] = [
        "douyin": "点页面右上角「登录」，用抖音 App 扫码 · 完成后自动连接",
        "kuaishou": "点页面右上角「登录」，用快手 App 扫码 · 完成后自动连接",
    ]

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
                .padding(.horizontal, 10).frame(maxWidth: .infinity).frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.07)))
                navButton(model.loading ? "xmark" : "arrow.clockwise", enabled: true, action: onReload)
            }
            .padding(.horizontal, 10).frame(maxWidth: .infinity).frame(height: 42)

            HStack(spacing: 8) {
                PlatformIcon(platform: platform.id, size: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text("在\(platform.name)官方页面登录").font(.system(size: 12, weight: .semibold))
                    Text(Self.hint[platform.id] ?? "登录完成后自动连接并关闭窗口 · 登录态只保存在这台 Mac").font(.system(size: 10)).foregroundStyle(.secondary)
                        .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                }
                Spacer()
                if model.mode == .web {
                    Button(action: onBrowser) { Label("在浏览器中登录", systemImage: "safari") }.controlSize(.small)
                        .help("在 Chrome 等默认浏览器里登录（可用 Google / Apple 账号），再把登录态导入")
                    if manual { Button("我已登录", action: onManual).controlSize(.small) }
                }
                Button("取消", action: onCancel).controlSize(.small)
            }
            .padding(.horizontal, 12).frame(maxWidth: .infinity).frame(height: 46)

            GeometryReader { g in
                Rectangle().fill(Color.accentColor)
                    .frame(width: g.size.width * (model.loading ? max(0.05, model.progress) : 0), height: 2)
                    .animation(.easeOut(duration: 0.2), value: model.progress)
            }
            .frame(height: 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.bar)
        // 窗口内容延伸到透明标题栏下：不忽略安全区的话，SwiftUI 会把整块往下推 28pt，最下面那行说明被截掉。
        .ignoresSafeArea()
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

/// 「在浏览器里登录后导入」：打开默认浏览器登录，再把 Cookie 请求头粘贴回来。
/// 不读取浏览器的 cookie 数据库——那需要浏览器加密密钥的权限，等于能读所有网站的登录态。
private struct BrowserImportView: View {
    let model: WebLoginModel
    let platform: PlatformState
    let onOpenBrowser: () -> Void
    let onBackToWindow: () -> Void
    let onSubmit: (String) async -> String?

    @State private var header = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let n = model.notice {
                    Label(n, systemImage: "exclamationmark.shield.fill")
                        .font(.system(size: 12)).foregroundStyle(.orange)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))
                }
                step(1, "在浏览器里登录\(platform.name)", "可以直接用浏览器里已登录的账号，或用 Google / Apple 登录。") {
                    Button(action: onOpenBrowser) { Label("打开浏览器登录", systemImage: "safari") }.controlSize(.regular)
                }
                step(2, "复制登录态（Cookie）", "在\(platform.name)页面按 ⌥⌘I 打开开发者工具 → 网络（Network）→ 刷新页面 → 点开任意一个发往该网站的请求 → 在「请求标头」里找到 Cookie，复制整行的值。") { EmptyView() }
                step(3, "粘贴到这里", "只保存在这台 Mac 的 ~/.catbus，校验通过后自动连接。") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextEditor(text: $header)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(height: 96)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                        HStack {
                            Button("从剪贴板粘贴") { header = NSPasteboard.general.string(forType: .string) ?? "" }
                            Spacer()
                            if busy { ProgressView().controlSize(.small) }
                            Button("连接") {
                                busy = true; error = nil
                                Task { error = await onSubmit(header); busy = false }
                            }
                            .keyboardShortcut(.defaultAction)
                            .disabled(header.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
                        }
                        if let e = error { Text(e).font(.system(size: 11)).foregroundStyle(.red) }
                    }
                }
                Button("返回窗口内登录", action: onBackToWindow).buttonStyle(.link).font(.system(size: 11))
            }
            .padding(18)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func step<Content: View>(_ n: Int, _ title: String, _ detail: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                .frame(width: 20, height: 20).background(Circle().fill(Color.accentColor))
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                content()
            }
        }
    }
}
