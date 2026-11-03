// 面板 / 全屏里的按键路由：只根据当前界面状态决定做什么，不碰界面本身，便于回归测试。
import Carbon.HIToolbox

struct KeyContext: Equatable {
    var fullscreen = false
    var commentsOpen = false
    var onboarding = false
    var savedPlaying = false
    var searchActive = false
    var searchPlaying = false
    /// 焦点在输入框里（搜索框打字）
    var typing = false
    var overlay: AppState.Overlay = .none
    /// 在电商板块里浏览（没在播测评）
    var commerceBrowsing = false
    /// 在电商板块里播测评
    var commercePlaying = false
    /// 电商的商品页或搜索结果开着：Esc 退一层
    var commerceBack = false
    var command = false
    /// ⌃ / ⌥ 等其他修饰键
    var otherModifiers = false

    var browsingResults: Bool { (searchActive && !searchPlaying) || commerceBrowsing }
    /// 能翻页：没开着设置等浮层（点赞收藏里点开在播的除外），评论也没开。
    var canPage: Bool { (overlay == .none || savedPlaying) && !commentsOpen }
}

enum KeyAction: Equatable {
    /// 不处理，交给系统 / 输入框
    case pass
    /// 吃掉按键但什么也不做（比如开着评论时按 ↓）
    case consume
    case openSearch, toggleFullscreen, exitFullscreen, skipOnboarding
    case closeComments, stopSaved, closeOverlay, stopSearchPlaying, closeSearch, collapse
    case stopCommercePlaying, commerceBack
    case page(Int), carousel(Int)
    case togglePause, toggleMute, like, collect, toggleComments
}

enum KeyRouter {
    /// ↑↓ / J K 翻页，←→ 图集，空格暂停，L 点赞，S 收藏，C 评论，M 静音，F 全屏，⌘F 搜索；Esc 按层级逐级退出。
    static func route(_ keyCode: Int, _ c: KeyContext) -> KeyAction {
        if c.command, keyCode == kVK_ANSI_F { return .openSearch }
        if c.command || c.otherModifiers { return .pass }
        if c.typing && keyCode != kVK_Escape { return .pass }
        switch keyCode {
        case kVK_Escape where c.fullscreen && !c.commentsOpen: return .exitFullscreen
        case kVK_ANSI_F where !c.browsingResults || c.fullscreen: return .toggleFullscreen
        case kVK_Escape where c.onboarding: return .skipOnboarding
        case kVK_Escape:
            if c.commentsOpen { return .closeComments }
            if c.savedPlaying { return .stopSaved }
            if c.overlay != .none { return .closeOverlay }
            if c.searchPlaying { return .stopSearchPlaying }
            if c.searchActive { return .closeSearch }
            if c.commercePlaying { return .stopCommercePlaying }
            if c.commerceBack { return .commerceBack }
            return .collapse
        case _ where c.browsingResults: return .pass
        case kVK_DownArrow, kVK_ANSI_J: return c.canPage ? .page(1) : .consume
        case kVK_UpArrow, kVK_ANSI_K: return c.canPage ? .page(-1) : .consume
        case kVK_LeftArrow: return .carousel(-1)
        case kVK_RightArrow: return .carousel(1)
        case kVK_Space: return .togglePause
        case kVK_ANSI_M: return .toggleMute
        case kVK_ANSI_L: return .like
        case kVK_ANSI_S: return .collect
        case kVK_ANSI_C: return .toggleComments
        default: return .pass
        }
    }
}
