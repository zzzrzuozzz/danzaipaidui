--[[
    Config.lua — 全局配置（唯一数值来源）
    ------------------------------------------------------------------
    · 所有时间、分数、半径、开关集中在此，其他模块只读不写
    · 时间单位一律换算为「逻辑帧」(tick)，避免浮点累加漂移
    · 场景契约命名也在这里定义，SceneRegistry 按此生成名称列表
]]

local Config = {}

-- ==================== ① 高频调参旋钮（改这里就够） ====================
Config.TICK_HZ            = 30      -- 逻辑帧率：固定 30Hz（1 秒 = 30 帧）
Config.PARKOUR_FALL_Y     = -5.0    -- 掉落判定高度阈值
Config.PICKUP_RADIUS      = 1.6     -- 拾取物拾取半径（蛋仔身位）
Config.FINISH_RADIUS      = 3.0     -- 终点冲线半径
Config.CHECKPOINT_RADIUS  = 3.0     -- 存档点触发半径
Config.RESPAWN_Y_OFFSET   = 1.5     -- 重生时在存档点上方的抬高量
Config.MAX_PLAYERS        = 8       -- 最大玩家数（座位 1~8）

Config.ENABLE_PUSH_BALL   = true    -- 第二阶段总开关：false 时 PUSH_BALL 直接跳过
Config.DEBUG_LOG          = true    -- 是否打印调试日志
Config.DEBUG_FAST         = false   -- true = 所有阶段压缩到 1/10，仅用于冒烟测试

-- ==================== ② 分数配置 ====================
Config.SCORE = {
    CANDY            = 1,           -- 樱花糖果
    STAR             = 3,           -- 冰晶星
}

-- 跑酷完赛名次分：索引 = 名次（1~8），未完赛记 0
Config.SCORE.FINISH_RANK = { 30, 25, 20, 15, 15, 15, 15, 15 }

-- ==================== ②-2 推球阶段参数（第二阶段） ====================
Config.PUSH_BALL = {
    BALL_TOUCH_RADIUS       = 1.8,    -- 触球判定半径
    GOAL_RADIUS             = 2.2,    -- 进球判定半径（球心到球洞中心）
    STEAL_WINDOW_TICKS      = 90,     -- 抢断窗口：90 帧（3s）内易主才算抢断
    BALL_RESPAWN_TICKS      = 60,     -- 球回收冷却：60 帧（2s）
    PUSH_BALL_FALL_Y        = -5.0,   -- 球掉出圆台的判定高度
    PARK_Y                  = -100.0, -- 隐藏停放高度（停放时同时关物理）
    RESPAWN_Y_OFFSET        = 1.5,    -- 球刷新落点抬高量
    SMALL_BALL_SCORE        = 15,     -- 糖果球进球分
    BIG_BALL_SCORE          = 35,     -- 冰晶大球进球分
    STEAL_BONUS             = 10,     -- 抢断额外加分（仅多人模式）
    BIG_BALL_ACTIVATE_TICKS = { 450, 900 },  -- 大球激活帧（15s / 30s）
    ENABLE_PUSH_FORCE       = true,   -- 是否施加辅助推力
    PUSH_FORCE              = 6.0,    -- 辅助推力强度
    PLAYER_RETURN_Y_OFFSET  = 1.5,    -- 玩家掉台回传抬高量
}

-- ==================== ③ 单人模式星级目标线 ====================
Config.PLAYER_COUNT_SINGLE = 1
Config.SINGLE_STAR = {
    { score = 120, name = "银星" },
    { score = 200, name = "金星" },
    { score = 280, name = "冰雪公主" },
}

-- ==================== ④ 阶段时长（秒 → 帧） ====================
-- 总时长 110s；编辑器「规则设置-计时规则」请设为 120s 兜底
local function sec_to_ticks(sec)
    if Config.DEBUG_FAST then sec = sec / 10 end
    return math.max(1, math.floor(sec * Config.TICK_HZ + 0.5))
end

Config.PHASE_SEC = {
    READY       = 5,
    PARKOUR     = 45,
    TRANSITION  = 5,
    PUSH_BALL   = 45,
    SETTLEMENT  = 10,
}

Config.PHASE_TICKS = {
    READY       = sec_to_ticks(Config.PHASE_SEC.READY),
    PARKOUR     = sec_to_ticks(Config.PHASE_SEC.PARKOUR),
    TRANSITION  = sec_to_ticks(Config.PHASE_SEC.TRANSITION),
    PUSH_BALL   = sec_to_ticks(Config.PHASE_SEC.PUSH_BALL),
    SETTLEMENT  = sec_to_ticks(Config.PHASE_SEC.SETTLEMENT),
}

-- ==================== ⑤ 场景契约（精确命名匹配） ====================
-- 名称格式：<prefix><两位编号>，例如 樱花糖果_01
Config.SCENE = {
    CHECKPOINT = { prefix = "存档点_",   count = 3,  pad = 2 },
    CANDY      = { prefix = "樱花糖果_", count = 40, pad = 2 },
    STAR       = { prefix = "冰晶星_",   count = 10, pad = 2 },
    TELEPORT   = { prefix = "传送点_",   count = 8,  pad = 2 },

    -- 第二阶段：预摆对象池（不做运行时动态创建，只移动复用）
    CANDY_BALL = { prefix = "糖果球_",   count = 4,  pad = 2 },
    BIG_BALL   = { prefix = "冰晶大球_", count = 2,  pad = 2 },
    BALL_HOLE  = { prefix = "球洞_",     count = 4,  pad = 2 },
    BALL_SPAWN = { prefix = "球刷新点_", count = 4,  pad = 2 },
}

Config.SCENE_FINISH = "终点_胜利区域"   -- 终点触发区（单件）

-- 按契约生成全部名称（供 SceneRegistry 遍历解析）
function Config.build_name_list(spec)
    local list = {}
    for i = 1, spec.count do
        list[i] = string.format("%s%0" .. spec.pad .. "d", spec.prefix, i)
    end
    return list
end

-- ==================== ⑥ UI 节点名（可选，留空则跳过 UI 刷新） ====================
-- 默认关闭：地图里还没建 UI 节点时，任何 set_label_text 调用都会让引擎报
-- 「节点类型不正确」。建好 UI 后把 ENABLED 改 true 并填写三个节点名即可。
Config.UI = {
    ENABLED       = false,
    SCORE_LABEL   = "积分",      -- 顶部总分显示
    RANK_LABEL    = "排名",      -- 排名/星线显示
    TIMER_LABEL   = "倒计时",    -- 阶段倒计时
}

-- ==================== ⑦ 埋点 Key ====================
Config.TRACK = {
    PICKUP   = "ice_pickup",      -- 拾取埋点
    FINISH   = "ice_finish",      -- 完赛埋点
    FALL     = "ice_fall",        -- 掉落埋点
    PHASE    = "ice_phase",       -- 阶段流转埋点
    RESULT   = "ice_result",      -- 结算埋点
    GOAL     = "ice_goal",        -- 推球进球埋点
    STEAL    = "ice_steal",       -- 抢断埋点
}

-- ==================== ⑧ 阶段枚举 ====================
Config.PHASE = {
    BOOT        = "BOOT",
    READY       = "READY",
    PARKOUR     = "PARKOUR",
    TRANSITION  = "TRANSITION",
    PUSH_BALL   = "PUSH_BALL",
    SETTLEMENT  = "SETTLEMENT",
    ENDED       = "ENDED",
}

return Config
