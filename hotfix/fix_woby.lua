-- 修复：大 Woby 变身时，周期任务指数级增殖
--
-- 原代码（wixie_postinit/prefabs/wobybig.lua 的 TriggerTransformation）：
--     inst:DoPeriodicTask(1, function(inst)
--         inst.transforming = false
--         TriggerTransformation(inst)          -- 回调里再调用自己
--     end)
-- 每次调用都会新建一条 1 秒周期任务，且旧任务从不 Cancel()，
-- 于是任务数量每个 tick 翻倍（1 -> 2 -> 4 -> ...），闭包和任务对象堆积。
--
-- 修复方式：不修改 UM 的源码，而是在实体上包一层 DoPeriodicTask，
-- 让同一时间最多只有一条「变身轮询」周期任务存活。
-- 只在实体身上出现过 inst.transforming 字段（UM 的标记）时启用此限制，
-- 以免影响原版 / 其他模组在 wobybig 上注册的其它周期任务。

local G = GLOBAL
local HF = G.UMHOTFIX

if not HF.flags.fix_woby_transform then
    HF.report("woby_transform", true, "配置已关闭")
    return
end

local function Apply(inst)
    if inst._umhotfix_woby_patched then
        return
    end
    inst._umhotfix_woby_patched = true

    local OriginalDoPeriodicTask = inst.DoPeriodicTask
    local transform_ticker = nil

    inst.DoPeriodicTask = function(self, time, fn, initialdelay, ...)
        local task = OriginalDoPeriodicTask(self, time, fn, initialdelay, ...)

        -- 只针对 UM 的「1 秒变身轮询」：它出现时 inst.transforming 字段已被创建
        if time == 1 and fn ~= nil and G.rawget(self, "transforming") ~= nil then
            if transform_ticker ~= nil and transform_ticker ~= task then
                transform_ticker:Cancel()
            end
            transform_ticker = task
            HF.debug_log("wobybig: 替换旧的变身轮询任务，保持单例")
        end
        return task
    end

    inst:ListenForEvent("onremove", function()
        if transform_ticker ~= nil then
            transform_ticker:Cancel()
            transform_ticker = nil
        end
    end)
end

AddPrefabPostInit("wobybig", function(inst)
    if not HF.is_master() then
        return
    end
    -- 本模组后加载，这里的 postinit 排在 UM 的 postinit 之后执行，
    -- 因此能包住 UM 之后注册的 DoPeriodicTask。
    HF.try("woby_transform", Apply, inst)
end)
