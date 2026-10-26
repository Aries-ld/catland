// CatAtlas：加载打包进 App 的小猫精灵表（Resources/Cats，见 scripts/pack_cats.py），切成逐帧 CGImage。
import AppKit
import CoreGraphics
import Foundation

struct CatAnimation {
    let frames: [CGImage]
    let frameWidth: Int
    let frameHeight: Int
    /// 32×32 源图在帧内的左上角：用于把不同动作的脚底锚点对齐。
    let originX: Int
    let originY: Int
}

final class CatAtlas {
    static let shared = CatAtlas()

    let sourceSize: Int
    /// 形象 → 动作 → 动画
    let cats: [String: [String: CatAnimation]]

    var skins: [String] { cats.keys.sorted() }
    var isEmpty: Bool { cats.isEmpty }

    private init() {
        guard let dir = Bundle.main.url(forResource: "Cats", withExtension: nil),
              let data = try? Data(contentsOf: dir.appendingPathComponent("cats.json")),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else {
            AppLog.warn("cat atlas missing, using placeholder cats")
            sourceSize = 32
            cats = [:]
            return
        }
        sourceSize = manifest.sourceSize
        var out: [String: [String: CatAnimation]] = [:]
        for (cat, actions) in manifest.cats {
            for (action, m) in actions {
                guard let img = NSImage(contentsOf: dir.appendingPathComponent(m.file))?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
                let frames: [CGImage] = (0..<m.frames).compactMap { i in
                    img.cropping(to: CGRect(x: (i % m.columns) * m.frameWidth, y: (i / m.columns) * m.frameHeight, width: m.frameWidth, height: m.frameHeight))
                }
                guard frames.count == m.frames else { continue }
                out[cat, default: [:]][action] = CatAnimation(frames: frames, frameWidth: m.frameWidth, frameHeight: m.frameHeight, originX: m.originX, originY: m.originY)
            }
        }
        cats = out
        AppLog.info("cat atlas loaded", ["cats": out.count, "animations": out.values.map(\.count).reduce(0, +)])
    }

    private struct Manifest: Decodable {
        struct Anim: Decodable {
            let file: String
            let frameWidth: Int
            let frameHeight: Int
            let columns: Int
            let frames: Int
            let originX: Int
            let originY: Int
        }
        let sourceSize: Int
        let cats: [String: [String: Anim]]
    }
}
