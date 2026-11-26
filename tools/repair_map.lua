-- 只补缺失（幂等修复）
local KEY = 100059

local function name_set()
    local s = {}
    local ids = EditorAPI.get_all_unit_ids()
    if ids == nil then return s end
    for i = 1, #ids do
        local ok, nm = pcall(function() return EditorAPI.get_unit_name(ids[i]) end)
        if ok and nm ~= nil then s[tostring(nm)] = true end
    end
    return s
end

local have = name_set()
local created, failed = 0, 0

local function need(x, y, z, name, sx, sy, sz)
    if have[name] then return end
    local ok, uid = pcall(function()
        return EditorAPI.create_obstacle(KEY, math.Vector3(x, y, z))
    end)
    if not ok or uid == nil then
        failed = failed + 1
        return
    end
    pcall(function() EditorAPI.set_unit_transform(uid, { x, y, z }, { 0, 0, 0 }, { sx, sy, sz }) end)
    pcall(function() EditorAPI.set_unit_attr(uid, "name", name) end)
    have[name] = true
    created = created + 1
end

for i = 0, 8 do
    need(0, -0.5, -7 - 14 * i, "跑道_" .. string.format("%02d", i + 1), 4, 0.25, 4)
end
need(0, -0.5, 60, "竞技台地面", 12, 0.25, 12)
for i = 1, 3 do
    need(0, 0.06, -30 - 37 * (i - 1), "存档点_" .. string.format("%02d", i), 0.3, 0.03, 0.3)
end
for i = 1, 40 do
    need((i % 2 == 1) and -3.2 or 3.2, 1.2, -116 + (i - 1) * 2.85,
        "樱花糖果_" .. string.format("%02d", i), 0.3, 0.3, 0.3)
end
for i = 1, 10 do
    need((i % 2 == 1) and 4.6 or -4.6, 3.0, -110 + (i - 1) * 11,
        "冰晶星_" .. string.format("%02d", i), 0.2, 0.4, 0.2)
end
for n = 0, 7 do
    local a = math.deg_to_rad(22.5 + n * 45)
    need(17 * math.sin(a), 0.06, 60 + 17 * math.cos(a),
        "传送点_" .. string.format("%02d", n + 1), 0.3, 0.03, 0.3)
end
local holes = { { 0, 79 }, { 19, 60 }, { 0, 41 }, { -19, 60 } }
for i, h in ipairs(holes) do
    need(h[1], 0.06, h[2], "球洞_" .. string.format("%02d", i), 0.4, 0.03, 0.4)
end
local spawns = {}
for n = 0, 3 do
    local a = math.deg_to_rad(45 + n * 90)
    local x, z = 8 * math.sin(a), 60 + 8 * math.cos(a)
    spawns[#spawns + 1] = { x, z }
    need(x, 0.06, z, "球刷新点_" .. string.format("%02d", n + 1), 0.3, 0.03, 0.3)
end
for n = 1, 4 do
    need(spawns[n][1], 1.6, spawns[n][2], "糖果球_" .. string.format("%02d", n), 0.7, 0.7, 0.7)
end
need(-3, 2.4, 60, "冰晶大球_01", 1.4, 1.4, 1.4)
need(3, 2.4, 60, "冰晶大球_02", 1.4, 1.4, 1.4)
need(0, 1.5, -2, "终点_胜利区域", 0.5, 0.5, 0.5)

return "created=" .. created .. " failed=" .. failed
