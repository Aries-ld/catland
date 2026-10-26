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

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(card.stats.comments.map { "\(Format.count($0)) 条评论" } ?? "评论").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) { state.commentsOpen = false } } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            Divider().opacity(0.3)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(comments) { c in
                        CommentRow(comment: c, replies: replies[c.id]) { Task { await loadReplies(c) } }
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
        guard replies[c.id] == nil else { return replies[c.id] = nil }
        if let page: CommentPage = try? await state.sidecar.call("comments.replies", ["key": card.key, "commentId": c.id]) {
            replies[c.id] = page.comments
        } else {
            replies[c.id] = []
        }
    }
}

struct CommentRow: View {
    let comment: Comment
    let replies: [Comment]?
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
                        Button(replies == nil ? "展开 \(r) 条回复" : "收起", action: toggleReplies).buttonStyle(.plain).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    }
                }
                if let rs = replies {
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
