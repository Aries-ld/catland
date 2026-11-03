// 设置：静音、快捷键说明、导出 / 导入我的数据、清空浏览历史；以及「我的」点赞 / 收藏列表。
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    let state: AppState

    var body: some View {
        ZStack {
            Color(white: 0.07)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("设置").font(.system(size: 16, weight: .semibold))
                    UpdateCard(updater: state.updater)
                    section("播放") {
                        PillToggle(isOn: state.settings.muted, action: { state.setMuted(!state.settings.muted) }) { Text("默认静音").font(.system(size: 12)) }
                    }
                    section("窗外") {
                        HStack(spacing: 6) {
                            Image(systemName: state.location.source == .system ? "location.fill" : "clock").font(.system(size: 10)).foregroundStyle(.secondary)
                            Text("\(state.location.name) · \(state.location.source == .system ? "系统定位" : "按系统时区估计")").font(.system(size: 12))
                            if let w = state.weather {
                                Text("· \(w.temperature.map { "\(Int($0.rounded()))°" } ?? "") \(IslandScene.weatherName(w.condition))").font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                        }
                        PillToggle(isOn: state.settings.weather ?? true, action: { state.setWeatherEnabled(!(state.settings.weather ?? true)) }) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("天气联动").font(.system(size: 12))
                                Text("新加坡用 NEA、其他地区用 Open-Meteo；只发送约 10km 精度的坐标").font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    section("快捷键") {
                        shortcut("⌥ `", "呼出 / 收起")
                        shortcut("⌥ Esc", "老板键：立刻收起并暂停")
                        shortcut("↑ ↓ / J K / 触控板上下滑", "上一条 / 下一条")
                        shortcut("← →", "图集翻页")
                        shortcut("空格", "暂停 / 播放")
                        shortcut("F", "全屏沉浸式刷（Esc 退出）")
                        shortcut("L / S / C / M", "点赞 / 收藏 / 评论 / 静音")
                    }
                    section("新手引导") {
                        Button("重新看一遍新手引导") {
                            state.overlay = .none
                            state.feed.resume()
                            state.onboarding.replay()
                        }
                        .controlSize(.small)
                    }
                    section("我的数据") {
                        Text("把点赞、收藏、浏览历史（含封面）存成一个文件，换 Mac 或备份时导入。不包含登录状态。").font(.system(size: 11)).foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Button("导出…") { exportLibrary() }.controlSize(.small)
                            Button("导入…") { importLibrary() }.controlSize(.small)
                        }
                    }
                    section("版本") {
                        HStack(spacing: 8) {
                            Text("catland \(AppUpdater.currentVersion)").font(.system(size: 12))
                            Spacer()
                            if state.updater.enabled {
                                Button(state.updater.phase == .checking ? "检查中…" : "检查更新") { state.updater.checkNow() }
                                    .controlSize(.small).disabled(state.updater.phase != .idle)
                            } else {
                                Text("调试版不检查更新").font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                        if state.updater.enabled {
                            PillToggle(isOn: state.updater.automaticChecks, action: { state.updater.automaticChecks.toggle() }) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("自动检查更新").font(.system(size: 12))
                                    Text("每天看一次 GitHub 上有没有新版，不发送任何个人信息").font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    section("隐私") {
                        Text("所有数据（点赞、收藏、历史、登录态）只保存在这台电脑上。").font(.system(size: 11)).foregroundStyle(.secondary)
                        Button("清空浏览历史") { Task { _ = try? await state.sidecar.callRaw("history.clear"); state.showToast("已清空浏览历史") } }.controlSize(.small)
                    }
                }
                .padding(18)
            }
        }
    }

    // MARK: - 导出 / 导入

    struct LibraryCounts: Decodable { let likes: Int; let collects: Int; let history: Int; let covers: Int }

    /// 系统存储 / 打开面板要盖过刘海面板（层级更高），并且让 catland 临时变成前台 App 才能接键盘。
    private func present(_ p: NSSavePanel) -> URL? {
        p.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 4)
        NSApp.activate(ignoringOtherApps: true)
        return p.runModal() == .OK ? p.url : nil
    }

    private func exportLibrary() {
        let p = NSSavePanel()
        let day = Date().formatted(.iso8601.year().month().day())
        p.nameFieldStringValue = "catland-我的收藏-\(day).json"
        p.allowedContentTypes = [.json]
        p.message = "导出点赞、收藏和浏览历史（不包含登录状态）"
        guard let url = present(p) else { return }
        Task {
            do {
                let c: LibraryCounts = try await state.sidecar.call("library.export", ["path": url.path])
                state.showToast("已导出 \(c.likes) 条点赞、\(c.collects) 条收藏、\(c.history) 条历史")
                AppLog.info("library export", ["likes": c.likes, "collects": c.collects, "history": c.history, "covers": c.covers])
            } catch {
                state.showToast("导出失败：\(error.localizedDescription)")
            }
        }
    }

    private func importLibrary() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.json]
        p.allowsMultipleSelection = false
        p.message = "选择 catland 导出的文件；已有的不会被覆盖"
        guard let url = present(p) else { return }
        Task {
            do {
                let c: LibraryCounts = try await state.sidecar.call("library.import", ["path": url.path])
                let added = c.likes + c.collects + c.history
                state.showToast(added == 0 ? "没有新内容，都已经在这台 Mac 上了" : "导入了 \(c.likes) 条点赞、\(c.collects) 条收藏、\(c.history) 条历史")
                AppLog.info("library import", ["likes": c.likes, "collects": c.collects, "history": c.history, "covers": c.covers])
            } catch {
                state.showToast("导入失败：\(error.localizedDescription)")
            }
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            content()
        }
    }

    private func shortcut(_ key: String, _ desc: String) -> some View {
        HStack {
            Text(key).font(.system(size: 11, design: .monospaced)).padding(.horizontal, 6).padding(.vertical, 2).background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.08)))
            Text(desc).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}

/// 有新版时显示在设置页最上面：版本号、更新说明、一个「更新」按钮；点了之后显示下载进度，装好自动重启。
struct UpdateCard: View {
    let updater: AppUpdater

    var body: some View {
        switch updater.phase {
        case .idle, .checking: EmptyView()
        case .available(let version, let notes):
            card {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("新版本 \(version)").font(.system(size: 13, weight: .semibold))
                        Text("当前 \(AppUpdater.currentVersion) · 更新后点赞收藏和登录都还在").font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                    Button { updater.install() } label: {
                        Text("更新").font(.system(size: 12, weight: .semibold)).foregroundStyle(.black)
                            .padding(.horizontal, 16).frame(height: 26)
                            .background(Capsule().fill(.white))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressStyle())
                }
                if let notes {
                    Text(notes).font(.system(size: 11)).foregroundStyle(.white.opacity(0.75)).lineLimit(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .downloading(let p):
            card {
                HStack {
                    Text("正在下载新版本…").font(.system(size: 12, weight: .medium))
                    Spacer()
                    if let p { Text("\(Int(p * 100))%").font(.system(size: 11, design: .monospaced)).foregroundStyle(.white.opacity(0.7)) }
                }
                ProgressBar(value: p)
            }
        case .installing:
            card {
                Text("正在安装，马上自动重启…").font(.system(size: 12, weight: .medium))
                ProgressBar(value: nil)
            }
        }
    }

    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 1, green: 0.42, blue: 0.5).opacity(0.28), Color(red: 0.55, green: 0.4, blue: 1).opacity(0.22)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.12)))
    }
}

/// 细进度条；不知道进度时来回滑动。
struct ProgressBar: View {
    let value: Double?

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                if let v = value {
                    Capsule().fill(.white).frame(width: max(4, g.size.width * v))
                } else {
                    TimelineView(.animation) { t in
                        let x = (sin(t.date.timeIntervalSinceReferenceDate * 2.4) + 1) / 2
                        Capsule().fill(.white).frame(width: g.size.width * 0.3).offset(x: x * g.size.width * 0.7)
                    }
                }
            }
        }
        .frame(height: 4)
    }
}

/// 自绘开关：面板不抢焦点时系统开关会显示成「非活跃」灰色，看起来像关着。
struct PillToggle<Label: View>: View {
    let isOn: Bool
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: { withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { action() } }) {
            HStack {
                label()
                Spacer()
                Capsule().fill(isOn ? Color.green : Color.white.opacity(0.18)).frame(width: 34, height: 20)
                    .overlay(alignment: isOn ? .trailing : .leading) { Circle().fill(.white).padding(2).shadow(radius: 1) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SavedView: View {
    let state: AppState
    @State private var kind = "like"
    @State private var entries: [SavedEntry] = []

    var body: some View {
        ZStack {
            Color(white: 0.07)
            if state.savedPlaying {
                LibraryPlayerView(state: state)
            } else {
            VStack(alignment: .leading, spacing: 12) {
                Picker("", selection: $kind) {
                    Text("点赞").tag("like")
                    Text("收藏").tag("collect")
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 160)
                if entries.isEmpty {
                    Text(kind == "like" ? "还没有点赞，刷到喜欢的按 L" : "还没有收藏，刷到想留的按 S").font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        // 和搜索结果同一套封面瀑布流
                        CoverMasonry(items: entries.map(CoverItem.init), columnWidth: (NotchGeometry.expandedSize.width - 28 - 8) / 2) { item in
                            if let e = entries.first(where: { $0.card.key == item.id }) { state.playSaved(e, title: kind == "like" ? "我的点赞" : "我的收藏") }
                        }
                    }
                }
            }
            .padding(14)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.9), value: state.savedPlaying)
        .task(id: kind) {
            let page: SavedPage? = try? await state.sidecar.call("interact.list", ["kind": kind, "limit": 100])
            entries = page?.entries ?? []
        }
    }
}

/// 点赞 / 收藏 / 浏览历史里点开的帖子：在这里直接播放，往下刷接着是推荐流。
struct LibraryPlayerView: View {
    let state: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { state.stopSaved() } } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                        Text(state.savedPlayingTitle).font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 10).frame(height: 28)
                    .background(Capsule().fill(.white.opacity(0.12)))
                    .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                Spacer()
            }
            .padding(.horizontal, 12).frame(height: 40)
            FeedView(state: state, feed: state.libraryPlayer)
        }
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }
}
