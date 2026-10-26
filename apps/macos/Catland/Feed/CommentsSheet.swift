// 评论抽屉：从底部滑出，滚到底自动加载下一页；楼中楼按需展开。只读。
import SwiftUI

struct CommentsSheet: View {
    let state: AppState
    let card: FeedCard
    @State private var comments: [Comment] = []
    @State private var cursor: String?
    @State private var hasMore = true
    @State private var loading = false
    @State private var error: String?
    @State private var replies: [String: [Comment]] = [:]
    /// 正在加载回复的评论：点击后立即展开并显示加载态，接口慢也有即时反馈。
    @State private var loadingReplies: Set<String> = []
    @State private var failedReplies: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(card.stats.comments.map { "\(Format.count($0)) 条评论" } ?? "评论").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) { state.commentsOpen = false } } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                        .frame(width: 28, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            Divider().opacity(0.3)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(comments) { c in
                        CommentRow(comment: c, replies: replies[c.id], loading: loadingReplies.contains(c.id), failed: failedReplies.contains(c.id)) { Task { await loadReplies(c) } }
                    }
                    if loading { ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding() }
                    if let e = error { Text(e).font(.system(size: 11)).foregroundStyle(.secondary).frame(maxWidth: .infinity) }
                    if !hasMore && !comments.isEmpty { Text("没有更多了").font(.system(size: 11)).foregroundStyle(.tertiary).frame(maxWidth: .infinity).padding(.bottom, 8) }
                    if !loading && comments.isEmpty && error == nil && !hasMore { Text("还没有评论").font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 40) }
                    Color.clear.frame(height: 1).onAppear { Task { await loadMore() } }
                }
                .padding(16)
            }
        }
        .background(Color(white: 0.09).opacity(0.98)) // 实底：盖在浅色图片上也保证白字可读
        .clipShape(UnevenRoundedRectangle(cornerRadii: .init(topLeading: 16, topTrailing: 16), style: .continuous))
        .task(id: card.key) {
            comments = []
            cursor = nil
            hasMore = true
            await loadMore()
        }
    }

    private func loadMore() async {
        guard hasMore, !loading else { return }
        loading = true
        defer { loading = false }
        var params: [String: Any] = ["key": card.key]
        if let cursor { params["cursor"] = cursor }
        do {
            let page: CommentPage = try await state.sidecar.call("comments.list", params)
            let known = Set(comments.map(\.id))
            comments += page.comments.filter { !known.contains($0.id) }
            cursor = page.cursor
            hasMore = page.hasMore && !page.comments.isEmpty
            error = nil
        } catch let e as RPCError where e.appCode == "RISK_CONTROL" {
            error = "平台要求验证，过一会儿再看评论"
            hasMore = false
        } catch {
            self.error = "评论加载失败"
            hasMore = false
        }
    }

    private func loadReplies(_ c: Comment) async {
        // 已展开（含加载中）再点一次就收起。
        if replies[c.id] != nil, !failedReplies.contains(c.id) {
            withAnimation(.easeOut(duration: 0.15)) { replies[c.id] = nil }
            loadingReplies.remove(c.id)
            return
        }
        withAnimation(.easeOut(duration: 0.15)) {
            replies[c.id] = []
            loadingReplies.insert(c.id)
            failedReplies.remove(c.id)
        }
        let page: CommentPage? = try? await state.sidecar.call("comments.replies", ["key": card.key, "commentId": c.id])
        guard loadingReplies.contains(c.id) else { return } // 加载期间被收起
        withAnimation(.easeOut(duration: 0.2)) {
            loadingReplies.remove(c.id)
            if let page { replies[c.id] = page.comments } else { failedReplies.insert(c.id) }
        }
    }
}

struct CommentRow: View {
    let comment: Comment
    let replies: [Comment]?
    var loading = false
    var failed = false
    let toggleReplies: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Avatar(name: comment.author?.name ?? "?")
            VStack(alignment: .leading, spacing: 4) {
                Text(comment.author?.name ?? "匿名").font(.system(size: 11)).foregroundStyle(.secondary)
                Text(comment.text).font(.system(size: 13)).textSelection(.enabled)
                HStack(spacing: 12) {
                    if let l = comment.stats.likes, l > 0 { Label(Format.count(l), systemImage: "heart").font(.system(size: 10)).foregroundStyle(.secondary) }
                    if let r = comment.stats.replies, r > 0 {
                        Button(action: toggleReplies) {
                            HStack(spacing: 3) {
                                Image(systemName: replies == nil ? "chevron.down" : "chevron.up").font(.system(size: 8, weight: .bold))
                                Text(replies == nil ? "展开 \(r) 条回复" : "收起")
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle()).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    }
                }
                if loading {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("正在加载回复…").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    .padding(.leading, 4)
                    .transition(.opacity)
                } else if failed {
                    Button("回复加载失败，点击重试", action: toggleReplies).buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.orange)
                } else if let rs = replies, rs.isEmpty {
                    Text("暂时看不到回复").font(.system(size: 11)).foregroundStyle(.tertiary).padding(.leading, 4)
                }
                if let rs = replies, !loading {
                    ForEach(rs) { r in
                        HStack(alignment: .top, spacing: 6) {
                            Text(r.author?.name ?? "匿名").font(.system(size: 11)).foregroundStyle(.secondary)
                            Text(r.text).font(.system(size: 12))
                        }
                    }
                    .padding(.leading, 4)
                }
            }
        }
    }
}

/// 评论接口不给头像：按昵称生成一个稳定的彩色圆形占位。
struct Avatar: View {
    let name: String
    var body: some View {
        // hashValue 每次启动随机，换成确定性的字符和。
        let hue = Double(name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % 360) / 360
        Circle().fill(Color(hue: hue, saturation: 0.45, brightness: 0.75)).frame(width: 28, height: 28)
            .overlay(Text(String(name.prefix(1))).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white))
    }
}
