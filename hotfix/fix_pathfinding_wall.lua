-- 修复：UMAddPathfindingWalls 在实体已被移除后仍写入寻路墙
--
-- 2026-11 更新把各 prefab 里分散的 RegisterPathFinding / UnregisterPathFinding
-- 合并成了全局的 UMAddPathfindingWalls（init/init_util.lua）。新实现会在
-- 实体上注册 "onremove" 清理，但很多调用点是：
--     inst:DoTaskInTime(0, UMAddPathfindingWalls)
-- 如果实体在 0 延迟任务执行前就被移除（例如 giant_tree 生成后 0~0.1 秒内
-- 因“间距过近”被 Remove），回调仍会在已移除的实体上执行：
--     * TheWorld.Pathfinder:AddWall(...) 照样写入寻路墙；
--     * 此时 "onremove" 已经触发过，新注册的清理回调永远不会执行；
-- 结果是在地图上留下永久不可通行的寻路墙。
--
-- 这里包装全局函数：实体已失效时直接跳过，不再写墙。

local G = GLOBAL
local HF = G.UMHOTFIX

if not HF.flags.fix_pathfinding_wall_leak then
    HF.report("pathfinding_wall_leak", true, "配置已关闭")
    return
end

local function Install()
    local add = G.UMAddPathfindingWalls
    if G.type(add) ~= "function" then
        HF.report("pathfinding_wall_leak", true, "当前版本没有 UMAddPathfindingWalls（无需处理）")
        return
    end

    if HF.pathfinding_wrapped then
        HF.report("pathfinding_wall_leak", true)
        return
    end

    local function SafeAdd(inst, radius)
        if inst == nil or not inst:IsValid() then
            HF.debug_log("pathfinding: 跳过已移除实体的寻路墙注册")
            return
        end
        return add(inst, radius)
    end

    HF.pathfinding_wrapped = true
    G.UMAddPathfindingWalls = SafeAdd
    HF.report("pathfinding_wall_leak", true, "已加失效实体检查")
end

if G.type(G.UMAddPathfindingWalls) == "function" then
    HF.try("pathfinding_wall_leak", Install)
else
    -- UM 的 init_util 理论上先于本模组加载；如果时序不同，等游戏初始化再包装
    AddGamePostInit(function()
        if HF.is_master() then
            HF.try("pathfinding_wall_leak", Install)
        end
    end)
end
