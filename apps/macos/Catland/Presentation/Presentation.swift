// 表现层（Presentation）：刘海里的落地窗场景——天空、城市、天气、季节、节日、彩蛋、事件、室内。
//
// 扩展方式：
//   - 新图层：实现 SceneLayer（id + stage + draw），在下面的 `layers` 里登记一行。
//   - 新天气效果：Modules/Weather.swift 的 `WeatherEffects.all` 里加一个 WeatherEffect。
//   - 新季节样式：Modules/Seasons.swift 的 `SeasonStyle.of` 表里改一项。
//   - 新城市地标：Modules/City.swift 的 `Landmarks.all` 里加一个 Landmark。
//   - 新节日：Modules/Holidays.swift 的 `HolidayCatalog.all` 里加一个 HolidayDef（可带装饰）。
//   - 新彩蛋：Modules/Eggs.swift 的 `Eggs.all` 里加一个 SceneEgg。
//   - 新事件：Modules/Events.swift 的 `Events.all` 里加一个 SceneEvent（排期 + 天气门槛 + 绘制 + 预告文案）。
// 模块之间不互相调用，只通过 SceneCanvas 读取共享情境。
import SwiftUI

/// 绘制阶段：决定前后遮挡关系，数值越小越靠后（越远）。
enum SceneStage: Int, Comparable {
    case sky, celestial, clouds, skyEvents, flyers, farCity, nearCity, water, shoreEvents, shore, transit,
         seasonFX, weather, frame, ornament, ceiling, decor, floor, indoor

    static func < (a: SceneStage, b: SceneStage) -> Bool { a.rawValue < b.rawValue }
}

protocol SceneLayer {
    var id: String { get }
    var stage: SceneStage { get }
    func draw(_ c: SceneCanvas)
}

enum Presentation {
    /// 唯一的图层注册表。顺序由 stage 决定，同一 stage 内按登记顺序。
    static let layers: [SceneLayer] = ordered([
        SkyLayer(), CelestialLayer(), CloudsLayer(), FlyersLayer(),
        FarCityLayer(), NearCityLayer(), WaterLayer(), MetroLayer(),
        TreesLayer(), StreetLampsLayer(), SeasonParticlesLayer(),
        WeatherLayer(),
        FrameLayer(), FrostLayer(), SeasonOrnamentLayer(), CeilingLayer(),
        HolidayDecorLayer(stage: .decor), FloorLayer(), HolidayDecorLayer(stage: .indoor),
        EggsLayer(stage: .skyEvents), EggsLayer(stage: .shoreEvents), EggsLayer(stage: .seasonFX), EggsLayer(stage: .indoor),
        EventsLayer(stage: .celestial), EventsLayer(stage: .skyEvents), EventsLayer(stage: .shoreEvents), EventsLayer(stage: .seasonFX),
    ])

    /// 按 stage 稳定排序（同一 stage 内保持登记顺序）。
    private static func ordered(_ list: [SceneLayer]) -> [SceneLayer] {
        list.enumerated().sorted { a, b in
            a.element.stage != b.element.stage ? a.element.stage < b.element.stage : a.offset < b.offset
        }.map(\.element)
    }

    static func render(_ c: SceneCanvas) {
        SceneSeason.current = c.season
        // 事件进行中（且天气允许）时，小猫停下来坐着看窗外。
        let region = RestDays.region(for: c.env.location)
        let live = EventScheduler.active(now: c.env.date, region: region, latitude: c.env.location.latitude)
        CatDirector.shared.watching = live.map { $0.event.canRun(condition: c.cond, intensity: c.intensity) } ?? false
        CatgirlDirector.shared.watching = CatDirector.shared.watching
        for layer in layers { layer.draw(c) }
    }
}
