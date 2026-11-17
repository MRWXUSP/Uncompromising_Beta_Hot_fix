-- 修复：幽灵推击 / 击退产生的 um_shoveentity 孤儿实体泄漏
--
-- 2026-11 更新新增了 ghost push（init/init_ghostpowers.lua）和
-- scripts/tools/um_shoveutility.lua：
--   * DoRepel 会生成一个不可见的 um_shoveentity，用它约束被推的目标；
--   * 正常结束时 UpdateRepel 通过 RemoveShoveEntity(child) 删除它；
--   * 但如果目标在击退结束前被移除 / 死亡，child 无效，UpdateRepel 只取消
--     自己的周期任务，不会删除 um_shoveentity；
--   * um_shoveentity 的 prefab 又设置了 SetDontRemoveOnSleep(true) 且
--     persists = false，于是它会作为隐形实体留在当前会话里，越积越多。
--
-- 这里用一个世界级周期清理（不依赖实体自身的任务，避免实体睡眠后任务暂停）
-- 回收所有失去目标或目标已失效的 um_shoveentity。

local G = GLOBAL
local HF = G.UMHOTFIX

if not HF.flags.fix_shove_entity_leak then
    HF.report("shove_entity_leak", true, "配置已关闭")
    return
end

HF.shove_entities = G.setmetatable({}, { __mode = "k" })

local function Sweep()
    for inst in G.pairs(HF.shove_entities) do
        if not inst:IsValid() then
            HF.shove_entities[inst] = nil
        else
            local child = inst.um_child
            if child == nil or not child:IsValid() then
                HF.debug_log("shove_entity: 清理失去目标的击退实体")
                HF.shove_entities[inst] = nil
                inst:Remove()
            end
        end
    end
end

-- 暴露给离线测试使用；游戏内不会主动调用
HF.shove_sweep = Sweep

local function Track(inst)
    if inst._umhotfix_shove_tracked then
        return
    end
    inst._umhotfix_shove_tracked = true
    HF.shove_entities[inst] = true
    inst:ListenForEvent("onremove", function(inst)
        HF.shove_entities[inst] = nil
    end)
end

AddPrefabPostInit("um_shoveentity", function(inst)
    if not HF.is_master() then
        return
    end
    Track(inst)
end)

AddGamePostInit(function()
    if not HF.is_master() then
        return
    end

    G.TheWorld:DoPeriodicTask(2, Sweep)
    HF.report("shove_entity_leak", true, "世界级清理任务已启动")
end)
