-- 幂等补齐：糖果 40 + 冰晶星 10（按跳台位置对齐）
local FLAT = 100059
local pads = {}
for i = 0, 9 do
    pads[#pads + 1] = { x = 3 * math.sin(i * 0.8), z = -114 + i * 11 }
end

local ids = EditorAPI.get_all_unit_ids()
local have = {}
for i = 1, #ids do
    local ok, nm = pcall(function() return EditorAPI.get_unit_name(ids[i]) end)
    if ok and nm ~= nil then have[tostring(nm)] = true end
end

local created, failed = 0, 0

local function put(x, y, z, name, sx, sy, sz)
    if have[name] then return end
    local ok, uid = pcall(function()
        return EditorAPI.create_obstacle(FLAT, math.Vector3(x, y, z))
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

local offs = { { -2.2, -2.2 }, { 2.2, -2.2 }, { -2.2, 2.2 }, { 2.2, 2.2 } }
local n = 0
for i = 1, 10 do
    local p = pads[i]
    for _, o in ipairs(offs) do
        n = n + 1
        put(p.x + o[1], 1.2, p.z + o[2], "樱花糖果_" .. string.format("%02d", n), 0.3, 0.3, 0.3)
    end
end

for i = 1, 10 do
    local p = pads[i]
    put(p.x, 3.0, p.z, "冰晶星_" .. string.format("%02d", i), 0.2, 0.4, 0.2)
end

return "created=" .. created .. " failed=" .. failed
