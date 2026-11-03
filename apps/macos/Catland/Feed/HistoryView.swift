// 浏览历史：按天分组的封面瀑布流（和搜索、点赞收藏同一套），点开在 catland 里接着播，往下刷进入推荐流。
// 历史只存在本机（最多 2000 条），右键可删一条，右上角清空。
import SwiftUI

struct HistoryView: View {
    let state: AppState
    @State private var entries: [SavedEntry] = []
    @State private var next: Double?
    @State private var loaded = false
    @State private var loadingMore = false
    /// 清空要点两次：第一次变成「再点一次清空」，3 秒内没点就恢复。
    @State private var confirmClear = false

    private static let pageSize = 60
    private let columnWidth = (NotchGeometry.expandedSize.width - 28 - 8) / 2

    var body: some View {
        ZStack {
            Color(white: 0.07)
            if state.savedPlaying {
                LibraryPlayerView(state: state)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    header
                    if loaded && entries.isEmpty {
                        VStack(spacing: 6) {
                            Text("还没有浏览记录").font(.system(size: 13, weight: .medium))
                            Text("刷过的内容会记在这里，只存在这台 Mac 上").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        list
                    }
                }
                .padding(14)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.9), value: state.savedPlaying)
        .task { await load(reset: true) }
    }

    private var header: some View {
        HStack {
            Text("浏览历史").font(.system(size: 15, weight: .semibold))
            Spacer()
            if !entries.isEmpty {
                Button(action: clear) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash").font(.system(size: 10, weight: .semibold))
                        Text(confirmClear ? "再点一次清空" : "清空").font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(confirmClear ? Color.white : .white.opacity(0.6))
                    .padding(.horizontal, 10).frame(height: 24)
                    .background(Capsule().fill(confirmClear ? Color.red.opacity(0.75) : .white.opacity(0.08)))
                    .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .animation(.easeOut(duration: 0.15), value: confirmClear)
            }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(Self.groups(entries), id: \.title) { g in
                    Text(g.title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    CoverMasonry(items: g.entries.map(CoverItem.init), columnWidth: columnWidth, open: open,
                                 remove: ("从浏览历史中删除", remove))
                }
                if next != nil {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity)
                        .onAppear { Task { await load(reset: false) } }
                }
            }
        }
    }

    private func open(_ item: CoverItem) {
        if let e = entries.first(where: { $0.card.key == item.id }) { state.playSaved(e, title: "浏览历史") }
    }

    private func remove(_ item: CoverItem) {
        withAnimation(.easeOut(duration: 0.2)) { entries.removeAll { $0.card.key == item.id } }
        Task { _ = try? await state.sidecar.callRaw("history.remove", ["key": item.id]) }
    }

    private func clear() {
        guard confirmClear else {
            confirmClear = true
            Task { try? await Task.sleep(for: .seconds(3)); confirmClear = false }
            return
        }
        confirmClear = false
        withAnimation(.easeOut(duration: 0.2)) { entries = []; next = nil }
        Task { _ = try? await state.sidecar.callRaw("history.clear"); state.showToast("已清空浏览历史") }
    }

    private func load(reset: Bool) async {
        guard reset || (next != nil && !loadingMore) else { return }
        loadingMore = true
        defer { loadingMore = false }
        var params: [String: Any] = ["limit": Self.pageSize]
        if !reset, let n = next { params["before"] = Int(n) }
        guard let page: SavedPage = try? await state.sidecar.call("history.list", params) else { loaded = true; return }
        let known = reset ? [] : Set(entries.map(\.card.key))
        entries = (reset ? [] : entries) + page.entries.filter { !known.contains($0.card.key) }
        next = page.next
        loaded = true
    }

    // MARK: - 按天分组

    struct DayGroup { let title: String; let entries: [SavedEntry] }

    static func groups(_ entries: [SavedEntry], now: Date = Date(), calendar: Calendar = .current) -> [DayGroup] {
        var out: [DayGroup] = []
        for e in entries {
            let title = dayTitle(parse(e.at) ?? now, now: now, calendar: calendar)
            if out.last?.title == title { out[out.count - 1] = DayGroup(title: title, entries: out[out.count - 1].entries + [e]) }
            else { out.append(DayGroup(title: title, entries: [e])) }
        }
        return out
    }

    static func dayTitle(_ d: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(d, inSameDayAs: now) { return "今天" }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(d, inSameDayAs: y) { return "昨天" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = calendar.isDate(d, equalTo: now, toGranularity: .year) ? "M月d日 EEEE" : "yyyy年M月d日"
        return f.string(from: d)
    }

    private static func parse(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}
