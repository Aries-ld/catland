import AVFoundation
import Carbon.HIToolbox
import SwiftUI
import XCTest
@testable import Catland

final class FormatTests: XCTestCase {
    func testCount() {
        XCTAssertEqual(Format.count(999), "999")
        XCTAssertEqual(Format.count(12_345), "1.2万")
        XCTAssertEqual(Format.count(230_000_000), "2.3亿")
    }

    func testSkylineKnownCitiesAndFallback() {
        XCTAssertEqual(Skyline.known(latitude: 39.95, longitude: 116.3)?.city, .beijing)
        XCTAssertEqual(Skyline.known(latitude: 39.95, longitude: 116.3)?.name, "北京")
        XCTAssertEqual(Skyline.known(latitude: 31.2, longitude: 121.5)?.city, .shanghai)
        XCTAssertNil(Skyline.known(latitude: 40.71, longitude: -74.0)) // 纽约
        let ny = SceneLocation(name: "纽约", latitude: 40.71, longitude: -74.0, source: .system)
        XCTAssertNil(ny.city)
        XCTAssertTrue([Skyline.beijing, .shanghai].contains(ny.skyline), "不在已知城市时用北京或上海")
        XCTAssertEqual(ny.skyline, ny.skyline, "随机选定后保持不变")
        XCTAssertEqual(RestDays.region(for: .beijing, timeZone: TimeZone(identifier: "Asia/Shanghai")!), .china)
    }

    func testClock() {
        XCTAssertEqual(Format.clock(0), "0:00")
        XCTAssertEqual(Format.clock(65.9), "1:05")
        XCTAssertEqual(Format.clock(850), "14:10")
        XCTAssertEqual(Format.clock(3723), "1:02:03")
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

final class RestDaysTests: XCTestCase {
    private func day(_ s: String) -> Date {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; f.timeZone = .current
        return f.date(from: s)!
    }

    func testNextHolidayChina() {
        let (h, days) = RestDays.nextHoliday(from: day("2026-10-26 15:00"), region: .china)!
        XCTAssertEqual(h.name, "万圣节")
        XCTAssertEqual(days, 5)
        let (h2, d2) = RestDays.nextHoliday(from: day("2026-09-20 10:00"), region: .china)!
        XCTAssertEqual(h2.name, "中秋")
        XCTAssertEqual(d2, 5)
    }

    func testPersonaCopyFollowsContext() {
        let base = BubbleCopy.Context(now: day("2026-10-26 15:00"), region: .china, city: "上海", condition: "rain", temperature: 19,
                                      season: .autumn, speakers: [.shushu])
        let chat = BubbleCopy.chat(base, as: .shushu)
        XCTAssertTrue(chat.contains("上海 19°，雨"))
        XCTAssertTrue(chat.contains("下雨了，毛可别淋湿了"))
        XCTAssertTrue(chat.contains("周一，连舔毛都提不起劲"))
        XCTAssertTrue(chat.contains("秋天的第一杯奶茶，喝了吗"))
        let time = BubbleCopy.time(base, as: .tietie)
        XCTAssertTrue(time.contains("还有 3 小时 0 分下班，挺住"), "\(time)")
        XCTAssertTrue(time.contains { $0.contains("万圣节") }, "\(time)")
        var late = base; late.now = day("2026-10-28 23:40")
        XCTAssertTrue(BubbleCopy.chat(late, as: .bibi).contains("这么晚了，快睡啦笨蛋"))
    }

    func testRotationSpeaksWithNamesAndTakesTurns() {
        let ctx = BubbleCopy.Context(now: day("2026-10-28 10:00"), region: .china, city: "上海", condition: "clear", temperature: 21,
                                     season: .autumn, speakers: [.shushu, .doudou, .bibi, .tietie])
        let a = BubbleCopy.rotation(ctx, seed: 1), b = BubbleCopy.rotation(ctx, seed: 2)
        XCTAssertEqual(a.count, 12)
        XCTAssertEqual(Set(a).count, a.count)
        XCTAssertNotEqual(a, b)
        let names = Set(a.compactMap { line in Persona.allCases.first { line.hasPrefix("\($0.name)：") } })
        XCTAssertEqual(names, [.shushu, .doudou, .bibi, .tietie], "四只小猫都应该轮到说话")
        var tired = ctx; tired.sleeping = [.bibi]
        let t = BubbleCopy.rotation(tired, seed: 4).filter { $0.hasPrefix("bibi：") }
        XCTAssertFalse(t.isEmpty)
        XCTAssertTrue(t.allSatisfy { line in Persona.bibi.lines.tired.contains { line == "bibi：\($0)" } }, "打盹的小猫只说累了：\(t)")
        let offline = BubbleCopy.rotation(BubbleCopy.Context(now: day("2026-10-28 10:00"), region: .other, city: "x", condition: nil, temperature: nil,
                                                             season: .tropical, speakers: []), seed: 3)
        XCTAssertFalse(offline.isEmpty)
        XCTAssertTrue(offline.allSatisfy { $0.hasPrefix("箱箱：") })
    }

    /// 凌晨、加班这类强情境：每次悬停的第一句必定是情境语；普通时段不总是情境语开头（避免刻意）。
    func testMomentsLeadTheRotation() {
        func ctx(_ t: String, _ cond: String? = "clear", _ temp: Double? = 20) -> BubbleCopy.Context {
            BubbleCopy.Context(now: day(t), region: .china, city: "上海", condition: cond, temperature: temp, season: .autumn,
                               speakers: [.shushu, .doudou, .bibi, .tietie])
        }
        func strip(_ line: String) -> (Persona, String)? {
            Persona.allCases.first { line.hasPrefix("\($0.name)：") }.map { ($0, String(line.dropFirst($0.name.count + 1))) }
        }
        for seed in UInt64(1)...20 {
            // 周三凌晨 3 点
            let (p, first) = strip(BubbleCopy.rotation(ctx("2026-10-28 03:00"), seed: seed)[0])!
            XCTAssertTrue(p.lines.moments["lateNight"]!.contains(first), "凌晨 3 点第一句应该是关心熬夜：\(first)")
            // 周三晚上 20:30 还在加班
            let (p2, first2) = strip(BubbleCopy.rotation(ctx("2026-10-28 20:30"), seed: seed)[0])!
            XCTAssertTrue(p2.lines.moments["overtime"]!.contains(first2), "加班时第一句应该是加班：\(first2)")
            // 雷雨
            let (p3, first3) = strip(BubbleCopy.rotation(ctx("2026-10-28 15:00", "thunder"), seed: seed)[0])!
            XCTAssertTrue(p3.lines.weather["thunder"]!.contains(first3), "雷雨天第一句应该说打雷：\(first3)")
        }
        // 周三上午 10 点：没有强情境，20 次悬停里应该既有情境语开头、也有泛化开头
        let firsts = (UInt64(1)...20).map { seed -> Bool in
            let (p, line) = strip(BubbleCopy.rotation(ctx("2026-10-28 10:00"), seed: seed)[0])!
            let mo = BubbleCopy.moments(ctx("2026-10-28 10:00"), as: p)
            return mo.mild.contains(line)
        }
        XCTAssertTrue(firsts.contains(true) && firsts.contains(false), "普通时段不应该总是情境语开头")
        // 周六下午还在电脑前
        let sat = BubbleCopy.moments(ctx("2026-10-31 15:00"), as: .bibi)
        XCTAssertTrue(sat.mild.contains("周末还工作？笨蛋吗你"))
        XCTAssertTrue(sat.strong.isEmpty)
    }

    /// 每只小猫的所有语料（含带数字的模板）都不超过 22 个字（不含名字），气泡放得下。
    func testPersonaLinesFitBubble() {
        for p in Persona.allCases {
            let l = p.lines
            var all = l.tap + l.tired + l.moments.values.flatMap { $0 } + l.mood + l.weather.values.flatMap { $0 } + l.season.values.flatMap { $0 }
                + l.daypart.values.flatMap { $0 } + l.weekday.values.flatMap { $0 }
            all += [l.offWork(12, 59), l.offSoon(59), l.dayProgress(100), l.weekProgress(100), l.holidayToday("劳动节"),
                    l.holidayTomorrow("劳动节"), l.holidayNear("劳动节", 7), l.holidayFar("劳动节", 365), l.monthEnd(6), l.yearProgress(2026, 100)]
            let long = all.filter { $0.count > 22 }
            XCTAssertTrue(long.isEmpty, "\(p.name) 的文案太长：\(long)")
        }
    }

}

final class EventSchedulerTests: XCTestCase {
    private func day(_ s: String) -> Date {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; f.timeZone = .current
        return f.date(from: s)!
    }

    override func setUp() { EventScheduler.extra = [] }

    func testMeteorShowerOnRealPeakNight() {
        let occ = EventScheduler.occurrences(around: day("2026-12-13 12:00"), region: .china, latitude: 31.2)
        let meteor = occ.first { $0.eventID == "meteorShower" && Calendar.current.isDate($0.start, inSameDayAs: day("2026-12-13 12:00")) }
        XCTAssertEqual(meteor?.start, day("2026-12-13 22:00"))
    }

    func testTeaserWithinSixHoursAndCountdown() {
        let lines = EventScheduler.bubbleLines(now: day("2026-12-13 17:30"), region: .china, latitude: 31.2, condition: "clear", intensity: 0, seed: 1)
        XCTAssertTrue(lines.contains { $0.contains("今晚 22:00") }, "\(lines)")
        XCTAssertTrue(lines.contains("距流星雨还有 4 小时 30 分"), "\(lines)")
        // 6 小时之外不预告
        let early = EventScheduler.bubbleLines(now: day("2026-12-13 15:00"), region: .china, latitude: 31.2, condition: "clear", intensity: 0, seed: 1)
        XCTAssertFalse(early.contains { $0.contains("流星雨") })
    }

    func testLiveCountdownAndWeatherCancellation() {
        let live = EventScheduler.bubbleLines(now: day("2026-12-13 22:04"), region: .china, latitude: 31.2, condition: "clear", intensity: 0, seed: 2)
        XCTAssertTrue(live.contains("流星雨还剩 6 分钟"), "\(live)")
        let rained = EventScheduler.bubbleLines(now: day("2026-12-13 22:04"), region: .china, latitude: 31.2, condition: "rain", intensity: 0.6, seed: 2)
        XCTAssertEqual(rained, ["天公不作美，流星雨看不成了 T_T"])
        XCTAssertNil(EventScheduler.active(now: day("2026-12-13 22:11"), region: .china, latitude: 31.2).flatMap { $0.eventID == "meteorShower" ? $0 : nil })
    }

    func testSingaporeLightShowEveryNightAndScheduleIsDeterministic() {
        let a = EventScheduler.occurrences(around: day("2026-10-28 12:00"), region: .singapore, latitude: 1.29)
        XCTAssertTrue(a.contains { $0.eventID == "lightShow" && $0.start == day("2026-10-28 20:00") })
        XCTAssertEqual(a, EventScheduler.occurrences(around: day("2026-10-28 12:00"), region: .singapore, latitude: 1.29))
    }

    func testTriggeredEventAndCatsWatch() {
        let now = day("2026-10-28 15:00")
        EventScheduler.trigger("rainbowAfterRain", at: now)
        XCTAssertEqual(EventScheduler.active(now: now.addingTimeInterval(60), region: .china, latitude: 31.2)?.eventID, "rainbowAfterRain")
        let director = CatDirector()
        director.watching = true
        let lane = CatDirector.Lane(min: 40, max: 120, exitLeft: true)
        var snap = director.tick(actor: "w", lane: lane, pixel: 1.5, time: 100, excited: false)
        for k in 1..<60 { snap = director.tick(actor: "w", lane: lane, pixel: 1.5, time: 100 + Double(k) / 30, excited: false) }
        XCTAssertEqual(snap.action, "watch")
    }

    func testEveryRegisteredEventHasCopy() {
        for e in Events.all {
            XCTAssertFalse(e.lives.isEmpty, e.id)
            XCTAssertFalse(e.cancelLine.isEmpty, e.id)
            if !e.triggered { XCTAssertFalse(e.teasers.isEmpty, e.id) }
        }
    }
}

final class DisplayOnlyHitTestTests: XCTestCase {
    @MainActor
    func testVideoContainerDoesNotSwallowClicks() {
        let player = VideoLayer.PlayerNSView(frame: .init(x: 0, y: 0, width: 100, height: 100))
        let container = NSView(frame: player.frame)   // 模拟 SwiftUI 的 PlatformGroupContainer
        container.addSubview(player)
        XCTAssertTrue(FirstMouseHostingView.isDisplayOnly(player))
        XCTAssertTrue(FirstMouseHostingView.isDisplayOnly(container))
        let control = NSSegmentedControl(frame: player.frame) // 真正可交互的 AppKit 控件不受影响
        XCTAssertFalse(FirstMouseHostingView.isDisplayOnly(control))
        XCTAssertNil(player.hitTest(NSPoint(x: 10, y: 10)))
    }

    /// 真实的 SwiftUI 层级：视频铺满、按钮叠在上面，点按钮位置时 AppKit 不能把点击交给视频或它的容器。
    @MainActor
    func testButtonOverVideoGetsTheClick() {
        let view = ZStack(alignment: .bottomTrailing) {
            VideoLayer(player: AVPlayer(), fill: true)
            Button("like") {}.frame(width: 44, height: 44)
        }
        .frame(width: 300, height: 500)
        let host = hosting(view, CGSize(width: 300, height: 500))
        XCTAssertTrue(containsPlayer(host), "测试层级里应有视频视图")
        // NSHostingView 是翻转坐标：y 从上往下
        for p in [NSPoint(x: 278, y: 478), NSPoint(x: 150, y: 250)] {
            let hit = host.hitTest(p)
            XCTAssertFalse(hit.map(FirstMouseHostingView.isDisplayOnly) ?? false, "\(p) 被视频抢走：\(String(describing: hit))")
        }
    }

    /// 屏幕外预渲染的上一条（offset -1）会伸到顶栏下面：顶栏按钮的点击不能落进它的视频视图。
    @MainActor
    func testPrerenderedCardDoesNotStealTopBarClicks() {
        let view = VStack(spacing: 0) {
            Button("connect") {}.frame(height: 40)
            ZStack {
                VideoLayer(player: AVPlayer(), fill: true).frame(width: 300, height: 460).offset(y: -460).allowsHitTesting(false)
                VideoLayer(player: AVPlayer(), fill: true).frame(width: 300, height: 460)
            }
            .frame(width: 300, height: 460)
            .clipped()
        }
        let host = hosting(view, CGSize(width: 300, height: 500))
        let hit = host.hitTest(NSPoint(x: 150, y: 20))
        XCTAssertFalse(hit.map(FirstMouseHostingView.isDisplayOnly) ?? false, "顶栏被预渲染卡片抢走：\(String(describing: hit))")
    }

    @MainActor
    private func hosting(_ v: some View, _ size: CGSize) -> FirstMouseHostingView {
        let host = FirstMouseHostingView(rootView: AnyView(v))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        return host
    }

    private func containsPlayer(_ v: NSView) -> Bool { v is VideoLayer.PlayerNSView || v.subviews.contains(where: containsPlayer) }
}

final class KeyRouterTests: XCTestCase {
    func testEscapeUnwindsOneLayerAtATime() {
        var c = KeyContext(fullscreen: true, commentsOpen: true, savedPlaying: true, searchActive: true, searchPlaying: true, overlay: .saved)
        // 全屏里开着评论：Esc 先关评论，不退全屏
        XCTAssertEqual(KeyRouter.route(kVK_Escape, c), .closeComments)
        c.commentsOpen = false
        XCTAssertEqual(KeyRouter.route(kVK_Escape, c), .exitFullscreen)
        c.fullscreen = false
        XCTAssertEqual(KeyRouter.route(kVK_Escape, c), .stopSaved)
        c.savedPlaying = false
        XCTAssertEqual(KeyRouter.route(kVK_Escape, c), .closeOverlay)
        c.overlay = .none
        XCTAssertEqual(KeyRouter.route(kVK_Escape, c), .stopSearchPlaying)
        c.searchPlaying = false
        XCTAssertEqual(KeyRouter.route(kVK_Escape, c), .closeSearch)
        c.searchActive = false
        XCTAssertEqual(KeyRouter.route(kVK_Escape, c), .collapse)
        c.onboarding = true
        XCTAssertEqual(KeyRouter.route(kVK_Escape, c), .skipOnboarding)
    }

    func testFullscreenKeyDoesNotFireWhileTypingOrBrowsingResults() {
        XCTAssertEqual(KeyRouter.route(kVK_ANSI_F, KeyContext()), .toggleFullscreen)
        XCTAssertEqual(KeyRouter.route(kVK_ANSI_F, KeyContext(typing: true)), .pass)
        XCTAssertEqual(KeyRouter.route(kVK_ANSI_F, KeyContext(searchActive: true)), .pass)
        XCTAssertEqual(KeyRouter.route(kVK_ANSI_F, KeyContext(searchActive: true, searchPlaying: true)), .toggleFullscreen)
        XCTAssertEqual(KeyRouter.route(kVK_ANSI_F, KeyContext(fullscreen: true)), .toggleFullscreen)
        XCTAssertEqual(KeyRouter.route(kVK_ANSI_F, KeyContext(typing: true, command: true)), .openSearch)
        XCTAssertEqual(KeyRouter.route(kVK_Escape, KeyContext(searchActive: true, typing: true)), .closeSearch)
    }

    func testCommerceEscapeAndKeys() {
        // 电商里浏览：方向键、空格交给页面；F 不进全屏；Esc 先关商品页 / 结果，再收起
        let browse = KeyContext(commerceBrowsing: true, commerceBack: true)
        XCTAssertEqual(KeyRouter.route(kVK_DownArrow, browse), .pass)
        XCTAssertEqual(KeyRouter.route(kVK_ANSI_F, browse), .pass)
        XCTAssertEqual(KeyRouter.route(kVK_Escape, browse), .commerceBack)
        XCTAssertEqual(KeyRouter.route(kVK_Escape, KeyContext(commerceBrowsing: true)), .collapse)
        // 播测评：和刷视频一样，Esc 回到电商页
        let playing = KeyContext(commercePlaying: true, commerceBack: true)
        XCTAssertEqual(KeyRouter.route(kVK_DownArrow, playing), .page(1))
        XCTAssertEqual(KeyRouter.route(kVK_ANSI_F, playing), .toggleFullscreen)
        XCTAssertEqual(KeyRouter.route(kVK_Escape, playing), .stopCommercePlaying)
    }

    func testPagingRespectsOverlaysAndComments() {
        XCTAssertEqual(KeyRouter.route(kVK_DownArrow, KeyContext()), .page(1))
        XCTAssertEqual(KeyRouter.route(kVK_ANSI_K, KeyContext()), .page(-1))
        XCTAssertEqual(KeyRouter.route(kVK_DownArrow, KeyContext(commentsOpen: true)), .consume)
        XCTAssertEqual(KeyRouter.route(kVK_DownArrow, KeyContext(overlay: .settings)), .consume)
        XCTAssertEqual(KeyRouter.route(kVK_DownArrow, KeyContext(savedPlaying: true, overlay: .saved)), .page(1))
        XCTAssertEqual(KeyRouter.route(kVK_DownArrow, KeyContext(fullscreen: true)), .page(1))
        // 搜索结果瀑布流里：方向键、空格交给瀑布流 / 系统
        XCTAssertEqual(KeyRouter.route(kVK_DownArrow, KeyContext(searchActive: true)), .pass)
        XCTAssertEqual(KeyRouter.route(kVK_Space, KeyContext(searchActive: true)), .pass)
        XCTAssertEqual(KeyRouter.route(kVK_ANSI_L, KeyContext(fullscreen: true)), .like)
        XCTAssertEqual(KeyRouter.route(kVK_ANSI_L, KeyContext(otherModifiers: true)), .pass)
    }
}

final class HistoryGroupingTests: XCTestCase {
    func testGroupsByDayWithFriendlyTitles() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Singapore")!
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-03T10:00:00+08:00"))
        func entry(_ id: String, _ at: String) -> SavedEntry {
            SavedEntry(card: CardSnapshot(key: "xhs:\(id)", platform: "xhs", url: "", kind: "video", title: nil, text: nil, author: nil, cover: nil, duration: nil),
                       at: at, localCover: nil)
        }
        let groups = HistoryView.groups([
            entry("a", "2026-11-03T01:30:00.000Z"), entry("b", "2026-11-02T20:00:00.000Z"),   // 新加坡 11-03 09:30、11-03 04:00
            entry("c", "2026-11-02T10:00:00.000Z"), entry("d", "2026-10-20T10:00:00.000Z"), entry("e", "2025-12-31T10:00:00Z"),
        ], now: now, calendar: cal)
        XCTAssertEqual(groups.map(\.title), ["今天", "昨天", "10月20日 星期二", "2025年12月31日"])
        XCTAssertEqual(groups[0].entries.map(\.card.key), ["xhs:a", "xhs:b"])
    }
}

final class ProductMatchTests: XCTestCase {
    /// 标题取自 2026-11-03 真实的京东搜索结果
    func testParsesBrandAndModelFromRealJDTitles() {
        let cases: [(String, String, Bool)] = [
            ("罗技（G）闪逸龙G316电竞版 8K客制化游戏键盘 98配列 机械键盘 FPS电竞 打瓦 三角洲 无畏契约必备 黑色L轴", "罗技 G316", true),
            ("雷蛇（Razer）黑寡妇蜘蛛标准版 机械键盘 游戏键盘 绿色背光 游戏电竞 有线机械键盘 绿轴", "雷蛇 黑寡妇蜘蛛", true),
            ("惠普（HP）机械键盘 办公电竞游戏专用有线 台式机笔记本电脑 侧刻渐变黑莓粉白光青轴 104键", "惠普 机械键盘", false),
            ("京东京造JZ990Pro静音三模机械键盘游戏办公安静无线蓝牙有线键盘无线类红轴WIN/Mac办公游戏大配列数字区", "京东京造 JZ990Pro", true),
            ("罗技（Logitech）K845机械键盘 有线键盘 办公电脑打字键盘  电竞游戏发光全尺寸个性化定制键帽 K845青轴+", "罗技 K845", true),
            ("【万人购】京造JZ990Pro键盘", "京造 JZ990Pro", true),
            ("狼蛛（AULA）F2088Air无线机械键盘鼠标套装蓝牙/2.4G/有线三模连接108键全键无冲电竞游戏办公笔记本电脑外", "狼蛛 F2088Air", true),
            ("雷蛇（Razer）黑寡妇蜘蛛V3竞技版 机械键盘 87键 电脑游戏电竞 RGB背光 绿轴", "雷蛇 黑寡妇蜘蛛V3", true),
            ("Apple/苹果 MacBook Air 13.6英寸 M3芯片 16GB 512GB 午夜色 笔记本电脑", "Apple M3", true),
        ]
        for (title, query, specific) in cases {
            let m = ProductMatch.parse(title)
            XCTAssertEqual(m.query, query, title)
            XCTAssertEqual(m.specific, specific, title)
        }
    }

    func testOnlyReviewsOfThisModelMatch() {
        let g316 = ProductMatch.parse("罗技（G）闪逸龙G316电竞版 8K客制化游戏键盘")
        XCTAssertTrue(g316.matches("罗技G316 一个月深度体验：8K 回报率到底有没有用"))
        XCTAssertTrue(g316.matches("闪逸龙 g 316 开箱"))
        XCTAssertFalse(g316.matches("2026 双十一机械键盘推荐清单"))
        XCTAssertFalse(g316.matches("罗技 G502 鼠标测评"))
        // 另一款（多了后缀）不算
        XCTAssertFalse(g316.matches("【测评】罗技G316X大配列游戏键盘"))
        XCTAssertFalse(ProductMatch.parse("京东京造JZ990Pro静音三模机械键盘").matches("京东京造JZ990ProV2鎏金黑开箱"))
        XCTAssertTrue(ProductMatch.parse("京东京造JZ990Pro静音三模机械键盘").matches("京东京造JZ990 Pro真的手感拉满"))
        // 短型号要求品牌也出现（括号里的英文名也算）
        let v3 = ProductMatch.parse("雷蛇（Razer）黑寡妇蜘蛛V3竞技版 机械键盘")
        XCTAssertTrue(v3.matches("Razer 黑寡妇 V3 值不值得买"))
        XCTAssertFalse(v3.matches("小米 V3 扫地机器人"))
        // 认不出型号：按品牌 + 品类，只算宽泛匹配
        let hp = ProductMatch.parse("惠普（HP）机械键盘 办公电竞游戏专用有线")
        XCTAssertTrue(hp.matches("HP 惠普机械键盘 百元入门"))
        XCTAssertFalse(hp.matches("机械键盘入门指南"))
    }
}

final class UpdaterNotesTests: XCTestCase {
    @MainActor
    func testReleaseNotesBecomePlainLines() {
        XCTAssertEqual(AppUpdater.plainNotes("<h2>新功能</h2><ul><li>浏览历史</li><li>导出 &amp; 导入</li></ul>"), "新功能\n· 浏览历史\n· 导出 & 导入")
        XCTAssertEqual(AppUpdater.plainNotes("## 新功能\n\n- **浏览历史**：按天分组\n- 全屏"), "新功能\n· 浏览历史：按天分组\n· 全屏")
        XCTAssertNil(AppUpdater.plainNotes(""))
    }
}

final class ScrollPagerTests: XCTestCase {
    @MainActor
    func testOneTrackpadGesturePagesOnceAndIgnoresMomentum() {
        let pager = ScrollPager()
        var pages: [Int] = [], sideways: [Int] = []
        pager.onPage = { pages.append($0) }
        pager.onHorizontal = { sideways.append($0) }
        _ = pager.handle(precise: true, momentum: false, began: true, ended: false, dx: 0, dy: -20)
        for _ in 0..<5 { _ = pager.handle(precise: true, momentum: false, began: false, ended: false, dx: 0, dy: -20) }
        _ = pager.handle(precise: true, momentum: false, began: false, ended: true, dx: 0, dy: 0)
        for _ in 0..<10 { _ = pager.handle(precise: true, momentum: true, began: false, ended: false, dx: 0, dy: -60) }
        XCTAssertEqual(pages, [1])
        _ = pager.handle(precise: true, momentum: false, began: true, ended: false, dx: -50, dy: 3)
        XCTAssertEqual(sideways, [1])
        XCTAssertEqual(pages, [1])
    }

    @MainActor
    func testMouseWheelThrottled() {
        let pager = ScrollPager()
        var pages: [Int] = []
        pager.onPage = { pages.append($0) }
        let t = Date()
        _ = pager.handle(precise: false, momentum: false, began: false, ended: false, dx: 0, dy: 1, now: t)
        _ = pager.handle(precise: false, momentum: false, began: false, ended: false, dx: 0, dy: 1, now: t.addingTimeInterval(0.1))
        _ = pager.handle(precise: false, momentum: false, began: false, ended: false, dx: 0, dy: -1, now: t.addingTimeInterval(0.5))
        XCTAssertEqual(pages, [-1, 1])
    }
}
