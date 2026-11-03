// 自动更新（Sparkle）：每天查一次 GitHub Releases 上的 appcast；有新版时小猫在刘海里提醒，
// 用户点「更新」后自动下载、校验签名（EdDSA + Developer ID）、安装并重启，中间不再弹窗。
// 界面由 catland 自己画（自定义 SPUUserDriver），不用 Sparkle 的标准窗口。只有这一个请求发往 GitHub，不带任何用户信息。
import AppKit
import Observation
import Sparkle

@MainActor
@Observable
final class AppUpdater: NSObject {
    enum Phase: Equatable {
        case idle
        case checking
        /// 有新版，等用户点「更新」
        case available(version: String, notes: String?)
        /// 下载中（0…1；还不知道大小时为 nil）
        case downloading(Double?)
        case installing
    }

    private(set) var phase: Phase = .idle
    /// 调试版不检查更新（否则会把 DerivedData 里的调试版换成发布版）。
    private(set) var enabled = false
    /// 定时检查发现新版：小猫在刘海里说一声。
    var onAvailable: ((String) -> Void)?
    /// 提示一句（已是最新、更新失败等）。
    var onMessage: ((String) -> Void)?

    private var updater: SPUUpdater?
    private var foundReply: ((SPUUserUpdateChoice) -> Void)?
    private var userInitiated = false
    private var expected: UInt64 = 0
    private var received: UInt64 = 0

    static var currentVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?" }

    func start() {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["CATLAND_UPDATER_TEST"] == "1" else { return }
        #endif
        let u = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: nil)
        u.sendsSystemProfile = false
        do {
            try u.start()
            updater = u
            enabled = true
            AppLog.info("updater started", ["auto": u.automaticallyChecksForUpdates, "feed": u.feedURL?.absoluteString ?? "-"])
        } catch {
            AppLog.warn("updater failed to start", ["err": error.localizedDescription])
        }
    }

    var automaticChecks: Bool {
        get { updater?.automaticallyChecksForUpdates ?? false }
        set { updater?.automaticallyChecksForUpdates = newValue }
    }

    /// 设置里的「检查更新」。
    func checkNow() {
        guard let updater else { return }
        if case .available = phase { return }
        updater.checkForUpdates()
    }

    /// 用户点了「更新」：下载、安装、重启一气呵成。
    func install() {
        guard let reply = foundReply else { return }
        foundReply = nil
        phase = .downloading(nil)
        AppLog.info("update install")
        reply(.install)
    }

    #if DEBUG
    /// 只给离屏渲染检查版式用（catland-debug render:update）。
    func debugPhase(_ p: Phase) { phase = p }
    #endif

    private func reset() {
        phase = .idle
        foundReply = nil
        userInitiated = false
    }

    /// appcast 里的更新说明（HTML 或 Markdown）：转成几行纯文字显示。
    static func plainNotes(_ html: String?) -> String? {
        guard let html, !html.isEmpty else { return nil }
        let text = html
            .replacingOccurrences(of: "(?m)^\\s*[-*] ", with: "· ", options: .regularExpression)
            .replacingOccurrences(of: "(?m)^#+\\s*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "<li[^>]*>", with: "· ", options: .regularExpression)
            .replacingOccurrences(of: "</(p|li|h[1-6]|div)>|<br ?/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}

// Sparkle 在主线程调用这些方法。
extension AppUpdater: SPUUserDriver {
    nonisolated func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        // Info.plist 已开启每天自动检查；不上传系统信息
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    nonisolated func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        MainActor.assumeIsolated { userInitiated = true; phase = .checking }
    }

    nonisolated func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        MainActor.assumeIsolated {
            let version = appcastItem.displayVersionString
            AppLog.info("update found", ["version": version, "stage": state.stage.rawValue, "userInitiated": state.userInitiated])
            // 上次已经在安装了（比如安装中途退出）：直接继续
            if state.stage == .installing { phase = .installing; reply(.install); return }
            foundReply = reply
            phase = .available(version: version, notes: Self.plainNotes(appcastItem.itemDescription))
            if !state.userInitiated { onAvailable?(version) }
        }
    }

    nonisolated func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    nonisolated func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    nonisolated func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        MainActor.assumeIsolated {
            if userInitiated { onMessage?("已经是最新版 \(Self.currentVersion)") }
            reset()
        }
        acknowledgement()
    }

    nonisolated func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        MainActor.assumeIsolated {
            AppLog.warn("update error", ["err": error.localizedDescription])
            // 后台定时检查失败（比如没网）不打扰；用户点过的才提示
            if userInitiated || phase != .checking && phase != .idle { onMessage?("更新没成功：\(error.localizedDescription)") }
            reset()
        }
        acknowledgement()
    }

    nonisolated func showDownloadInitiated(cancellation: @escaping () -> Void) {
        MainActor.assumeIsolated { expected = 0; received = 0; phase = .downloading(nil) }
    }

    nonisolated func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        MainActor.assumeIsolated { expected = expectedContentLength; received = 0 }
    }

    nonisolated func showDownloadDidReceiveData(ofLength length: UInt64) {
        MainActor.assumeIsolated {
            received += length
            guard expected > 0 else { return }
            let p = min(1, Double(received) / Double(expected))
            // 每 1% 更新一次界面就够了
            if case .downloading(let old) = phase, let old, abs(old - p) < 0.01 { return }
            phase = .downloading(p)
        }
    }

    nonisolated func showDownloadDidStartExtractingUpdate() {
        MainActor.assumeIsolated { phase = .installing }
    }

    nonisolated func showExtractionReceivedProgress(_ progress: Double) {}

    nonisolated func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        // 用户已经点过「更新」：不再多问一次，直接安装并重启
        MainActor.assumeIsolated { phase = .installing; AppLog.info("update ready, relaunching") }
        reply(.install)
    }

    nonisolated func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        MainActor.assumeIsolated { phase = .installing }
    }

    nonisolated func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        MainActor.assumeIsolated { reset() }
        acknowledgement()
    }

    nonisolated func showUpdateInFocus() {
        MainActor.assumeIsolated { if case .available(let v, _) = phase { onAvailable?(v) } }
    }

    nonisolated func dismissUpdateInstallation() {
        MainActor.assumeIsolated {
            // 还在等用户点「更新」时 Sparkle 不会走到这里；其他情况（装完、出错、取消）回到空闲
            if foundReply == nil { reset() }
        }
    }
}
