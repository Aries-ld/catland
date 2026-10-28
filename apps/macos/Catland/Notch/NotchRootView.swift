// 刘海面板根视图：收起（刘海 + 小猫）→ 悬停（下探一行提示）→ 展开（完整刷刷面板）。
import SwiftUI

struct NotchRootView: View {
    let state: AppState

    private var size: CGSize {
        let c = state.notch.collapsedSize
        if state.expanded { return NotchGeometry.expandedSize }
        return state.showingRoom ? CGSize(width: c.width + NotchGeometry.hoverGrow.width, height: c.height + NotchGeometry.hoverGrow.height) : c
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                NotchShape(bottomRadius: state.expanded ? 24 : (state.showingRoom ? 14 : 10)).fill(Color.black)
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
            .clipShape(NotchShape(bottomRadius: state.expanded ? 24 : (state.showingRoom ? 14 : 10)))
            .shadow(color: .black.opacity(state.expanded ? 0.45 : 0), radius: 18, y: 8)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .top) {
            if let t = state.toast {
                // 展开时浮在顶栏下方、收起时贴在刘海下方；原地淡入 + 轻微缩放，不从屏幕顶上「飞」下来。
                Text(t)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
                    .padding(.top, state.expanded ? 58 : size.height + 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
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

/// 收起态：刘海本身是一面像素落地窗，小猫在地面上活动。
/// 悬停时整面窗跟着变大（露出更多海湾和岸边的树，没有黑边），小猫蹦一下，其中一只冒出对话气泡。
struct CollapsedView: View {
    let state: AppState

    private var width: CGFloat { state.notch.collapsedSize.width + (state.showingRoom ? NotchGeometry.hoverGrow.width : 0) }

    /// 猫洞 = 物理刘海所在区域（需要有刘海且开了步道，猫才走得到洞口下方）。
    private var denRect: CatDen? {
        let n = state.notch
        guard n.den, n.hasNotch, n.shelf > 0 else { return nil }
        let left = (width - n.notchSize.width) / 2
        return CatDen(minX: left, maxX: left + n.notchSize.width, bottom: n.notchSize.height)
    }

    /// 悬停时轮播：事件预告 / 倒计时排最前，后面是闲聊 / 时间 / 戳我三类交错；每次悬停换一个随机顺序。
    /// 没悬停但小猫主动探出来时，只说那一句。
    private var bubbles: [String] {
        if !state.hovering { return state.peekMessage.map { [$0] } ?? [] }
        let env = state.sceneEnv(now: Date())
        let region = RestDays.region(for: state.location)
        let events = EventScheduler.bubbleLines(now: env.date, region: region, latitude: state.location.latitude,
                                                condition: env.condition, intensity: env.intensity, seed: state.hoverSession)
        let ctx = BubbleCopy.Context(now: env.date, region: RestDays.region(for: state.location), city: state.location.name,
                                     condition: state.weather?.condition, temperature: state.weather?.temperature,
                                     season: SceneSeason.of(env.date, latitude: state.location.latitude),
                                     speakers: state.speakers, sleeping: state.sleepingCats)
        let host = state.speakers.first { !state.sleepingCats.contains($0) } ?? state.speakers.first ?? .box
        // 推荐流在「休息站」：悬停第一句是还要歇多久
        var rest: [String] = []
        if let p = state.feed.pause, p.mode == .resting, !p.arrived, let r = p.resumeAt, r > env.date {
            rest = [p.speaker.say("还要歇 \(EventScheduler.countdown(r.timeIntervalSince(env.date)))，先去忙吧")]
        }
        return rest + events.map(host.say) + BubbleCopy.rotation(ctx, seed: state.hoverSession)
    }

    var body: some View {
        ZStack {
            IslandScene(state: state)
            // 正常连接的平台，对应的小猫住进来（被风控时打盹）；都没接入时是纸箱里的小奶猫箱箱。
            CatStage(cast: state.speakers,
                     sleeping: state.sleepingCats,
                     hiddenWidth: state.notch.hasNotch && state.notch.shelf == 0 ? state.notch.notchSize.width : 0,
                     excited: state.showingRoom,
                     den: denRect,
                     bubbles: bubbles,
                     bubbleEpoch: state.hoverStartedAt)
            // 还没接平台：小岛轻轻发光，提示点进来
            if state.onboardingHint { OnboardingGlow() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension PlatformBrand {
    static func swiftColor(_ id: String) -> Color {
        let c = color(id)
        return Color(red: c.r, green: c.g, blue: c.b)
    }
}

/// 新手提示：小岛边缘一圈呼吸的粉色光。
struct OnboardingGlow: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
            let phase = (sin(tl.date.timeIntervalSinceReferenceDate * 2.2) + 1) / 2
            NotchShape(bottomRadius: 10)
                .stroke(Color.pink.opacity(0.35 + 0.45 * phase), lineWidth: 2)
                .shadow(color: .pink.opacity(0.6 * phase), radius: 6)
        }
        .allowsHitTesting(false)
    }
}
