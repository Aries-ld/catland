import XCTest
@testable import Catland

final class FormatTests: XCTestCase {
    func testCount() {
        XCTAssertEqual(Format.count(999), "999")
        XCTAssertEqual(Format.count(12_345), "1.2万")
        XCTAssertEqual(Format.count(230_000_000), "2.3亿")
    }

    func testCaptionDedupesTitle() {
        XCTAssertEqual(Format.caption(title: "美女", text: "美女 大长腿 #美女[话题]#"), "美女 大长腿 #美女#")
        XCTAssertEqual(Format.caption(title: "标题", text: "正文"), "标题\n正文")
        XCTAssertEqual(Format.caption(title: nil, text: "正文"), "正文")
        XCTAssertEqual(Format.caption(title: "标题", text: nil), "标题")
    }

    func testAspectDefaultsToPortrait() throws {
        let json = #"{"key":"x:1","platform":"x","id":"1","url":"u","kind":"video","title":null,"text":null,"author":null,"createdAt":null,"cover":null,"stats":{"views":null,"likes":1,"comments":null,"collects":null,"shares":null},"video":{"url":"v","headers":{},"width":1920,"height":1080,"duration":3},"images":[],"expiresAt":0,"resolvedAt":0,"liked":true}"#
        let card = try JSONDecoder().decode(FeedCard.self, from: Data(json.utf8))
        XCTAssertEqual(card.aspect, 1920.0 / 1080.0, accuracy: 0.001)
        XCTAssertEqual(card.liked, true)
        XCTAssertNil(card.collected)
    }
}

final class NotchGeometryTests: XCTestCase {
    func testActiveRectCentersOnScreenTop() {
        let g = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), notchSize: CGSize(width: 200, height: 32), hasNotch: true)
        let c = g.activeRect(expanded: false)
        XCTAssertEqual(c.midX, 756)
        XCTAssertEqual(c.minY, 982 - 32)
        XCTAssertGreaterThan(c.maxY, 982) // 向上多留几个点，覆盖屏幕最上沿
        XCTAssertEqual(c.width, 200 + NotchGeometry.wing * 2)
        XCTAssertEqual(g.activeRect(expanded: true).width, NotchGeometry.expandedSize.width)
        XCTAssertTrue(g.activeRect(expanded: false, hovering: true).contains(CGPoint(x: 756, y: 982 - 32 - 20)))
    }
}

final class PixelCatArtTests: XCTestCase {
    func testAllPosesAndHeadsHaveValidSize() {
        for p in [PixelCatArt.stand, PixelCatArt.sit, PixelCatArt.loaf, PixelCatArt.stretch, PixelCatArt.back] {
            XCTAssertEqual(p.rows.count, PixelCatArt.height)
            for r in p.rows { XCTAssertEqual(r.count, PixelCatArt.width, r) }
        }
        for h in PixelCatArt.Head.allCases { XCTAssertTrue(h.rows.allSatisfy { $0.count == 6 }) }
    }

    func testEveryActionComposesAndRendersForEverySkin() {
        XCTAssertGreaterThanOrEqual(PixelCatArt.skins.count, 10)
        XCTAssertGreaterThanOrEqual(PixelCatArt.actions.count, 12)
        for action in PixelCatArt.actions {
            XCTAssertTrue(action.intro + action.outro < action.frames.count || (action.intro == 0 && action.outro == 0), action.name)
            for f in action.frames {
                let g = PixelCatArt.compose(f)
                XCTAssertEqual(g.count, PixelCatArt.height)
                XCTAssertTrue(g.joined().contains("E") || g.joined().contains("C"), "\(action.name) frame without eyes")
            }
        }
        for skin in PixelCatArt.skins {
            XCTAssertNotNil(PixelCatArt.render(PixelCatArt.compose(.init(pose: PixelCatArt.stand)), skin: skin), skin.name)
        }
    }

    func testHopLiftsBodyButNotParticles() {
        let hop = PixelCatArt.actions.first { $0.name == "hop" }!
        let g = PixelCatArt.compose(hop.frames[2])
        XCTAssertEqual(g[0][2], "V") // 爱心留在画布顶部
        XCTAssertTrue(g[11].allSatisfy { $0 == "." }) // 身体离地
    }

    func testSegmentedPlayback() {
        let nap = CatAtlas.shared.cats["orange"]!["nap"]!
        let mid = nap.frames.count - nap.intro - nap.outro
        XCTAssertEqual(CatDirector.frameIndex(raw: 0, anim: nap, loops: 3), 0)
        XCTAssertEqual(CatDirector.frameIndex(raw: nap.intro + mid, anim: nap, loops: 3), nap.intro) // 中段循环
        XCTAssertEqual(CatDirector.frameIndex(raw: 999, anim: nap, loops: 3), nap.frames.count - 1) // 停在最后一帧
        XCTAssertEqual(CatDirector.duration(nap, loops: 3), Double(nap.intro + mid * 3 + nap.outro) / nap.fps, accuracy: 0.001)
    }

    func testCatwalkMakesCollapsedTaller() {
        var g = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), notchSize: CGSize(width: 200, height: 32), hasNotch: true)
        let h0 = g.collapsedSize.height
        g.shelf = NotchGeometry.shelfHeight
        XCTAssertEqual(g.collapsedSize.height, h0 + NotchGeometry.shelfHeight)
    }
}

final class SceneClockTests: XCTestCase {
    private func date(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

    func testSingaporeSunAltitude() {
        let noon = SceneClock.sun(at: date("2026-10-26T13:00:00+08:00"))   // 新加坡太阳正午约 12:50
        let midnight = SceneClock.sun(at: date("2026-10-26T00:30:00+08:00"))
        let sunrise = SceneClock.sun(at: date("2026-10-26T06:50:00+08:00"))
        XCTAssertGreaterThan(noon.altitude, 70)
        XCTAssertLessThan(midnight.altitude, -60)
        XCTAssertEqual(sunrise.altitude, 0, accuracy: 4)
        XCTAssertLessThan(sunrise.azimuth, 120) // 早上在东边
        XCTAssertEqual(SceneClock.darkness(noon), 0)
        XCTAssertEqual(SceneClock.darkness(midnight), 1)
    }
}

final class CatDenTests: XCTestCase {
    func testCatClimbsIntoDenHidesShowsEffectThenDropsBack() {
        let director = CatDirector()
        director.forceDen = true
        let lane = CatDirector.Lane(min: 100, max: 160, exitLeft: true)
        let den = CatDen(minX: 80, maxX: 240, bottom: 32)
        var t: TimeInterval = 1000
        var sawHidden = false, sawEffect = false, landed = false
        var snap = director.tick(actor: "a", lane: lane, pixel: 1.5, time: t, excited: false, den: den, groundToDen: 12)
        for _ in 0..<(60 * 30 * 3) { // 最多模拟 3 分钟（30fps）
            t += 1.0 / 30
            snap = director.tick(actor: "a", lane: lane, pixel: 1.5, time: t, excited: false, den: den, groundToDen: 12)
            if snap.opacity == 0 { sawHidden = true; XCTAssertGreaterThan(snap.lift, 12) }
            if snap.denEffect != nil { sawEffect = true }
            if sawHidden && snap.opacity > 0 && snap.lift == 0 { landed = true; break }
        }
        XCTAssertTrue(sawHidden, "cat never entered the den")
        XCTAssertTrue(sawEffect, "no tail / paws / peek / zzz while in den")
        XCTAssertTrue(landed, "cat never came back down")
        XCTAssertGreaterThanOrEqual(snap.x, den.minX)
        XCTAssertLessThanOrEqual(snap.x, den.maxX)
    }
}
