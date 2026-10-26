// RestDays：地区判定 + 「下一个节日」，节假日数据统一来自表现层的 HolidayCatalog。
import Foundation

enum RestDays {
    typealias Region = Catland.Region

    static func region(for loc: SceneLocation, timeZone: TimeZone = .current) -> Region {
        if loc.skyline == .singapore || timeZone.identifier == "Asia/Singapore" { return .singapore }
        if loc.skyline == .shanghai || ["Asia/Shanghai", "Asia/Chongqing", "Asia/Urumqi", "Asia/Harbin"].contains(timeZone.identifier) { return .china }
        return .other
    }

    /// 下一个节日（含今天）及距今天数。
    static func nextHoliday(from now: Date, region: Region, calendar cal: Calendar = .current) -> (HolidayDef, Int)? {
        HolidayCatalog.next(from: now, region: region, calendar: cal)
    }
}
