// 设置：静音、信息源勾选、快捷键说明、清空浏览历史；以及「我的」点赞 / 收藏列表。
import SwiftUI

struct SettingsView: View {
    let state: AppState

    var body: some View {
        ZStack {
            Color(white: 0.07)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("设置").font(.system(size: 16, weight: .semibold))
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
                    section("小猫") {
                        PillToggle(isOn: state.catwalk, action: { state.setCatwalk(!state.catwalk) }) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("刘海下方小猫步道").font(.system(size: 12))
                                Text("刘海处没有屏幕像素；打开后小猫能从刘海下方走过，会遮住其下约 15pt").font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    section("视频板块的信息源") {
                        if state.connectedContentPlatforms.isEmpty { Text("还没有连接内容平台").font(.system(size: 12)).foregroundStyle(.secondary) }
                        ForEach(state.connectedContentPlatforms) { p in
                            PillToggle(isOn: state.isSourceEnabled(p.id), action: { state.toggleSource(p.id) }) {
                                HStack(spacing: 6) { PlatformBadge(platform: p.id); Text(p.current?.user?.name ?? "").font(.system(size: 12)).foregroundStyle(.secondary) }
                            }
                        }
                    }
                    section("快捷键") {
                        shortcut("⌥ `", "呼出 / 收起")
                        shortcut("⌥ Esc", "老板键：立刻收起并暂停")
                        shortcut("↑ ↓ / J K / 触控板上下滑", "上一条 / 下一条")
                        shortcut("← →", "图集翻页")
                        shortcut("空格", "暂停 / 播放")
                        shortcut("L / S / C / M", "点赞 / 收藏 / 评论 / 静音")
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
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                            ForEach(entries, id: \.card.key) { e in SavedTile(entry: e) }
                        }
                    }
                }
            }
            .padding(14)
        }
        .task(id: kind) {
            let page: SavedPage? = try? await state.sidecar.call("interact.list", ["kind": kind, "limit": 100])
            entries = page?.entries ?? []
        }
    }
}

struct SavedTile: View {
    let entry: SavedEntry
    var body: some View {
        Button {
            if let u = URL(string: entry.card.url) { NSWorkspace.shared.open(u) }
        } label: {
            ZStack(alignment: .bottomLeading) {
                RemoteImage(source: entry.card.cover.map { ImageSource(url: $0, headers: [:], width: nil, height: nil) })
                    .frame(height: 150).clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 3) {
                    PlatformBadge(platform: entry.card.platform)
                    Text(entry.card.title ?? entry.card.text ?? "").font(.system(size: 11)).lineLimit(2).foregroundStyle(.white)
                }
                .padding(8)
            }
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(PressStyle())
    }
}
