-- 重构跑酷段：连续跑道 → 浮空跳跃台（7x1x7，间距 11 → 间隙 4）
local PAD = 100114          -- 简易舞台 7x1x7
local FLAT = 100059         -- 障碍物类，用于存档点/糖果/星星（需被 query_unit 检索）

local DEL = { "跑道_", "樱花糖果_", "冰晶星_" }

-- ============ 1. 删除旧的连续跑道与旧糖果星星 ============
local ids = EditorAPI.get_all_unit_ids()
local removed = 0
for i = 1, #ids do
    local uid = ids[i]
    local ok, nm = pcall(function() return EditorAPI.get_unit_name(uid) end)
    if ok and nm ~= nil then
        local s = tostring(nm)
        for _, p in ipairs(DEL) do
            if string.find(s, p, 1, true) then
                pcall(function() EditorAPI.destroy_obstacle(uid) end)
                removed = removed + 1
                break
            end
        end
    end
end

-- ============ 2. 建立 10 块浮空台 ============
local pads = {}
local created = 0
for i = 0, 9 do
    local z = -114 + i * 11
    local x = 3 * math.sin(i * 0.8)
    local ok, uid = pcall(function()
        return EditorAPI.create_obstacle(PAD, math.Vector3(x, -0.5, z))
    end)
    if ok and uid ~= nil then
        pcall(function() EditorAPI.set_unit_transform(uid, { x, -0.5, z }, { 0, 0, 0 }, { 1, 1, 1 }) end)
        pcall(function() EditorAPI.set_unit_attr(uid, "name", "跳台_" .. string.format("%02d", i + 1)) end)
        created = created + 1
    end
    pads[#pads + 1] = { x = x, z = z }
end

-- ============ 3. 存档点放到第 3/6/9 块台上 ============
local cp_idx = { 3, 6, 9 }
local cp_made = 0
for n = 1, 3 do
    local p = pads[cp_idx[n]]
    local ok, uid = pcall(function()
        return EditorAPI.create_obstacle(FLAT, math.Vector3(p.x, 0.06, p.z))
    end)
    if ok and uid ~= nil then
        pcall(function() EditorAPI.set_unit_transform(uid, { p.x, 0.06, p.z }, { 0, 0, 0 }, { 0.3, 0.03, 0.3 }) end)
        pcall(function() EditorAPI.set_unit_attr(uid, "name", "存档点_" .. string.format("%02d", n)) end)
        cp_made = cp_made + 1
    end
end

-- ============ 4. 出生点移到第 1 块台 ============
local all = EditorAPI.get_all_unit_ids()
local moved = 0
for i = 1, #all do
    local uid = all[i]
    local ok, nm = pcall(function() return EditorAPI.get_unit_name(uid) end)
    if ok and nm ~= nil then
        local s = tostring(nm)
        if string.find(s, "分阵营出生点", 1, true) or string.find(s, "蛋仔：试玩出生点", 1, true) then
            pcall(function()
                EditorAPI.set_unit_transform(uid, { pads[1].x, 2, pads[1].z }, { 0, 0, 0 }, { 1, 1, 1 })
            end)
            moved = moved + 1
        end
    end
end

-- ============ 5. 终点移到最后一台 ============
pcall(function()
    local last = pads[10]
    local uid = nil
    for i = 1, #all do
        local ok, nm = pcall(function() return EditorAPI.get_unit_name(all[i]) end)
        if ok and nm ~= nil and string.find(tostring(nm), "终点_胜利区域", 1, true) then uid = all[i] break end
    end
    if uid ~= nil then
        EditorAPI.set_unit_transform(uid, { last.x, 1.5, last.z }, { 0, 0, 0 }, { 1, 1, 1 })
    end
end)

return string.format("removed=%d pads=%d checkpoints=%d spawns_moved=%d | pad1=(%.1f,%.1f) pad10=(%.1f,%.1f)",
    removed, created, cp_made, moved, pads[1].x, pads[1].z, pads[10].x, pads[10].z)
