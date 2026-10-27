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
}
