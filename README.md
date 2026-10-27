<div align="center">

<img src="assets/brand/banner.png" width="100%" alt="catland — 把小猫们装进你的刘海里，点一下就开刷">

<br>

**MacBook 的刘海，是你离摸鱼最近的地方。**<br>
小红书 · 抖音 · Bilibili · 快手，点一下刘海就开刷。

<br>

[![macOS](https://img.shields.io/badge/macOS-14%2B-000000?style=for-the-badge&logo=apple&logoColor=white)](#-下载安装)
[![License: MIT](https://img.shields.io/badge/license-MIT-A6E3A1?style=for-the-badge)](LICENSE)
[![Local First](https://img.shields.io/badge/数据-只在本机-F38BA8?style=for-the-badge)](#-隐私纯本地)
[![Powered by catbus](https://img.shields.io/badge/powered%20by-catbus-FAB387?style=for-the-badge)](https://github.com/cv-cat/catbus)
[![Agent Ready](https://img.shields.io/badge/AI%20Agent-可直接构建-CBA6F7?style=for-the-badge)](#-让-agent-帮你从源码构建)

[下载安装](#-下载安装) · [它能做什么](#-它能做什么) · [刘海里的小世界](#-刘海里的小世界) · [从源码构建](#-从源码构建) · [开发者文档](docs/development.md)

</div>

<br>

> [catbus](https://github.com/cv-cat/catbus)（猫巴士）把各个平台的小猫装上同一辆车；**catland 把它们放进同一片 land**——你 MacBook 屏幕顶上的那块刘海（land 也谐音 is**land**，灵动岛）。
>
> 写代码等编译、跑模型等结果、开会等别人说完……这些碎片时间里，你不想拿起手机、不想切窗口、更不想一个个打开 App。**鼠标往刘海上一放，点一下，就开刷。**

## ✨ 它能做什么

<table>
<tr>
<td width="50%" valign="top">

### 🐾 刘海就是入口
平时刘海里是一面像素风落地窗：窗外是你所在城市的天际线，小猫在窗台上散步、打盹、钻进刘海里的「猫洞」。鼠标移上去小猫会蹦一下跟你打招呼，**点一下就展开成刷刷面板**，再点外面就收起。老板来了？`⌥ Esc` 一键收起并暂停。

</td>
<td width="50%" valign="top">

### 📱 多平台混排，手感对标短视频 App
小红书、抖音、Bilibili……的推荐流混在一条流里，**各平台均匀轮换、看过的不再出现**。封面先行、前后条预加载，划到下一条几乎零等待；触控板一滑一页，横屏视频居中铺模糊底，图文左右翻页，评论抽屉一点就开。

</td>
</tr>
<tr>
<td width="50%" valign="top">

### ❤️ 点赞收藏只留在本地
在 catland 里点赞、收藏，**不会回写到原平台**，不会被推荐算法拿去「更懂你」，也不会出现在你的主页。所有平台的喜欢，收在同一个地方。

</td>
<td width="50%" valign="top">

### 🔒 纯本地，没有服务器
没有 catland 账号、没有云端、没有遥测。登录态在你 Mac 的 `~/.catbus/`，点赞 / 收藏 / 历史在本机数据库，App 和本地服务之间连网络端口都不开。

</td>
</tr>
</table>

## 🌆 刘海里的小世界

刘海不只是入口，也是一个会陪你上班的小世界。我们把天气、季节、节日、彩蛋、事件统称为**表现层**，全部手绘像素风：

<div align="center">
<img src="assets/brand/scenes.png" width="88%" alt="刘海里的场景：四季、昼夜、天气与事件">
</div>

- **跟你同一片天**：用 Mac 的系统定位（不看 IP，挂 VPN 也准），窗外的日出日落、晴雨雪雾跟你所在城市一致；上海能看到东方明珠，新加坡能看到金沙和摩天轮。
- **四季会变**：春天飘樱花、夏夜有萤火虫、秋天落叶、冬天窗户结霜、挂满冰凌。
- **节日有仪式感**：春节挂红灯笼、中秋一整晚的金色满月、万圣节南瓜灯、圣诞彩灯。
- **会发生大事件**：真实流星雨极大日的流星雨、夏夜花火大会、滨海湾灯光秀、樱花雨、热气球节……**小猫会提前 6 小时预告**，事件开始时大家一起坐下来看窗外。
- **随机彩蛋**：雨天海湾里漂着纸船，工作日上午窗台上有杯冒热气的咖啡，偶尔……会有 UFO。
- **一只懂你的猫**：悬停刘海，小猫会跟你聊两句——「今日搬砖进度 63%，快通关了」「老板画的饼，猫猫不吃」「距国庆还有 5 天，数着日子摸鱼」。

## 📦 下载安装

1. 到 [Releases](https://github.com/Aries-ld/catland/releases) 下载对应芯片的 DMG：
   - Apple 芯片（M1 / M2 / M3 / M4…）：`catland-x.y.z-macos-arm64.dmg`
   - Intel 芯片：暂未提供安装包，请按下面的「从源码构建」在本机打包
2. 打开 DMG，把 **catland** 拖进「应用程序」。
3. 在「应用程序」里打开 catland。安装包经过 Apple 开发者签名与公证，和其他正规 App 一样双击即可打开。
4. 打开后刘海里会出现小猫。点一下刘海 → **连接平台**：
   - 小红书、Bilibili、快手：用手机 App 扫码。
   - 抖音：在弹出的抖音官方登录页里扫码或用验证码登录，完成后自动连接。

> App 里已经自带运行所需的一切（Node 运行时、本地服务、catbus），不需要另外安装任何东西。需要 macOS 14 及以上，带刘海的 MacBook 体验最好；没有刘海的 Mac 也能用，小猫会住在屏幕顶部正中。

## ⌨️ 快捷键

| 操作 | 方式 |
|---|---|
| 呼出 / 收起 | 点刘海，或 `⌥ \`` |
| 老板键 | `⌥ Esc`：立刻收起并暂停 |
| 翻页 | 触控板上下滑、鼠标滚轮、`↑` `↓` / `J` `K` |
| 图集翻页 | 触控板左右滑、`←` `→` |
| 点赞 / 收藏 / 评论 | 双击画面或 `L` / `S` / `C` |
| 暂停 / 静音 | `空格` / `M`（默认静音） |

## 🧩 支持的平台

| 平台 | 登录方式 | 状态 |
|---|---|---|
| 小红书 | 扫码 | ✅ 已实测 |
| Bilibili | 扫码 | ✅ 已实测 |
| 抖音 | 官方登录页（扫码 / 验证码） | ✅ 已实测 |
| 快手 | 扫码 | ✅ 已实测 |
| 微博 | — | ⏸ 暂未开放：catbus 还不支持微博推荐流，能登录但刷不出内容 |
| X · TikTok | — | ⏸ 暂未开放：很多账号用 Google / Apple 登录，而这两家不允许在 App 内登录（TikTok 还需要特定网络）。等「浏览器助手」能把浏览器里的登录态自动交给 catland 后再开放 |
| 淘宝 · 京东 · 闲鱼 | — | 🚧 电商比价，下个版本 |

平台能力来自 [catbus](https://github.com/cv-cat/catbus)，它支持的平台 catland 都可以逐步接进来。

## 🛠 从源码构建

不想用打包好的 DMG，或者想自己改？在你的 Mac 上几分钟就能构建：

```bash
# 准备（只需一次）：Xcode 16+、Homebrew
brew install node xcodegen             # Node 需要 26 及以上
git clone https://github.com/Aries-ld/catland.git && cd catland
(cd apps/sidecar && npm install)

# 方式一：直接运行开发版
apps/macos/scripts/run.sh

# 方式二：打包成和 Releases 一样的 DMG（产物在 dist/）
scripts/package-dmg.sh
```

### 🤖 让 Agent 帮你从源码构建

把下面这段话直接发给 Claude Code / Codex / Cursor 等编码 Agent 就行：

```text
请在我的 Mac 上从源码构建并安装 catland（https://github.com/Aries-ld/catland）：
1. 确认已安装 Xcode 16+；用 Homebrew 安装 node（26 及以上）和 xcodegen。
2. 克隆仓库，在 apps/sidecar 里执行 npm install。
3. 在仓库根目录执行 scripts/package-dmg.sh，按我的芯片架构打包 DMG（产物在 dist/）。
4. 挂载 DMG，把 Catland.app 拷到 /Applications，执行 xattr -dr com.apple.quarantine /Applications/Catland.app，然后打开它。
仓库里的 AGENTS.md 和 docs/development.md 有项目约定和更多命令。
```

## 🔒 隐私：纯本地

- **没有 catland 服务器、账号、统计或崩溃上报。**
- 网络请求只发往你连接的平台；唯一的例外是窗外天气：新加坡用 NEA，其他地区用 Open-Meteo，只发送约 10 km 精度的坐标，设置里可以关掉。
- 登录态保存在 `~/.catbus/`，本地数据在 `~/Library/Application Support/catland/`，日志在 `~/Library/Logs/catland/`（会自动打码 cookie、token）。
- 网页登录用的是一次性的隔离浏览器环境，窗口关闭即清空；catland 不读取你浏览器里保存的任何数据。

## ⚠️ 声明

- 本项目**仅供学习研究，不商用**。内容来自各平台公开接口（经 catbus），请遵守各平台的用户协议，合理使用、不要高频请求。
- 各平台名称与图标归其所有者所有，本项目仅用于标识内容来源，与这些平台无任何关联。
- catland 不会代你在平台上点赞、评论、关注或发布；这些写操作容易触发平台风控，默认不调用。

## 🗺 接下来

- [ ] 电商板块：淘宝 / 京东 / 闲鱼商品搜索与跨平台比价
- [ ] 宣传视频与动图演示
- [ ] 更多城市的窗外地标与地貌（北京、深圳、东京、纽约……），更多事件与彩蛋
- [ ] 本地数据导出 / 导入

## 🙏 致谢

- [catbus](https://github.com/cv-cat/catbus) 与作者 [cv-cat](https://github.com/cv-cat)：catland 的全部平台能力都来自这辆猫巴士。
- 所有在工位上偷偷看刘海的打工人。🐱

<div align="center">
<sub>MIT License · Made with 🐾 for every tired worker</sub>
</div>
