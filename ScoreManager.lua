--[[
    ScoreManager.lua — 玩家状态、计分、排名、称号
    ------------------------------------------------------------------
    锁步确定性要点：
      · 玩家列表每次 sync 都按 roleId 字符串升序排序，座位号 = 排序序号
      · 排名排序：totalScore 降序，同分按 roleId 升序（消除 table.sort 不稳定）
      · 拾取防重：以「组件名」为键做一次性标记，不依赖时间或随机

    预埋字段（供第二阶段推球与终局称号使用）：
      parkourScore / pushScore / totalScore / checkpointIndex /
      isFinishedParkour / finishRank / parkourFinishTicks / fallCount /
      pushGoals / stealCount
]]

local Config  = require("Config")
local Adapter = require("EggyAdapter")

local Score = {}

-- roleId(string) -> player
Score.players = {}
-- 拾取防重：组件名 -> true
Score.taken = {}
-- 完赛顺序计数器
Score.finished_count = 0

-- ==================== 内部工具 ====================

local function to_key(role_id)
    return tostring(role_id)
end

--- 取排序后的玩家列表（锁定顺序，供遍历/结算用）
local function sorted_players()
    local list = {}
    for _, p in pairs(Score.players) do
        list[#list + 1] = p
    end
    table.sort(list, function(a, b)
        return a.sortKey < b.sortKey
    end)
    return list
end
Score.sorted_players = sorted_players

-- ==================== 初始化 / 同步 ====================

--- 新建一个玩家档案
local function new_player(role, role_id)
    return {
        role               = role,
        roleId             = role_id,
        sortKey            = to_key(role_id),
        seat               = 0,     -- 座位号 1~8，由 sync 统一分配
        name               = Adapter.role_name(role),

        -- 分数
        parkourScore       = 0,
        pushScore          = 0,
        totalScore         = 0,

        -- 跑酷进度
        checkpointIndex    = 0,     -- 0 = 尚未触碰存档点
        isFinishedParkour  = false,
        finishRank         = 0,     -- 0 = 未完赛
        parkourFinishTicks = 0,     -- 完赛耗时（帧）

        -- 统计（称号用）
        fallCount          = 0,
        candyCount         = 0,
        starCount          = 0,
        isFalling          = false,  -- 掉落去抖状态（防止低于阈值时每帧重复计数）

        -- 第二阶段预留
        pushGoals          = 0,
        stealCount         = 0,
    }
end

--- 同步玩家列表：新增玩家入场、座位按 roleId 排序确定
function Score.sync_roles(roles)
    local seen = {}
    local newcomers = {}

    for _, role in ipairs(roles) do
        local id = Adapter.role_id(role)
        if id ~= nil then
            local key = to_key(id)
            seen[key] = true
            local p = Score.players[key]
            if p == nil then
                p = new_player(role, id)
                Score.players[key] = p
                newcomers[#newcomers + 1] = p
            else
                p.role = role        -- 刷新句柄，防对象失效
            end
        end
    end

    -- 座位号：按当前全体 roleId 升序重新分配（确定性）
    local all = sorted_players()
    for i, p in ipairs(all) do
        p.seat = i
    end

    if #newcomers > 0 then
        for _, p in ipairs(newcomers) do
            Adapter.log(string.format("玩家入场：%s (roleId=%s) 座位=%d",
                p.name, p.sortKey, p.seat))
        end
    end

    return #all
end

--- 当前在场玩家数（决定单/多人模式）
function Score.player_count()
    local n = 0
    for _ in pairs(Score.players) do n = n + 1 end
    return n
end

--- 是否单人模式
function Score.is_single()
    return Score.player_count() <= Config.PLAYER_COUNT_SINGLE
end

-- ==================== 计分 ====================

--- 内部：把总分同步到引擎积分板
local function flush_engine_score(p)
    Adapter.set_score(p.role, p.totalScore)
end

--- 加分
---@param p table 玩家档案
---@param delta number 增量（可为负）
---@param reason string 来源标记（日志用）
function Score.add(p, delta, reason)
    if p == nil or delta == 0 then return end
    p.totalScore = p.totalScore + delta
    if p.totalScore < 0 then p.totalScore = 0 end
    flush_engine_score(p)
end

--- 跑酷拾取加分
function Score.add_pickup(p, kind)
    if kind == "candy" then
        p.parkourScore = p.parkourScore + Config.SCORE.CANDY
        p.candyCount   = p.candyCount + 1
        Score.add(p, Config.SCORE.CANDY, "candy")
    elseif kind == "star" then
        p.parkourScore = p.parkourScore + Config.SCORE.STAR
        p.starCount    = p.starCount + 1
        Score.add(p, Config.SCORE.STAR, "star")
    end
end

-- ==================== 拾取防重 ====================

--- 尝试占用一个拾取物；成功返回 true
---@param unit_name string 组件名
function Score.try_take(unit_name)
    if Score.taken[unit_name] then return false end
    Score.taken[unit_name] = true
    return true
end

--- 该拾取物是否已被取走
function Score.is_taken(unit_name)
    return Score.taken[unit_name] == true
end

-- ==================== 完赛与名次 ====================

--- 标记完赛，并分配名次分
---@param p table 玩家档案
---@param elapsed_ticks integer 从 PARKOUR 开始到冲线的帧数
---@return integer rank 名次（1 基）
function Score.mark_finish(p, elapsed_ticks)
    if p.isFinishedParkour then return p.finishRank end

    Score.finished_count = Score.finished_count + 1
    local rank = Score.finished_count

    p.isFinishedParkour  = true
    p.finishRank         = rank
    p.parkourFinishTicks = elapsed_ticks

    local bonus = Config.SCORE.FINISH_RANK[rank] or Config.SCORE.FINISH_RANK[#Config.SCORE.FINISH_RANK]
    if rank <= 8 then
        p.parkourScore = p.parkourScore + bonus
        Score.add(p, bonus, "finish_rank")
    end

    Adapter.log(string.format("完赛：%s 第 %d 名 +%d 分（用时 %.2fs）",
        p.name, rank, bonus, elapsed_ticks / Config.TICK_HZ))
    Adapter.track(p.role, Config.TRACK.FINISH, rank)

    return rank
end

--- 是否全员完赛（用于 PARKOUR 提前结束）
function Score.all_finished()
    for _, p in pairs(Score.players) do
        if not p.isFinishedParkour then return false end
    end
    return true
end

-- ==================== 排名 ====================

--- 实时排名（totalScore 降序，同分按 roleId 升序）
---@return table list
function Score.get_ranked()
    local list = sorted_players()
    table.sort(list, function(a, b)
        if a.totalScore ~= b.totalScore then
            return a.totalScore > b.totalScore
        end
        return a.sortKey < b.sortKey      -- 锁步确定性：同分不依赖 sort 稳定性
    end)
    return list
end

--- 单人模式星级（返回星级名，未达线返回 nil）
function Score.single_star(p)
    local star = nil
    for _, s in ipairs(Config.SINGLE_STAR) do
        if p.totalScore >= s.score then star = s end
    end
    return star
end

-- ==================== 称号判定 ====================

--- 计算全部称号，返回 { [roleId] = { titles... } }
function Score.compute_titles()
    local result = {}
    local list = sorted_players()
    local single = Score.is_single()
    local finished_count = 0

    for _, p in ipairs(list) do
        result[p.sortKey] = {}
        if p.isFinishedParkour then finished_count = finished_count + 1 end
    end

    local ranked = Score.get_ranked()

    -- ① 冰雪樱花女王：总分第 1（单/多人都发）
    if ranked[1] then
        table.insert(result[ranked[1].sortKey], "冰雪樱花女王")
    end

    if not single then
        -- ② 甜心追风少女：完赛用时最短，且完赛人数 ≥ 2
        if finished_count >= 2 then
            local best, best_ticks = nil, math.huge
            for _, p in ipairs(list) do
                if p.isFinishedParkour and p.parkourFinishTicks < best_ticks then
                    best, best_ticks = p, p.parkourFinishTicks
                end
            end
            if best then table.insert(result[best.sortKey], "甜心追风少女") end
        end
    end

    -- ③ 超级推推王：推球进球最多，且 ≥ 1 球（单/多人都发）
    local king, king_goals = nil, 0
    for _, p in ipairs(list) do
        if p.pushGoals > king_goals then king, king_goals = p, p.pushGoals end
    end
    if king and king_goals >= 1 then
        table.insert(result[king.sortKey], "超级推推王")
    end

    if not single then
        -- ④ 优雅小神偷：抢断后进球最多，且 ≥ 1 次
        local thief, thief_n = nil, 0
        for _, p in ipairs(list) do
            if p.stealCount > thief_n then thief, thief_n = p, p.stealCount end
        end
        if thief and thief_n >= 1 then
            table.insert(result[thief.sortKey], "优雅小神偷")
        end
    end

    -- ⑤ 冰面平衡大师：零掉落（多人另要求完赛人数 ≥ 2）
    local balanced = {}
    for _, p in ipairs(list) do
        if p.fallCount == 0 then balanced[#balanced + 1] = p end
    end
    if single then
        if #balanced >= 1 then
            table.insert(result[balanced[1].sortKey], "冰面平衡大师")
        end
    elseif finished_count >= 2 then
        for _, p in ipairs(balanced) do
            table.insert(result[p.sortKey], "冰面平衡大师")
        end
    end

    if not single then
        -- ⑥ 蹦蹦跳跳小迷糊：掉台次数最多，且 ≥ 2 次
        local clumsy, clumsy_n = nil, 1
        for _, p in ipairs(list) do
            if p.fallCount > clumsy_n then clumsy, clumsy_n = p, p.fallCount end
        end
        if clumsy then
            table.insert(result[clumsy.sortKey], "蹦蹦跳跳小迷糊")
        end
    end

    return result
end

return Score
