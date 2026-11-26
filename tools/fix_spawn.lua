-- 修正出生点/终点方向：出生点在跑道远端，终点在近端
local ids = EditorAPI.get_all_unit_ids()
local byname = {}
for i = 1, #ids do
    local uid = ids[i]
    local ok, nm = pcall(function() return EditorAPI.get_unit_name(uid) end)
    if ok and nm ~= nil then byname[tostring(nm)] = uid end
end

local function move(name, x, y, z)
    local uid = byname[name]
    if uid == nil then return name .. "=MISSING" end
    pcall(function() EditorAPI.set_unit_transform(uid, { x, y, z }, { 0, 0, 0 }, { 1, 1, 1 }) end)
    return name .. "@(" .. x .. "," .. y .. "," .. z .. ")"
end

local out = {}
out[#out + 1] = move("蛋仔：试玩出生点", 0, 2, -116)
out[#out + 1] = move("分阵营出生点1", 0, 2, -116)
out[#out + 1] = move("终点_胜利区域", 0, 1.5, -2)

return table.concat(out, " | ")
