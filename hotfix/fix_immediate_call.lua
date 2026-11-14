-- 修复：定时器参数被立即求值（同步无限递归 / nil 回调）
--
-- 1) postinit/components/uncompromising_shadowfollower.lua
--        self.porttask = inst:DoTaskInTime(0, self:DoPortNeartarget(target_pos))
--    DoPortNeartarget 被立即执行（作者注释里都写了这样会崩），
--    并且 porttask 拿到 nil，防重入失效，每秒重复尝试传送。
--
-- 2) postinit/prefabs/ruinsstatues.lua
--        inst:DoTaskInTime(0.1, SpawnSpawner(inst))
--    立即求值成了同步递归；在虚空包围的遗迹里会栈溢出。
--
-- 3) scripts/um_preparedfoods.lua / stuffed_peeper_poppers
--        inst:DoTaskInTime(0, SpawnEyes(inst, eater))   -- 回调为 nil
--    延迟任务收到 nil 回调，会在到期时报错。
--
-- 4) scripts/prefabs/rnelevitator.lua
--        v:DoTaskInTime(0.5, Perterbate(v))
--    夜间立即无限自递归（当前版本该 prefab 未被生成，属潜伏修复）。

local G = GLOBAL
local HF = G.UMHOTFIX

if not HF.flags.fix_immediate_call then
    HF.report("immediate_call", true, "配置已关闭")
    return
end

--------------------------------------------------------------------------------
-- 1) 暗影跟随者
--------------------------------------------------------------------------------

local function FixedDoPortCheck(inst)
    local self = inst.components.uncompromising_shadowfollower
    if self == nil then
        return
    end

    if self.porttask ~= nil then
        self.porttask:Cancel()
        self.porttask = nil
    end

    local combat = inst.components.combat
    if combat ~= nil and combat:HasTarget() then
        local c_target = combat.target
        if c_target ~= nil and self.target ~= c_target then
            self:SetTarget(c_target)
        end
    end

    if self.target == nil or self.target:IsAsleep() then
        return
    end

    if inst.sg ~= nil and (inst.sg:HasStateTag("attack") or inst.sg:HasStateTag("busy")) then
        return
    end

    local init_pos = inst:GetPosition()
    local target_pos = self.target:GetPosition()
    local max_dist = 32
    if G.TUNING.DSTU ~= nil and G.TUNING.DSTU.MAX_DISTANCE_TO_SHADOWS ~= nil then
        max_dist = G.TUNING.DSTU.MAX_DISTANCE_TO_SHADOWS
    end

    if G.distsq(target_pos, init_pos) > max_dist then
        local angle = self.target:GetAngleToPoint(init_pos) + 180 + G.math.random(-30, 30)
        local offset = G.FindWalkableOffset(target_pos, angle * G.DEGREES, 32, 5, false, true, nil, true, true)
        if offset ~= nil then
            target_pos.x = target_pos.x + offset.x
            target_pos.z = target_pos.z + offset.z
        end
        target_pos.y = 0

        if inst.prefab == "dreadeye" and inst.oncooldown == nil and not inst.isdisguised and
            inst.components.health ~= nil and not inst.components.health:IsDead() and
            (combat == nil or not combat:HasTarget()) then
            inst:TryDisguise(inst, self.target)
        else
            -- 关键：真正延迟执行，并保存任务句柄
            self.porttask = inst:DoTaskInTime(0, function()
                self:DoPortNeartarget(target_pos)
            end)
        end
    end
end

local function PatchShadowFollower(self)
    if self.inst == nil then
        return
    end

    local replaced = false
    local start_leashing = self.StartLeashing
    if G.type(start_leashing) == "function" then
        -- 替换共享 upvalue，后续 StartLeashing 注册的监听也会用修复版
        replaced = HF.replace_upvalue(start_leashing, "DoPortCheck", FixedDoPortCheck)
    end

    -- 构造函数已经用旧函数注册了一条周期任务，先取消再换成修复版
    if self.porttask2 ~= nil then
        self.porttask2:Cancel()
        self.porttask2 = nil
    end
    self.porttask2 = self.inst:DoPeriodicTask(1, FixedDoPortCheck)

    if replaced then
        HF.report("immediate.shadowfollower", true)
    else
        HF.report("immediate.shadowfollower", false, "未找到 DoPortCheck upvalue（已仅重建周期任务）")
    end
end

AddComponentPostInit("uncompromising_shadowfollower", function(self)
    if not HF.is_master() then
        return
    end
    HF.try("immediate.shadowfollower", PatchShadowFollower, self)
end)

--------------------------------------------------------------------------------
-- 2) 遗迹雕像：提前把 trepidation spawner 放好，避免 UM 走进同步递归
--------------------------------------------------------------------------------

local STATUE_PREFABS =
{
    "ruins_statue_head",
    "ruins_statue_head_nogem",
    "ruins_statue_mage",
    "ruins_statue_mage_nogem",
}

local function EnsureTrepidationSpawner(inst)
    if inst._umhotfix_trepidation then
        return
    end
    inst._umhotfix_trepidation = true

    local pt = inst:GetPosition()
    local spawners = G.TheSim:FindEntities(pt.x, pt.y, pt.z, 100, { "trepidationspawner" })
    if #spawners > 0 then
        return
    end

    -- 在雕像 ±10 内找一个可站立点；找不到就放在雕像脚下当作兜底
    local x, z = pt.x, pt.z
    for _ = 1, 20 do
        local px = pt.x + G.math.random(-10, 10)
        local pz = pt.z + G.math.random(-10, 10)
        if G.TheWorld.Map:IsAboveGroundAtPoint(px, 0, pz) then
            x, z = px, pz
            break
        end
    end

    local anchor = G.SpawnPrefab("ancient_trepidation_anchor")
    if anchor ~= nil then
        anchor.Transform:SetPosition(x, 0, z)
    end
    HF.report("immediate.ruinsstatues", true)
end

for _, prefab in G.ipairs(STATUE_PREFABS) do
    AddPrefabPostInit(prefab, function(inst)
        if not HF.is_master() then
            return
        end
        HF.try("immediate.ruinsstatues", EnsureTrepidationSpawner, inst)
    end)
end

--------------------------------------------------------------------------------
-- 3) 爆爆椒：拦截 nil 回调任务，避免每颗都报一次错
--------------------------------------------------------------------------------

local function GuardNilTask(inst)
    if inst._umhotfix_nil_task then
        return
    end
    inst._umhotfix_nil_task = true

    local OriginalDoTaskInTime = inst.DoTaskInTime
    inst.DoTaskInTime = function(self, time, fn, ...)
        if fn == nil then
            HF.debug_log("stuffed_peeper_poppers: 拦截 nil 回调任务")
            return nil
        end
        return OriginalDoTaskInTime(self, time, fn, ...)
    end
    HF.report("immediate.peeper", true)
end

AddPrefabPostInit("stuffed_peeper_poppers", function(inst)
    if not HF.is_master() then
        return
    end
    HF.try("immediate.peeper", GuardNilTask, inst)
end)

--------------------------------------------------------------------------------
-- 4) rnelevitator（当前版本未生成，仅做潜伏修复）
--------------------------------------------------------------------------------

local function FixedPerterbate(v)
    if v == nil or not v:IsValid() then
        return
    end
    if v.Physics ~= nil then
        v.Physics:SetMotorVel(0, 1 + G.math.random(-0.5, 0.5), 0)
    end
    if G.TheWorld.state.isnight then
        v:DoTaskInTime(0.5, FixedPerterbate)
    end
end

local function FixedLevitato(v)
    if v == nil or not v:IsValid() or v.Physics == nil then
        return
    end
    v.Physics:SetMotorVel(0, 4, 0)
    v:DoTaskInTime(15 + G.math.random(1, 3), FixedPerterbate)
end

local rnelevitator_patched = false

local function TryPatchRnelevitator()
    if rnelevitator_patched then
        return
    end
    local fn = HF.prefab_fn("rnelevitator")
    if fn == nil then
        return
    end
    local do_levip = HF.descend(fn, "DoLevipotato")
    if G.type(do_levip) ~= "function" then
        return
    end

    local ok = false
    local original_levitato = HF.descend(do_levip, "Levitato")
    if G.type(original_levitato) == "function" then
        ok = HF.replace_upvalue(original_levitato, "Perterbate", FixedPerterbate) or ok
    end
    ok = HF.replace_upvalue(do_levip, "Levitato", FixedLevitato) or ok

    if ok then
        rnelevitator_patched = true
        HF.report("immediate.rnelevitator", true)
    else
        HF.report("immediate.rnelevitator", false, "未找到 Levitato / Perterbate upvalue")
    end
end

-- 在 prefab 注册完成后的第一时间修补（GamePostInit 或首个实体创建时）
AddGamePostInit(TryPatchRnelevitator)
AddPrefabPostInitAny(function()
    if not rnelevitator_patched then
        TryPatchRnelevitator()
    end
end)
