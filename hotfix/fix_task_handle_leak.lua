-- 修复：任务句柄 / 引用表只增不减造成的缓慢泄漏
--
-- 1) scripts/prefabs/um_ocupus.lua
--    - surfacetents / regulartents / undertents 只 table.insert，从不清理；
--      RemoveAllTentacles 只对每个触手调 Leave()，失效引用永远留在表里。
--    - inst.boatcheck = inst:DoPeriodicTask(1, BoatCheck) 覆盖旧句柄，
--      旧周期任务无人取消；重复交手时会出现多个 BoatCheck 同时运行，
--      其中一条 Cancel 时句柄已被置 nil，直接报错。
--
-- 2) init/init_gemology/misc.lua（monkey）
--    inst.geode_search_task = inst:DoPeriodicTask(3, SearchForGeodes)
--    entitywake 重复触发时旧任务句柄被覆盖，旧周期任务永远在跑。

local G = GLOBAL
local HF = G.UMHOTFIX

if not HF.flags.fix_task_handle_leak then
    HF.report("task_handle_leak", true, "配置已关闭")
    return
end

--------------------------------------------------------------------------------
-- 1) Ocupus
--------------------------------------------------------------------------------

local function CleanList(list)
    if G.type(list) ~= "table" then
        return
    end
    for i = #list, 1, -1 do
        local v = list[i]
        if v == nil or not v:IsValid() then
            G.table.remove(list, i)
        end
    end
end

local function PatchOcupus(inst)
    if inst._umhotfix_ocupus then
        return
    end
    inst._umhotfix_ocupus = true

    -- 周期清理失效的触手引用（每 5 秒一次，开销极小）
    inst:DoPeriodicTask(5, function(inst)
        CleanList(inst.surfacetents)
        CleanList(inst.regulartents)
        CleanList(inst.undertents)
    end, 5)

    -- boatcheck 单例：每次创建 1 秒周期任务时取消上一条
    local OriginalDoPeriodicTask = inst.DoPeriodicTask
    local boatcheck = nil
    inst.DoPeriodicTask = function(self, time, fn, initialdelay, ...)
        local task = OriginalDoPeriodicTask(self, time, fn, initialdelay, ...)
        if time == 1 and fn ~= nil then
            if boatcheck ~= nil and boatcheck ~= task then
                boatcheck:Cancel()
            end
            boatcheck = task
            inst.boatcheck = task
        end
        return task
    end

    -- 实体移除时清空引用表，避免闭包/表继续持有已删除实体
    inst:ListenForEvent("onremove", function()
        inst.surfacetents = nil
        inst.regulartents = nil
        inst.undertents = nil
        if boatcheck ~= nil then
            boatcheck:Cancel()
            boatcheck = nil
        end
    end)

    HF.report("task_handle_leak.ocupus", true)
end

AddPrefabPostInit("um_ocupus", function(inst)
    if not HF.is_master() then
        return
    end
    HF.try("task_handle_leak.ocupus", PatchOcupus, inst)
end)

--------------------------------------------------------------------------------
-- 2) 猴子寻石芽周期任务
--------------------------------------------------------------------------------

local function PatchMonkey(inst)
    if inst._umhotfix_monkey then
        return
    end
    inst._umhotfix_monkey = true

    local OriginalDoPeriodicTask = inst.DoPeriodicTask
    inst.DoPeriodicTask = function(self, time, fn, initialdelay, ...)
        -- UM 的 SearchForGeodes 周期为 3 秒：先清掉旧句柄再建新的
        if time == 3 and inst.geode_search_task ~= nil then
            inst.geode_search_task:Cancel()
            inst.geode_search_task = nil
        end
        local task = OriginalDoPeriodicTask(self, time, fn, initialdelay, ...)
        if time == 3 then
            inst.geode_search_task = task
        end
        return task
    end

    HF.report("task_handle_leak.monkey", true)
end

AddPrefabPostInit("monkey", function(inst)
    if not HF.is_master() then
        return
    end
    HF.try("task_handle_leak.monkey", PatchMonkey, inst)
end)
