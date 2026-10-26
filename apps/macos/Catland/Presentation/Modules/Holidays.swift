// 节日模块：唯一的节日目录。气泡里的「距 XX 还有 N 天」与窗边装饰共用这一份数据。
// 新增节日：在 HolidayCatalog.all 里加一个 HolidayDef（日期、哪些地区、是否放假、装饰显示窗口、装饰绘制）。
// 农历节日写死近几年的公历日期（2026–2031），到期前补上即可。
import SwiftUI

enum Region: CaseIterable { case china, singapore, other }

struct HolidayDef {
    let id: String
    let name: String
    /// 哪些地区过这个节（空 = 所有地区）。
    let regions: Set<Region>
    /// 哪些地区放假。
    let offIn: Set<Region>
    /// 某一年的日期（返回 nil 表示该年没有 / 未登记）。
    let date: (Int) -> DateComponents?
    /// 装饰显示窗口：节日前几天到节日后几天。
    var decorBefore = 0
    var decorAfter = 0
    var decorStage: SceneStage = .decor
    var decor: ((SceneCanvas) -> Void)? = nil

    func applies(to r: Region) -> Bool { regions.isEmpty || regions.contains(r) }
    func isOff(in r: Region) -> Bool { offIn.contains(r) }
}

private func fixed(_ m: Int, _ d: Int) -> (Int) -> DateComponents? { { y in DateComponents(year: y, month: m, day: d) } }
private func table(_ t: [Int: (Int, Int)]) -> (Int) -> DateComponents? { { y in t[y].map { DateComponents(year: y, month: $0.0, day: $0.1) } } }

enum HolidayCatalog {
    static let springFestivalDates: [Int: (Int, Int)] = [2026: (2, 17), 2027: (2, 6), 2028: (1, 26), 2029: (2, 13), 2030: (2, 3), 2031: (1, 23)]
    static let midAutumnDates: [Int: (Int, Int)] = [2026: (9, 25), 2027: (9, 15), 2028: (10, 3), 2029: (9, 22), 2030: (9, 12), 2031: (10, 1)]

    static let all: [HolidayDef] = [
        HolidayDef(id: "newYear", name: "元旦", regions: [], offIn: [.china, .singapore, .other], date: fixed(1, 1)),
        HolidayDef(id: "valentine", name: "情人节", regions: [], offIn: [], date: fixed(2, 14), decor: Decor.hearts),
        HolidayDef(id: "springFestival", name: "春节", regions: [.china, .singapore], offIn: [.china, .singapore], date: table(springFestivalDates),
                   decorBefore: 7, decorAfter: 15, decor: Decor.lanterns),
        HolidayDef(id: "qingming", name: "清明", regions: [.china], offIn: [.china],
                   date: table([2026: (4, 5), 2027: (4, 5), 2028: (4, 4), 2029: (4, 4), 2030: (4, 5), 2031: (4, 5)])),
        HolidayDef(id: "goodFriday", name: "耶稣受难日", regions: [.singapore], offIn: [.singapore],
                   date: table([2026: (4, 3), 2027: (3, 26), 2028: (4, 14), 2029: (3, 30), 2030: (4, 19), 2031: (4, 11)])),
        HolidayDef(id: "labour", name: "劳动节", regions: [.china, .singapore], offIn: [.china, .singapore], date: fixed(5, 1)),
        HolidayDef(id: "dragonBoat", name: "端午", regions: [.china], offIn: [.china],
                   date: table([2026: (6, 19), 2027: (6, 9), 2028: (5, 28), 2029: (6, 16), 2030: (6, 5), 2031: (6, 24)]),
                   decorBefore: 2, decorAfter: 1, decorStage: .indoor, decor: Decor.zongzi),
        HolidayDef(id: "nationalDaySG", name: "国庆日", regions: [.singapore], offIn: [.singapore], date: fixed(8, 9),
                   decorBefore: 7, decorAfter: 0, decor: Decor.flags(red: 0xE8323C, white: 0xFFFFFF)),
        HolidayDef(id: "midAutumn", name: "中秋", regions: [.china, .singapore], offIn: [.china], date: table(midAutumnDates),
                   decorBefore: 1, decorAfter: 1, decorStage: .indoor, decor: Decor.mooncake),
        HolidayDef(id: "nationalDayCN", name: "国庆", regions: [.china], offIn: [.china], date: fixed(10, 1),
                   decorBefore: 0, decorAfter: 6, decor: Decor.flags(red: 0xE02B2B, white: 0xFFD84A)),
        HolidayDef(id: "halloween", name: "万圣节", regions: [], offIn: [], date: fixed(10, 31),
                   decorBefore: 5, decorAfter: 1, decorStage: .indoor, decor: Decor.pumpkin),
        HolidayDef(id: "christmas", name: "圣诞节", regions: [], offIn: [.singapore], date: fixed(12, 25),
                   decorBefore: 7, decorAfter: 1, decor: Decor.christmasLights),
    ]

    /// 当天处于装饰窗口内的节日。
    static func active(on date: Date, region: Region, calendar cal: Calendar = .current) -> [HolidayDef] {
        let y = cal.component(.year, from: date), today = cal.startOfDay(for: date)
        return all.filter { h in
            guard h.applies(to: region), h.decor != nil else { return false }
            return [y - 1, y, y + 1].contains { year in
                guard let comps = h.date(year), let d = cal.date(from: comps) else { return false }
                let diff = cal.dateComponents([.day], from: d, to: today).day ?? 999
                return diff >= -h.decorBefore && diff <= h.decorAfter
            }
        }
    }

    /// 下一个节日（含今天）及距今天数。
    static func next(from now: Date, region: Region, calendar cal: Calendar = .current) -> (HolidayDef, Int)? {
        let today = cal.startOfDay(for: now), y = cal.component(.year, from: now)
        return all.filter { $0.applies(to: region) }
            .flatMap { h in [y, y + 1].compactMap { year -> (HolidayDef, Int)? in
                guard let comps = h.date(year), let d = cal.date(from: comps) else { return nil }
                let days = cal.dateComponents([.day], from: today, to: d).day ?? -1
                return days >= 0 ? (h, days) : nil
            } }
            .min { $0.1 < $1.1 }
    }
}

struct HolidayDecorLayer: SceneLayer {
    let id: String
    let stage: SceneStage
    init(stage: SceneStage) { self.stage = stage; id = "holidayDecor.\(stage.rawValue)" }
    func draw(_ c: SceneCanvas) {
        for h in c.holidays where h.decorStage == stage { h.decor?(c) }
    }
}

/// 节日装饰的绘制。
enum Decor {
    /// 春节：刘海底下两盏会晃的红灯笼，夜里发光。
    static let lanterns: (SceneCanvas) -> Void = { c in
        guard c.hasNotch else { return }
        let nc = c.notchCols
        for (i, lx) in [nc.lowerBound + nc.count / 4, nc.upperBound - nc.count / 4].enumerated() {
            let sway = Int((sin(c.t * 1.6 + Double(i)) * 0.8).rounded())
            let y = c.notchRows + 1
            c.fill(lx, y, 1, 1, c.rgb(0x8A5A2B).color)
            c.fill(lx - 1 + sway, y + 1, 3, 3, c.rgb(0xE02B2B).color)
            c.fill(lx - 2 + sway, y + 2, 5, 1, c.rgb(0xE02B2B).color)
            c.fill(lx + sway, y + 2, 1, 1, c.rgb(0xFFD84A).color)
            c.fill(lx + sway, y + 4, 1, 1, c.rgb(0xFFD84A).color)
            if c.dark > 0.4 { c.fill(lx - 2 + sway, y, 5, 6, Color(red: 1, green: 0.3, blue: 0.2).opacity(0.18 * c.dark)) }
        }
    }

    /// 圣诞：窗框上一串闪烁的彩灯。
    static let christmasLights: (SceneCanvas) -> Void = { c in
        let colors: [Color] = [.red, Color(red: 0.3, green: 0.9, blue: 0.4), Color(red: 1, green: 0.85, blue: 0.3), Color(red: 0.4, green: 0.7, blue: 1)]
        let nc = c.notchCols
        for (i, x) in stride(from: 1, to: c.cols, by: 4).enumerated() {
            let on = (i + Int(c.t * 2)) % 3 != 0
            let y = (c.hasNotch && nc.contains(x)) ? c.notchRows + 1 : 1
            c.fill(x, y, 1, 1, colors[i % colors.count].opacity(on ? 1 : 0.35))
        }
    }

    /// 万圣节：地面右侧一盏南瓜灯，夜里发光。
    static let pumpkin: (SceneCanvas) -> Void = { c in
        let x = c.hasNotch ? c.notchCols.upperBound + 6 : c.cols - 12, y = c.floorTop - 3
        c.fill(x, y, 4, 3, c.rgb(0xF08A24).color); c.fill(x + 1, y - 1, 2, 1, c.rgb(0xF08A24).color); c.fill(x + 2, y - 2, 1, 1, c.rgb(0x3F7D3A).color)
        let eye = c.dark > 0.4 ? Color(red: 1, green: 0.9, blue: 0.4) : c.rgb(0x3A1E0E).color
        c.fill(x + 1, y + 1, 1, 1, eye); c.fill(x + 3, y + 1, 1, 1, eye)
        if c.dark > 0.4 { c.fill(x - 1, y - 1, 6, 5, Color(red: 1, green: 0.6, blue: 0.2).opacity(0.2 * c.dark)) }
    }

    /// 端午：地面上一只粽子。
    static let zongzi: (SceneCanvas) -> Void = { c in
        let x = c.hasNotch ? c.notchCols.lowerBound - 10 : 8, y = c.floorTop - 1
        c.fill(x, y, 5, 1, c.rgb(0x4F8F3A).color); c.fill(x + 1, y - 1, 3, 1, c.rgb(0x5FA347).color); c.fill(x + 2, y - 2, 1, 1, c.rgb(0x5FA347).color)
        c.fill(x + 2, y - 1, 1, 1, c.rgb(0xE8D9A8).color)
    }

    /// 中秋：地面上一块月饼。
    static let mooncake: (SceneCanvas) -> Void = { c in
        let x = c.hasNotch ? c.notchCols.lowerBound - 10 : 8, y = c.floorTop - 2
        c.fill(x, y, 4, 2, c.rgb(0xC98A3F).color); c.fill(x + 1, y - 1, 2, 1, c.rgb(0xC98A3F).color); c.fill(x + 1, y, 2, 1, c.rgb(0xE8B865).color)
    }

    /// 情人节：小猫头顶飘起的小爱心。
    static let hearts: (SceneCanvas) -> Void = { c in
        var rng = SeededRandom(seed: 214)
        for _ in 0..<4 {
            let x0 = Int(rng.next() % UInt64(max(1, c.cols))), ph = Double(rng.next() % 1000) / 1000
            let k = (ph + c.t * 0.08).truncatingRemainder(dividingBy: 1)
            let x = x0 + Int((sin(c.t + Double(x0)) * 1.5).rounded()), y = c.floorTop - 2 - Int(k * Double(c.floorTop - c.skyTop - 4))
            let col = c.rgb(0xFF6B8A).color.opacity(1 - k)
            c.fill(x, y, 1, 1, col); c.fill(x + 2, y, 1, 1, col); c.fill(x + 1, y + 1, 1, 1, col)
        }
    }

    /// 国庆：窗框上一串小旗。
    static func flags(red: UInt32, white: UInt32) -> (SceneCanvas) -> Void {
        { c in
            let nc = c.notchCols
            for (i, x) in stride(from: 2, to: c.cols - 2, by: 5).enumerated() {
                let y = (c.hasNotch && nc.contains(x)) ? c.notchRows + 1 : 1
                let flutter = (Int(c.t * 2) + i) % 2
                c.fill(x, y, 2, 1, c.rgb(i % 2 == 0 ? red : white).color)
                c.fill(x + flutter, y + 1, 1, 1, c.rgb(i % 2 == 0 ? red : white).color)
            }
        }
    }
}
