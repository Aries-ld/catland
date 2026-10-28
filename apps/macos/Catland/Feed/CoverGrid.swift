// 封面瀑布流：搜索结果、点赞 / 收藏共用同一套封面卡片和两列瀑布流，展示逻辑只有这一份。
// 格子高度按封面的真实宽高比（图片加载后记录）；加载前按平台常见比例估算（B 站横版 16:9，其他竖版 3:4）。
import AppKit
import Observation
import SwiftUI

/// 封面宽高比（高 / 宽）。平台接口经常不给封面尺寸，只能等图片加载后按真实尺寸记录。
@MainActor
@Observable
final class CoverAspects {
    static let shared = CoverAspects()
    private(set) var ratios: [String: Double] = [:]

    func record(_ url: String, size: CGSize) {
        guard size.width > 0, size.height > 0, ratios[url] == nil else { return }
        ratios[url] = size.height / size.width
    }

    /// 格子用的高宽比：真实尺寸 → 接口给的尺寸 → 平台常见比例；限制在 16:9 横版到 5:7 竖版之间，避免过扁或过长。
    func ratio(url: String?, platform: String, hint: Double?) -> Double {
        let raw = url.flatMap { ratios[$0] } ?? hint ?? Self.platformHint(platform)
        return min(max(raw, 9.0 / 16.0), 1.4)
    }

    static func platformHint(_ platform: String) -> Double { platform == "bilibili" ? 9.0 / 16.0 : 4.0 / 3.0 }
}

/// 一张封面卡片要显示的内容（搜索结果、点赞 / 收藏都转成它）。
struct CoverItem: Identifiable, Hashable {
    let id: String
    let platform: String
    let cover: ImageSource?
    let isVideo: Bool
    /// 视频时长（秒），平台没给时为 nil。
    let duration: Double?
    let title: String?
    let author: String?
    let likes: Int?
    /// 接口给的封面高宽比（可能没有）。
    let ratioHint: Double?
    /// 右键「在浏览器中打开原帖」。
    let url: String?
}

extension CoverItem {
    init(_ hit: SearchHit) {
        let hint = hit.cover.flatMap { c in c.width.flatMap { w in c.height.map { h in w > 0 ? h / w : 0 } } }.flatMap { $0 > 0 ? $0 : nil }
        self.init(id: hit.key, platform: hit.platform, cover: hit.cover, isVideo: hit.kind == "video", duration: hit.duration,
                  title: hit.title, author: hit.author?.name, likes: hit.stats.likes, ratioHint: hint, url: hit.url)
    }

    init(_ entry: SavedEntry) {
        let src = (entry.localCover ?? entry.card.cover).map { ImageSource(url: $0, headers: [:], width: nil, height: nil) }
        self.init(id: entry.card.key, platform: entry.card.platform, cover: src, isVideo: entry.card.kind == "video", duration: entry.card.duration,
                  title: entry.card.title ?? entry.card.text, author: entry.card.author?.name, likes: nil, ratioHint: nil, url: entry.card.url)
    }
}

/// 两列瀑布流：按估算高度把卡片分到较短的一列。
struct CoverMasonry: View {
    let items: [CoverItem]
    let columnWidth: CGFloat
    let open: (CoverItem) -> Void

    var body: some View {
        let cols = columns()
        HStack(alignment: .top, spacing: 8) {
            ForEach(0..<2, id: \.self) { c in
                LazyVStack(spacing: 10) {
                    ForEach(cols[c]) { item in CoverTile(item: item, width: columnWidth).onTapGesture { open(item) } }
                }
                .frame(width: columnWidth)
            }
        }
    }

    private func columns() -> [[CoverItem]] {
        var cols: [[CoverItem]] = [[], []], heights: [CGFloat] = [0, 0]
        for item in items {
            let c = heights[0] <= heights[1] ? 0 : 1
            cols[c].append(item)
            heights[c] += CoverTile.coverHeight(item, width: columnWidth) + 54
        }
        return cols
    }
}

/// 封面卡片：封面（左上角平台图标、视频右下角时长）+ 两行标题 + 作者与点赞。
struct CoverTile: View {
    let item: CoverItem
    let width: CGFloat
    @State private var hovering = false

    static func coverHeight(_ item: CoverItem, width: CGFloat) -> CGFloat {
        (width * CoverAspects.shared.ratio(url: item.cover?.url, platform: item.platform, hint: item.ratioHint)).rounded()
    }

    var body: some View {
        let h = Self.coverHeight(item, width: width)
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RemoteImage(source: item.cover)
                    .frame(width: width, height: h)
                    .clipped()
                PlatformIcon(platform: item.platform, size: 16)
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                if item.isVideo {
                    Group {
                        if let d = item.duration, d > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "play.fill").font(.system(size: 7))
                                Text(Format.clock(d)).font(.system(size: 10, weight: .semibold, design: .rounded))
                            }
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Capsule().fill(.black.opacity(0.55)))
                        } else {
                            Image(systemName: "play.fill").font(.system(size: 9))
                                .padding(5).background(Circle().fill(.black.opacity(0.5)))
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
            .frame(width: width, height: h)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.white.opacity(hovering ? 0.35 : 0), lineWidth: 1))
            let title = Format.caption(title: item.title, text: nil)
            Text(title.isEmpty ? "（无标题）" : title)
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.9))
                .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 4) {
                Text(item.author ?? "").lineLimit(1)
                Spacer(minLength: 4)
                if let likes = item.likes {
                    Image(systemName: "heart").font(.system(size: 9))
                    Text(Format.count(likes))
                }
            }
            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
        }
        .frame(width: width)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            if let s = item.url, let u = URL(string: s) { Button("在浏览器中打开原帖") { NSWorkspace.shared.open(u) } }
        }
    }
}
