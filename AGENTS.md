# AGENTS.md — 樱花冰晶：甜心推推冲分赛

《蛋仔派对》原点编辑器（FS 帧同步）UGC 地图项目。本文件供 AI Agent（opencode / Codex / 其他）阅读。

## 一、蛋仔官方规则从哪读

官方规则与技能包已装在本机，**动手前先读**，不要凭猜：

- FS 规则全文：`~/.eggitor/codex/fs/rules/eggy-fs.mdc`
- FS 技能包（7 个）：`~/.eggitor/codex/fs/skills/`
  - `eggy-fs-design` 玩法设计 · `eggy-fs-dev-plan` 开发计划 · `eggy-fs-lua-coding` 写码
  - `eggy-fs-editor-cli` 编辑器操作 · `eggy-fs-playtest` 试玩 · `eggy-fs-log-triage` 日志排错 · `eggy-fs-qa` 验收
- 云端文档检索：`editor-cli docs search "<问题>" --docset manual`

## 二、FS 四条铁律

1. **锁步确定性**：所有倒计时/状态/计分由整数帧累加驱动，禁用 `os.time()`
2. **确定性随机**：禁用 `math.random()`，用 `GameAPI.random_int` / `GameAPI.randint`
3. **逻辑表现分离**：状态变更只在逻辑 tick 内，UI 回调里不碰玩法状态
4. **浮点容差**：距离/高度判定统一带 `EPS = 0.01`

引擎约定：1 秒 = 30 帧；主循环用 `LuaAPI.call_delay_frame(1, cb)` 自递归，**不要用** `call_delay_time`。

## 三、命令链路（本机已装 editor-cli 0.20.17）

```powershell
$cli = "$env:USERPROFILE\.eggitor\cli\editor-cli.exe"

& $cli status                       # 第一个动作永远是它：确认编辑器活着
& $cli code validate --workspace . --strict
& $cli code push --workspace . --dry-run --show-diff
& $cli code push --workspace .
& $cli play restart                 # play start 常只返回 accepted，restart 才真入场
& $cli log grep "ICE"
& $cli map save                     # 试玩刚结束可能 can_save False，等 idle 重试
& $cli code diff                    # 期望 unchanged
```

新地图才需要 `code init`：

```powershell
& $cli code init --workspace <空目录>   # 生成 eggy.json + 脚手架 + EggyAPI 存根
```

编辑器侧脚本执行（改场景用这个）：

```powershell
& $cli exec --file tools/xxx.lua --json --timeout 60
```

## 四、场景契约（名称必须精确匹配，代码按名检索）

| 名称 | 数量 | 备注 |
|---|---|---|
| `存档点_01`~`03` | 3 | |
| `樱花糖果_01`~`40` | 40 | |
| `冰晶星_01`~`10` | 10 | |
| `传送点_01`~`08` | 8 | 按角色座位号对应 |
| `终点_胜利区域` | 1 | |
| `糖果球_01`~`04` | 4 | |
| `冰晶大球_01`~`02` | 2 | |
| `球洞_01`~`04` | 4 | |
| `球刷新点_01`~`04` | 4 | |

## 五、已经踩过的坑（别再踩）

1. **`set_unit_name` 是空操作**：返回成功、名字不变。必须用 `EditorAPI.set_unit_attr(uid, "name", "...")`
2. **`LuaAPI.query_unit` 只检索障碍物类组件**：装饰类（地毯/发光果实/气球）搜不到。契约组件统一用障碍物预制体（100059 已验证可用）
3. **`set_unit_transform` 的缩放不可靠**：调用成功但尺寸没变。排布要依赖组件**原生尺寸**
4. **没有染色 API**：`api list-editor` 里没有设置颜色的接口，粉色系只能选原生粉色素材或人工刷色
5. **`exec` 有 5 秒硬预算**：大脚本会被截断，必须拆批 + 写幂等补齐脚本
6. **`editor-unit` 命令在 FS 下不可用**：缺 `query_scene_units` RPC。改场景走 `exec` + `EditorAPI`
7. **编辑器可能没开**：所有命令会报 `INTERNAL_ERROR`，先 `status` 再动手
8. **Git push 需要 GCM**：沙箱阻断命名管道时 push 会失败，需放宽权限

## 六、代码结构

```
main.lua              入口装配 · 30Hz 主循环 · UI 绑定
Config.lua            全局配置（数值/阶段帧数/场景命名模板）
EggyAdapter.lua       引擎 API 唯一出口（pcall 降级 + 调用约定自适应）
SceneRegistry.lua     场景契约解析
ScoreManager.lua      计分 · 排名 · 称号
MatchStateMachine.lua 5 阶段状态机
ParkourLogic.lua      跑酷：拾取/存档点/掉落/冲线
PushBallLogic.lua     推球：归属/抢断/进球/回收
tools/                场景构建脚本（编辑器侧，幂等）
```

依赖单向：各 Logic 模块不反向依赖状态机。

## 七、当前进度

- 五阶段闭环已完成，60 个契约组件全部解析命中
- 跑酷段已改为浮空跳跃台（10 块 7×1×7，间隙 4）
- 排版方案 v2（12 块台 + 机关）待实施，见 `../跑酷段重排版方案_v2.md`
- 视觉层仍为占位素材，未做樱花粉色化
