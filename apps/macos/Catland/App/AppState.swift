// AppState：全局状态（连接、设置、通知分发），视图只读它、调它的方法。
import AppKit
import Foundation
import SwiftUI
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
    /// 跨平台搜索（搜索页 + 搜索结果的播放器）。
    let search: SearchController
    /// 当前在播的那一套卡片：正在看搜索结果时是搜索的播放器，否则是推荐流。
    var activeFeed: FeedController { search.playing ? search.player : feed }
    private let log = Logger(subsystem: "app.catland", category: "app")

    var phase: Phase = .starting
    var platforms: [PlatformState] = []
    var settings = Settings(muted: true, sources: [:])
    var section: Section = .content
    var overlay: Overlay = .none
    var expanded = false
    var hovering = false {
        didSet {
            guard hovering && !oldValue else { return }
            hoverSession = UInt64.random(in: 1...UInt64.max / 2)
            hoverStartedAt = Date().timeIntervalSinceReferenceDate
        }
    }
    /// 本次悬停开始的时刻：气泡从第一句（事件预告 / 倒计时）开始轮播。
    private(set) var hoverStartedAt: TimeInterval = 0
    /// 每次悬停一个新种子：气泡语料的轮播顺序随之变化。
    private(set) var hoverSession: UInt64 = 1

    // MARK: - 事件预告（小猫主动探出来说一句）

    /// 小猫主动说的话：刘海会像悬停一样探出来，气泡显示 8 秒后收回。
    private(set) var peekMessage: String?
    var peeking: Bool { peekMessage != nil }
    /// 悬停或主动探出时，刘海都展开成「大窗」。
    var showingRoom: Bool { hovering || peeking }
    private var peekTask: Task<Void, Never>?
    private var announced: Set<String> = []
    private var eventsTask: Task<Void, Never>?

    /// 刘海里出场的小猫：只有正常连接的平台（登录失效、被禁用的不出现）；一个都没有时是纸箱里的箱箱。
    var speakers: [Persona] {
        castOverride ?? Persona.speakers(platforms: connectedContentPlatforms
            .filter { $0.health != "expired" && sourceStatus[$0.id] != "auth" }
            .map(\.id))
    }
    /// 被风控暂停中的平台：它的小猫趴下打盹。
    var sleepingCats: Set<Persona> {
        if let o = sleepOverride { return o }
        return Set(sourceStatus.filter { $0.value == "cooldown" }.compactMap { Persona.forPlatform($0.key) })
    }
    /// 调试：临时让某些小猫打盹（catland-debug sleep:bibi / sleep:off）。
    var sleepOverride: Set<Persona>?
    /// 调试：临时指定刘海里出场的角色（catland-debug cast:box / cast:off），不影响真实的平台连接。
    var castOverride: [Persona]?

    func announce(_ text: String, seconds: Double = 8) {
        // 主动探头说话也带上名字（随机挑一只醒着的小猫）
        let awake = speakers.filter { !sleepingCats.contains($0) }
        let text = Persona.allCases.contains { text.hasPrefix("\($0.name)：") } ? text : ((awake.isEmpty ? speakers : awake).randomElement() ?? .box).say(text)
        AppLog.info("cat announce", ["text": text])
        peekTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { peekMessage = text }
        peekTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { self?.peekMessage = nil }
        }
    }

    /// 每 15 秒看一眼事件：开始前 6 小时 / 1 小时 / 10 分钟各预告一次，开始时喊一声（天气不允许就说取消了）。
    func startEventWatcher() {
        eventsTask?.cancel()
        eventsTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.checkEvents()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    func checkEvents() {
        let env = sceneEnv(now: Date())
        let now = env.date, region = RestDays.region(for: location), lat = location.latitude
        if let a = EventScheduler.active(now: now, region: region, latitude: lat) {
            let key = "\(a.eventID)@\(a.start.timeIntervalSince1970)@live"
            guard !announced.contains(key) else { return }
            announced.insert(key)
            let e = a.event
            announce(e.canRun(condition: env.condition, intensity: env.intensity) ? (e.lives.first ?? e.name) : e.cancelLine)
            return
        }
        guard let u = EventScheduler.upcoming(now: now, region: region, latitude: lat) else { return }
        let left = u.start.timeIntervalSince(now)
        let bucket = left <= 600 ? "10m" : (left <= 3600 ? "1h" : "6h")
        let key = "\(u.eventID)@\(u.start.timeIntervalSince1970)@\(bucket)"
        guard !announced.contains(key) else { return }
        announced.insert(key)
        let e = u.event, time = EventScheduler.timeLabel(u.start, now: now)
        switch bucket {
        case "10m": announce("\(e.name)马上开始！快来窗边")
        case "1h": announce("还有 \(EventScheduler.countdown(left))就是\(e.name)啦，\(time) 别错过")
        default: announce((e.teasers.first ?? "{time} 有\(e.name)").replacingOccurrences(of: "{time}", with: time))
        }
    }

    /// 天气触发型事件：白天雨转晴 → 雨后彩虹；这个冬天第一次下雪 → 初雪。
    private func triggerWeatherEvents(from old: WeatherInfo?, to new: WeatherInfo) {
        let now = Date()
        let wasWet = old.map { WeatherStyle.of($0.condition).wet } ?? false
        let daytime = SceneClock.sun(at: now, location: location).altitude > 5
        if wasWet, ["clear", "partly"].contains(new.condition), daytime { EventScheduler.trigger("rainbowAfterRain", at: now) }
        if ["snow", "sleet"].contains(new.condition) {
            let cal = Calendar.current
            let winter = cal.component(.year, from: now) + (cal.component(.month, from: now) == 12 ? 1 : 0)
            let key = "firstSnow-\(winter)"
            if !UserDefaults.standard.bool(forKey: key) {
                UserDefaults.standard.set(true, forKey: key)
                EventScheduler.trigger("firstSnow", at: now)
            }
        }
    }
    var commentsOpen = false
    /// 内嵌网页登录窗口是否打开（打开时面板会自动收起，让出屏幕给登录页）。
    var webLoginActive = false
    var notch = NotchGeometry(screenFrame: .zero, notchSize: CGSize(width: 180, height: 32), hasNotch: false)
    /// 扫码登录进行中：平台 → 二维码 PNG 与最新进度。
    var qrLogin: (platform: String, png: Data?, message: String?)?
    /// 各平台内容源的状态（active / backoff / cooldown / auth），来自 sidecar 的 feed.source 通知。
    var sourceStatus: [String: String] = [:]
    /// 已连接的内容平台全都在风控冷却：刷刷页给一句温和说明（单个平台冷却时用户无感）。
    var allSourcesResting: Bool {
        let ids = connectedContentPlatforms.map(\.id).filter(isSourceEnabled)
        return !ids.isEmpty && ids.allSatisfy { sourceStatus[$0] == "cooldown" }
    }

    /// 扫码登录被平台风控拦下（如抖音 2046「请前往 App 完成验证」）：引导改用浏览器登录后导入。
    var qrRiskBlocked = false
    var toast: String?
    private var toastTask: Task<Void, Never>?

    init() {
        feed = FeedController(sidecar: sidecar)
        search = SearchController(sidecar: sidecar)
    }

    /// 能搜索的平台：正常连接（登录没失效）的内容平台。
    var searchPlatforms: [String] {
        connectedContentPlatforms.filter { $0.health != "expired" && sourceStatus[$0.id] != "auth" }.map(\.id)
    }

    /// 打开搜索页：暂停推荐流。
    func openSearch() {
        overlay = .none
        commentsOpen = false
        feed.pauseAll()
        search.open()
    }

    /// 面板收起 / 展开时的搜索会话：收起只算暂停；隔超过 30 分钟再展开，结束这次搜索、回到推荐流。
    func searchPanelChanged(expanded: Bool) {
        guard search.active else { return }
        if !expanded { search.collapsedAt = Date(); return }
        if let t = search.collapsedAt, Date().timeIntervalSince(t) > SearchController.staleAfter { closeSearch() }
        search.collapsedAt = nil
    }

    /// 关闭搜索页：回到推荐流，接着刚才那条播。
    func closeSearch() {
        search.close()
        commentsOpen = false
        if expanded { feed.resume() }
    }

    var connectedContentPlatforms: [PlatformState] {
        platforms.filter { $0.connected && $0.unavailable == nil && $0.sections.contains("content") }
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
            search.player.muted = settings.muted
            phase = .ready
            startWeather()
            startEventWatcher()
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
            if let p = try? dec.decode(P.self, from: params) { setPlatforms(p.platforms) }
            if method == "app.ready" { Task { await feed.prime() } }
        case "accounts.login":
            if let e = try? dec.decode(LoginEvent.self, from: params), qrLogin?.platform == e.platform {
                if e.type == "qrcode", let b64 = e.png { qrLogin?.png = Data(base64Encoded: b64) }
                if e.type == "progress" { qrLogin?.message = e.message }
            }
        case "feed.source":
            if let s = try? dec.decode(SourceState.self, from: params) {
                sourceStatus[s.platform] = s.status
                // 风控冷却对用户无感：只是暂时不推这个平台，到点自动探测恢复；只有登录失效需要用户处理。
                if s.status == "auth" { showToast("\(PlatformBrand.shortName(s.platform)) 登录已失效，请重新连接") }
            }
        default: break
        }
    }

    // MARK: - 账号

    /// 更新平台列表；新连上内容平台而刷刷页还空着时（比如第一次连接），立刻拉首屏，不用等用户手动划。
    private func setPlatforms(_ list: [PlatformState]) {
        let before = Set(connectedContentPlatforms.map(\.id))
        platforms = list
        let added = Set(connectedContentPlatforms.map(\.id)).subtracting(before)
        guard !added.isEmpty else { return }
        if feed.cards.isEmpty {
            AppLog.info("first content source connected, priming feed", ["added": added.sorted().joined(separator: ",")])
            Task { await feed.prime() }
        } else {
            // 新连上平台：丢掉还没看的预取卡片重新取，新平台的内容马上出现（当前这条继续播）。
            AppLog.info("content source added, refreshing upcoming cards", ["added": added.sorted().joined(separator: ",")])
            Task { await feed.sourcesChanged() }
        }
    }

    func refreshAccounts() async {
        if let list: [PlatformState] = try? await sidecar.call("accounts.list") { setPlatforms(list) }
    }

    func loginQrcode(_ platform: String) async {
        qrLogin = (platform, nil, "正在获取二维码…")
        qrRiskBlocked = false
        do {
            let _: Account = try await sidecar.call("accounts.loginQrcode", ["platform": platform])
            showToast("已连接 \(PlatformBrand.shortName(platform))")
            qrLogin = nil
        } catch let e as RPCError where e.appCode == "ABORTED" {
            qrLogin = nil
        } catch let e as RPCError where e.appCode == "RISK_CONTROL" {
            AppLog.warn("qr login blocked by risk control", ["platform": platform, "err": e.localizedDescription])
            qrRiskBlocked = true
            qrLogin?.message = "\(PlatformBrand.shortName(platform))这次拦下了扫码登录（平台风控）。别连续重试，改用浏览器登录更稳。"
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

    /// 从浏览器复制来的 Cookie 请求头（「在浏览器中登录」后导入）。
    func loginCookie(_ platform: String, header: String) async throws {
        let _: Account = try await sidecar.call("accounts.loginCookie", ["platform": platform, "cookies": header])
        showToast("已连接 \(PlatformBrand.shortName(platform))")
        await refreshAccounts()
    }

    func loginCookie(_ platform: String, cookies: [[String: Any]]) async throws {
        let _: Account = try await sidecar.call("accounts.loginCookie", ["platform": platform, "cookies": cookies])
        showToast("已连接 \(PlatformBrand.shortName(platform))")
        await refreshAccounts()
    }

    func logout(_ platform: String) async {
        do {
            setPlatforms(try await sidecar.call("accounts.logout", ["platform": platform]))
        } catch {
            showToast("退出失败：\(error.localizedDescription)")
        }
    }

    // MARK: - 设置

    func setMuted(_ muted: Bool) {
        settings.muted = muted
        feed.muted = muted
        search.player.muted = muted
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

    var catwalk = NotchGeometry.catwalkEnabled

    // MARK: - 猫咪之家（时间 / 天气）

    struct WeatherInfo: Decodable, Equatable {
        let condition: String
        let intensity: Double?
        let text: String
        let temperature: Double?
    }

    var weather: WeatherInfo?
    /// 鼠标在场景里的水平位置（-1~1），驱动视差。
    var roomMouse: CGFloat = 0
    /// 调试：覆盖场景的时间（小时）与天气。
    var sceneOverride: (hour: Double, condition: String)?
    /// 调试：覆盖日期（看季节 / 节日）与天气强度。
    var sceneDateOverride: Date?
    var sceneIntensityOverride: Double?
    private var weatherTask: Task<Void, Never>?
    var location: SceneLocation = LocationProvider.fromTimeZone()
    private let locationProvider = LocationProvider()

    func sceneEnv(now: Date) -> SceneEnv {
        if let o = sceneOverride {
            let start = Calendar.current.startOfDay(for: now)
            return SceneEnv(date: sceneDateOverride ?? start.addingTimeInterval(o.hour * 3600), condition: o.condition, temperature: weather?.temperature,
                            mouse: roomMouse, location: location, intensity: sceneIntensityOverride ?? 0.7)
        }
        return SceneEnv(date: sceneDateOverride ?? now, condition: weather?.condition ?? "partly", temperature: weather?.temperature, mouse: roomMouse,
                        location: location, intensity: weather?.intensity ?? 0.6)
    }

    func setWeatherEnabled(_ on: Bool) {
        settings.weather = on
        Task {
            let _: Settings? = try? await sidecar.call("settings.update", ["weather": on])
            if on { await fetchWeather() } else { weather = nil }
        }
    }

    /// 每 30 分钟取一次天气（sidecar 侧有缓存；设置关闭时返回 null）。
    func startWeather() {
        locationProvider.start { [weak self] loc in
            guard let self else { return }
            let moved = abs(loc.latitude - self.location.latitude) > 0.05 || abs(loc.longitude - self.location.longitude) > 0.05
            self.location = loc
            if moved { Task { await self.fetchWeather() } }
        }
        weatherTask?.cancel()
        weatherTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.fetchWeather()
                try? await Task.sleep(for: .seconds(30 * 60))
                self?.locationProvider.refresh()
            }
        }
    }

    /// 按当前位置取天气（坐标由 sidecar 粗化后再发出）。
    func fetchWeather() async {
        let params: [String: Any] = ["latitude": location.latitude, "longitude": location.longitude]
        do {
            let w: WeatherInfo? = try await sidecar.call("weather.get", params)
            if let w { triggerWeatherEvents(from: weather, to: w) }
            weather = w
            if let w { AppLog.info("weather", ["condition": w.condition, "text": w.text, "temp": w.temperature ?? -1, "city": location.name]) }
        } catch {
            AppLog.warn("weather failed", ["err": error.localizedDescription])
        }
    }

    /// 刘海下方小猫步道开关：存在本机 UserDefaults，改完重算刘海几何。
    func setCatwalk(_ on: Bool) {
        catwalk = on
        UserDefaults.standard.set(on, forKey: NotchGeometry.catwalkKey)
        NotificationCenter.default.post(name: .catlandGeometryChanged, object: nil)
    }

    /// 收起面板回到刘海（例如打开网页登录窗口时，让出屏幕给登录页）。
    func collapsePanel() {
        guard expanded else { return }
        AppLog.info("panel collapsed", ["reason": webLoginActive ? "web login" : "request"])
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            expanded = false
            overlay = .none
        }
    }

    /// 老板键：立刻收起、暂停、静音。
    func bossKey() {
        expanded = false
        overlay = .none
        feed.pauseAll()
        search.player.pauseAll()
    }
}

extension Notification.Name {
    static let catlandGeometryChanged = Notification.Name("app.catland.geometryChanged")
}
