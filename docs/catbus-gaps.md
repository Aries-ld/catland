# catbus 能力缺口登记

catland 的原则：**平台操作尽量收敛到 catbus**（它的作者专做爬虫，签名、设备指纹、风控应对都比我们自己写可靠），避免各平台各写一套分支。

遇到 catbus 能力不够的地方，**先和产品负责人确认处理方式**，再登记到本文件。每条写清：现象、影响、当前处理、上游怎么补（可以给 catbus 提 issue / PR）。上游补上后，切回 catbus 并把该条移到「已解决」。

## 待解决

### 1. Bilibili：`item media` 只返回 DASH 分轨流

- **现象**：`catbus bilibili item media <BV>` 返回分离的视频轨（最高 1080P）和音频轨（`fnval=4048`），常落在 P2P 加速节点（`*.mcdn.bilivideo.cn`、`*.edge.mountaintoys.cn`）。
- **实测**（2026-10-27）：AVPlayer 首帧 4–7 秒；音频需强制 MIME 才能打开；视频轨时长识别错误（850 秒识别成 50 秒）；P2P 节点证书无效，偶发直接播放失败。现方案首帧约 1.7 秒。
- **当前处理（已确认，临时例外）**：推荐流、详情、评论仍走 catbus（带用户登录态）；**只有播放地址**由 `BilibiliAdapter` 直接请求网页 H5 播放器的公开 MP4 接口（`x/web-interface/view` + `x/player/playurl?platform=html5`），用与账号无关的匿名访客 buvid，不带用户 cookie。被 412 限流时报 `RISK_CONTROL`，不影响账号。
- **上游怎么补**：给 `bilibili item media` 增加选项（如 `--format mp4`），走 `fnval=1&platform=html5` 返回音视频合一的 MP4 并避开 P2P 节点；合并后 `BilibiliAdapter` 改回 `catbus item media`，删除直连代码。

### 2. 微博：没有推荐流

- **现象**：`catbus weibo feed list` 返回 `NOT_IMPLEMENTED`（能力矩阵里是 ○ 规划中）。微博能登录，但刷不出任何内容。
- **当前处理（已确认）**：微博在平台目录里置灰（`unavailable`），不能连接、不进刷刷流。
- **上游怎么补**：实现 `weibo feed list`（网页端热门 / 关注时间线），接入后去掉置灰。

### 3. 抖音：推荐流里的媒体地址不是 http 地址

- **现象**：`catbus douyin feed list` 返回的 `media[].url` 是内部 uri（如 `aeb0f54f…`），不是可播放的链接；`item get` / `item media` 返回的才是 `https://…douyinvod.com/…`。
- **当前处理**：仍全部走 catbus。适配器把非 http 地址视为「缺媒体」，自动用 `item get` 补全（多一次 catbus 调用）。
- **上游怎么补**：`feed list` 的媒体取 `play_addr.url_list` 里的 http 地址，取不到时不填 `url`。

## 已解决

（暂无）

## 4. 抖音 / Bilibili / 快手：没有实时热搜（keyword hot）

- **现象**：`catbus <platform> keyword hot` 只有小红书实现；抖音、Bilibili、快手返回 `NOT_IMPLEMENTED`（能力矩阵里是 ○ 规划中）。
- **影响**：搜索首页的「猜你想搜」只能显示小红书的实时热搜，其余平台没有。
- **目前的处理**：只用 catbus 能拿到的（小红书，sidecar 缓存 30 分钟）；不够时用本地按季节、时段挑的示例词兜底。catbus 没实现的平台记住，不再重复请求。**没有绕开 catbus 自己请求平台接口。**
- **上游可以怎么补**：给这三个平台实现 `keyword hot`（各平台网页端都有公开的热搜 / 热榜接口），输出统一的 `{text, heat}`。

