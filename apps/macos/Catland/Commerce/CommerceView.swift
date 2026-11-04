// 电商板块（顶栏「电商」）：搜索框 + 首页（最近搜索、心愿单）/ 搜索结果（大家怎么说 + 京东）/ 商品页；点开测评在这里接着刷。
import SwiftUI

struct CommerceView: View {
    let state: AppState

    private var c: CommerceController { state.commerce }
    private var jdConnected: Bool { state.platforms.first { $0.id == "jd" }.map { $0.connected && $0.health != "expired" } ?? false }
    private var reviewItems: [CoverItem] { c.reviews.hits.map(CoverItem.init) }

    var body: some View {
        ZStack {
            Color(white: 0.07)
            if c.playing {
                reviewPlayer.transition(.move(edge: .trailing).combined(with: .opacity))
            } else if !jdConnected || c.needsLogin {
                StatusView(text: "先连接京东", detail: "登录一次就好，之后搜商品、盯价格都在这台 Mac 上完成",
                           action: ("连接京东", { state.overlay = .connections }))
            } else {
                VStack(spacing: 0) {
                    CommerceSearchBar(query: c.query, text: Bindable(c).query, onSubmit: submit, onClear: { c.query = ""; c.clear() })
                        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 10)
                    ScrollView { page.padding(.horizontal, 14).padding(.bottom, 14) }
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.9), value: c.playing)
        .animation(.spring(response: 0.3, dampingFraction: 0.9), value: c.detail)
        .task { await c.refreshWishes() }
        .onChange(of: c.query) { _, q in
            if q.trimmingCharacters(in: .whitespaces).isEmpty && !c.submitted.isEmpty { c.clear() }
        }
    }

    @ViewBuilder private var page: some View {
        if let d = c.detail {
            ProductDetailView(product: d, reviews: c.detailReviews.visibleHits.map(CoverItem.init), wish: c.wish(for: d),
                              priceAt: c.rest != nil ? c.cachedAt : nil,
                              reviewsTitle: c.detailMatch.map { "「\($0.query)」的测评" } ?? "大家怎么说",
                              reviewsNote: reviewsNote,
                              onBack: { c.detail = nil }, onWish: { toggleWish(d) }, onBuy: { c.openInJD(d) },
                              onReview: { playDetail($0) })
                .transition(.move(edge: .trailing).combined(with: .opacity))
        } else if c.submitted.isEmpty {
            CommerceHome(wishes: c.wishes, orders: [], recent: c.recent, rest: c.rest,
                         onRecent: { q in c.query = q; submit() },
                         onOpenWish: { w in c.openDetail(w.product, contentPlatforms: state.searchPlatforms) },
                         onRemoveWish: { w in toggleWish(w.product) })
        } else {
            CommerceResults(query: c.submitted, reviews: reviewItems, products: c.products, wished: c.wishedIDs,
                            rest: c.rest, cachedAt: c.cachedAt, sort: c.sort, loading: c.loading, reviewsLoading: c.reviews.searching, hasMore: c.hasMore, failed: c.failed, onRetry: c.retry,
                            onSort: c.setSort, onOpen: { c.openDetail($0, contentPlatforms: state.searchPlatforms) }, onWish: toggleWish, onReview: play,
                            onSearchInJD: { c.searchInJD(c.submitted) }, onLoadMore: c.loadMore)
        }
    }

    /// 点开的测评：和搜索页一样上下刷，左上角返回。
    private var reviewPlayer: some View {
        VStack(spacing: 0) {
            HStack {
                Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { c.stopPlaying() } } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                        Text("测评 · \(c.playingTitle)").font(.system(size: 13, weight: .medium)).lineLimit(1)
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
            FeedView(state: state, feed: c.player)
        }
    }

    private func submit() {
        c.submit(contentPlatforms: state.searchPlatforms)
    }

    private func play(_ item: CoverItem) {
        guard let hit = c.reviews.hits.first(where: { $0.key == item.id }) else { return }
        state.feed.pauseAll()
        c.setMuted(state.settings.muted)
        c.reviews.play(hit)
    }

    private func playDetail(_ item: CoverItem) {
        guard let hit = c.detailReviews.visibleHits.first(where: { $0.key == item.id }) else { return }
        state.feed.pauseAll()
        c.setMuted(state.settings.muted)
        c.detailReviews.play(hit)
    }

    /// 商品页测评区的说明：正在找 / 没找到这一款 / 认不出型号只能宽泛地找
    private var reviewsNote: String? {
        let r = c.detailReviews
        if r.searching && r.visibleHits.isEmpty { return "正在找这一款的测评…" }
        if r.visibleHits.isEmpty { return "暂时没找到这一款的测评" }
        if c.detailMatch?.specific == false { return "这件商品没写型号，下面是同品牌同品类的测评" }
        return nil
    }

    private func toggleWish(_ p: Product) {
        let adding = !c.wishedIDs.contains(p.id)
        Task {
            if let err = await c.toggleWish(p) { state.showToast(err) }
            else if adding { state.showToast("放进心愿单了，箱箱帮你盯着价格") }
        }
    }
}
