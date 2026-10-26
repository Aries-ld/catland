# catland

把各平台的小猫放进同一片 land：常驻 macOS 刘海的聚合刷刷器，基于 [catbus](https://github.com/cv-cat/catbus)。

> 仅供学习研究，不商用。数据与登录态只保存在本机。

## 状态

MVP 开发中：sidecar 已完成 catbus 调用层（`apps/sidecar`）。

## 架构

- `apps/macos`（待建）：Swift 原生客户端，刘海灵动岛 + 播放器
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
apps/       客户端与本地服务（待定）
assets/art  美术资源
docs/       设计文档与 ADR
scripts/    工具脚本
vendor/     catbus 源码只读参考（不进版本控制）
```
