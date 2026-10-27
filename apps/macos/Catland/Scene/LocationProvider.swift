// LocationProvider：用 Mac 系统定位（CoreLocation，基于 Wi‑Fi，与 VPN / IP 无关）确定所在地，
// 驱动太阳位置与天气。未授权或失败时，退回按系统时区估计城市——也不看 IP。
// 位置只留在本机；向天气服务发送时由 sidecar 粗化到 0.1°。
import CoreLocation
import Foundation

struct SceneLocation: Equatable {
    enum Source: String { case system, timezone }

    let name: String
    let latitude: Double
    let longitude: Double
    let source: Source
    /// 真正所在的已知城市（120km 以内）；不在任何已知城市附近时为 nil。节假日地区等按它判断。
    var city: Skyline? { Skyline.known(latitude: latitude, longitude: longitude)?.city }
    /// 窗外地标用哪个城市的天际线：在已知城市就用它，否则用随机选定的北京 / 上海。
    var skyline: Skyline { city ?? Skyline.fallback }

    static let singapore = SceneLocation(name: "新加坡", latitude: 1.2903, longitude: 103.8520, source: .timezone)
    static let shanghai = SceneLocation(name: "上海", latitude: 31.23, longitude: 121.47, source: .timezone)
    static let beijing = SceneLocation(name: "北京", latitude: 39.90, longitude: 116.40, source: .timezone)
}

/// 有专属地标的城市。新增城市：在这里登记坐标和名字，再在 City.swift 里实现它的 Landmark。
enum Skyline: String, CaseIterable {
    case singapore, shanghai, beijing

    private static let cities: [(city: Skyline, name: String, lat: Double, lon: Double)] = [
        (.singapore, "新加坡", 1.29, 103.85), (.shanghai, "上海", 31.23, 121.47), (.beijing, "北京", 39.90, 116.40),
    ]

    /// 120km 以内的已知城市。
    static func known(latitude: Double, longitude: Double) -> (city: Skyline, name: String)? {
        for c in cities {
            let dLat = (c.lat - latitude) * 111, dLon = (c.lon - longitude) * 111 * cos(latitude * .pi / 180)
            if dLat * dLat + dLon * dLon < 120 * 120 { return (c.city, c.name) }
        }
        return nil
    }

    private static let fallbackKey = "fallbackSkyline"
    /// 不在任何已知城市附近时，窗外用北京或上海的天际线：第一次随机抽一个并记住，之后保持不变（天气和时间仍跟随真实所在地）。
    static var fallback: Skyline {
        if let raw = UserDefaults.standard.string(forKey: fallbackKey), let s = Skyline(rawValue: raw), s != .singapore { return s }
        let pick: Skyline = Bool.random() ? .beijing : .shanghai
        UserDefaults.standard.set(pick.rawValue, forKey: fallbackKey)
        return pick
    }
}

@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var onUpdate: ((SceneLocation) -> Void)?
    private static let cacheKey = "lastLocation"

    /// 启动时先给出缓存的系统定位或时区估计，拿到系统定位后再回调一次。
    func start(_ onUpdate: @escaping (SceneLocation) -> Void) {
        self.onUpdate = onUpdate
        onUpdate(Self.cached() ?? Self.fromTimeZone())
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorized: manager.requestLocation()
        default: AppLog.info("location not authorized, using time zone", ["tz": TimeZone.current.identifier])
        }
    }

    /// 每隔一段时间刷新一次（出差 / 换城市）。
    func refresh() {
        if [.authorizedAlways, .authorized].contains(manager.authorizationStatus) { manager.requestLocation() }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let s = manager.authorizationStatus
            AppLog.info("location authorization", ["status": s.rawValue])
            if s == .authorizedAlways || s == .authorized { manager.requestLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last else { return }
        Task { @MainActor in
            // 城市名：在已知城市附近用它的名字（北京用户的系统时区也是 Asia/Shanghai，不能按时区叫「上海」）
            let known = Skyline.known(latitude: l.coordinate.latitude, longitude: l.coordinate.longitude)?.name
            let loc = SceneLocation(name: known ?? Self.cityName(for: TimeZone.current) ?? "当前位置", latitude: l.coordinate.latitude,
                                    longitude: l.coordinate.longitude, source: .system)
            UserDefaults.standard.set([loc.latitude, loc.longitude], forKey: Self.cacheKey)
            AppLog.info("location", ["source": "system", "skyline": loc.skyline.rawValue])
            self.onUpdate?(loc)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in AppLog.warn("location failed", ["err": error.localizedDescription]) }
    }

    private static func cached() -> SceneLocation? {
        guard let v = UserDefaults.standard.array(forKey: cacheKey) as? [Double], v.count == 2 else { return nil }
        let known = Skyline.known(latitude: v[0], longitude: v[1])?.name
        return SceneLocation(name: known ?? cityName(for: .current) ?? "当前位置", latitude: v[0], longitude: v[1], source: .system)
    }

    // MARK: - 时区兜底

    private static let zones: [String: (String, Double, Double)] = [
        "Asia/Shanghai": ("上海", 31.23, 121.47), "Asia/Chongqing": ("重庆", 29.56, 106.55), "Asia/Urumqi": ("乌鲁木齐", 43.83, 87.62),
        "Asia/Hong_Kong": ("香港", 22.32, 114.17), "Asia/Macau": ("澳门", 22.2, 113.55), "Asia/Taipei": ("台北", 25.03, 121.57),
        "Asia/Singapore": ("新加坡", 1.29, 103.85), "Asia/Kuala_Lumpur": ("吉隆坡", 3.14, 101.69), "Asia/Tokyo": ("东京", 35.68, 139.69),
        "Asia/Seoul": ("首尔", 37.57, 126.98), "Asia/Bangkok": ("曼谷", 13.76, 100.5), "Asia/Dubai": ("迪拜", 25.2, 55.27),
        "Europe/London": ("伦敦", 51.51, -0.13), "Europe/Paris": ("巴黎", 48.86, 2.35), "Europe/Berlin": ("柏林", 52.52, 13.4),
        "America/New_York": ("纽约", 40.71, -74.0), "America/Los_Angeles": ("洛杉矶", 34.05, -118.24), "America/Chicago": ("芝加哥", 41.88, -87.63),
        "America/Toronto": ("多伦多", 43.65, -79.38), "Australia/Sydney": ("悉尼", -33.87, 151.21),
    ]

    static func cityName(for tz: TimeZone) -> String? { zones[tz.identifier]?.0 }

    /// 系统时区 → 代表城市；未知时区按 UTC 偏移估经度。
    static func fromTimeZone(_ tz: TimeZone = .current) -> SceneLocation {
        if let z = zones[tz.identifier] { return SceneLocation(name: z.0, latitude: z.1, longitude: z.2, source: .timezone) }
        let lon = Double(tz.secondsFromGMT()) / 3600 * 15
        return SceneLocation(name: tz.identifier, latitude: 30, longitude: lon, source: .timezone)
    }
}
