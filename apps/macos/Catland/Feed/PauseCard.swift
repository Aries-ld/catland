// 猫猫卡：推荐流暂时没货时插进来的一张整屏卡片（设计见 ADR 0002「请求节奏」）。
// - 在路上：下一条 1.5 秒内没准备好（常见于只刷一个平台）。猫抱着纸箱来回走；新内容一到，变成「搬到啦，往下滑继续」。
// - 休息站：开着的平台都在冷却、或都用完了这一小时的额度。猫们趴着打盹，轮到的那只说一句，中间是倒计时；倒计时前划不动。
import SwiftUI

/// 推荐流当前的暂停状态（由 FeedController 维护）。
struct PauseInfo: Equatable {
    enum Mode: Equatable { case waiting, resting }
    var mode: Mode
    /// 预计恢复的时间（休息站的倒计时）。
    var resumeAt: Date?
    /// 新内容已经到了：卡片提示往下滑继续。
    var arrived = false
    /// 这一批已经搬到几张（攒够 batch 张就放行）。
    var progress = 0
    var batch = 3
    /// 这次出场说话的猫，和一起打盹的猫。
    var speaker: Persona
    var cats: [Persona]
    /// 只开了一个平台（在路上时补一句「猫猫比较辛苦」）。
    var single: Bool
    /// 这次说哪一句（每次出现换一句）。
    var line: Int
}

extension FeedCard {
    static let pauseKind = "pause"
    var isPause: Bool { kind == Self.pauseKind }

    /// 猫猫卡在推荐流里占一个位置，但没有媒体。
    static func pause() -> FeedCard {
        FeedCard(key: "pause:\(UUID().uuidString)", platform: "catland", id: "", url: "", kind: pauseKind, title: nil, text: nil,
                 author: nil, createdAt: nil, cover: nil, stats: ItemStats(views: nil, likes: nil, comments: nil, collects: nil, shares: nil),
                 video: nil, images: [], expiresAt: .greatestFiniteMagnitude, liked: nil, collected: nil)
    }
}

/// 每只猫在猫猫卡上的话术（按性格；休息站按时段分「干活去」和「早点睡」）。
enum PauseCopy {
    static func waiting(_ p: Persona) -> [String] {
        switch p {
        case .shushu: return ["本小姐正在挑下一条，别催～", "好看的要慢慢挑嘛", "稍等，本小姐在补妆…不是，在搬内容"]
        case .doudou: return ["家人们稍等，好东西马上到", "下一条在路上了，别划走", "正在加载快乐，请稍候"]
        case .bibi: return ["才、才没有偷懒…马上就好！", "下一条在缓冲啦，别急嘛", "等我一下下，就一下"]
        case .tietie: return ["老铁别急，这就给你整来", "马上马上，搬着呢", "稍等一会儿，好货在后头"]
        case .box: return ["猫猫在搬了…稍等一下下"]
        }
    }

    static func arrived(_ p: Persona) -> String {
        switch p {
        case .shushu: return "搬到啦！本小姐挑的，往下滑看看"
        case .doudou: return "到货了家人们！往下滑继续"
        case .bibi: return "好、好了！往下滑嘛"
        case .tietie: return "整来了老铁！往下滑接着看"
        case .box: return "搬到啦！往下滑继续"
        }
    }

    static func resting(_ p: Persona, hour: Int) -> [String] {
        let late = hour >= 23 || hour < 6
        switch p {
        case .shushu: return late ? ["这么晚了，本小姐也要睡美容觉", "眼睛要熬坏啦，快去睡"] : ["嘘——老板来了", "本小姐累了，你也歇会儿", "刷了好久啦，喝口水吧"]
        case .doudou: return late ? ["家人们，下播睡觉啦", "今天的快乐额度用完了，明天见"] : ["今天的快乐额度用完啦，过会儿见", "家人们，先去搬会儿砖", "嘘，老板在后面"]
        case .bibi: return late ? ["都几点了！快去睡啦笨蛋", "才不是关心你…早点睡"] : ["才不是关心你…眼睛该休息了", "休、休息一下嘛，又不会跑", "去干会儿活，我在这儿等你"]
        case .tietie: return late ? ["大半夜的，老铁睡觉去", "熬夜伤身，明儿再刷"] : ["都玩了好久了，干会儿活去！", "老铁歇会儿，活儿还等着呢", "嘘，领导过来了"]
        case .box: return ["猫猫们睡着了…过一会儿再来"]
        }
    }
}

struct PauseCardView: View {
    let pause: PauseInfo
    let size: CGSize

    var body: some View {
        ZStack {
            background
            VStack(spacing: 18) {
                Spacer()
                cats
                bubble
                if pause.mode == .waiting && !pause.arrived { progressBar }
                if pause.mode == .resting && !pause.arrived { countdown }
                if pause.arrived { swipeHint }
                Spacer()
                if pause.mode == .waiting && pause.single && !pause.arrived {
                    Text("只刷一个平台时，猫猫会比较辛苦，搬得慢一点")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                }
            }
            .padding(.horizontal, 28).padding(.bottom, 36)
        }
        .frame(width: size.width, height: size.height)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: pause.arrived)
    }

    private var background: some View {
        ZStack {
            LinearGradient(colors: pause.mode == .resting
                           ? [Color(red: 0.05, green: 0.06, blue: 0.16), Color(red: 0.12, green: 0.1, blue: 0.24)]
                           : [Color(red: 0.16, green: 0.2, blue: 0.38), Color(red: 0.42, green: 0.32, blue: 0.5)],
                           startPoint: .top, endPoint: .bottom)
            // 几颗像素星星
            Canvas { ctx, sz in
                var rng = SeededRandom(seed: 7)
                for _ in 0..<40 {
                    let x = CGFloat(rng.next() % 1000) / 1000 * sz.width, y = CGFloat(rng.next() % 1000) / 1000 * sz.height * 0.6
                    ctx.fill(Path(CGRect(x: x, y: y, width: 2, height: 2)), with: .color(.white.opacity(0.25 + Double(rng.next() % 50) / 100)))
                }
            }
        }
    }

    private var cats: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if pause.mode == .resting && !pause.arrived {
                ForEach(pause.cats, id: \.self) { p in CatSprite(skin: p.skin, action: p == pause.speaker ? "sit" : "nap", scale: 5) }
            } else {
                ZStack(alignment: .bottomTrailing) {
                    CatSprite(skin: pause.speaker.skin, action: pause.arrived ? "hop" : "walk", scale: 7)
                    if !pause.arrived { // 抱着的纸箱
                        RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.78, green: 0.58, blue: 0.36))
                            .frame(width: 26, height: 20)
                            .overlay(Rectangle().fill(Color(red: 0.62, green: 0.44, blue: 0.26)).frame(height: 3))
                            .offset(x: 14, y: -6)
                    }
                }
            }
        }
    }

    private var bubble: some View {
        let text: String = {
            if pause.arrived { return pause.mode == .resting ? "\(pause.speaker.name)：猫猫回来啦！往下滑继续" : "\(pause.speaker.name)：\(PauseCopy.arrived(pause.speaker))" }
            let pool = pause.mode == .resting ? PauseCopy.resting(pause.speaker, hour: Calendar.current.component(.hour, from: Date())) : PauseCopy.waiting(pause.speaker)
            return "\(pause.speaker.name)：\(pool[pause.line % pool.count])"
        }()
        return Text(text)
            .font(.system(size: 15, weight: .medium)).foregroundStyle(Color(white: 0.12))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white))
            .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
    }

    private var countdown: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tl in
            let left = max(0, (pause.resumeAt ?? tl.date).timeIntervalSince(tl.date))
            Text(String(format: "%02d:%02d", Int(left) / 60, Int(left) % 60))
                .font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(.white)
        }
    }

    /// 搬运进度：这一批搬到了几张（纸箱一格一格装满），正在搬的那一格轻轻闪；
    /// 平台这一分钟的额度用完、要等一会儿才能接着搬时，说清楚还要等几秒，别让人以为卡住了。
    private var progressBar: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { tl in
            let wait = max(0, (pause.resumeAt ?? tl.date).timeIntervalSince(tl.date))
            let pulse = Int(tl.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(0..<pause.batch, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(i < pause.progress ? Color(red: 0.95, green: 0.72, blue: 0.4)
                                  : (i == pause.progress && wait < 3 ? Color(red: 0.95, green: 0.72, blue: 0.4).opacity(pulse ? 0.45 : 0.2) : .white.opacity(0.15)))
                            .frame(width: 46, height: 8)
                    }
                }
                Text(wait >= 90 ? "猫猫歇口气，约 \(Int((wait / 60).rounded(.up))) 分钟后接着搬"
                     : (wait >= 3 ? "猫猫歇口气，约 \(Int(wait.rounded())) 秒后接着搬" : "搬运中 \(pause.progress)/\(pause.batch)"))
                    .font(.system(size: 11, weight: .medium)).monospacedDigit()
                    .foregroundStyle(.white.opacity(0.6))
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: pause.progress)
        }
    }

    private var swipeHint: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
            Image(systemName: "chevron.down")
                .font(.system(size: 22, weight: .bold)).foregroundStyle(.white.opacity(0.85))
                .offset(y: sin(tl.date.timeIntervalSinceReferenceDate * 4) * 5)
        }
    }
}
