// IslandScene：刘海里的像素落地窗。具体画什么全部交给表现层（Catland/Presentation），这里只负责
// 每帧建一块 SceneCanvas（像素网格 + 布局 + 当下的时间 / 天气 / 位置）并按注册表依次绘制。
import SwiftUI

struct IslandScene: View {
    let state: AppState

    /// 地板厚度（美术像素）。小猫站在地板上，CatStage 底部留出这么多空间。
    static let floorRows = 3
    static var floorInset: CGFloat { 0 }

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15)) { tl in
            Canvas { ctx, size in
                let p = max(1, (1.5 * displayScale).rounded()) / max(displayScale, 1)
                Presentation.render(SceneCanvas(ctx: ctx, size: size, p: p, env: state.sceneEnv(now: tl.date),
                                                notch: state.notch, t: tl.date.timeIntervalSinceReferenceDate))
            }
        }
        .allowsHitTesting(false)
    }

    static func weatherName(_ c: String) -> String { WeatherStyle.of(c).name }
}
