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
    /// 窗外地标用哪个城市的天际线。
    var skyline: Skyline { Skyline.nearest(latitude: latitude, longitude: longitude) }

    static let singapore = SceneLocation(name: "新加坡", latitude: 1.2903, longitude: 103.8520, source: .timezone)
}

enum Skyline: String {
    case singapore, shanghai, generic

    private static let cities: [(Skyline, Double, Double)] = [(.singapore, 1.29, 103.85), (.shanghai, 31.23, 121.47)]

    /// 120km 以内的已知城市用它的地标，否则用通用楼群。
    static func nearest(latitude: Double, longitude: Double) -> Skyline {
        for (city, lat, lon) in cities {
            let dLat = (lat - latitude) * 111, dLon = (lon - longitude) * 111 * cos(latitude * .pi / 180)
            if dLat * dLat + dLon * dLon < 120 * 120 { return city }
        }
        return .generic
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
            let loc = SceneLocation(name: Self.cityName(for: TimeZone.current) ?? "当前位置", latitude: l.coordinate.latitude,
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
        return SceneLocation(name: cityName(for: .current) ?? "当前位置", latitude: v[0], longitude: v[1], source: .system)
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
