// 与 sidecar RPC 对应的数据模型（字段见 apps/sidecar/src/content/types.ts、catbus/types.ts）。
import Foundation

struct UserRef: Codable, Hashable {
    let id: String
    let name: String?
    let url: String?
}

struct ItemStats: Codable, Hashable {
    let views: Int?
    let likes: Int?
    let comments: Int?
    let collects: Int?
    let shares: Int?
}

struct VideoSource: Codable, Hashable {
    let url: String
    let headers: [String: String]
    let width: Double?
    let height: Double?
    let duration: Double?
    /// HLS 播放列表（地址可能以 .mp4 结尾，见 sidecar isHls）。
    let hls: Bool?
}

struct ImageSource: Codable, Hashable {
    let url: String
    let headers: [String: String]
    let width: Double?
    let height: Double?
}

struct FeedCard: Codable, Identifiable, Hashable {
    let key: String
    let platform: String
    let id: String
    let url: String
    let kind: String
    let title: String?
    let text: String?
    let author: UserRef?
    let createdAt: String?
    let cover: ImageSource?
    let stats: ItemStats
    let video: VideoSource?
    let images: [ImageSource]
    let expiresAt: Double
    var liked: Bool?
    var collected: Bool?

    var isVideo: Bool { video != nil }
    /// 画面宽高比（宽 / 高），未知时按竖屏 9:16。
    var aspect: Double {
        if let v = video, let w = v.width, let h = v.height, w > 0, h > 0 { return w / h }
        if let i = images.first, let w = i.width, let h = i.height, w > 0, h > 0 { return w / h }
        return 9.0 / 16.0
    }
}

/// 搜索结果（只用于封面网格，点开时再 search.resolve 成 FeedCard）。
struct SearchHit: Codable, Identifiable, Hashable {
    let key: String
    let platform: String
    let id: String
    let url: String
    let kind: String
    let title: String?
    let author: UserRef?
    let cover: ImageSource?
    let stats: ItemStats
    let duration: Double?

    /// 封面宽高比（宽 / 高），未知时按 3:4。
    var aspect: Double {
        if let c = cover, let w = c.width, let h = c.height, w > 0, h > 0 { return w / h }
        return 3.0 / 4.0
    }
}

/// 平台实时热搜词（search.hot）。
struct HotWord: Codable, Hashable {
    let text: String
    let platform: String
    let heat: Double?
}

struct SearchResult: Codable {
    /// ok / resting（平台在风控冷却）/ auth（登录失效）/ unsupported
    let status: String
    let hits: [SearchHit]
    let cursor: String?
    let hasMore: Bool
}

struct FeedNext: Codable {
    let cards: [FeedCard]
    let sources: [String]
    /// 没货时：waiting（马上有）/ resting（要歇一阵），resumeAt 是预计恢复的时间（毫秒时间戳）。
    let availability: Availability?
}

struct Availability: Codable {
    let state: String
    let resumeAt: Double?
}

struct Account: Codable, Hashable {
    let platform: String
    let account: String
    let current: Bool
    let user: UserRef?
    let method: String?
}

struct PlatformState: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let primaryLogin: String
    let loginUrl: String
    let requiredCookies: [[String]]
    let sections: [String]
    /// 暂不开放的原因（置灰：不能连接、不进刷刷流）；nil 表示可用。
    let unavailable: String?
    let connected: Bool
    let current: Account?
    let accounts: [Account]
    let health: String
    let loginInProgress: Bool
}

struct SourceState: Codable, Hashable {
    let platform: String
    let status: String
    let until: Double?
    let pending: Int
    let ready: Int
}

struct Comment: Codable, Identifiable, Hashable {
    struct Stats: Codable, Hashable {
        let likes: Int?
        let replies: Int?
    }
    let id: String
    let parentId: String?
    let author: UserRef?
    let text: String
    let createdAt: String?
    let stats: Stats

    enum CodingKeys: String, CodingKey {
        case id, author, text, stats
        case parentId = "parent_id"
        case createdAt = "created_at"
    }
}

struct CommentPage: Codable {
    let comments: [Comment]
    let cursor: String?
    let hasMore: Bool
}

struct InteractState: Codable, Hashable {
    let liked: Bool
    let collected: Bool
}

struct Settings: Codable, Hashable {
    var muted: Bool
    var sources: [String: [String]]
    var weather: Bool?
}

struct CardSnapshot: Codable, Hashable {
    let key: String
    let platform: String
    let url: String
    let kind: String
    let title: String?
    let text: String?
    let author: UserRef?
    let cover: String?
    /// 视频时长（秒）；旧的收藏没有。
    let duration: Double?
}

struct SavedEntry: Codable, Hashable {
    let card: CardSnapshot
    let at: String
    /// 存在本机的封面（file://）；平台的封面地址会过期，优先用它。
    let localCover: String?
}

struct SavedPage: Codable {
    let entries: [SavedEntry]
    let next: Double?
}

struct HelloResult: Codable {
    let version: String
    let settings: Settings
}

struct LoginEvent: Codable {
    let type: String
    let platform: String
    let png: String?
    let message: String?
}

/// 各平台的展示信息（品牌色、短名）。
enum PlatformBrand {
    static func color(_ id: String) -> (r: Double, g: Double, b: Double) {
        switch id {
        case "xhs": return (1.0, 0.16, 0.27)
        case "douyin": return (0.15, 0.95, 0.93)
        case "bilibili": return (0.98, 0.45, 0.61)
        case "kuaishou": return (1.0, 0.45, 0.13)
        case "x": return (0.9, 0.9, 0.9)
        case "tiktok": return (0.15, 0.95, 0.93)
        case "weibo": return (0.9, 0.2, 0.2)
        case "jd": return (0.88, 0.1, 0.1)
        case "taobao": return (1.0, 0.4, 0.0)
        case "xianyu": return (1.0, 0.85, 0.0)
        default: return (0.7, 0.7, 0.7)
        }
    }

    static func shortName(_ id: String) -> String {
        switch id {
        case "xhs": return "小红书"
        case "douyin": return "抖音"
        case "bilibili": return "Bilibili"
        case "kuaishou": return "快手"
        case "x": return "X"
        case "tiktok": return "TikTok"
        case "weibo": return "微博"
        case "jd": return "京东"
        case "taobao": return "淘宝"
        case "xianyu": return "闲鱼"
        default: return id
        }
    }
}
