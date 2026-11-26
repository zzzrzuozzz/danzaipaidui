--[[
    PushBallLogic.lua — 第二阶段：推球偷分轻对抗
    ------------------------------------------------------------------
    设计要点：
      · 只依赖 Config / EggyAdapter / ScoreManager / SceneRegistry，
        不反向依赖状态机（由状态机单向调用）
      · 球体走「场景预摆 + 隐藏停放复用」，不做运行时动态创建
        （create_obstacle 需要预制体 _u_key，易踩坑）
      · 停放 = 移到 y = PARK_Y + 关闭物理，彻底退出模拟

    锁步确定性要点：
      · 球按序号升序遍历，玩家按 roleId 升序遍历
      · 刷新点用 Adapter.random_int（引擎确定性随机），不用 math.random
      · 所有距离比较带 EPS 容差
]]

local Config   = require("Config")
local Adapter  = require("EggyAdapter")
local Score    = require("ScoreManager")
local Registry = require("SceneRegistry")

local PushBall = {}

local EPS = 0.01
local PB  = Config.PUSH_BALL

-- 球状态数组
local balls          = {}
local running        = false
local big_activated  = 0     -- 已激活的大球数量

-- ==================== 内部：停放 / 复位 ====================

--- 停放：清零速度与旋转、关闭物理、移到隐藏位
local function park(ball)
    local unit = ball.unit
    Adapter.set_linear_velocity(unit, Adapter.vec(0, 0, 0))
    Adapter.set_angular_velocity(unit, Adapter.vec(0, 0, 0))
    Adapter.set_physics_active(unit, false)
    Adapter.set_pos(unit, Adapter.vec(0, PB.PARK_Y, 0))

    ball.active        = false
    ball.lastOwnerKey  = nil
    ball.lastTouchTick = 0
    ball.forceTick     = 0
    ball.isStolen      = false
end

--- 复位到指定刷新点并激活
local function reset_ball(ball, spawn_item)
    if spawn_item == nil or spawn_item.pos == nil then return false end

    local target = Adapter.offset(spawn_item.pos, 0, PB.RESPAWN_Y_OFFSET, 0)
    Adapter.set_pos(ball.unit, target)
    Adapter.set_linear_velocity(ball.unit, Adapter.vec(0, 0, 0))
    Adapter.set_angular_velocity(ball.unit, Adapter.vec(0, 0, 0))
    Adapter.set_physics_active(ball.unit, true)

    ball.active        = true
    ball.cooldownTicks = 0
    ball.lastOwnerKey  = nil
    ball.lastTouchTick = 0
    ball.forceTick     = 0
    ball.isStolen      = false
    return true
end

--- 确定性选一个刷新点
local function pick_spawn()
    local n = Registry.ball_spawn_count()
    if n == 0 then return nil end
    local idx = Adapter.random_int(1, n)
    return Registry.get_ball_spawn(idx)
end

-- ==================== 内部：建球 ====================

local function build_balls()
    balls = {}

    for i = 1, Registry.candy_ball_count() do
        local it = Registry.get_candy_ball(i)
        balls[#balls + 1] = {
            kind          = "small",
            index         = i,
            name          = it.name,
            unit          = it.unit,
            baseScore     = PB.SMALL_BALL_SCORE,
            active        = false,
            cooldownTicks = 0,
            lastOwnerKey  = nil,
            lastTouchTick = 0,
            forceTick     = 0,
            isStolen      = false,
        }
    end

    for i = 1, Registry.big_ball_count() do
        local it = Registry.get_big_ball(i)
        balls[#balls + 1] = {
            kind          = "big",
            index         = i,
            name          = it.name,
            unit          = it.unit,
            baseScore     = PB.BIG_BALL_SCORE,
            active        = false,
            cooldownTicks = 0,
            lastOwnerKey  = nil,
            lastTouchTick = 0,
            forceTick     = 0,
            isStolen      = false,
        }
    end
end

-- ==================== 内部：采集玩家 ====================

local function collect_players()
    local players = Score.sorted_players()
    local posmap  = {}
    local unitmap = {}
    for _, p in ipairs(players) do
        if p.isOnline then
            local unit = Adapter.ctrl_unit(p.role)
            unitmap[p.sortKey] = unit
            if unit then
                posmap[p.sortKey] = Adapter.get_pos(unit)
            end
        end
    end
    return players, posmap, unitmap
end

-- ==================== 内部：触球 / 归属 / 抢断 ====================

local function on_touch(ball, player_key, player_pos, ball_pos, phase_tick)
    -- 抢断判定：上次归属是别人，且距今在窗口内
    if ball.lastOwnerKey ~= nil
        and ball.lastOwnerKey ~= player_key
        and (phase_tick - ball.lastTouchTick) <= PB.STEAL_WINDOW_TICKS then
        ball.isStolen = true
    end

    ball.lastOwnerKey  = player_key
    ball.lastTouchTick = phase_tick

    -- 辅助推力：按 6 帧节流，避免每帧持续加速
    if PB.ENABLE_PUSH_FORCE and (phase_tick - ball.forceTick) >= 6 then
        ball.forceTick = phase_tick
        local dx = ball_pos.x - player_pos.x
        local dz = ball_pos.z - player_pos.z
        local len = math.sqrt(dx * dx + dz * dz)
        if len > 0.001 then
            local f = Adapter.vec(dx / len * PB.PUSH_FORCE, 0, dz / len * PB.PUSH_FORCE)
            Adapter.apply_force(ball.unit, f)
        end
    end
end

-- ==================== 内部：进球 ====================

local function try_goal(ball, ball_pos)
    local holes = Registry.ball_hole_count()
    if holes == 0 then return false end

    for h = 1, holes do
        local hole = Registry.get_ball_hole(h)
        if hole and hole.pos then
            if Adapter.dist(ball_pos, hole.pos) < PB.GOAL_RADIUS + EPS then
                local p = (ball.lastOwnerKey ~= nil) and Score.players[ball.lastOwnerKey] or nil
                if p ~= nil then
                    Score.add_push_goal(p, ball.baseScore, ball.isStolen)
                    Adapter.log(string.format("进球：%s 用%s进 %s 分（抢断=%s，累计 %d 球）",
                        p.name,
                        ball.kind == "big" and "冰晶大球" or "糖果球",
                        tostring(ball.baseScore),
                        tostring(ball.isStolen),
                        p.pushGoals))
                    Adapter.tips(p.role, string.format("进球 +%d！", ball.baseScore), 2.0)
                else
                    Adapter.log(string.format("进球无效：%s 无有效归属（无人触碰）", ball.name))
                end
                return true
            end
        end
    end
    return false
end

-- ==================== 内部：回收 ====================

local function recycle(ball)
    park(ball)
    ball.cooldownTicks = PB.BALL_RESPAWN_TICKS
end

-- ==================== 内部：大球激活 ====================

local function tick_big_ball(phase_tick)
    for _, at in ipairs(PB.BIG_BALL_ACTIVATE_TICKS) do
        if phase_tick == at then
            local seen = 0
            for _, ball in ipairs(balls) do
                if ball.kind == "big" then
                    seen = seen + 1
                    if seen == big_activated + 1 then
                        local sp = pick_spawn()
                        if sp then
                            big_activated = big_activated + 1
                            reset_ball(ball, sp)
                            Adapter.log(string.format("冰晶大球激活（第 %d 颗，帧 %d）",
                                big_activated, phase_tick))
                            for _, p in ipairs(Score.sorted_players()) do
                                Adapter.tips(p.role, "冰晶大球出现！+35 分", 3.0)
                            end
                        end
                        return
                    end
                end
            end
        end
    end
end

-- ==================== 内部：玩家掉台回传 ====================

local function handle_player_fall(players, posmap, unitmap)
    for _, p in ipairs(players) do
        local pos = posmap[p.sortKey]
        if pos then
            if pos.y < PB.PUSH_BALL_FALL_Y - EPS then
                if not p.isFalling then
                    p.isFalling = true
                    local unit = unitmap[p.sortKey]
                    local tp = Registry.get_teleport(p.seat)
                    if unit and tp and tp.pos then
                        Adapter.set_pos(unit,
                            Adapter.offset(tp.pos, 0, PB.PLAYER_RETURN_Y_OFFSET, 0))
                    end
                    Adapter.set_linear_velocity(unit, Adapter.vec(0, 0, 0))
                    p.fallCount = p.fallCount + 1
                    Adapter.track(p.role, Config.TRACK.FALL, 1)
                    Adapter.log(string.format("推球区掉台回传：%s（累计 %d 次）",
                        p.name, p.fallCount))
                end
            else
                p.isFalling = false
            end
        end
    end
end

-- ==================== 公开：生命周期 ====================

--- 进入 PUSH_BALL 时调用一次
function PushBall.start()
    build_balls()
    big_activated = 0

    -- 全部先停放
    for _, ball in ipairs(balls) do
        park(ball)
    end

    -- 小球按刷新点确定性铺开
    local spawn_n = Registry.ball_spawn_count()
    local placed  = 0
    if spawn_n > 0 then
        local cursor = 0
        for _, ball in ipairs(balls) do
            if ball.kind == "small" then
                cursor = cursor + 1
                local idx = ((cursor - 1) % spawn_n) + 1
                if reset_ball(ball, Registry.get_ball_spawn(idx)) then
                    placed = placed + 1
                end
            end
        end
    else
        print("[ICE][WARN] 无球刷新点，推球阶段将没有可用球体")
    end

    running = true

    print(string.format(
        "[ICE] 推球阶段启动：糖果球 %d，冰晶大球 %d，球洞 %d，刷新点 %d（小球已上场 %d）",
        Registry.candy_ball_count(), Registry.big_ball_count(),
        Registry.ball_hole_count(), spawn_n, placed))
end

--- 每逻辑帧调用（phase_tick = 进入 PUSH_BALL 后经过的帧数）
function PushBall.update(phase_tick)
    if not running then return end

    tick_big_ball(phase_tick)

    local players, posmap, unitmap = collect_players()

    -- ① 玩家掉台回传
    handle_player_fall(players, posmap, unitmap)

    -- ② 逐球处理（按序号升序，保证确定性）
    for _, ball in ipairs(balls) do
        if not ball.active then
            -- 回收冷却中：倒计时结束后刷新
            if ball.cooldownTicks > 0 then
                ball.cooldownTicks = ball.cooldownTicks - 1
                if ball.cooldownTicks <= 0 then
                    local sp = pick_spawn()
                    reset_ball(ball, sp)
                end
            end
        else
            local ball_pos = Adapter.get_pos(ball.unit)
            if ball_pos then
                -- 触球归属（玩家按 roleId 升序，首个命中者生效）
                for _, p in ipairs(players) do
                    local pp = posmap[p.sortKey]
                    if pp then
                        if Adapter.dist(pp, ball_pos) < PB.BALL_TOUCH_RADIUS + EPS then
                            on_touch(ball, p.sortKey, pp, ball_pos, phase_tick)
                            break
                        end
                    end
                end
                -- 未被触碰则不更新归属：球自己滚进洞，功劳仍归上一次触球者

                -- 掉出圆台
                if ball_pos.y < PB.PUSH_BALL_FALL_Y - EPS then
                    Adapter.log(string.format("球掉台：%s 回收", ball.name))
                    recycle(ball)
                else
                    -- 进球判定
                    if try_goal(ball, ball_pos) then
                        recycle(ball)
                    end
                end
            end
        end
    end
end

--- 进入 SETTLEMENT 前调用：冻结全场球体，避免结算期间误进球
function PushBall.stop()
    if not running then return end
    running = false
    for _, ball in ipairs(balls) do
        park(ball)
    end
    print("[ICE] 推球阶段结束，全场球体已冻结")
end

--- 查询是否运行中
function PushBall.is_running()
    return running
end

return PushBall
