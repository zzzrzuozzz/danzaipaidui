--[[
    MatchStateMachine.lua — 5 阶段状态机（固定逻辑帧驱动）
    ------------------------------------------------------------------
    时间轴（默认 110s = 3300 帧）：
      READY 150 → PARKOUR 1350 → TRANSITION 150 → PUSH_BALL 1350 → SETTLEMENT 300

    锁步确定性要点：
      · 全程只用整数帧计数，不用秒/浮点累加
      · 状态迁移只发生在逻辑帧内
      · PARKOUR 提前结束条件：全员完赛（Score.all_finished）
]]

local Config     = require("Config")
local Adapter    = require("EggyAdapter")
local Score      = require("ScoreManager")
local Registry   = require("SceneRegistry")
local Parkour    = require("ParkourLogic")

local Match = {}

local state        = Config.PHASE.BOOT
local phase_tick   = 0     -- 当前阶段已过帧数
local total_tick   = 0     -- 整局已过帧数
local running      = false

-- ==================== 查询接口 ====================

function Match.get_state()       return state      end
function Match.get_phase_tick()  return phase_tick end
function Match.get_total_tick()  return total_tick end
function Match.get_phase_limit()
    return Config.PHASE_TICKS[state] or 0
end
function Match.is_running()      return running    end

-- ==================== 阶段进入 ====================

--- 广播阶段提示（玩家级 + 全场）
local function announce(state_name, text)
    print(string.format("[ICE][PHASE] %s (tick=%d, %.2fs)",
        state_name, total_tick, total_tick / Config.TICK_HZ))
    for _, p in ipairs(Score.sorted_players()) do
        Adapter.tips(p.role, text, 2.5)
        Adapter.track(p.role, Config.TRACK.PHASE, 1)
    end
end

--- 锁定/解锁全部玩家移动
local function lock_all(locked)
    for _, p in ipairs(Score.sorted_players()) do
        Adapter.lock_role(p.role, locked)
    end
end

--- 按座位号把全员传送到圆台外圈
local function teleport_all()
    local players = Score.sorted_players()
    local moved, failed = 0, 0
    for _, p in ipairs(players) do
        local tp = Registry.get_teleport(p.seat)
        local unit = Adapter.ctrl_unit(p.role)
        if tp and tp.pos and unit then
            if Adapter.set_pos(unit, tp.pos) then
                moved = moved + 1
            else
                failed = failed + 1
            end
        else
            failed = failed + 1
        end
    end
    print(string.format("[ICE] 转场传送：成功 %d，失败 %d", moved, failed))
end

--- 打印实时积分榜（转场与结算用）
local function print_board(title)
    print("[ICE] ===== " .. title .. " =====")
    for i, p in ipairs(Score.get_ranked()) do
        print(string.format("[ICE] %d. %s  总分=%d（跑酷=%d 推球=%d）完赛=%s 掉落=%d",
            i, p.name, p.totalScore, p.parkourScore, p.pushScore,
            p.isFinishedParkour and ("是/第" .. p.finishRank .. "名") or "否",
            p.fallCount))
    end
end

--- 进入新阶段（副作用集中在这里，只执行一次）
local function enter(new_state)
    state      = new_state
    phase_tick = 0

    if new_state == Config.PHASE.READY then
        lock_all(true)
        announce("READY", "冲过樱花赛道攒底分，终局推球抢大礼！")

    elseif new_state == Config.PHASE.PARKOUR then
        lock_all(false)
        announce("PARKOUR", "开跑！樱花糖果 +1，冰晶星 +3")

    elseif new_state == Config.PHASE.TRANSITION then
        teleport_all()
        print_board("跑酷阶段积分榜")
        announce("TRANSITION", "转场：准备进入水晶圆台")

    elseif new_state == Config.PHASE.PUSH_BALL then
        -- 第二阶段占位：这里是推球逻辑的生命周期入口
        announce("PUSH_BALL", "推球抢分！")
        print("[ICE] PUSH_BALL 已进入（本阶段实现预留，逻辑开关见 Config.ENABLE_PUSH_BALL）")

    elseif new_state == Config.PHASE.SETTLEMENT then
        lock_all(true)
        print_board("最终结算")
        Match.award_titles()
        announce("SETTLEMENT", "结算中…")

    elseif new_state == Config.PHASE.ENDED then
        print("[ICE] 对局结束，调用 game_end")
        Adapter.game_end()
    end
end

-- ==================== 称号颁发 ====================

function Match.award_titles()
    local titles = Score.compute_titles()
    local single = Score.is_single()

    print("[ICE] ===== 称号 =====")
    if single then
        local only = Score.get_ranked()[1]
        if only then
            local list = titles[only.sortKey] or {}
            print(string.format("[ICE] 单人模式称号：%s", #list > 0 and table.concat(list, "、") or "无"))
            local star = Score.single_star(only)
            if star then
                Adapter.tips(only.role, "达成 " .. star.name .. "！", 4.0)
            end
        end
        return
    end

    for _, p in ipairs(Score.sorted_players()) do
        local list = titles[p.sortKey] or {}
        if #list > 0 then
            local text = table.concat(list, "、")
            print(string.format("[ICE] %s 获得称号：%s", p.name, text))
            Adapter.tips(p.role, "获得称号：" .. text, 4.0)
            Adapter.track(p.role, Config.TRACK.RESULT, #list)
        end
    end
end

-- ==================== 每帧驱动 ====================

--- 由 Main 的固定帧循环每帧调用一次
function Match.update()
    if not running then return end

    phase_tick = phase_tick + 1
    total_tick = total_tick + 1

    local limit = Config.PHASE_TICKS[state] or 0

    if state == Config.PHASE.READY then
        if phase_tick >= limit then
            enter(Config.PHASE.PARKOUR)
        end

    elseif state == Config.PHASE.PARKOUR then
        Parkour.update(phase_tick)
        -- 全员完赛 或 45s 到点，先到先切
        if Score.all_finished() or phase_tick >= limit then
            if Score.all_finished() then
                print(string.format("[ICE] 全员完赛，PARKOUR 提前结束（%.2fs）",
                    phase_tick / Config.TICK_HZ))
            end
            enter(Config.PHASE.TRANSITION)
        end

    elseif state == Config.PHASE.TRANSITION then
        if phase_tick >= limit then
            if Config.ENABLE_PUSH_BALL then
                enter(Config.PHASE.PUSH_BALL)
            else
                print("[ICE] ENABLE_PUSH_BALL = false，跳过推球阶段")
                enter(Config.PHASE.SETTLEMENT)
            end
        end

    elseif state == Config.PHASE.PUSH_BALL then
        -- 第二阶段逻辑挂载点（预留）
        if phase_tick >= limit then
            enter(Config.PHASE.SETTLEMENT)
        end

    elseif state == Config.PHASE.SETTLEMENT then
        if phase_tick >= limit then
            enter(Config.PHASE.ENDED)
        end
    end
end

-- ==================== 启动 / 重置 ====================

function Match.start()
    state      = Config.PHASE.BOOT
    phase_tick = 0
    total_tick = 0
    running    = true
    print(string.format("[ICE] 状态机启动：总计 %d 帧（%.1fs）",
        Config.PHASE_TICKS.READY + Config.PHASE_TICKS.PARKOUR
        + Config.PHASE_TICKS.TRANSITION
        + (Config.ENABLE_PUSH_BALL and Config.PHASE_TICKS.PUSH_BALL or 0)
        + Config.PHASE_TICKS.SETTLEMENT,
        (Config.PHASE_TICKS.READY + Config.PHASE_TICKS.PARKOUR
        + Config.PHASE_TICKS.TRANSITION
        + (Config.ENABLE_PUSH_BALL and Config.PHASE_TICKS.PUSH_BALL or 0)
        + Config.PHASE_TICKS.SETTLEMENT) / Config.TICK_HZ))
    enter(Config.PHASE.READY)
end

function Match.stop()
    running = false
end

return Match
