--[[
    ParkourLogic.lua — 第一阶段玩法逻辑
    ------------------------------------------------------------------
    职责：
      · 拾取物判定（樱花糖果 / 冰晶星），带防重拾
      · 存档点推进
      · 掉落判定与回点重生（记录 fallCount）
      · 终点冲线（分配名次）

    确定性说明：
      · 每帧先按 roleId 升序采集全部玩家坐标，再按「物件序号」遍历拾取，
        同一物件被多人同时覆盖时，roleId 较小者优先 —— 保证多端结果一致
      · 所有距离比较都带 0.01 容差
]]

local Config     = require("Config")
local Adapter    = require("EggyAdapter")
local Score      = require("ScoreManager")
local Registry   = require("SceneRegistry")

local Parkour = {}

local EPS = 0.01   -- 浮点容差（FS 铁律 4）

-- ==================== 拾取物 ====================

--- 遍历一组拾取物，判定并结算
---@param group table Registry 中的糖果/星星列表
---@param kind string "candy" | "star"
---@param players table 已按 roleId 排序的玩家列表
---@param posmap table roleId -> Vector3
local function collect_group(group, kind, players, posmap)
    for _, item in ipairs(group) do
        if not Score.is_taken(item.name) and item.pos then
            -- 按 roleId 升序找第一个进入拾取半径的玩家
            for _, p in ipairs(players) do
                local pos = posmap[p.sortKey]
                if pos then
                    local d = Adapter.dist(pos, item.pos)
                    if d < Config.PICKUP_RADIUS + EPS then
                        -- 先占位，再结算（防同一帧重复取）
                        if Score.try_take(item.name) then
                            Score.add_pickup(p, kind)
                            Adapter.destroy_unit(item.unit)
                            Adapter.track(p.role, Config.TRACK.PICKUP,
                                kind == "candy" and Config.SCORE.CANDY or Config.SCORE.STAR)
                        end
                        break        -- 该物件已归属，跳出玩家循环
                    end
                end
            end
        end
    end
end

-- ==================== 存档点 ====================

--- 推进玩家存档点（只前进不后退）
local function update_checkpoint(p, pos)
    local count = Registry.checkpoint_count()
    for i = p.checkpointIndex + 1, count do
        local cp = Registry.get_checkpoint(i)
        if cp and cp.pos then
            if Adapter.dist(pos, cp.pos) < Config.CHECKPOINT_RADIUS + EPS then
                p.checkpointIndex = i
            else
                break        -- 存档点是有序的，遇到未触碰的即可停止
            end
        end
    end
end

-- ==================== 掉落重生 ====================

--- 掉落回点：不扣分，只记 fallCount（v1.1 规则）
local function respawn(p, unit)
    local cp = Registry.get_checkpoint(p.checkpointIndex)
    if cp == nil then cp = Registry.get_checkpoint(1) end

    if cp and cp.pos then
        local target = Adapter.offset(cp.pos, 0, Config.RESPAWN_Y_OFFSET, 0)
        Adapter.set_pos(unit, target)
    end

    p.fallCount = p.fallCount + 1
    Adapter.log(string.format("掉落重生：%s（累计 %d 次，回到存档点 %d）",
        p.name, p.fallCount, p.checkpointIndex > 0 and p.checkpointIndex or 1))
    Adapter.track(p.role, Config.TRACK.FALL, 1)
end

-- ==================== 主更新 ====================

--- 每逻辑帧调用一次
---@param elapsed_ticks integer 从 PARKOUR 开始累计的帧数
function Parkour.update(elapsed_ticks)
    local players = Score.sorted_players()

    -- ① 采集坐标（每帧每玩家只取一次，减少跨语言调用）
    local posmap = {}
    local unitmap = {}
    for _, p in ipairs(players) do
        local unit = Adapter.ctrl_unit(p.role)
        unitmap[p.sortKey] = unit
        if unit then
            posmap[p.sortKey] = Adapter.get_pos(unit)
        end
    end

    -- ② 逐玩家：掉落 → 存档点 → 冲线
    for _, p in ipairs(players) do
        local pos = posmap[p.sortKey]
        if pos then
            if pos.y < Config.PARKOUR_FALL_Y - EPS then
                -- 掉落去抖：一次坠落只结算一次，避免低于阈值时每帧重复计数
                if not p.isFalling then
                    p.isFalling = true
                    respawn(p, unitmap[p.sortKey])
                end
            else
                p.isFalling = false
                update_checkpoint(p, pos)

                if not p.isFinishedParkour then
                    local finish = Registry.get_finish()
                    if finish and finish.pos then
                        if Adapter.dist(pos, finish.pos) < Config.FINISH_RADIUS + EPS then
                            Score.mark_finish(p, elapsed_ticks)
                        end
                    end
                end
            end
        end
    end

    -- ③ 拾取物（必须在玩家坐标采集之后、且按物件序号遍历）
    collect_group(Registry.candies, "candy", players, posmap)
    collect_group(Registry.stars,  "star",  players, posmap)
end

return Parkour
