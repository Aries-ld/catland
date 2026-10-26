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

    static let expandedSize = CGSize(width: 400, height: 720)

    static func current(_ screen: NSScreen) -> NotchGeometry {
        let f = screen.frame
        if screen.safeAreaInsets.top > 0, let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            return NotchGeometry(screenFrame: f, notchSize: CGSize(width: f.width - l.width - r.width, height: screen.safeAreaInsets.top), hasNotch: true,
                                 shelf: catwalkEnabled ? shelfHeight : 0)
        }
        return NotchGeometry(screenFrame: f, notchSize: CGSize(width: 180, height: 28), hasNotch: false, shelf: catwalkEnabled ? shelfHeight : 0)
    }

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

    /// 悬停时面板下探的尺寸（与 NotchRootView 一致）。
    static let hoverGrow = CGSize(width: 24, height: 28)
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

/// 面板不抢焦点：默认第一次点击只会激活窗口而不传给内容，导致「点了没反应」。
final class FirstMouseHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
