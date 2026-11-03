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
            if c.reviews.playing {
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
        .animation(.spring(response: 0.3, dampingFraction: 0.9), value: c.reviews.playing)
        .animation(.spring(response: 0.3, dampingFraction: 0.9), value: c.detail)
        .task { await c.refreshWishes() }
        .onChange(of: c.query) { _, q in
            if q.trimmingCharacters(in: .whitespaces).isEmpty && !c.submitted.isEmpty { c.clear() }
        }
    }

    @ViewBuilder private var page: some View {
        if let d = c.detail {
            ProductDetailView(product: d, reviews: c.submitted.isEmpty ? [] : reviewItems, wish: c.wish(for: d),
                              priceAt: c.rest != nil ? c.cachedAt : nil,
                              onBack: { c.detail = nil }, onWish: { toggleWish(d) }, onBuy: { c.openInJD(d) }, onReview: play)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        } else if c.submitted.isEmpty {
            CommerceHome(wishes: c.wishes, orders: [], recent: c.recent, rest: c.rest,
                         onRecent: { q in c.query = q; submit() },
                         onOpenWish: { w in c.detail = w.product },
                         onRemoveWish: { w in toggleWish(w.product) })
        } else {
            CommerceResults(query: c.submitted, reviews: reviewItems, products: c.products, wished: c.wishedIDs,
                            rest: c.rest, cachedAt: c.cachedAt, sort: c.sort, loading: c.loading, reviewsLoading: c.reviews.searching, hasMore: c.hasMore,
                            onSort: c.setSort, onOpen: { c.detail = $0 }, onWish: toggleWish, onReview: play,
                            onSearchInJD: { c.searchInJD(c.submitted) }, onLoadMore: c.loadMore)
        }
    }

    /// 点开的测评：和搜索页一样上下刷，左上角返回。
    private var reviewPlayer: some View {
        VStack(spacing: 0) {
            HStack {
                Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { c.reviews.stopPlaying() } } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                        Text("大家怎么说 · \(c.submitted)").font(.system(size: 13, weight: .medium)).lineLimit(1)
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
            FeedView(state: state, feed: c.reviews.player)
        }
    }

    private func submit() {
        c.submit(contentPlatforms: state.searchPlatforms)
    }

    private func play(_ item: CoverItem) {
        guard let hit = c.reviews.hits.first(where: { $0.key == item.id }) else { return }
        state.feed.pauseAll()
        c.reviews.player.muted = state.settings.muted
        c.reviews.play(hit)
    }

    private func toggleWish(_ p: Product) {
        let adding = !c.wishedIDs.contains(p.id)
        Task {
            if let err = await c.toggleWish(p) { state.showToast(err) }
            else if adding { state.showToast("放进心愿单了，箱箱帮你盯着价格") }
        }
    }
}
