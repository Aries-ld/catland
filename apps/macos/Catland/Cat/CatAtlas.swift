// CatAtlas：启动时把手绘像素小猫（PixelCatArt）按「花色 × 动作」渲染成逐帧 CGImage，供 CatStage 绘制。
import CoreGraphics
import Foundation

struct CatAnimation {
    let frames: [CGImage]
    let frameWidth: Int
    let frameHeight: Int
    let fps: Double
    /// 前 intro 帧、后 outro 帧各播一次，中段按 loops 循环。
    let intro: Int
    let outro: Int
    let loops: ClosedRange<Int>
    let weight: Double
}

final class CatAtlas {
    static let shared = CatAtlas()

    /// 花色 → 动作 → 动画
    let cats: [String: [String: CatAnimation]]
    /// 需要浅色描边的花色（深色猫在黑色刘海上）。
    let rimmed: Set<String>
    /// 美术朝左绘制：朝右走时翻转。
    let facesLeft = true

    /// 随机路过的猫可选的花色（不含平台小猫）。
    var skins: [String] { cats.keys.filter { !PixelCatArt.platformSkins.contains($0) }.sorted() }
    var isEmpty: Bool { cats.isEmpty }

    private init() {
        var out: [String: [String: CatAnimation]] = [:]
        for skin in PixelCatArt.skins {
            for action in PixelCatArt.actions {
                let frames = action.frames.compactMap { PixelCatArt.render(PixelCatArt.compose($0, accessory: skin.accessory), skin: skin) }
                guard frames.count == action.frames.count else { continue }
                out[skin.name, default: [:]][action.name] = CatAnimation(
                    frames: frames, frameWidth: PixelCatArt.width, frameHeight: PixelCatArt.height,
                    fps: action.fps, intro: action.intro, outro: action.outro, loops: action.loops, weight: action.weight)
            }
        }
        cats = out
        rimmed = Set(PixelCatArt.skins.filter(\.rim).map(\.name))
        AppLog.info("cat atlas built", ["skins": out.count, "actions": PixelCatArt.actions.count])
    }
}
