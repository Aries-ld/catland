# catland

把各平台的小猫放进同一片 land：常驻 macOS 刘海的聚合刷刷器，基于 [catbus](https://github.com/cv-cat/catbus)。

> 仅供学习研究，不商用。数据与登录态只保存在本机。

## 状态

MVP 开发中：sidecar 已完成 catbus 调用层（`apps/sidecar`）。

## 架构

- `apps/macos`（待建）：Swift 原生客户端，刘海灵动岛 + 播放器
- `apps/sidecar`：Node 本地服务，由客户端以子进程启动，经 stdio 通信、不监听端口；包装 catbus 取数

纯本地：无自有服务器、无账号、无遥测，数据与登录态只在本机。

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
