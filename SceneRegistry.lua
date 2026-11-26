--[[
    SceneRegistry.lua — 场景契约解析与缓存
    ------------------------------------------------------------------
    职责：
      1. 启动时按 Config 的命名模板，逐个解析场景组件
      2. 缺失只打印告警，绝不崩溃
      3. 对外提供「按序取件」接口，并缓存坐标（坐标在开局后不变）

    为什么缓存坐标：
      unit.get_position() 是跨语言调用，每帧对 50+ 物件调用开销可观。
      这些物件在跑酷阶段是静止的，开局解析一次即可。
]]

local Config      = require("Config")
local Adapter     = require("EggyAdapter")

local Registry = {}

-- 按类别存放：{ [1] = { name = , unit = , pos = } }
Registry.checkpoints = {}
Registry.candies     = {}
Registry.stars       = {}
Registry.teleports   = {}
Registry.finish      = nil

-- 解析统计（用于启动日志）
Registry.stats = {}

-- ==================== 内部：解析一组同类组件 ====================

local function resolve_group(spec, label)
    local list  = {}
    local names = Config.build_name_list(spec)
    local missing = {}

    for i, name in ipairs(names) do
        local unit = Adapter.find_unit(name)
        if unit then
            list[#list + 1] = {
                index = i,
                name  = name,
                unit  = unit,
                pos   = Adapter.get_pos(unit),
            }
        else
            missing[#missing + 1] = name
        end
    end

    if #missing > 0 then
        -- 只打印前 5 个，避免刷屏
        local preview = table.concat(missing, ", ", 1, math.min(#missing, 5))
        if #missing > 5 then preview = preview .. " …(共 " .. #missing .. " 个)" end
        print(string.format("[ICE][WARN] %s 缺失 %d/%d：%s", label, #missing, spec.count, preview))
    end

    return list
end

-- ==================== 公开：全量解析 ====================

function Registry.build()
    -- 清空旧数据（支持重开）
    Registry.checkpoints = {}
    Registry.candies     = {}
    Registry.stars       = {}
    Registry.teleports   = {}
    Registry.finish      = nil
    Registry.stats       = {}

    Adapter.clear_unit_cache()

    Registry.checkpoints = resolve_group(Config.SCENE.CHECKPOINT, "存档点")
    Registry.candies     = resolve_group(Config.SCENE.CANDY,      "樱花糖果")
    Registry.stars       = resolve_group(Config.SCENE.STAR,       "冰晶星")
    Registry.teleports   = resolve_group(Config.SCENE.TELEPORT,   "传送点")

    -- 终点（单件）
    local finish_unit = Adapter.find_unit(Config.SCENE_FINISH)
    if finish_unit then
        Registry.finish = {
            name = Config.SCENE_FINISH,
            unit = finish_unit,
            pos  = Adapter.get_pos(finish_unit),
        }
    else
        print("[ICE][WARN] 终点 缺失：" .. Config.SCENE_FINISH .. "（冲线判定将失效）")
    end

    Registry.stats = {
        checkpoint = #Registry.checkpoints,
        candy      = #Registry.candies,
        star       = #Registry.stars,
        teleport   = #Registry.teleports,
        finish     = Registry.finish and 1 or 0,
    }

    print(string.format(
        "[ICE] 场景解析完成：存档点 %d/%d，糖果 %d/%d，冰晶星 %d/%d，传送点 %d/%d，终点 %d/1",
        Registry.stats.checkpoint, Config.SCENE.CHECKPOINT.count,
        Registry.stats.candy,      Config.SCENE.CANDY.count,
        Registry.stats.star,       Config.SCENE.STAR.count,
        Registry.stats.teleport,   Config.SCENE.TELEPORT.count,
        Registry.stats.finish
    ))

    return Registry.stats
end

-- ==================== 按序取件 ====================

--- 取第 index 个存档点（1 基）；越界返回 nil
function Registry.get_checkpoint(index)
    return Registry.checkpoints[index]
end

--- 取第 index 个糖果
function Registry.get_candy(index)
    return Registry.candies[index]
end

--- 取第 index 个冰晶星
function Registry.get_star(index)
    return Registry.stars[index]
end

--- 取第 seat 个传送点；缺失时回退到第一个可用传送点
function Registry.get_teleport(seat)
    local t = Registry.teleports[seat]
    if t then return t end
    return Registry.teleports[1]     -- 座位数 > 传送点数时的兜底
end

--- 取终点
function Registry.get_finish()
    return Registry.finish
end

--- 取所有存档点数量
function Registry.checkpoint_count()
    return #Registry.checkpoints
end

return Registry
