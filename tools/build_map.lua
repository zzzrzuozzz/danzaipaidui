-- 樱花冰晶 · 地图重建 v3（彻底清理 + 单一障碍物预制体）
-- 结论：LuaAPI.query_unit 只检索障碍物类组件 → 所有契约组件统一用 100059
local KEY = 100059
local PREFIXES = {
    "跑道_", "竞技台地面", "存档点_", "樱花糖果_", "冰晶星_",
    "传送点_", "球洞_", "球刷新点_", "糖果球_", "冰晶大球_", "终点_胜利区域",
}

-- ==================== 1. 保护真正的胜利区域 ====================
local ids = EditorAPI.get_all_unit_ids()
for i = 1, #ids do
    local uid = ids[i]
    local ok, nm = pcall(function() return EditorAPI.get_unit_name(uid) end)
    if ok and nm ~= nil then
        local s = tostring(nm)
        if string.find(s, "终点_胜利区域", 1, true) or string.find(s, "终点胜利000", 1, true) then
            pcall(function() EditorAPI.set_unit_attr(uid, "name", "胜利区域_保留") end)
        end
    end
end

-- ==================== 2. 清理所有契约组件 ====================
ids = EditorAPI.get_all_unit_ids()
local deleted = 0
for i = 1, #ids do
    local uid = ids[i]
    local ok, nm = pcall(function() return EditorAPI.get_unit_name(uid) end)
    if ok and nm ~= nil then
        local s = tostring(nm)
        for _, p in ipairs(PREFIXES) do
            if string.find(s, p, 1, true) then
                pcall(function() EditorAPI.destroy_obstacle(uid) end)
                deleted = deleted + 1
                break
            end
        end
    end
end

-- ==================== 3. 重建 ====================
local created, failed = 0, 0

local function place(x, y, z, name, sx, sy, sz)
    local ok, uid = pcall(function()
        return EditorAPI.create_obstacle(KEY, math.Vector3(x, y, z))
    end)
    if not ok or uid == nil then
        failed = failed + 1
        return nil
    end
    pcall(function() EditorAPI.set_unit_transform(uid, { x, y, z }, { 0, 0, 0 }, { sx, sy, sz }) end)
    pcall(function() EditorAPI.set_unit_attr(uid, "name", name) end)
    created = created + 1
    return uid
end

for i = 0, 8 do
    place(0, -0.5, -7 - 14 * i, "跑道_" .. string.format("%02d", i + 1), 4, 0.25, 4)
end
place(0, -0.5, 60, "竞技台地面", 12, 0.25, 12)

for i = 1, 3 do
    place(0, 0.06, -30 - 37 * (i - 1), "存档点_" .. string.format("%02d", i), 0.3, 0.03, 0.3)
end
for i = 1, 40 do
    place((i % 2 == 1) and -3.2 or 3.2, 1.2, -116 + (i - 1) * 2.85,
        "樱花糖果_" .. string.format("%02d", i), 0.3, 0.3, 0.3)
end
for i = 1, 10 do
    place((i % 2 == 1) and 4.6 or -4.6, 3.0, -110 + (i - 1) * 11,
        "冰晶星_" .. string.format("%02d", i), 0.2, 0.4, 0.2)
end
for n = 0, 7 do
    local a = math.deg_to_rad(22.5 + n * 45)
    place(17 * math.sin(a), 0.06, 60 + 17 * math.cos(a),
        "传送点_" .. string.format("%02d", n + 1), 0.3, 0.03, 0.3)
end

local holes = { { 0, 79 }, { 19, 60 }, { 0, 41 }, { -19, 60 } }
for i, h in ipairs(holes) do
    place(h[1], 0.06, h[2], "球洞_" .. string.format("%02d", i), 0.4, 0.03, 0.4)
end

local spawns = {}
for n = 0, 3 do
    local a = math.deg_to_rad(45 + n * 90)
    local x, z = 8 * math.sin(a), 60 + 8 * math.cos(a)
    spawns[#spawns + 1] = { x, z }
    place(x, 0.06, z, "球刷新点_" .. string.format("%02d", n + 1), 0.3, 0.03, 0.3)
end
for n = 1, 4 do
    place(spawns[n][1], 1.6, spawns[n][2], "糖果球_" .. string.format("%02d", n), 0.7, 0.7, 0.7)
end
place(-3, 2.4, 60, "冰晶大球_01", 1.4, 1.4, 1.4)
place(3, 2.4, 60, "冰晶大球_02", 1.4, 1.4, 1.4)

-- 终点占位（障碍物类，可被 query_unit 找到）
place(0, 1.5, -2, "终点_胜利区域", 0.5, 0.5, 0.5)

-- ==================== 4. 校验 ====================
local check = EditorAPI.get_all_unit_ids()
local c = {}
for i = 1, #check do
    local uid = check[i]
    local ok, nm = pcall(function() return EditorAPI.get_unit_name(uid) end)
    if ok and nm ~= nil then
        local s = tostring(nm)
        local m = {
            { "樱花糖果_", "candy" }, { "传送点_", "tp" }, { "球洞_", "hole" },
            { "球刷新点_", "spawn" }, { "存档点_", "cp" }, { "糖果球_", "ball" },
            { "冰晶大球_", "big" }, { "冰晶星_", "star" }, { "终点_胜利区域", "finish" },
        }
        for _, e in ipairs(m) do
            if string.find(s, e[1], 1, true) then c[e[2]] = (c[e[2]] or 0) + 1 break end
        end
    end
end

return string.format(
    "deleted=%d created=%d failed=%d | total=%d | candy=%d star=%d cp=%d tp=%d hole=%d spawn=%d ball=%d big=%d finish=%d",
    deleted, created, failed, #check,
    c.candy or 0, c.star or 0, c.cp or 0, c.tp or 0,
    c.hole or 0, c.spawn or 0, c.ball or 0, c.big or 0, c.finish or 0)
