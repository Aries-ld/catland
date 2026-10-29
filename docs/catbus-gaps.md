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

## 5. B 站 / 小红书：搜索结果没有视频时长和封面尺寸

- **现象**：`catbus bilibili item search`、`catbus xhs item search` 返回的 item 里 `media` 为空，没有 `duration`，也没有封面的宽高；抖音、快手的搜索结果带视频的宽高和时长。
- **影响**：B 站、小红书的搜索结果封面上只能显示播放标记，不能显示时长；封面比例要等图片加载后才知道。
- **目前的处理**：封面按图片加载后的真实宽高比排版（加载前按平台常见比例估算：B 站 16:9，其他 3:4）；没有时长就只显示播放标记。不为了拿时长对每条结果再调 `item get`（会成倍增加请求、提高风控风险）。
- **上游可以怎么补**：B 站搜索接口本身返回 `duration`（"mm:ss"），可以填进 `media[0].duration`；封面尺寸能拿到时一并输出。

## 6. 评论没有图片、头像、IP 属地

- **现象**：catbus 统一的 Comment 只有 `id item_id parent_id author text created_at stats`。小红书评论的 `pictures`（图片评论）、各平台的头像、IP 属地在整理时都丢掉了；纯图片评论的 `text` 是空字符串。
- **影响**：图片评论在 catland 里只有昵称没有内容；评论区没有真实头像。
- **目前的处理**：空文字的评论显示「图片评论 · 去原帖看」，点一下用浏览器打开原帖；头像用昵称首字的彩色圆形代替。表情代码（`[doge]`、`[笑哭R]`）在 App 里换成 emoji。没有绕开 catbus 自己请求。
- **上游可以怎么补**：Comment 增加 `media: Media[]`（评论图片 / 表情包）、`author.avatar`、`ip_location`；各平台评论接口本身都返回这些字段。

