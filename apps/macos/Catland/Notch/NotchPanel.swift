// NotchPanel：贴在刘海位置、浮于菜单栏之上的无边框面板，模拟「灵动岛」。
// 窗口固定为展开尺寸，形状由 SwiftUI 绘制；收起时只有刘海区域响应鼠标，其余区域点击穿透。
import AppKit
import SwiftUI

/// 刘海几何：有刘海的屏幕取真实刘海宽高，没有刘海的屏幕退化为顶部居中的胶囊。
struct NotchGeometry: Equatable {
    let screenFrame: CGRect
    let notchSize: CGSize
    let hasNotch: Bool

    static let expandedSize = CGSize(width: 400, height: 720)

    static func current(_ screen: NSScreen) -> NotchGeometry {
        let f = screen.frame
        if screen.safeAreaInsets.top > 0, let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            return NotchGeometry(screenFrame: f, notchSize: CGSize(width: f.width - l.width - r.width, height: screen.safeAreaInsets.top), hasNotch: true)
        }
        return NotchGeometry(screenFrame: f, notchSize: CGSize(width: 180, height: 28), hasNotch: false)
    }

    /// 刘海两侧各留一小段「翅膀」给小猫散步；太宽会压住菜单栏项目。
    static let wing: CGFloat = 30
    var collapsedSize: CGSize { CGSize(width: notchSize.width + Self.wing * 2, height: notchSize.height) }

    var windowFrame: CGRect {
        let s = Self.expandedSize
        return CGRect(x: screenFrame.midX - s.width / 2, y: screenFrame.maxY - s.height, width: s.width, height: s.height)
    }

    /// 屏幕坐标下的可交互区域。
    func activeRect(expanded: Bool) -> CGRect {
        let s = expanded ? Self.expandedSize : collapsedSize
        return CGRect(x: screenFrame.midX - s.width / 2, y: screenFrame.maxY - s.height, width: s.width, height: s.height)
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
        let host = NSHostingView(rootView: rootView)
        host.wantsLayer = true
        host.layer?.backgroundColor = .clear
        contentView = host
    }

    func reposition(_ g: NotchGeometry) {
        setFrame(g.windowFrame, display: true)
    }
}
