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
            ZStack {
                Text(card.stats.comments.map { "\(Format.count($0)) 条评论" } ?? "评论").font(.system(size: 13, weight: .semibold))
                HStack {
                    Spacer()
                    Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) { state.commentsOpen = false } } label: {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                            .frame(width: 28, height: 28).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            Divider().opacity(0.3)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(comments) { c in
                        CommentRow(comment: c, replies: replies[c.id], loading: loadingReplies.contains(c.id), failed: failedReplies.contains(c.id),
                                   toggleReplies: { Task { await loadReplies(c) } }, openOriginal: openOriginal)
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

    /// 图片评论：catbus 不给评论图片，点一下去原帖看。
    private func openOriginal() {
        if let u = URL(string: card.url) { NSWorkspace.shared.open(u) }
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

/// 一条评论（版式对齐抖音 / 小红书）：头像 | 昵称、正文、时间、展开回复 | 右侧竖排的爱心和点赞数；楼中楼缩进显示。
struct CommentRow: View {
    let comment: Comment
    let replies: [Comment]?
    var loading = false
    var failed = false
    let toggleReplies: () -> Void
    let openOriginal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CommentLine(comment: comment, avatar: 32, openOriginal: openOriginal)
            VStack(alignment: .leading, spacing: 10) {
                if let rs = replies, !loading {
                    ForEach(rs) { r in CommentLine(comment: r, avatar: 22, replyTo: replyTarget(r, in: rs), openOriginal: openOriginal) }
                }
                if loading {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("正在加载回复…").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    .transition(.opacity)
                } else if failed {
                    Button("回复加载失败，点击重试", action: toggleReplies).buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.orange)
                } else if let rs = replies, rs.isEmpty {
                    Text("暂时看不到回复").font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                if let r = comment.stats.replies, r > 0 {
                    Button(action: toggleReplies) {
                        HStack(spacing: 6) {
                            Rectangle().fill(.white.opacity(0.2)).frame(width: 18, height: 1)
                            Text(replies == nil ? "展开 \(r) 条回复" : "收起")
                            Image(systemName: replies == nil ? "chevron.down" : "chevron.up").font(.system(size: 8, weight: .bold))
                        }
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.45))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                }
            }
            .padding(.leading, 42)
        }
    }

    /// 楼中楼里回复的不是楼主、而是另一条回复时，显示「▸ 被回复的人」。
    private func replyTarget(_ r: Comment, in rs: [Comment]) -> String? {
        guard let p = r.parentId, p != comment.id else { return nil }
        return rs.first { $0.id == p }?.author?.name
    }
}

/// 评论或回复的一行：头像、昵称（回复别人时带「▸ 某某」）、正文（表情换成 emoji）、时间；右侧爱心和点赞数。
struct CommentLine: View {
    let comment: Comment
    let avatar: CGFloat
    var replyTo: String? = nil
    let openOriginal: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Avatar(name: comment.author?.name ?? "?", size: avatar)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(comment.author?.name ?? "匿名").lineLimit(1)
                    if let t = replyTo {
                        Image(systemName: "arrowtriangle.right.fill").font(.system(size: 6))
                        Text(t).lineLimit(1)
                    }
                }
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                if comment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // 图片 / 表情包评论：catbus 不给图，只给空文字——给一个去原帖看的入口
                    Button(action: openOriginal) {
                        HStack(spacing: 4) {
                            Image(systemName: "photo").font(.system(size: 10))
                            Text("图片评论 · 去原帖看")
                        }
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                        .padding(.horizontal, 8).frame(height: 22)
                        .background(Capsule().fill(.white.opacity(0.08)))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    CommentText.render(replyTo != nil ? CommentText.stripReplyPrefix(comment.text) : comment.text)
                        .font(.system(size: avatar > 24 ? 14 : 13)).foregroundStyle(.white.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                if let t = CommentText.relative(comment.createdAt) {
                    Text(t).font(.system(size: 11)).foregroundStyle(.white.opacity(0.35))
                }
            }
            Spacer(minLength: 8)
            VStack(spacing: 2) {
                Image(systemName: "heart").font(.system(size: 12))
                if let l = comment.stats.likes, l > 0 { Text(Format.count(l)).font(.system(size: 10)) }
            }
            .foregroundStyle(.white.opacity(0.4))
            .frame(width: 28)
        }
    }
}

/// 评论接口不给头像：按昵称生成一个稳定的彩色圆形占位。
struct Avatar: View {
    let name: String
    var size: CGFloat = 28
    var body: some View {
        // hashValue 每次启动随机，换成确定性的字符和。
        let hue = Double(name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % 360) / 360
        Circle().fill(Color(hue: hue, saturation: 0.45, brightness: 0.75)).frame(width: size, height: size)
            .overlay(Text(String(name.prefix(1))).font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(.white))
    }
}
