# catland 开发者文档

> 产品介绍见 [README](../README.md)，给 AI 编码代理的约定见 [AGENTS.md](../AGENTS.md)。

## 运行（开发版）

```bash
cd apps/sidecar && npm install          # 首次
brew install xcodegen                   # 首次
apps/macos/scripts/run.sh               # 构建并启动，刘海处出现小猫
```

## 打包 DMG

```bash
scripts/package-dmg.sh            # 按本机架构（Apple 芯片 arm64 / Intel x86_64）
scripts/package-dmg.sh x86_64     # 指定架构
```

产物在 `dist/`：`catland-<版本>-macos-<架构>.dmg` 与 `.sha256`。App 内自带锁定版本的官方 Node、sidecar 与 catbus，用户无需安装任何依赖。签名为 ad-hoc（未公证）。

## 阶段验收（每个阶段结束时做）

- 平台实测：每个已接入的平台走一遍「连接 → 刷刷 → 评论 → 断开」，记录结果；目前待实测：快手、微博、TikTok、X（浏览器导入）。
- 交互回归：刘海悬停 / 点击展开、翻页、点赞收藏评论（含视频卡片）、连接面板、设置、收藏页。
- 打包：`scripts/package-dmg.sh`，挂载 DMG 拷出 App 启动一次，确认使用的是内置 Node、能刷出内容。

## 品牌素材

- `scripts/make_icons.py`：App 图标（`apps/macos/Resources/AppIcon.icns`、`assets/brand/icon-1024.png`）与菜单栏模板图。
- `scripts/make_readme_art.py`：README 的 banner 与场景拼图。素材来自 App 的离屏渲染（同一套表现层代码，不截屏，没有物理刘海黑块）：先运行 App，执行 `apps/macos/build/catland-debug snapshots:/tmp/catland-snaps`，再跑脚本 `--snaps /tmp/catland-snaps`。渲染预设在 `SceneSnapshot.presets`，事件会自动挑最热闹的一帧。
- `scripts/fetch_platform_icons.py`：各平台官方图标（固定的干净版本）。

## 架构

- `apps/macos`：Swift 原生客户端，刘海灵动岛 + 播放器 + 表现层（见 [ADR 0003](decisions/0003-presentation-layer.md)）
- `apps/sidecar`：Node 本地服务，由客户端以子进程启动，经 stdio 通信、不监听端口；包装 catbus 取数

纯本地：无自有服务器、无账号、无遥测，数据与登录态只在本机。

## sidecar RPC 概览

行分隔 JSON-RPC 2.0，经 stdin / stdout。实现见 `apps/sidecar/src/app.ts`。

| 方法 | 说明 |
|---|---|
| `app.hello` | 版本与设置 |
| `accounts.list` / `refresh` / `checkHealth` | 平台点亮状态、登录态体检 |
| `accounts.loginQrcode` / `loginCookie` / `cancelLogin` / `logout` / `use` | 扫码 / 网页登录、登出、切换账号 |
| `feed.next {count, waitMs}` | 取已解析、可直接播放的卡片（带 liked / collected） |
| `feed.refresh {key}` / `feed.view {key, dwellMs}` / `feed.sources` | 换新媒体地址、记录浏览、信息源状态 |
| `comments.list {key, cursor}` / `comments.replies` | 评论（只读） |
| `interact.set {key, kind, on}` / `states` / `list` | 本地点赞、收藏 |
| `history.list` / `history.clear` | 浏览历史 |
| `settings.get` / `settings.update` | 静音、各板块信息源 |

服务端通知：`app.ready`、`accounts.changed`、`accounts.login`（二维码 / 进度）、`feed.source`（平台冷却 / 失效）。

数据：`~/Library/Application Support/catland/catland.db`（0600），日志：`~/Library/Logs/catland/`。

## 本地环境

- macOS 26（Apple Silicon）、Xcode 26、Node 26
- `npm i -g catbus-cli`，然后按需 `catbus <platform> auth login`
- 美术工具：`conda create -n catlands python=3.12`，`pip install requests Pillow`
- `cp .env.example .env` 后填写密钥

## 目录

```
apps/       macOS 客户端（apps/macos）与本地服务（apps/sidecar）
assets/     美术资源（art/ 生成素材存档，brand/ 图标与 README 配图）
docs/       设计文档与 ADR
scripts/    工具脚本
vendor/     catbus 源码只读参考（不进版本控制）
```
