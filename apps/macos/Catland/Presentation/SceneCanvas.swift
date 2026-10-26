// SceneCanvas：表现层所有模块共享的「画布」。
// 提供像素网格绘制（fill）、布局（刘海 / 两翼 / 天空上沿 / 城市地平线 / 地面）、
// 以及当下情境（时间、太阳、天气、季节、节日、事件）。模块只读它，不互相依赖。
// 一个美术像素 = p pt（Retina 上 1.5pt = 3 个物理像素），坐标单位都是像素格，(0,0) 为左上角。
import SwiftUI

struct SceneCanvas {
    let ctx: GraphicsContext
    let size: CGSize
    let p: CGFloat
    let env: SceneEnv
    let notch: NotchGeometry
    /// 动画时钟（秒）。
    let t: TimeInterval

    // MARK: - 布局

    var cols: Int { Int(size.width / p) }
    var rows: Int { Int(size.height / p) }
    var floorTop: Int { rows - SceneCanvas.floorRows }
    static let floorRows = 3

    /// 物理刘海在画布里占的列与行（看不见的区域）。
    var notchCols: ClosedRange<Int> {
        let w = Int((notch.notchSize.width / p).rounded())
        let left = (cols - w) / 2
        return left...(left + w - 1)
    }
    var notchRows: Int { notch.hasNotch ? Int((notch.notchSize.height / p).rounded()) : 0 }
    var hasNotch: Bool { notchRows > 0 }

    /// 天花板模式：顶部整条与刘海同为黑色天花板；窗户从天花板下沿开始。
    var ceilingMode: Bool { notch.ceiling && hasNotch }
    /// 窗户可见区域的最上一行。
    var skyTop: Int { ceilingMode ? notchRows + 1 : 0 }

    /// 城市地平线贴着地面（中间隔一条 3 行的海湾）。
    var cityBase: Int { floorTop - 3 }
    var collapsedRows: Int { Int((notch.collapsedSize.height / p).rounded(.down)) }
    /// 悬停变高时楼群按比例长高：当前可用高度 / 收起态可用高度。
    var heightScale: Double {
        let collapsedSpan = collapsedRows - SceneCanvas.floorRows - 3 - skyTop
        return min(2.4, max(1, Double(cityBase - skyTop) / Double(max(1, collapsedSpan))))
    }
    func tall(_ h: Int) -> Int { Int((Double(h) * heightScale).rounded()) }

    /// 两翼（刘海左右露出的区域）的中心列；没有刘海时取左右四分之一处。
    var wingL: Int { hasNotch ? max(4, notchCols.lowerBound / 2) : cols / 4 }
    var wingR: Int { hasNotch ? min(cols - 4, notchCols.upperBound + (cols - notchCols.upperBound) / 2) : cols * 3 / 4 }

    // MARK: - 情境

    var sun: SunPosition { SceneClock.sun(at: env.date, location: env.location) }
    var dark: Double { SceneClock.darkness(sun) }
    var dusk: Double { SceneClock.twilight(sun) }
    var cond: String { env.condition }
    var intensity: Double { env.intensity }
    var weather: WeatherStyle { WeatherStyle.of(cond) }
    var overcast: Double { weather.overcast(intensity) }
    var raining: Bool { weather.wet }
    var season: SceneSeason { SceneSeason.of(env.date, latitude: env.location.latitude) }
    var seasonStyle: SeasonStyle { SeasonStyle.of(season) }
    var holidays: [HolidayDef] { HolidayCatalog.active(on: env.date, region: RestDays.region(for: env.location)) }
    var hour: Double {
        let c = Calendar.current
        return Double(c.component(.hour, from: env.date)) + Double(c.component(.minute, from: env.date)) / 60
    }
    var isWeekend: Bool { [1, 7].contains(Calendar.current.component(.weekday, from: env.date)) }
    var clearSky: Bool { ["clear", "partly"].contains(cond) }

    /// 天空配色（已叠加季节倾向）。
    var sky: SkyPalette.Stops { seasonStyle.tint(SkyPalette.stops(darkness: dark, twilight: dusk, overcast: overcast), dark: dark) }

    // MARK: - 绘制工具

    func fill(_ x: Int, _ y: Int, _ w: Int = 1, _ h: Int = 1, _ c: Color) {
        ctx.fill(Path(CGRect(x: CGFloat(x) * p, y: CGFloat(y) * p, width: CGFloat(w) * p, height: CGFloat(h) * p)), with: .color(c))
    }

    func rgb(_ hex: UInt32) -> SkyPalette.RGB { .hex(hex) }

    /// 视差：该层随鼠标移动 depth 个像素（越远越小）。
    func parallax(_ depth: Double) -> Int { Int((Double(env.mouse) * -depth).rounded()) }

    /// 像素圆环上的点（摩天轮、彩虹等）。
    func ringPoints(_ r: Int) -> [(Int, Int)] {
        var pts: [(Int, Int)] = []
        let n = max(8, r * 8)
        for i in 0..<n {
            let a = Double(i) / Double(n) * 2 * .pi
            let pt = (Int((cos(a) * Double(r)).rounded()), Int((sin(a) * Double(r)).rounded()))
            if !pts.contains(where: { $0 == pt }) { pts.append(pt) }
        }
        return pts
    }

    /// 0~1 之间的确定性随机数（按种子）。
    static func chance(_ seed: UInt64) -> Double {
        var r = SeededRandom(seed: seed)
        return Double(r.next() % 10_000) / 10_000
    }
}
