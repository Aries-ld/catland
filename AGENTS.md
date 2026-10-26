# AGENTS.md — catland

> 给 AI 编码代理与协作者的统一说明。产品目标、资源、约定只在这里维护一份。

## 1. 产品

- **一句话**：常驻 macOS 刘海（灵动岛）的聚合刷刷器——一键开刷小红书 / 抖音 / B 站 / X 等平台的内容，跨淘宝 / 京东浏览和比价商品。
- **命名**：基于 [catbus](https://github.com/cv-cat/catbus)（猫巴士把各平台小猫装上车）；catland 把小猫放进同一片 land，land 也谐音 island（灵动岛）。
- **目标用户**：vibe coding / 工作摸鱼的碎片时间里，懒得拿起手机、打开 App 的人。点一下就开刷。
- **定位**：基于爬虫数据，**不商用、只开源**，追求影响力。所有数据与登录态只留在用户本机。
- **核心原则**：catland 是凌驾于各 UGC 平台之上的一层：点赞、收藏、浏览历史都**收敛在 catland 本地**，默认不回写到原平台。

### 1.1 已定决策（详见 `docs/decisions/0001-architecture-and-mvp-scope.md`）

- **纯本地（红线）**：无自有服务器、无账号体系、无遥测；网络请求只发往用户连接的平台。例外：刘海场景的天气联动（匿名 GET、不带用户信息、30 分钟缓存，设置里可关）——新加坡用 NEA（data.gov.sg），其他地区用 Open-Meteo，坐标先粗化到 0.1°。sidecar 与 App 走 stdio，不监听端口；新增密钥存钥匙串。
- 技术栈：Swift 原生客户端（刘海 NSPanel + AVPlayer）+ Node sidecar 包装 catbus。
- MVP：连接面板 + 登录、灵动岛 + 小猫动画、视频/内容板块；电商延后到 v2。
- 点赞 / 收藏 / 历史只存本地，不回写原平台。
- 只做 macOS，不做云同步、不做自动更新。
- 登录：支持扫码的平台（xhs / douyin / bilibili / kuaishou / xianyu / jd）在面板内扫码；只支持 cookie 的平台（tiktok / weibo / x / taobao）自动打开内嵌官方登录页，用户登录完成后自动获取登录态写入 catbus，用户不接触 cookie。
- 美术：**像素风**，开发阶段用 Meowa 生成并打包进 App（运行时不联网生成）。小猫要有多套形象 × 多套动作，运行时随机组合展示，避免固定循环。审美把关：统一调色板、尺寸、光源与描边规范，每批素材按原生倍数检查后才入库。

## 2. 资源

| 资源 | 位置 / 用法 |
|---|---|
| catbus CLI | 全局 `catbus` 0.2.1。登录态在 `~/.catbus/` |
| catbus 源码（只读参考） | `vendor/catbus/`，不进版本控制。能力矩阵 `vendor/catbus/docs/capabilities.md`，统一类型 `vendor/catbus/docs/guide/output.md` |
| 美术（Meowa game-assets skill） | `~/.agents/skills/game-assets/meowart_api.py`，用 conda env `catlands` 运行，key 从项目根 `.env` 的 `MEOWART_API_KEY` 读取 |
| Python 环境 | conda env `catlands`（Python 3.12）：`~/miniconda3/envs/catlands/bin/python` |

| 小猫美术 | **手绘像素（代码生成，用户确认保持此风格）**：`apps/macos/Catland/Cat/PixelCatArt.swift`。Meowa 版（`assets/art/cats/`，`scripts/gen_cats.py` / `pack_cats.py`）用户觉得不如手绘可爱，已不打包进 App，仅留档 |

| 开发者文档 | `docs/development.md`（开发运行、打包、品牌素材、sidecar RPC、目录结构）；README 是面向用户的产品介绍页 |

后续新资源统一补充到本表。

### 2.1 小猫美术规范

- 风格：手绘像素、Q 版大头、色块干净。画布 16×12，朝左绘制；一个美术像素 = 1.5pt（Retina 上 3 个物理像素，整数倍保证锐利）。
- 部件化：头（normal / blink / happy / yawn / lick / lookAhead / lookBack / lookUp）+ 身体姿势（stand / sit / loaf / stretch / back）+ 腿 + 尾巴 + 粒子（z、爱心、蝴蝶）组合成帧；花色由涂装规则上色（条纹、三花色块、暹罗重点色、白袜子），深色猫加浅色描边。
- 现有 10 种花色 × 12 个动作：idle walk look sit groom yawn nap loaf stretch hop play roll。动作带 intro / 循环段 / outro 与权重，由 `CatDirector`（`CatStage.swift`）随机编排。
- 新增动作：在 `PixelCatArt.actions` 里加一组 Frame；跑 Swift 测试（尺寸、可渲染）并生成预览图人工把关后再提交。
- 刘海下方「小猫步道」（默认开，设置里可关）：物理刘海没有像素，步道让小猫能从刘海下方走过。
- **表现层**（刘海里的落地窗场景：天空、城市、天气、季节、节日、彩蛋、事件、室内）在 `apps/macos/Catland/Presentation/`，结构、原则与扩展清单见 `docs/decisions/0003-presentation-layer.md`。新增内容走对应注册表（`Presentation.layers` / `WeatherEffects.all` / `SeasonStyle.of` / `Landmarks.all` / `HolidayCatalog.all` / `Eggs.all` / `Events.all`），模块之间不互相调用，只读 `SceneCanvas`。
- 刘海创意（默认都开）：**猫洞**（猫走到刘海下方跳进去，洞口垂尾巴 / 扒爪子 / 飘 z，过一阵跳下来；`CatDirector` 的 toDen → climbing → inDen → dropping）和**地铁隧道**（刘海 = 隧道口，MRT 小列车每 50 秒穿过，`MetroLayer`）。切换：`catland-debug notch:den|tunnel|both|beam`，`catland-debug den` 强制一只猫进洞。
- 所在地：Mac 系统定位（CoreLocation，与 VPN / IP 无关），未授权时按系统时区估计（`LocationProvider`）。太阳、天气、地标、节日地区都跟随所在地。
- 事件：每次 10 分钟；开始前 6 小时 / 1 小时 / 10 分钟小猫主动探出刘海预告，悬停气泡最前面显示倒计时；开始时天气不允许就取消；进行中小猫坐着抬头看（`watch`）。
- 气泡语料在 `apps/macos/Catland/Scene/BubbleCopy.swift`：受众是打工人，做陪伴——不说教、不打鸡血，站在打工人这边，小红书风（可爱、有梗）。三类交错（闲聊 / 时间 / 戳我），每句停 5 秒，每次悬停从第一句开始；单句不超过 22 个字。
- 平台图标：`scripts/fetch_platform_icons.py`，地址固定在 PINNED（人工确认的干净版本，不随活动图标变化）。界面统一用 `PlatformIcon` / `PlatformBadge`。
- 调试命令见 ADR 0003（`catland-debug date: / scene: / event: / egg: / say: / hoverpin` 等）。

## 3. 约定

- 密钥只放 `.env`（已 gitignore），模板见 `.env.example`；不写进代码、日志、提交。
- `vendor/` 只读，不修改 catbus 受版本控制的文件。
- catbus 写操作（点赞、评论、关注、发布）会触发平台风控，默认不调用；遇到 `RISK_CONTROL` 停止，不自动重试。
- 设计决策记录在 `docs/decisions/`（ADR）。
- sidecar 调 catbus 只经 `CatbusRunner`（`apps/sidecar/src/catbus/runner.ts`）：用随包的 `catbus-cli`（版本锁定），凭证经 stdin 传、不进 argv 和日志；stdout 只留给 RPC，日志只写文件。
- 新依赖锁精确版本，且选发布满 7 天的版本。
- 内容体验对标抖音 / 小红书（手感、布局、时延），指标与预加载策略见 `docs/decisions/0002-content-pipeline-and-preloading.md`；改动内容管线后跑 `npm run smoke:feed` 对照指标。
- 媒体请求头按平台给（`MEDIA_HEADERS`），不要统一加 Referer：X 带错 Referer 会 403。
- 交互类 bug（点不动、点错）先复现再修：加点击诊断日志（落在哪个视图），用真实点击复现，看到原因再改，不凭猜测修。
- 验证会写用户真实数据（点赞、收藏、登录态）的操作要成对、可撤销，结束后核对；用户正在使用 App 时，不做自动点击等打扰操作，先征得同意。
- 调试覆盖（`catland-debug date: / scene: / city: / event:` 等）用完必须复原（`date:off`、`scene:off`、重启 App），不要留给用户。
- 批量改代码后，用效果验证（截图 / 测试 / 日志），不只看编译通过：替换没匹配上时不会报错。
- 界面自检截图只用 `shot-window`（只拍 catland 窗口），不要全屏截图，避免拍到用户其他应用的内容。
- 面板是不抢焦点的 NSPanel：系统控件（Toggle 等）会显示为非活跃样式，用自绘控件（如 `PillToggle`）。
- NSViewRepresentable 包装的 AppKit 视图（如视频的 AVPlayerLayer）连同 SwiftUI 给它包的容器（PlatformGroupContainer）会抢在其上方的 SwiftUI 按钮之前接到点击：纯展示视图实现 `DisplayOnlyView`，`FirstMouseHostingView.hitTest` 会把落在它（及只包着它的容器）上的点击交还 SwiftUI。屏幕外预渲染的卡片要 `.allowsHitTesting(false)`——`.clipped()` 只裁画面不裁点击区域。自绘按钮的 label 要加 `contentShape`，否则只有实色像素可点。

## 4. 常用命令

```bash
# sidecar（apps/sidecar，Node 26 直接运行 .ts，TS 7 只做类型检查）
cd apps/sidecar && npm run typecheck && npm test   # 每次改动后必跑
npm run smoke                                       # 真机只读冒烟，日志在 ~/Library/Logs/catland/sidecar.log
npm run smoke:accounts [platform]                   # 账号面板 + 体检 + 扫码取到二维码后立即取消
npm run smoke:feed [条数] [停留ms]                   # 混排刷 N 条：首屏、划动等待、媒体可达性
npm run smoke:rpc                                   # 以子进程启动 sidecar，经 stdio RPC 走全流程（临时数据目录）

# macOS App（apps/macos，XcodeGen 生成工程，project.yml 是唯一来源）
apps/macos/scripts/run.sh                           # 生成工程 + 构建 + 启动调试版
cd apps/macos && xcodebuild -project Catland.xcodeproj -scheme Catland -derivedDataPath build/DerivedData test
apps/macos/build/catland-debug <pin|unpin|toggle|next|prev|right|pause|comments|connections|settings|saved|close|boss>  # 仅调试版：驱动界面
apps/macos/build/shot-window /tmp/x.png             # 只截 catland 自己的窗口（不拍用户其他应用）
# App 日志：~/Library/Logs/catland/app.log；sidecar 日志：~/Library/Logs/catland/sidecar.log


# macOS 客户端（apps/macos）
apps/macos/scripts/run.sh                           # 开发版：构建并启动
scripts/package-dmg.sh [arm64|x86_64]               # 打包可分发的 DMG（自带 Node + sidecar + catbus，ad-hoc 签名），产物在 dist/
~/miniconda3/envs/catlands/bin/python scripts/make_icons.py        # App 图标 + 菜单栏图标
~/miniconda3/envs/catlands/bin/python scripts/make_readme_art.py   # README banner / 场景拼图（先 catland-debug snapshots:/tmp/catland-snaps 离屏渲染）

catbus auth list                                  # 已登录的平台
catbus <platform> feed list --limit 10            # 推荐流
catbus <platform> item search <kw> --limit 20     # 搜索
catbus <platform> item media <item>               # 可播放媒体地址
~/miniconda3/envs/catlands/bin/python ~/.agents/skills/game-assets/meowart_api.py credits-balance
```
