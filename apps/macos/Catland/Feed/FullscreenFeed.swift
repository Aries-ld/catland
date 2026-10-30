// 全屏沉浸式刷：在当前屏幕上铺满一个黑底窗口，里面是同一套刷刷卡片（推荐流 / 搜索结果 / 收藏里点开的，都跟着当前在播的那一套）。
// 进入：卡片右侧的全屏按钮或按 F；退出：Esc、再按 F，或右上角的按钮。
import AppKit
import SwiftUI

/// 无边框窗口默认不能成为 key window，接不到键盘；全屏窗口需要接。
final class FullscreenWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

struct FullscreenFeedView: View {
    let state: AppState
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            // 横屏视频铺满整个屏幕宽度；竖屏内容在中间一栏上下铺满（两侧是模糊封面）
            GeometryReader { geo in
                let aspect = state.activeFeed.current?.aspect ?? 9.0 / 16.0
                let w = aspect >= 1 ? geo.size.width : min(geo.size.width, geo.size.height * max(aspect, 9.0 / 16.0) * 1.25)
                FeedView(state: state, feed: state.activeFeed)
                    .frame(width: w, height: geo.size.height)
                    .frame(maxWidth: .infinity)
                    .animation(.easeInOut(duration: 0.25), value: aspect >= 1)
            }
            Button { state.setFullscreen(false) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.right.and.arrow.up.left").font(.system(size: 12, weight: .semibold))
                    Text("退出全屏").font(.system(size: 13, weight: .medium))
                    Text("Esc").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14).frame(height: 34)
                .background(Capsule().fill(.white.opacity(0.12)))
                .contentShape(Capsule())
            }
            .buttonStyle(PressStyle())
            .padding(24)
            .opacity(hovering ? 1 : 0.35)
        }
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.2), value: hovering)
    }
}
