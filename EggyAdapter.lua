--[[
    EggyAdapter.lua — 引擎 API 唯一出口层
    ------------------------------------------------------------------
    设计目的：
      1. 其他模块不直接调用引擎 API，全部经过本层，便于替换与降级
      2. 所有调用做 pcall 保护，缺失/报错只告警不崩溃
      3. 统一处理「实例方法调用约定」差异（点式 / 冒号式）

    用到的编辑器 API 一览（按用途标注）：
      · LuaAPI.query_unit(name)          —— 按名称查场景单位（较慢，须缓存）
      · GameAPI.get_unit_id_by_name()    —— 名称转单位 ID（备用路径）
      · GameAPI.get_unit(id)             —— ID 转单位对象
      · unit.get_position / set_position —— 读写单位世界坐标（物理传送用）
      · unit.apply_force(vec)            —— 施加瞬间力（预留推球用）
      · GameAPI.get_all_valid_roles()    —— 取全部玩家角色
      · role.get_ctrl_unit()             —— 玩家 → 其操控的蛋仔单位
      · role.add_score / get_score / set_score —— 积分板（引擎侧显示）
      · role.set_role_ctrl_enabled(bool) —— 锁定/解锁移动（READY / SETTLEMENT）
      · role.get_roleid()                —— 玩家唯一 ID（锁步排序主键）
      · role.show_tips(text, dur)        —— 玩家级飘字
      · role.set_label_text / set_node_visible —— 玩家级 UI 刷新
      · LuaAPI.call_delay_frame(n, cb)   —— 帧级定时器（30Hz 定步长驱动）
      · LuaAPI.global_register_trigger_event —— 全局事件注册（GAME_INIT 等）
      · GameAPI.random_int / randint     —— 确定性随机（禁 math.random）
      · GameAPI.destroy_unit(unit)       —— 销毁单位（拾取后消失）
      · GameAPI.game_end()               —— 主动结束对局
      · LuaAPI.log / GlobalAPI.show_tips —— 日志与全场提示
]]

local Adapter = {}

-- ==================== 内部状态 ====================
local warned = {}            -- 告警去重表
local method_conv = nil      -- "dot" | "colon"，实例方法调用约定（首次调用时探测）

local function warn_once(key, msg)
    if warned[key] then return end
    warned[key] = true
    print("[ICE][WARN] " .. tostring(msg))
end

-- ==================== 日志 / 埋点 ====================

--- 统一日志
function Adapter.log(msg)
    print("[ICE] " .. tostring(msg))
end

--- 玩家级埋点：优先走引擎埋点 API，失败则退化为日志
---@param role table|nil 玩家（nil 表示全局埋点）
---@param key string 埋点 key
---@param value number 增量
function Adapter.track(role, key, value)
    if role == nil then return end
    local v = value or 1

    -- 统一经 mcall 调用，避免与其他实例方法的调用约定不一致
    if role["send_track_data_log"] ~= nil then
        local ok = pcall(function()
            Adapter.mcall(role, "send_track_data_log", key, v)
        end)
        if ok then return end
    end
    pcall(function()
        Adapter.mcall(role, "send_track_data_change", key, v)
    end)
end

-- ==================== 实例方法调用（兼容点式/冒号式） ====================

--- 统一的实例方法调用
--- 说明：引擎对「实例方法」存在点式（obj.f(a)）与冒号式（obj:f(a)）两种可能约定，
---       这里首次调用时自动探测并锁定，之后零开销。
---@param obj table 单位/玩家对象
---@param name string 方法名
function Adapter.mcall(obj, name, ...)
    if obj == nil then return nil end
    local fn = obj[name]
    if fn == nil then return nil end

    if method_conv == "dot" then
        return fn(...)
    elseif method_conv == "colon" then
        return fn(obj, ...)
    end

    -- 未探测：先试点式，失败再试冒号式
    local ok, result = pcall(fn, ...)
    if ok then
        method_conv = "dot"
        return result
    end
    method_conv = "colon"
    return fn(obj, ...)
end

-- ==================== 向量 / 数学 ====================

--- 构造三维向量（引擎注入 math.Vector3）
function Adapter.vec(x, y, z)
    return math.Vector3(x, y, z)
end

--- 构造四元数（引擎注入 math.Quaternion）
function Adapter.quat(x, y, z)
    return math.Quaternion(x or 0, y or 0, z or 0)
end

--- 两点距离；任一点无效返回极大值，调用方自然跳过
function Adapter.dist(a, b)
    if a == nil or b == nil then return math.huge end
    local ok, d = pcall(function() return (a - b):length() end)
    if ok and d then return d end
    return math.huge
end

--- 向量加法（用于重生抬高）
function Adapter.offset(pos, dx, dy, dz)
    if pos == nil then return nil end
    local ok, v = pcall(function() return pos + Adapter.vec(dx, dy, dz) end)
    if ok then return v end
    return pos
end

-- ==================== 单位查询 / 读写 ====================

--- 按名称查单位（带缓存，避免每帧调用 query_unit）
local unit_cache = {}
function Adapter.find_unit(name)
    if name == nil then return nil end
    if unit_cache[name] ~= nil then return unit_cache[name] or nil end

    local unit = nil
    local ok1, u1 = pcall(function() return LuaAPI.query_unit(name) end)
    if ok1 and u1 then
        unit = u1
    else
        -- 备用路径：名称 → ID → 对象
        local ok2, id = pcall(function() return GameAPI.get_unit_id_by_name(name) end)
        if ok2 and id then
            local ok3, u2 = pcall(function() return GameAPI.get_unit(id) end)
            if ok3 and u2 then unit = u2 end
        end
    end

    unit_cache[name] = unit or false
    return unit
end

--- 清空单位缓存（换图/重开时用）
function Adapter.clear_unit_cache()
    unit_cache = {}
end

--- 读取单位坐标
function Adapter.get_pos(unit)
    if unit == nil then return nil end
    local ok, p = pcall(function() return Adapter.mcall(unit, "get_position") end)
    if ok then return p end
    return nil
end

--- 设置单位坐标（传送用）
function Adapter.set_pos(unit, pos)
    if unit == nil or pos == nil then return false end
    local ok = pcall(function() Adapter.mcall(unit, "set_position", pos) end)
    return ok
end

--- 施加瞬间力（第二阶段推球预留）
function Adapter.apply_force(unit, force)
    if unit == nil or force == nil then return false end
    local ok = pcall(function() Adapter.mcall(unit, "apply_force", force) end)
    return ok
end

--- 设置线速度（掉落重生 / 转场传送后清零惯性）
--- 对应引擎 API：Unit.set_linear_velocity(_vel)
function Adapter.set_linear_velocity(unit, vel)
    if unit == nil or vel == nil then return false end
    local ok = pcall(function() Adapter.mcall(unit, "set_linear_velocity", vel) end)
    return ok
end

--- 销毁单位
function Adapter.destroy_unit(unit)
    if unit == nil then return false end
    local ok = pcall(function() GameAPI.destroy_unit(unit) end)
    return ok
end

-- ==================== 玩家 ====================

--- 取全部有效玩家角色（返回数组，失败返回空表）
function Adapter.get_all_roles()
    local ok, roles = pcall(function() return GameAPI.get_all_valid_roles() end)
    if ok and roles then return roles end
    return {}
end

--- 玩家唯一 ID
function Adapter.role_id(role)
    if role == nil then return nil end
    local ok, id = pcall(function() return Adapter.mcall(role, "get_roleid") end)
    if ok then return id end
    return nil
end

--- 玩家操控的单位（蛋仔本体）
function Adapter.ctrl_unit(role)
    if role == nil then return nil end
    local ok, u = pcall(function() return Adapter.mcall(role, "get_ctrl_unit") end)
    if ok then return u end
    return nil
end

--- 玩家昵称（日志/结算用）
function Adapter.role_name(role)
    if role == nil then return "?" end
    local ok, n = pcall(function() return Adapter.mcall(role, "get_name") end)
    if ok and n then return n end
    return "?"
end

--- 读取引擎侧积分
function Adapter.get_score(role)
    if role == nil then return 0 end
    local ok, s = pcall(function() return Adapter.mcall(role, "get_score") end)
    if ok and s then return s end
    return 0
end

--- 写入引擎侧积分（同步积分板显示）
function Adapter.set_score(role, score)
    if role == nil then return end
    pcall(function() Adapter.mcall(role, "set_score", score) end)
end

--- 锁定/解锁玩家移动
function Adapter.lock_role(role, locked)
    if role == nil then return end
    pcall(function() Adapter.mcall(role, "set_role_ctrl_enabled", not locked) end)
end

-- ==================== 表现（不改变玩法状态） ====================

--- 玩家级飘字
function Adapter.tips(role, text, duration)
    if role then
        pcall(function() Adapter.mcall(role, "show_tips", text, duration or 2.0) end)
    else
        pcall(function() GlobalAPI.show_tips(text, duration or 2.0) end)
    end
end

--- 玩家级 UI 文本（节点由 Main 在初始化时解析并传入，避免运行时 query）
function Adapter.set_ui_text(role, node, text)
    if role == nil or node == nil then return end
    pcall(function() Adapter.mcall(role, "set_label_text", node, tostring(text)) end)
end

--- 玩家级 UI 显隐
function Adapter.set_ui_visible(role, node, visible)
    if role == nil or node == nil then return end
    pcall(function() Adapter.mcall(role, "set_node_visible", node, visible) end)
end

--- 解析 UI 节点（一次，运行时不要再调用）
function Adapter.query_ui_nodes(names)
    if names == nil or #names == 0 then return nil end
    local ok, nodes = pcall(function() return LuaAPI.query_ui_nodes(names) end)
    if ok then return nodes end
    warn_once("ui_nodes", "UI 节点解析失败，UI 刷新将被跳过")
    return nil
end

-- ==================== 定时 / 事件 ====================

--- 帧级延迟（30Hz 定步长驱动的核心）
---@param frames integer 延迟帧数
---@param cb function 回调
function Adapter.delay_frames(frames, cb)
    local ok = pcall(function() LuaAPI.call_delay_frame(frames, cb) end)
    if not ok then
        warn_once("delay_frame", "call_delay_frame 调用失败")
    end
end

--- 注册全局事件
function Adapter.on_global(event_desc, cb)
    local ok, id = pcall(function()
        return LuaAPI.global_register_trigger_event(event_desc, cb)
    end)
    if ok then return id end
    warn_once("global_event", "全局事件注册失败: " .. tostring(event_desc[1]))
    return nil
end

-- ==================== 确定性随机 ====================

--- 确定性随机整数 [min, max]；禁用 math.random
function Adapter.random_int(min_value, max_value)
    if min_value > max_value then min_value, max_value = max_value, min_value end
    local ok, v = pcall(function() return GameAPI.random_int(min_value, max_value) end)
    if ok and v then return v end
    local ok2, v2 = pcall(function() return GameAPI.randint(min_value, max_value) end)
    if ok2 and v2 then return v2 end
    -- 双路都不可用时退化为确定值（宁可不随机，也不能破坏锁步）
    warn_once("random", "确定性随机 API 不可用，降级返回下界")
    return min_value
end

-- ==================== 对局控制 ====================

--- 主动结束对局
function Adapter.game_end()
    pcall(function() GameAPI.game_end() end)
end

return Adapter
