// 刘海面板根视图：收起（刘海 + 小猫）→ 悬停（下探一行提示）→ 展开（完整刷刷面板）。
import SwiftUI

struct NotchRootView: View {
    let state: AppState

    private var size: CGSize {
        let c = state.notch.collapsedSize
        if state.expanded { return NotchGeometry.expandedSize }
        return state.hovering ? CGSize(width: c.width + NotchGeometry.hoverGrow.width, height: c.height + NotchGeometry.hoverGrow.height) : c
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                NotchShape(bottomRadius: state.expanded ? 24 : (state.hovering ? 14 : 10)).fill(Color.black)
                if state.expanded {
                    ExpandedPanel(state: state)
                        .padding(.top, state.notch.notchSize.height)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                } else {
                    CollapsedView(state: state)
                        .transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(NotchShape(bottomRadius: state.expanded ? 24 : (state.hovering ? 14 : 10)))
            .shadow(color: .black.opacity(state.expanded ? 0.45 : 0), radius: 18, y: 8)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .top) {
            if let t = state.toast {
                Text(t)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, size.height + 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: state.toast)
        .preferredColorScheme(.dark)
    }
}

/// 顶边贴住屏幕、底部圆角的刘海形状。
struct NotchShape: Shape {
    var bottomRadius: CGFloat
    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        UnevenRoundedRectangle(cornerRadii: .init(topLeading: 0, bottomLeading: bottomRadius, bottomTrailing: bottomRadius, topTrailing: 0), style: .continuous).path(in: rect)
    }
}

/// 收起态：小猫在刘海两侧散步；悬停时下探一行，显示已连接平台与提示。
struct CollapsedView: View {
    let state: AppState

    /// 猫洞 = 物理刘海所在区域（需要有刘海且开了步道，猫才走得到洞口下方）。
    private var denRect: CatDen? {
        let n = state.notch
        guard n.den, n.hasNotch, n.shelf > 0 else { return nil }
        let left = (n.collapsedSize.width - n.notchSize.width) / 2
        return CatDen(minX: left, maxX: left + n.notchSize.width, bottom: n.notchSize.height)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                IslandScene(state: state)
                CatStage(cats: state.notch.shelf > 0 ? 3 : 2,
                         hiddenWidth: state.notch.hasNotch && state.notch.shelf == 0 ? state.notch.notchSize.width : 0,
                         excited: state.hovering,
                         den: denRect)
                    .padding(.bottom, IslandScene.floorInset)
            }
            .frame(width: state.notch.collapsedSize.width, height: state.notch.collapsedSize.height)
            .clipShape(NotchShape(bottomRadius: 10))
            if state.hovering {
                HStack(spacing: 6) {
                    HStack(spacing: -3) {
                        ForEach(state.connectedContentPlatforms.prefix(5)) { p in PlatformIcon(platform: p.id, size: 13) }
                    }
                    Text(state.connectedContentPlatforms.isEmpty ? "点一下，连接平台" : "点一下，开刷")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                    if let w = state.weather, let t = w.temperature {
                        Text("· \(Int(t.rounded()))° \(IslandScene.weatherName(w.condition))").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                    }
                }
                .frame(height: 26)
                .transition(.opacity)
            }
        }
    }
}

extension PlatformBrand {
    static func swiftColor(_ id: String) -> Color {
        let c = color(id)
        return Color(red: c.r, green: c.g, blue: c.b)
    }
}
