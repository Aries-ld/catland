# AGENTS.md — catland

> 给 AI 编码代理与协作者的统一说明。产品目标、资源、约定只在这里维护一份。

## 1. 产品

- **一句话**：常驻 macOS 刘海（灵动岛）的聚合刷刷器——一键开刷小红书 / 抖音 / B 站 / X 等平台的内容，跨淘宝 / 京东浏览和比价商品。
- **命名**：基于 [catbus](https://github.com/cv-cat/catbus)（猫巴士把各平台小猫装上车）；catland 把小猫放进同一片 land，land 也谐音 island（灵动岛）。
- **目标用户**：vibe coding / 工作摸鱼的碎片时间里，懒得拿起手机、打开 App 的人。点一下就开刷。
- **定位**：基于爬虫数据，**不商用、只开源**，追求影响力。所有数据与登录态只留在用户本机。
- **核心原则**：catland 是凌驾于各 UGC 平台之上的一层：点赞、收藏、浏览历史都**收敛在 catland 本地**，默认不回写到原平台。

### 1.1 已定决策（详见 `docs/decisions/0001-architecture-and-mvp-scope.md`）

- **纯本地（红线）**：无自有服务器、无账号体系、无遥测；网络请求只发往用户连接的平台。sidecar 与 App 走 stdio，不监听端口；新增密钥存钥匙串。
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

后续新资源统一补充到本表。

## 3. 约定

- 密钥只放 `.env`（已 gitignore），模板见 `.env.example`；不写进代码、日志、提交。
- `vendor/` 只读，不修改 catbus 受版本控制的文件。
- catbus 写操作（点赞、评论、关注、发布）会触发平台风控，默认不调用；遇到 `RISK_CONTROL` 停止，不自动重试。
- 设计决策记录在 `docs/decisions/`（ADR）。
- sidecar 调 catbus 只经 `CatbusRunner`（`apps/sidecar/src/catbus/runner.ts`）：用随包的 `catbus-cli`（版本锁定），凭证经 stdin 传、不进 argv 和日志；stdout 只留给 RPC，日志只写文件。
- 新依赖锁精确版本，且选发布满 7 天的版本。

## 4. 常用命令

```bash
# sidecar（apps/sidecar，Node 26 直接运行 .ts，TS 7 只做类型检查）
cd apps/sidecar && npm run typecheck && npm test   # 每次改动后必跑
npm run smoke                                       # 真机只读冒烟，日志在 ~/Library/Logs/catland/sidecar.log


catbus auth list                                  # 已登录的平台
catbus <platform> feed list --limit 10            # 推荐流
catbus <platform> item search <kw> --limit 20     # 搜索
catbus <platform> item media <item>               # 可播放媒体地址
~/miniconda3/envs/catlands/bin/python ~/.agents/skills/game-assets/meowart_api.py credits-balance
```
