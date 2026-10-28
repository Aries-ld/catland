// 入口：菜单栏常驻（无 Dock 图标），刘海面板 + 鼠标 / 键盘 / 触控板事件路由 + 全局快捷键。
import AppKit
import Carbon.HIToolbox
import SwiftUI

@main
enum Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()
    private var panel: NotchPanel!
    private var geometry: NotchGeometry!
    private var statusItem: NSStatusItem!
    private var monitors: [Any] = []
    private var hotKeys: [HotKey] = []
    private let pager = ScrollPager()
    /// 调试：固定展开，点击面板外不收起。
    private var pinned = false
    /// 调试：固定显示猫咪之家（不随鼠标离开收起）。
    private var pinnedHover = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        geometry = NotchGeometry.current(Self.targetScreen())
        state.notch = geometry
        panel = NotchPanel(rootView: NotchRootView(state: state), geometry: geometry)
        panel.orderFrontRegardless()
        setupStatusItem()
        setupMonitors()
        setupHotKeys()
        observeExpanded()
        for name in [NSApplication.didChangeScreenParametersNotification, .catlandGeometryChanged] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.screenChanged() }
            }
        }
        pager.onPage = { [weak self] dir in self?.page(dir) }
        pager.onHorizontal = { [weak self] dir in self?.state.activeFeed.carousel(dir) }
        #if DEBUG
        setupDebugCommands()
        #endif
        Task { await state.start() }
    }

    #if DEBUG
    /// 仅调试构建：通过分布式通知驱动界面，便于自动化截图自检（scripts/catland-debug.swift）。
    private func setupDebugCommands() {
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("app.catland.debug"), object: nil, queue: .main) { [weak self] n in
            let cmd = n.object as? String ?? ""
            MainActor.assumeIsolated {
                guard let self else { return }
                switch cmd {
                case "toggle": self.toggle()
                case "pin": self.pinned = true; if !self.state.expanded { self.toggle() }
                case "unpin": self.pinned = false
                case "hover": self.state.hovering.toggle()
                case "next": self.page(1)
                case "prev": self.page(-1)
                case "right": self.state.activeFeed.carousel(1)
                case "pause": self.state.activeFeed.togglePause()
                case "comments": self.state.commentsOpen.toggle()
                case "connections", "settings", "saved":
                    if !self.state.expanded { self.toggle() }
                    self.state.overlay = AppState.Overlay(rawValue: cmd) ?? .none
                case "close": self.state.overlay = .none
                case "boss": self.state.bossKey()
                case let c where c.hasPrefix("scene:"):
                    // scene:<小时>:<天气>，如 scene:19.2:rain；scene:off 恢复真实时间与天气
                    let parts = c.split(separator: ":")
                    if parts.count == 3, let h = Double(parts[1]) { self.state.sceneOverride = (h, String(parts[2])) } else { self.state.sceneOverride = nil }
                case let c where c.hasPrefix("notch:"):
                    // notch:tunnel / notch:den / notch:both / notch:beam
                    let m = c.dropFirst(6)
                    UserDefaults.standard.set(m == "tunnel" || m == "both", forKey: NotchGeometry.tunnelKey)
                    UserDefaults.standard.set(m == "den" || m == "both", forKey: NotchGeometry.denKey)
                    self.screenChanged()
                case "den": CatDirector.shared.forceDen = true
                case "cats:dump": AppLog.info("cats", CatDirector.shared.debugDump())
                case "search:close": self.state.closeSearch()
                case let c where c.hasPrefix("render:search"):
                    // 离屏渲染搜索首页（不弹出面板），用于检查版式；render:search-edit 渲染编辑历史记录的样子
                    let editing = c.hasSuffix("-edit")
                    self.state.search.editingRecent = editing
                    let view = SearchHome(state: self.state)
                        .frame(width: 384, height: 620, alignment: .top).background(Color(white: 0.04)).environment(\.colorScheme, .dark)
                    let r = ImageRenderer(content: view); r.scale = 2
                    if let cg = r.cgImage, let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
                        try? data.write(to: URL(fileURLWithPath: editing ? "/tmp/search-home-edit.png" : "/tmp/search-home.png"))
                    }
                    self.state.search.editingRecent = false
                case let c where c.hasPrefix("search:filter:"):
                    let f = String(c.dropFirst(14)); self.state.search.filter = f == "all" ? nil : f
                case "search:next": self.page(1)
                case let c where c.hasPrefix("search:play:"):
                    if let i = Int(c.dropFirst(12)), self.state.search.visibleHits.indices.contains(i) { self.state.search.play(self.state.search.visibleHits[i]) }
                case let c where c.hasPrefix("search:"):
                    self.expand(source: "debug")
                    self.state.openSearch()
                    let q = String(c.dropFirst(7))
                    if !q.isEmpty { self.state.search.query = q; self.state.search.submit(platforms: self.state.searchPlatforms) }
                case "cast:off": self.state.castOverride = nil
                case "sleep:off": self.state.sleepOverride = nil
                case let c where c.hasPrefix("sleep:"):
                    self.state.sleepOverride = Set(c.dropFirst(6).split(separator: ",").compactMap { Persona(rawValue: String($0)) })
                case let c where c.hasPrefix("cast:"):
                    self.state.castOverride = c.dropFirst(5).split(separator: ",").compactMap { Persona(rawValue: String($0)) }
                case let c where c.hasPrefix("film:"):
                    let n = SceneSnapshot.film(to: URL(fileURLWithPath: String(c.dropFirst(5))))
                    AppLog.info("film", ["frames": n])
                case let c where c.hasPrefix("snapshots:"):
                    let files = SceneSnapshot.renderAll(to: URL(fileURLWithPath: String(c.dropFirst(10))))
                    AppLog.info("snapshots", ["count": files.count])
                case "weblogin:close": WebLoginController.shared.close()
                case let c where c.hasPrefix("weblogin:"):
                    if let p = self.state.platforms.first(where: { $0.id == String(c.dropFirst(9)) }) { WebLoginController.shared.open(state: self.state, platform: p) }
                case let c where c.hasPrefix("egg:"):
                    let id = String(c.dropFirst(4)); Eggs.forced = id == "none" ? nil : id
                case let c where c.hasPrefix("event:"):
                    // event:<id> 立即开始；event:<id>:<分钟> 在 N 分钟后开始（看预告）；event:none 清除
                    let parts = c.split(separator: ":").map(String.init)
                    if parts.count >= 2, parts[1] == "none" { EventScheduler.extra = [] } else if parts.count >= 2 {
                        let start = self.state.sceneEnv(now: Date()).date.addingTimeInterval((Double(parts.count > 2 ? parts[2] : "0") ?? 0) * 60)
                        EventScheduler.extra = [EventOccurrence(eventID: parts[1], start: start)]
                        self.state.checkEvents()
                    }
                case let c where c.hasPrefix("say:"): self.state.announce(String(c.dropFirst(4)))
                case let c where c.hasPrefix("date:"):
                    // date:2026-12-24T21:00 覆盖日期与时间（看季节 / 节日）；date:off 恢复
                    let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]; f.timeZone = .current
                    self.state.sceneDateOverride = f.date(from: String(c.dropFirst(5)))
                case let c where c.hasPrefix("intensity:"): self.state.sceneIntensityOverride = Double(c.dropFirst(10))
                case "city:shanghai": self.state.location = .shanghai
                case "city:beijing": self.state.location = .beijing
                case "city:singapore": self.state.location = .singapore
                case "ceiling:on", "ceiling:off":
                    UserDefaults.standard.set(cmd == "ceiling:on", forKey: NotchGeometry.ceilingKey)
                    self.screenChanged()
                case "hoverpin": self.state.hovering = true; self.pinnedHover = true
                case "hoverunpin": self.pinnedHover = false
                default: break
                }
            }
        }
    }
    #endif

    func applicationWillTerminate(_ notification: Notification) {
        state.stop()
    }

    /// 优先带刘海的内建屏。
    private static func targetScreen() -> NSScreen {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func screenChanged() {
        geometry = NotchGeometry.current(Self.targetScreen())
        panel.reposition(geometry)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { state.notch = geometry }
    }

    // MARK: - 展开 / 收起

    private func observeExpanded() {
        state.notch = geometry
        withObservationTracking { _ = state.expanded } onChange: { [weak self] in
            Task { @MainActor in
                self?.expandedChanged()
                self?.observeExpanded()
            }
        }
    }

    private func expandedChanged() {
        state.searchPanelChanged(expanded: state.expanded)
        if state.expanded {
            panel.ignoresMouseEvents = false
            panel.makeKey()
            // 搜索页开着但没在播：不恢复推荐流
            if state.savedPlaying || (state.overlay == .none && (!state.search.active || state.search.playing)) { state.activeFeed.resume() }
        } else {
            state.feed.pauseAll()
            state.search.player.pauseAll()
            state.libraryPlayer.pauseAll()
            panel.resignKey()
            updateMouse(NSEvent.mouseLocation)
        }
    }

    func toggle() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { state.expanded.toggle() }
    }

    private func collapse() {
        guard state.expanded else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            state.expanded = false
            state.overlay = .none
        }
    }

    // MARK: - 事件

    private func setupMonitors() {
        // 鼠标位置决定面板是否接收事件：收起态只有刘海区域可交互，其余区域穿透给下面的窗口。
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateMouse(NSEvent.mouseLocation) }
        } as Any)
        // 鼠标移动事件在顶边附近可能来得晚，再用 60Hz 轮询兜底（只比较坐标，开销可忽略）。
        let poll = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.state.expanded else { return }
                self.updateMouse(NSEvent.mouseLocation)
            }
        }
        RunLoop.main.add(poll, forMode: .common)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] e in
            self?.updateMouse(NSEvent.mouseLocation)
            return e
        } as Any)
        // 全局点击：收起态点在刘海区域 → 展开（兜底：鼠标从屏幕顶边直接移入时面板可能还在穿透状态）；
        // 展开态点在面板外 → 收起。
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] e in
            MainActor.assumeIsolated {
                guard let self else { return }
                let p = NSEvent.mouseLocation
                if !self.state.expanded {
                    if e.type == .leftMouseDown, self.geometry.activeRect(expanded: false, hovering: self.state.hovering).contains(p) { self.expand(source: "global-click") }
                    return
                }
                guard !self.geometry.activeRect(expanded: true).contains(p), !self.pinned else { return }
                self.collapse()
            }
        } as Any)
        // 本 App 内的点击：收起态点刘海直接展开，在 AppKit 层处理，不依赖 SwiftUI 手势识别。
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] e in
            guard let self, e.window === self.panel else { return e }
            if self.state.expanded {
                // 诊断：记录点击落在哪个视图上（排查「点不动」）。
                let hit = self.panel.contentView?.hitTest(self.panel.contentView?.convert(e.locationInWindow, from: nil) ?? .zero)
                AppLog.debug("click", ["x": Int(e.locationInWindow.x), "y": Int(e.locationInWindow.y), "hit": hit.map { String(describing: type(of: $0)) } ?? "nil",
                                       "key": self.panel.isKeyWindow, "ignores": self.panel.ignoresMouseEvents])
                return e
            }
            self.expand(source: "click")
            return nil
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] e in
            // 点赞 / 收藏里点开帖子播放时，滚轮也能翻页
            guard let self, self.state.expanded, e.window === self.panel, self.state.overlay == .none || self.state.savedPlaying, !self.state.commentsOpen else { return e }
            // 搜索结果瀑布流自己滚动；只有在播搜索结果时才按页翻
            if self.state.search.active && !self.state.search.playing { return e }
            return self.pager.handle(e) ? nil : e
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] e in
            guard let self, self.state.expanded, e.window === self.panel else { return e }
            return self.handleKey(e) ? nil : e
        } as Any)
    }

    private func expand(source: String) {
        // 网页登录进行中：点刘海是想回到登录窗口，而不是展开刷刷面板。
        if state.webLoginActive, WebLoginController.shared.bringToFront() { return }
        guard !state.expanded else { return }
        AppLog.info("expand", ["source": source])
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { state.expanded = true }
    }

    private func updateMouse(_ p: NSPoint) {
        let inside = geometry.activeRect(expanded: state.expanded, hovering: state.hovering).contains(p)
        if inside && !state.expanded {
            let x = (p.x - geometry.screenFrame.midX) / (geometry.collapsedSize.width / 2)
            if abs(x - state.roomMouse) > 0.02 { state.roomMouse = min(1, max(-1, x)) }
        }
        panel.ignoresMouseEvents = !(inside || state.expanded)
        if pinnedHover { return }
        if state.hovering != inside {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { state.hovering = inside }
        }
    }

    private func page(_ dir: Int) {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            dir > 0 ? state.activeFeed.next() : state.activeFeed.previous()
        }
    }

    /// 键盘：↑↓ / J K 翻页，空格暂停，L 点赞，S 收藏，C 评论，M 静音，Esc 收起。
    private func handleKey(_ e: NSEvent) -> Bool {
        // ⌘F：打开搜索
        if e.modifierFlags.contains(.command), Int(e.keyCode) == kVK_ANSI_F {
            if state.search.playing { state.search.stopPlaying() }
            state.openSearch()
            return true
        }
        if e.modifierFlags.intersection([.command, .control, .option]).isEmpty == false { return false }
        // 正在搜索框里打字：只接管 Esc，其余按键交给输入框
        let typing = panel.firstResponder is NSTextView
        if typing && Int(e.keyCode) != kVK_Escape { return false }
        let feed = state.activeFeed
        let browsingResults = state.search.active && !state.search.playing
        switch Int(e.keyCode) {
        case kVK_Escape:
            if state.commentsOpen { state.commentsOpen = false }
            else if state.savedPlaying { withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { state.stopSaved() } }
            else if state.overlay != .none { state.overlay = .none; state.feed.resume() }
            else if state.search.playing { withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { state.search.stopPlaying() } }
            else if state.search.active { state.closeSearch() }
            else { collapse() }
            return true
        case _ where browsingResults: return false
        case kVK_DownArrow, kVK_ANSI_J: if state.overlay == .none || state.savedPlaying, !state.commentsOpen { page(1) }; return true
        case kVK_UpArrow, kVK_ANSI_K: if state.overlay == .none || state.savedPlaying, !state.commentsOpen { page(-1) }; return true
        case kVK_LeftArrow: feed.carousel(-1); return true
        case kVK_RightArrow: feed.carousel(1); return true
        case kVK_Space: feed.togglePause(); return true
        case kVK_ANSI_M: state.setMuted(!state.settings.muted); return true
        case kVK_ANSI_L: if let c = feed.current { Task { await feed.setInteract(c, kind: "like", on: !(c.liked ?? false)) } }; return true
        case kVK_ANSI_S: if let c = feed.current { Task { await feed.setInteract(c, kind: "collect", on: !(c.collected ?? false)) } }; return true
        case kVK_ANSI_C: withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) { state.commentsOpen.toggle() }; return true
        default: return false
        }
    }

    private func setupHotKeys() {
        // ⌥` 呼出 / 收起；⌥Esc 老板键（立刻收起、暂停）。
        if let h = HotKey(keyCode: kVK_ANSI_Grave, modifiers: optionKey, handler: { [weak self] in self?.toggle() }) { hotKeys.append(h) }
        if let h = HotKey(keyCode: kVK_Escape, modifiers: optionKey, handler: { [weak self] in self?.state.bossKey() }) { hotKeys.append(h) }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let paw = NSImage(named: "MenuBarIcon") {
            paw.isTemplate = true // 模板图：随菜单栏深浅色自动着色
            paw.size = NSSize(width: 18, height: 18)
            statusItem.button?.image = paw
        } else {
            statusItem.button?.title = "🐾"
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "打开 catland（⌥`）", action: #selector(menuToggle), keyEquivalent: "").target = self
        menu.addItem(withTitle: "连接平台…", action: #selector(menuConnections), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 catland", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func menuToggle() { toggle() }

    @objc private func menuConnections() {
        if !state.expanded { toggle() }
        state.overlay = .connections
    }
}

/// 触控板 / 鼠标滚轮 → 翻页：一次手势只翻一页，忽略惯性滚动；横向手势交给图集轮播。
@MainActor
final class ScrollPager {
    var onPage: ((Int) -> Void)?
    var onHorizontal: ((Int) -> Void)?
    private var accY: CGFloat = 0
    private var accX: CGFloat = 0
    private var fired = false
    private var lastWheel = Date.distantPast
    static let threshold: CGFloat = 36

    /// 返回 true 表示事件已消费。
    func handle(_ e: NSEvent) -> Bool {
        if !e.hasPreciseScrollingDeltas {
            // 普通鼠标滚轮：每格翻一页，节流 300ms。
            guard abs(e.scrollingDeltaY) > 0, Date().timeIntervalSince(lastWheel) > 0.3 else { return true }
            lastWheel = Date()
            onPage?(e.scrollingDeltaY < 0 ? 1 : -1)
            return true
        }
        if e.momentumPhase != [] { return true } // 惯性阶段不翻页
        if e.phase == .began || e.phase == .mayBegin { accY = 0; accX = 0; fired = false }
        accY += e.scrollingDeltaY
        accX += e.scrollingDeltaX
        if !fired {
            if abs(accY) > Self.threshold, abs(accY) > abs(accX) {
                fired = true
                onPage?(accY < 0 ? 1 : -1) // 与系统滚动方向一致：内容向上滚 = 下一条
            } else if abs(accX) > Self.threshold * 1.1, abs(accX) > abs(accY) {
                fired = true
                onHorizontal?(accX < 0 ? 1 : -1)
            }
        }
        if e.phase == .ended || e.phase == .cancelled { accY = 0; accX = 0; fired = false }
        return true
    }
}
