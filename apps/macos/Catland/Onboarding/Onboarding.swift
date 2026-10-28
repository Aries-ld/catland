// 新手引导（线框稿 docs/design/v0.3-onboarding*.png）：
// 0 启动：没接平台时箱箱在小岛里招手（气泡 + 小岛发光），点开是欢迎页，先接一个平台；
// 接上、开始刷之后，3 步高亮讲解核心操作：上下滑换一条 → 一次搜遍 → 老板键。
// 每步周围压暗、只亮出目标，气泡里由一只猫讲解；「下一步」「跳过」都行，做了真实操作也会自动进入下一步。
// 只出现一次（新用户第一次开刷时）；老用户不弹；设置里可以重看。
import AppKit
import Observation
import SwiftUI

/// 需要高亮的界面元素。
enum CoachTarget: Hashable { case card, search }

struct CoachAnchorKey: PreferenceKey {
    static let defaultValue: [CoachTarget: Anchor<CGRect>] = [:]
    static func reduce(value: inout [CoachTarget: Anchor<CGRect>], nextValue: () -> [CoachTarget: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// 标记一个可以被新手引导高亮的元素。
    func coachAnchor(_ t: CoachTarget) -> some View {
        anchorPreference(key: CoachAnchorKey.self, value: .bounds) { [t: $0] }
    }
}

@MainActor
@Observable
final class Onboarding {
    static let doneKey = "onboardingDone"

    /// 当前讲到第几步（nil = 没在讲）。
    private(set) var step: Int?
    private(set) var done: Bool
    static let total = 3

    init() {
        done = UserDefaults.standard.bool(forKey: Self.doneKey)
    }

    /// 第一次拿到平台列表：已经接过平台的老用户直接视为看过，不弹引导。
    func noteFirstPlatforms(connected: Bool) {
        guard UserDefaults.standard.object(forKey: Self.doneKey) == nil else { return }
        if connected { markDone() }
        else { UserDefaults.standard.set(false, forKey: Self.doneKey) }
    }

    /// 开刷且有内容时开始讲（只讲一次）。
    func startIfNeeded() {
        guard !done, step == nil else { return }
        step = 0
        AppLog.info("onboarding start")
    }

    func next() {
        guard let s = step else { return }
        if s + 1 >= Self.total { finish() } else { step = s + 1 }
    }

    /// 做了真实操作：正好在讲这一步就进入下一步。
    func advance(from s: Int) {
        if step == s { next() }
    }

    func skip() {
        AppLog.info("onboarding skipped", ["step": step ?? -1])
        step = nil
        markDone()
    }

    func finish() {
        AppLog.info("onboarding finished")
        step = nil
        markDone()
    }

    /// 设置里「重新看一遍新手引导」。
    func replay() {
        done = false
        step = 0
    }

    private func markDone() {
        done = true
        UserDefaults.standard.set(true, forKey: Self.doneKey)
    }
}

/// 高亮浮层：压暗整个面板，只亮出目标元素，旁边一个说明气泡。点压暗区域不会退出（免得误触）。
struct CoachMarksOverlay: View {
    let state: AppState
    let anchors: [CoachTarget: Anchor<CGRect>]
    /// 离屏渲染用：指定显示第几步（不改动真实的引导进度）。
    var forcedStep: Int? = nil

    private struct Step {
        let target: CoachTarget?
        let persona: Persona
        let title: String
        let body: String
    }

    private var steps: [Step] {
        let cats = state.speakers.filter { $0 != .box }
        func cat(_ i: Int) -> Persona { cats.isEmpty ? .box : cats[i % cats.count] }
        return [
            Step(target: .card, persona: cat(0), title: "上下滑，换一条", body: "触控板、滚轮、↑↓ 都行；双击点赞\n点赞收藏只存在你的 Mac 上，不会同步回原平台"),
            Step(target: .search, persona: cat(1), title: "一次搜遍几个平台", body: "点放大镜或按 ⌘F\n猫们会分头去各个平台帮你找"),
            Step(target: nil, persona: cat(2), title: "老板来了？⌥ Esc", body: "一键收起小岛、暂停视频\n点小岛外面也能收起，随时回来接着刷"),
        ]
    }

    var body: some View {
        if let i = forcedStep ?? state.onboarding.step, steps.indices.contains(i) {
            GeometryReader { proxy in
                let step = steps[i]
                let hole = step.target.flatMap { anchors[$0] }.map { proxy[$0].insetBy(dx: -4, dy: -4) }
                ZStack(alignment: .topLeading) {
                    dimming(hole: hole, size: proxy.size)
                    bubble(step, index: i)
                        .frame(width: min(320, proxy.size.width - 32))
                        .position(bubblePosition(hole: hole, size: proxy.size))
                }
            }
            .transition(.opacity)
        }
    }

    private func dimming(hole: CGRect?, size: CGSize) -> some View {
        ZStack {
            Color.black.opacity(0.62)
                .mask {
                    ZStack {
                        Rectangle()
                        if let h = hole {
                            RoundedRectangle(cornerRadius: h.height > 100 ? 18 : 10, style: .continuous)
                                .frame(width: h.width, height: h.height)
                                .position(x: h.midX, y: h.midY)
                                .blendMode(.destinationOut)
                        }
                    }
                    .compositingGroup()
                }
            if let h = hole {
                RoundedRectangle(cornerRadius: h.height > 100 ? 18 : 10, style: .continuous)
                    .stroke(Color.pink, lineWidth: 2)
                    .shadow(color: .pink.opacity(0.8), radius: 6)
                    .frame(width: h.width, height: h.height)
                    .position(x: h.midX, y: h.midY)
                    .allowsHitTesting(false)
            }
        }
        // 吞掉压暗区域的点击（误触不退出）；滚轮翻页走全局监听，不受影响
        .contentShape(Rectangle())
        .onTapGesture {}
    }

    /// 大目标（卡片）把气泡放在中间；小目标（按钮）放在它下方，靠右对齐；没有目标时居中。
    private func bubblePosition(hole: CGRect?, size: CGSize) -> CGPoint {
        guard let h = hole else { return CGPoint(x: size.width / 2, y: size.height * 0.45) }
        if h.height > size.height * 0.5 { return CGPoint(x: size.width / 2, y: h.midY - 40) }
        let w = min(320, size.width - 32)
        let x = min(max(w / 2 + 16, h.midX), size.width - w / 2 - 16)
        return CGPoint(x: x, y: h.maxY + 80)
    }

    private func bubble(_ step: Step, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                CatSprite(skin: step.persona.skin, action: "sit", scale: 2.5)
                VStack(alignment: .leading, spacing: 5) {
                    Text(step.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(white: 0.1))
                    Text(step.body).font(.system(size: 11)).foregroundStyle(Color(white: 0.38)).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 5) {
                ForEach(0..<Onboarding.total, id: \.self) { k in
                    Circle().fill(k == index ? Color.pink : Color(white: 0.82)).frame(width: 6, height: 6)
                }
                Spacer()
                if index < Onboarding.total - 1 {
                    Button("跳过") { withAnimation { state.onboarding.skip() } }
                        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Color(white: 0.55))
                }
                Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { state.onboarding.next() } } label: {
                    Text(index == Onboarding.total - 1 ? "开刷" : "下一步")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(white: 0.1))
                        .padding(.horizontal, 14).frame(height: 26)
                        .background(Capsule().fill(Color.pink))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white))
        .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
    }
}

/// 欢迎页（还没接任何平台时）：先讲清能干嘛，再选一个平台接上；登录在面板里完成。
struct OnboardingWelcome: View {
    let state: AppState
    /// 离屏渲染时不包 ScrollView（ImageRenderer 画不出滚动视图）。
    var scrollable = true

    private var platforms: [PlatformState] {
        let order = ["xhs", "douyin", "bilibili", "kuaishou"]
        return order.compactMap { id in state.platforms.first { $0.id == id && $0.unavailable == nil } }
    }

    var body: some View {
        if scrollable { ScrollView { content } } else { content }
    }

    private var content: some View {
            VStack(spacing: 14) {
                ZStack(alignment: .bottom) {
                    CatSprite(skin: Persona.box.skin, action: "look", scale: 5)
                    RoundedRectangle(cornerRadius: 3).fill(Color(red: 0.78, green: 0.58, blue: 0.36)).frame(width: 66, height: 18)
                }
                .padding(.top, 18)
                Text("把你常刷的 App 接回家").font(.system(size: 18, weight: .semibold))
                Text("接上后就能在这儿刷小红书、抖音、B 站、快手，还能一次搜遍\n登录信息只存在你的 Mac 上")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).multilineTextAlignment(.center)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(platforms) { p in card(p) }
                }
                .padding(.top, 4)
                if let first = platforms.first {
                    Button { connect(first) } label: {
                        Text("先接\(PlatformBrand.shortName(first.id))").font(.system(size: 14, weight: .semibold)).foregroundStyle(.black)
                            .frame(maxWidth: .infinity).frame(height: 40)
                            .background(Capsule().fill(Color.pink))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressStyle())
                }
                Button("跳过引导") { state.onboarding.skip(); state.overlay = .connections }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.white.opacity(0.45))
            }
            .padding(.horizontal, 16).padding(.bottom, 16)
    }

    private func card(_ p: PlatformState) -> some View {
        Button { connect(p) } label: {
            VStack(alignment: .leading, spacing: 8) {
                if let persona = Persona.forPlatform(p.id) {
                    CatSprite(skin: persona.skin, action: "idle", scale: 3.5).frame(maxWidth: .infinity)
                }
                HStack(spacing: 6) {
                    PlatformIcon(platform: p.id, size: 18)
                    Text(PlatformBrand.shortName(p.id)).font(.system(size: 14, weight: .medium))
                }
                Text(p.primaryLogin == "qrcode" ? "手机扫码 10 秒" : "官方页面登录").font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.06)))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressStyle())
    }

    /// 和「连接」页同一套登录：扫码平台在面板里显示二维码，抖音打开官方登录页。
    private func connect(_ p: PlatformState) {
        state.overlay = .connections
        if p.primaryLogin == "qrcode" { Task { await state.loginQrcode(p.id) } }
        else { WebLoginController.shared.open(state: state, platform: p) }
    }
}
