# 0003 表现层（Presentation）：模块化与扩展方式

- 状态：已采纳
- 日期：2026-10-26

## 背景

刘海里的落地窗场景已经包含天空、城市、天气、季节、节日、彩蛋、事件、室内等十几类元素。最初都写在一个 900 行的渲染器里，新增一个元素要改主流程、容易互相牵连。我们把这些统称为**表现层**，要求：模块化、可扩展、已有内容好维护。

## 决策

### 结构

```
apps/macos/Catland/Presentation/
  SceneCanvas.swift      共享画布：像素网格、布局（刘海 / 两翼 / 天空上沿 / 城市地平线 / 地面）、当下情境
  Presentation.swift     SceneLayer 协议 + SceneStage（绘制阶段）+ 唯一的图层注册表
  Modules/
    Sky.swift            天空、太阳、星星、月亮（真实月相）、云、飞鸟 / 飞机
    City.swift           远景 / 近景楼群、城市地标（Landmark 注册表）、海湾、地铁
    Weather.swift        WeatherStyle 样式表 + WeatherEffect 注册表
    Seasons.swift        SceneSeason 判定 + SeasonStyle 样式表 + 行道树 / 路灯 / 粒子 / 窗角装饰 / 结霜
    Holidays.swift       HolidayCatalog：节日唯一数据源（倒计时文案与装饰共用）
    Eggs.swift           SceneEgg 注册表 + 每日抽签
    Events.swift         SceneEvent 注册表 + EventScheduler（排期 / 预告 / 倒计时 / 取消 / 天气触发）
    Interior.swift       窗框、天花板、地面
```

### 原则

- **模块之间不互相调用**，只通过 `SceneCanvas` 读取共享情境（时间、太阳、天气、季节、节日、布局）。
- **绘制顺序只由 `SceneStage` 决定**（远 → 近），同一阶段内按注册顺序。新内容选一个阶段即可，不用关心别的模块。
- **数据驱动优先**：能用表格描述的（天气名称 / 阴沉度 / 云量、季节配色 / 粒子 / 装饰 / 小猫行为偏好、节日日期 / 地区 / 是否放假）都放在表里，改表不改逻辑。
- **确定性随机**：彩蛋、事件排期都按「日期 + id」做种子，同一天结果稳定，可测试、可预告。

### 扩展清单

| 想加的东西 | 改哪里 |
|---|---|
| 新图层 | 实现 `SceneLayer`，在 `Presentation.layers` 登记 |
| 新天气 | `WeatherStyle.table` 加一行；需要专属画面时加一个 `WeatherEffect` 到 `WeatherEffects.all`；sidecar 的 `classify` / `classifyWmo` 产出该 condition |
| 调整季节表现 | `SeasonStyle.of` 改对应季节 |
| 新城市地标 | 实现 `Landmark` 加进 `Landmarks.all`；`Skyline` 里登记城市坐标和名字（现有新加坡、上海、北京；不在这些城市 120km 内时，窗外随机选定北京或上海并记住，天气和时间仍跟随真实所在地） |
| 新节日 | `HolidayCatalog.all` 加 `HolidayDef`（日期、地区、是否放假、装饰窗口与绘制） |
| 新彩蛋 | 实现 `SceneEgg` 加进 `Eggs.all` |
| 新事件 | 实现 `SceneEvent`（排期 `start(on:)`、天气门槛 `canRun`、`draw`、预告 / 进行中 / 取消文案）加进 `Events.all` |

### 事件

- 每次持续 10 分钟，开头 / 结尾各 40 秒淡入淡出。
- 排期型：按真实日期（流星雨极大日、节日）、星期、季节概率决定；开始前 6 小时、1 小时、10 分钟，小猫会主动探出刘海预告一次（`AppState.checkEvents`），悬停气泡最前面显示预告与倒计时。
- 开始时再看天气，不满足就取消，小猫说一句取消文案。
- 天气触发型（雨后彩虹、初雪）：由天气变化触发，没有预告。
- 进行中小猫停下来坐着抬头看（`watch` 动作）。

### 调试命令

`catland-debug date:<ISO 时间>` / `scene:<小时>:<天气>` / `intensity:<0~1>` / `city:<shanghai|singapore>` / `egg:<id|none>` / `event:<id>[:<分钟后开始，可为负>]` / `event:none` / `say:<一句话>` / `hoverpin` / `hoverunpin`。

## 影响

- 新增一个彩蛋 / 事件 / 节日通常只改一个文件、加一处登记。
- 表现层的单元测试覆盖排期、预告、倒计时、取消、触发事件、小猫观看、节日倒计时与文案；画面通过调试命令截图人工把关。

## 城市场景包（v0.3）

每个城市一个场景包（`Presentation/Cities/<城市>.swift`，协议见 `CityPack.swift`），按所在地整包加载；新增城市 = 新写一个包并登记到 `CityPacks.all`。

| 内容 | 说明 |
|---|---|
| 地标 | 只放在刘海左右两侧看得见的区域；横向放不下时前后叠放（后排雾化）。地标用 1pt 细网格（`FineGrid`，比普通楼群精细 1.5 倍），收起时宽度按可用高度等比收窄，保持修长比例 |
| 动态元素（`CityElement`） | 各自声明画在哪层：天空（飞机、鸟群、风筝）、水面（游船）、高架桥（地铁、车流，由 `MetroLayer` 在桥和隧道口之间调用） |
| 夜景霓虹（`NeonStyle`） | 地平线光晕（`HorizonGlowLayer`）、近景楼的霓虹招牌（`NeonSignsLayer`，挂在 `nearBuildings` 上）、水面倒影（`WaterReflectionLayer`） |
| 地标夜景 | 按真实建筑的照明方式画（泛光、扭转缝细光、镂空一圈光、立面点状灯），不套统一的轮廓灯带 |

| 城市 | 左翼 / 右翼地标 | 动态元素 | 霓虹 |
|---|---|---|---|
| 上海 | 东方明珠 / 金茂 + 环球 + 上海中心 | 地铁（绿色腰带）、黄浦江渡轮 / 夜游船、飞机、鸟群 | 粉、青、紫、金 |
| 北京 | 天坛祈年殿 / 央视大楼 + 中国尊 | 长安街车流（夜里红白车灯）、春秋天的风筝、鸟群 | 暖金为主，点缀红、青 |
| 新加坡 | 金沙酒店 / 摩天轮 | MRT（红色腰带）、鸟群、飞机 | 青、品红、金 |

调试：`catland-debug render:cities` 按真机刘海几何离屏渲染上海、北京的收起 / 悬停 × 白天 / 夜里（自动挑动态元素都在画面里的时刻）。

