--[[
    main.lua — 入口装配与固定帧主循环
    ------------------------------------------------------------------
    执行时机：场景布置完成之后、真正的游戏开始之前
    职责：
      1. 注册 GAME_INIT，初始化配置/场景/计分
      2. 启动 30Hz 固定帧循环（LuaAPI.call_delay_frame(1, ...) 自递归）
      3. 每帧驱动状态机；按固定间隔刷新 UI
      4. 兜底：若 GAME_INIT 未触发，延迟若干帧后自行启动

    锁步铁律：本文件不含任何 os.time / math.random；
              所有状态推进只发生在 tick() 内。
]]

local Config   = require("Config")
local Adapter  = require("EggyAdapter")
local Registry = require("SceneRegistry")
local Score    = require("ScoreManager")
local Match    = require("MatchStateMachine")

local VERSION = "v1.1-phase1"

-- ==================== 运行状态 ====================

local started     = false
local ui          = { score = nil, rank = nil, timer = nil }
local ui_ready    = false
local ui_counter  = 0

-- ==================== UI 初始化 ====================

local function init_ui()
    -- 显式开关：未开启时完全不碰 UI，避免引擎侧「节点类型不正确」刷屏
    if not Config.UI.ENABLED then
        ui_ready = false
        print("[ICE] UI 刷新未启用（Config.UI.ENABLED = false）")
        return
    end

    local names = { Config.UI.SCORE_LABEL, Config.UI.RANK_LABEL, Config.UI.TIMER_LABEL }

    -- 统一经 EggyAdapter 调用，保持引擎 API 只有一个出口
    local result = Adapter.query_ui_nodes(names)

    if result == nil then
        ui_ready = false
        print("[ICE] UI 查询失败，UI 刷新跳过（不影响玩法）")
        return
    end

    -- 兼容两种返回形态：① 单个列表 table ② 多返回值
    local nodes
    if type(result) == "table" then
        nodes = result
    else
        nodes = { result }
    end

    ui.score = nodes[1]
    ui.rank  = nodes[2]
    ui.timer = nodes[3]

    -- 只有确实拿到节点句柄（非 table、非 nil）才算绑定成功
    local function usable(n) return n ~= nil and type(n) ~= "table" end
    ui_ready = usable(ui.score) or usable(ui.rank) or usable(ui.timer)
    if not ui_ready then
        ui.score, ui.rank, ui.timer = nil, nil, nil
    end

    if ui_ready then
        print("[ICE] UI 节点已绑定")
    else
        print("[ICE] 未找到 UI 节点，UI 刷新跳过（不影响玩法）")
    end
end

-- ==================== UI 刷新（只读状态，不改状态） ====================

local function refresh_ui_for(p)
    if not ui_ready or p == nil then return end

    -- 总分
    if ui.score then
        Adapter.set_ui_text(p.role, ui.score, "积分 " .. p.totalScore)
    end

    -- 排名 / 单人星线
    if ui.rank then
        if Score.is_single() then
            local star = Score.single_star(p)
            local next_line = nil
            for _, s in ipairs(Config.SINGLE_STAR) do
                if p.totalScore < s.score then next_line = s break end
            end
            if star then
                Adapter.set_ui_text(p.role, ui.rank, star.name)
            elseif next_line then
                Adapter.set_ui_text(p.role, ui.rank,
                    string.format("距%s %d", next_line.name, next_line.score - p.totalScore))
            else
                Adapter.set_ui_text(p.role, ui.rank, "")
            end
        else
            local ranked = Score.get_ranked()
            local my_rank = 0
            for i, q in ipairs(ranked) do
                if q.sortKey == p.sortKey then my_rank = i break end
            end
            Adapter.set_ui_text(p.role, ui.rank,
                string.format("第 %d/%d 名", my_rank, #ranked))
        end
    end

    -- 阶段倒计时
    if ui.timer then
        local left = Match.get_phase_limit() - Match.get_phase_tick()
        if left < 0 then left = 0 end
        Adapter.set_ui_text(p.role, ui.timer,
            string.format("%s %d", Match.get_state(), math.floor(left / Config.TICK_HZ)))
    end
end

local function refresh_ui_all()
    for _, p in ipairs(Score.sorted_players()) do
        refresh_ui_for(p)
    end
end

-- ==================== 固定帧主循环 ====================

local function tick()
    -- ① 周期性同步玩家列表（每 30 帧一次 = 1 秒）
    if Match.get_total_tick() % Config.TICK_HZ == 0 then
        Score.sync_roles(Adapter.get_all_roles())
    end

    -- ② 推进状态机（唯一的状态变更入口）
    Match.update()

    -- ③ UI 刷新（每 15 帧一次，只读）
    ui_counter = ui_counter + 1
    if ui_counter >= 15 then
        ui_counter = 0
        refresh_ui_all()
    end

    -- ④ 自递归，保持 30Hz 定步长
    if Match.get_state() ~= Config.PHASE.ENDED then
        Adapter.delay_frames(1, tick)
    else
        print("[ICE] 主循环停止")
    end
end

-- ==================== 启动 ====================

local function boot()
    if started then return end
    started = true

    print(string.format("[ICE] ===== 樱花冰晶 · 甜心推推冲分赛 %s =====", VERSION))

    -- 重置计分状态（GAME_INIT 可能因重开而多次触发）
    Score.players        = {}
    Score.taken          = {}
    Score.finished_count = 0

    -- 解析场景
    Registry.build()

    -- 初始化玩家
    local n = Score.sync_roles(Adapter.get_all_roles())
    print(string.format("[ICE] 玩家数：%d（%s模式）", n,
        Score.is_single() and "单人" or "多人"))

    -- UI
    init_ui()

    -- 启动状态机
    Match.start()

    -- 启动主循环
    Adapter.delay_frames(1, tick)
end

-- ==================== 事件注册 ====================

Adapter.on_global({ EVENT.GAME_INIT }, function()
    if Config.DEBUG_LOG then
        print("[ICE] GAME_INIT 收到")
    end
    boot()
end)

-- 兜底：若 GAME_INIT 因注册时机错过，延迟 10 帧后自行启动
Adapter.delay_frames(10, function()
    if not started then
        print("[ICE][WARN] 未收到 GAME_INIT，兜底启动")
        boot()
    end
end)

print("[ICE] main.lua 已加载，等待 GAME_INIT")
