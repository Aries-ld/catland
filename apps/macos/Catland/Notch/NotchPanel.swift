// NotchPanel：贴在刘海位置、浮于菜单栏之上的无边框面板，模拟「灵动岛」。
// 窗口固定为展开尺寸，形状由 SwiftUI 绘制；收起时只有刘海区域响应鼠标，其余区域点击穿透。
import AppKit
import SwiftUI

/// 刘海几何：有刘海的屏幕取真实刘海宽高，没有刘海的屏幕退化为顶部居中的胶囊。
struct NotchGeometry: Equatable {
    let screenFrame: CGRect
    let notchSize: CGSize
    let hasNotch: Bool
    /// 刘海下方的小猫步道高度（0 = 关闭）。物理刘海处没有像素，步道让小猫能从刘海下面走过去。
    var shelf: CGFloat = 0

    static let shelfHeight: CGFloat = 15
    static let catwalkKey = "catwalk"
    static var catwalkEnabled: Bool { UserDefaults.standard.object(forKey: catwalkKey) as? Bool ?? true }
    /// 天花板模式：刘海融进整条黑色天花板，窗户在下方，步道需要更高才放得下窗外的楼。
    static let ceilingKey = "notchCeiling"
    static var ceilingEnabled: Bool { UserDefaults.standard.object(forKey: ceilingKey) as? Bool ?? false }
    static let ceilingShelfHeight: CGFloat = 27
    var ceiling = false
    /// 刘海创意：tunnel = 刘海是地铁隧道口，MRT 小列车从中穿过；den = 刘海是猫洞，小猫钻进钻出。
    static let tunnelKey = "notchTunnel", denKey = "notchDen"
    static var tunnelEnabled: Bool { UserDefaults.standard.object(forKey: tunnelKey) as? Bool ?? true }
    static var denEnabled: Bool { UserDefaults.standard.object(forKey: denKey) as? Bool ?? true }
    var tunnel = false
    var den = false

    static let expandedSize = CGSize(width: 400, height: 720)

    static func current(_ screen: NSScreen) -> NotchGeometry {
        let f = screen.frame
        if screen.safeAreaInsets.top > 0, let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            return NotchGeometry(screenFrame: f, notchSize: CGSize(width: f.width - l.width - r.width, height: screen.safeAreaInsets.top), hasNotch: true,
                                 shelf: ceilingEnabled ? ceilingShelfHeight : (catwalkEnabled ? shelfHeight : 0), ceiling: ceilingEnabled,
                                 tunnel: tunnelEnabled && !ceilingEnabled, den: denEnabled && !ceilingEnabled)
        }
        return NotchGeometry(screenFrame: f, notchSize: CGSize(width: 180, height: 28), hasNotch: false, shelf: catwalkEnabled ? shelfHeight : 0)
    }

    /// 悬停时面板下探的尺寸（与 NotchRootView 一致）。
    static let hoverGrow = CGSize(width: 24, height: 28)

    /// 刘海两侧各留一小段「翅膀」给小猫散步；太宽会压住菜单栏项目。
    static let wing: CGFloat = 36
    var collapsedSize: CGSize { CGSize(width: notchSize.width + Self.wing * 2, height: notchSize.height + shelf) }

    var windowFrame: CGRect {
        let s = Self.expandedSize
        return CGRect(x: screenFrame.midX - s.width / 2, y: screenFrame.maxY - s.height, width: s.width, height: s.height)
    }

    /// 屏幕坐标下的可交互区域。向上多留几个点：鼠标顶到屏幕最上沿时 y 可能等于 maxY。
    func activeRect(expanded: Bool, hovering: Bool = false) -> CGRect {
        var s = expanded ? Self.expandedSize : collapsedSize
        if !expanded && hovering { s = CGSize(width: s.width + Self.hoverGrow.width, height: s.height + Self.hoverGrow.height) }
        return CGRect(x: screenFrame.midX - s.width / 2, y: screenFrame.maxY - s.height, width: s.width, height: s.height + 4)
    }

}

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(rootView: some View, geometry: NotchGeometry) {
        super.init(contentRect: geometry.windowFrame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = true
        let host = FirstMouseHostingView(rootView: AnyView(rootView))
        host.wantsLayer = true
        host.layer?.backgroundColor = .clear
        contentView = host
    }

    func reposition(_ g: NotchGeometry) {
        setFrame(g.windowFrame, display: true)
    }
}

/// 纯展示的 AppKit 视图（如视频画面）：不应接收任何点击。
protocol DisplayOnlyView: NSView {}

/// 面板不抢焦点：默认第一次点击只会激活窗口而不传给内容，导致「点了没反应」。
final class FirstMouseHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// SwiftUI 会给 NSViewRepresentable 包一层容器（PlatformGroupContainer），AppKit 命中测试时它会抢在
    /// 叠在上面的 SwiftUI 按钮之前接到点击——视频铺满时，右侧点赞 / 收藏 / 评论就「点不动」。
    /// 命中的是纯展示视图（或只包着它的容器）时，把点击交还给 SwiftUI 自己分发。
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        return Self.isDisplayOnly(hit) ? self : hit
    }

    static func isDisplayOnly(_ v: NSView) -> Bool {
        if v is DisplayOnlyView { return true }
        // 只包着展示视图的容器（SwiftUI 的 PlatformGroupContainer 等）
        return !v.subviews.isEmpty && v.subviews.allSatisfy { isDisplayOnly($0) }
    }
}
