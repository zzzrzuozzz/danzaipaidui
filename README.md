# 樱花冰晶：甜心推推冲分赛（Eggy Party · 原点编辑器 / FS 帧同步）

4–8 人 FFA 抢分玩法的 Lua 实现。两个阶段均已完成：**READY → PARKOUR → TRANSITION → PUSH_BALL → SETTLEMENT** 的完整确定性闭环。

## 模块结构

```
main.lua              入口装配 · 30Hz 固定帧主循环 · UI 绑定 · 兜底启动
Config.lua            全局配置：所有可调旋钮、阶段帧数、场景命名模板
EggyAdapter.lua       引擎 API 唯一出口层（pcall 降级 + 调用约定自适应）
SceneRegistry.lua     场景契约解析：按名解析 50+ 组件，缺失只告警
ScoreManager.lua      玩家状态 · 计分 · 防重拾 · 名次分 · 确定性排序 · 称号
MatchStateMachine.lua 5 阶段状态机 · 全员完赛提前结束 · 按座位传送 · 结算
ParkourLogic.lua      拾取判定 · 存档点推进 · 掉落去抖重生 · 终点冲线
PushBallLogic.lua     推球 · 触球归属 · 抢断判定 · 进球计分 · 球体回收刷新
```

依赖单向：`ParkourLogic` / `PushBallLogic` 都不反向依赖状态机，由
`MatchStateMachine` 单向调用其 `start / update / stop` 生命周期。

## 关键设计

**时间全部用整数帧。** `READY=150`、`PARKOUR=1350`…（30Hz）。秒转帧在
`Config.lua` 加载时一次性完成，累加整数无浮点漂移。

**主循环用 `LuaAPI.call_delay_frame(1, tick)` 自递归**，不用 `call_delay_time`。
后者内部仍按帧驱动，且不保证 0.01 / 0.02 的回调先后顺序。

**实例方法调用约定自适应。** 引擎里 Unit/Role 方法文档存在点式与冒号式两种写法，
`EggyAdapter.mcall` 首次调用时探测并锁定，之后零额外开销。

**拾取判定用坐标距离，不用触发器事件。** 50 个拾取物各注册一个触发区事件开销过大，
且要求美术侧配合。改为「按物件序号遍历 + 玩家按 roleId 升序取首个命中者」，
天然确定性。

## FS 四条铁律的落地

| 铁律 | 实现 |
|---|---|
| 锁步确定性 | 只用整数帧计数，全程无 `os.time` |
| 确定性随机 | 统一走 `EggyAdapter.random_int` → `GameAPI.random_int`，禁 `math.random` |
| 逻辑表现分离 | 状态变更只在 `Match.update()` 内；UI 刷新是只读旁路 |
| 浮点容差 | 距离/高度判定统一带 `EPS = 0.01` |

## 运行方式（编辑器 CLI）

```powershell
$cli = "$env:USERPROFILE\.eggitor\cli\editor-cli.exe"

& $cli code init --workspace <空目录>    # 为新地图生成工程（每图一次）
& $cli code validate --workspace . --strict
& $cli code push --workspace . --dry-run --show-diff
& $cli code push --workspace .
& $cli play restart
& $cli log grep "ICE"
& $cli map save
```

## 高频调参旋钮（`Config.lua` 顶部）

| 项 | 默认值 | 说明 |
|---|---|---|
| `TICK_HZ` | 30 | 逻辑帧率 |
| `PARKOUR_FALL_Y` | -5.0 | 掉落判定高度 |
| `PICKUP_RADIUS` | 1.6 | 拾取半径 |
| `ENABLE_PUSH_BALL` | false | 推球阶段总开关 |
| `DEBUG_FAST` | false | 阶段压缩到 1/10，仅冒烟测试用 |
| `UI.ENABLED` | false | 未建 UI 节点时必须保持 false |

> `ENABLE_PUSH_BALL=false` 时整局 **65s**（1950 帧）；开启后 **110s**（3300 帧）。
> 编辑器「规则设置-计时规则」建议统一设 **120s** 兜底。

## 场景契约（组件名必须精确匹配）

| 名称 | 数量 |
|---|---|
| `存档点_01` ~ `存档点_03` | 3 |
| `樱花糖果_01` ~ `樱花糖果_40` | 40 |
| `冰晶星_01` ~ `冰晶星_10` | 10 |
| `传送点_01` ~ `传送点_08` | 8 |
| `终点_胜利区域` | 1 |
| `糖果球_01` ~ `糖果球_04` | 4（+15 分） |
| `冰晶大球_01` ~ `冰晶大球_02` | 2（+35 分，第 450/900 帧激活） |
| `球洞_01` ~ `球洞_04` | 4 |
| `球刷新点_01` ~ `球刷新点_04` | 4 |

缺失只打印告警，不会崩溃 —— 当前仓库中的地图尚未搭建这些组件。

## 已知限制

- UI 刷新默认关闭：节点不存在时 `set_label_text` 会让引擎持续报「节点类型不正确」，
  `pcall` 无法拦截这类引擎侧参数校验日志。
- 推球阶段已实现，但**尚未在真实球 / 球洞场景下验证计分正确性**（当前地图未摆放这些组件）。
- 拾取 / 冲线 / 存档点链路已在空场景下验证不崩溃，但尚未用真实组件验证计分正确性。

## `EggyAPI.lua` 说明

该文件约 330KB，由 PC 编辑器「LUA → 蛋仔开发助手」自动生成，提供 API 类型存根，
便于 IDE 补全。换图后需重新生成，不要手工修改。

## 策划案

完整数值与规则见同目录上级的
`樱花冰晶_甜心推推冲分赛_策划案_v1.1`（v1.0 → v1.1 修订 12 项）。
