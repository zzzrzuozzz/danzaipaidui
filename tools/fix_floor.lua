-- 修地面：改用原生 14x1x14 的迪厅舞池(100174)，不依赖缩放；间距 12 保证重叠无缝
local FLOOR = 100174
local REMOVE = { "跑道_", "竞技台地面" }

local ids = EditorAPI.get_all_unit_ids()
local removed = 0
for i = 1, #ids do
    local uid = ids[i]
    local ok, nm = pcall(function() return EditorAPI.get_unit_name(uid) end)
    if ok and nm ~= nil then
        local s = tostring(nm)
        for _, p in ipairs(REMOVE) do
            if string.find(s, p, 1, true) then
                pcall(function() EditorAPI.destroy_obstacle(uid) end)
                removed = removed + 1
                break
            end
        end
    end
end

local made = 0
local function tile(x, y, z)
    local ok, uid = pcall(function()
        return EditorAPI.create_obstacle(FLOOR, math.Vector3(x, y, z))
    end)
    if ok and uid ~= nil then
        pcall(function() EditorAPI.set_unit_transform(uid, { x, y, z }, { 0, 0, 0 }, { 1, 1, 1 }) end)
        made = made + 1
    end
end

-- 跑道：10 块，z 从 -6 到 -114，间距 12（相邻重叠 2）
for i = 0, 9 do
    tile(0, -0.5, -6 - 12 * i)
end

-- 竞技台：4x4 网格，中心 (0,60)，覆盖 x/z 约 ±25
for ix = -1, 2 do
    for iz = -1, 2 do
        tile(ix * 12 + 6 - 6, -0.5, 60 + iz * 12)
    end
end

return "removed=" .. removed .. " tiles_created=" .. made
