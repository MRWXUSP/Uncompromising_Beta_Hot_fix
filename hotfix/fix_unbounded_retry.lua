-- 修复：随机点重试递归没有上限（栈溢出 / 世界生成卡死）
--
-- 涉及：
--   prefabs/widowwebspawner.lua     TrySpawnCocoon / TrySpawnDecor
--   prefabs/riceplantspawner.lua    CheckPoint
--   prefabs/nymph.lua               FindSmallOffset（当前版本未注册该 prefab）
--   components/um_pestilencecontroller.lua  FindSmallOffset（当前版本未挂载）
--   prefabs/moonmaw_dragonfly.lua   TryEjectLavae
--   prefabs/viperfruit.lua          SpawnFriend
--
-- 这些函数都在「找不到合法落点」时直接 return 自己，没有次数上限。
-- 修复方式：用有限次循环 / 带次数的实现替换模块级局部函数
-- （通过 upvalue 替换，同一个闭包 cell 被所有调用者共享）。

local G = GLOBAL
local HF = G.UMHOTFIX

if not HF.flags.fix_unbounded_retry then
    HF.report("unbounded_retry", true, "配置已关闭")
    return
end

local function ReportFail(key, what)
    HF.report(key, false, "未找到 " .. what)
end

-- 记录已经替换过的函数，避免每次生成实体都重复包装
local PATCHED = G.setmetatable({}, { __mode = "k" })

--------------------------------------------------------------------------------
-- widowwebspawner
--------------------------------------------------------------------------------

local function FixedTrySpawnCocoon(x, z, ctype)
    local util = G.UMWebbedCreatureUtil
    if ctype ~= nil then
        ctype = G.string.upper(ctype)
    end
    if ctype == nil then
        if util == nil then
            return
        end
        if G.math.random() > .95 then
            ctype = util.COCOON_CHARACTERS[G.math.random(#util.COCOON_CHARACTERS)]
        elseif G.IsIslandWorld ~= nil and G.IsIslandWorld() then
            ctype = util.COCOON_CREATURES_SHIPWRECKED[G.math.random(#util.COCOON_CREATURES_SHIPWRECKED)]
        else
            ctype = util.COCOON_CREATURES_DEFAULT[G.math.random(#util.COCOON_CREATURES_DEFAULT)]
        end
    end

    local sim = G.TheSim
    for _ = 1, 10 do
        local xi = x + G.math.random(-8, 8)
        local zi = z + G.math.random(-8, 8)
        if #sim:FindEntities(xi, 0, zi, 1.5, { "webbedcreature" }) == 0 and
            #sim:FindEntities(xi, 0, zi, 3, { "webbedcreature" }) < 2 and
            #sim:FindEntities(xi, 0, zi, 8, { "webbedcreature" }) < 6 then
            local cocoon = G.SpawnPrefab("webbedcreature")
            if cocoon ~= nil then
                cocoon.Transform:SetPosition(xi, 0, zi)
                if ctype ~= nil then
                    cocoon.cocoon_creature = ctype
                    cocoon.cocoon_data = util.COCOON_DEFS.DEFAULT[ctype]
                else
                    cocoon:Remove()
                end
            end
            return
        end
    end
    -- 10 次都失败：放弃，不再递归
end

local function FixedTrySpawnDecor(x, z, ctype)
    local sim = G.TheSim
    for _ = 1, 12 do
        local xi = x + G.math.random(-12, 12)
        local zi = z + G.math.random(-12, 12)
        if #sim:FindEntities(xi, 0, zi, 1.5, { "webbedcreature", "webdecor" }) == 0 and
            #sim:FindEntities(xi, 0, zi, 3, { "webbedcreature", "webdecor" }) < 2 and
            #sim:FindEntities(xi, 0, zi, 5, { "webbedcreature", "webdecor" }) < 6 and
            G.math.abs(xi) > 6 and G.math.abs(zi) > 6 then
            local decor = G.SpawnPrefab("widowdecor")
            if decor ~= nil then
                decor.Transform:SetPosition(xi, 9, zi)
                decor.category = ctype
                decor.AnimState:PlayAnimation(ctype)
            end
            return
        end
    end
end

local function PatchWidowWeb()
    local fn = HF.prefab_fn("widowwebspawner")
    if fn == nil then
        return ReportFail("unbounded_retry.widowweb", "widowwebspawner")
    end

    local ok = false
    local spawn_cocoon = HF.descend(fn, "SpawnCocoon")
    if G.type(spawn_cocoon) == "function" then
        ok = HF.replace_upvalue(spawn_cocoon, "TrySpawnCocoon", FixedTrySpawnCocoon) or ok
    end
    local spawn_decor = HF.descend(fn, "SpawnDecor")
    if G.type(spawn_decor) == "function" then
        ok = HF.replace_upvalue(spawn_decor, "TrySpawnDecor", FixedTrySpawnDecor) or ok
    end
    HF.report("unbounded_retry.widowweb", ok)
end

--------------------------------------------------------------------------------
-- riceplantspawner
--------------------------------------------------------------------------------

local function FixedCheckPoint(pt)
    local map = G.TheWorld.Map
    for _ = 1, 20 do
        local moved = false
        if map:IsAboveGroundAtPoint(pt.x + 4, pt.y, pt.z) then
            moved = true
            pt.x = pt.x - G.math.random(2, 4)
        end
        if map:IsAboveGroundAtPoint(pt.x - 4, pt.y, pt.z) then
            moved = true
            pt.x = pt.x + G.math.random(2, 4)
        end
        if map:IsAboveGroundAtPoint(pt.x, pt.y, pt.z + 4) then
            moved = true
            pt.z = pt.z - G.math.random(2, 4)
        end
        if map:IsAboveGroundAtPoint(pt.x, pt.y, pt.z - 4) then
            moved = true
            pt.z = pt.z + G.math.random(2, 4)
        end
        if not moved then
            return pt
        end
    end
    return pt
end

local function PatchRicePlant()
    local fn = HF.prefab_fn("riceplantspawner")
    if fn == nil then
        return ReportFail("unbounded_retry.riceplant", "riceplantspawner")
    end
    local spawn_rice = HF.descend(fn, "SpawnRicePre")
    if G.type(spawn_rice) ~= "function" then
        return ReportFail("unbounded_retry.riceplant", "SpawnRicePre")
    end
    HF.report("unbounded_retry.riceplant",
        HF.replace_upvalue(spawn_rice, "CheckPoint", FixedCheckPoint))
end

--------------------------------------------------------------------------------
-- nymph / pestilence：共用的 FindSmallOffset
--------------------------------------------------------------------------------

local function FixedFindSmallOffset(x, z)
    local map = G.TheWorld.Map
    for _ = 1, 12 do
        local x_off = G.math.random(-10, 10) / 5 + x
        local z_off = G.math.random(-10, 10) / 5 + z
        if map:IsVisualGroundAtPoint(x_off, 0, z_off) then
            return x_off, z_off
        end
    end
    return x, z -- 兜底：退回原坐标，绝不递归
end

local function PatchNymph()
    local fn = HF.prefab_fn("nymph")
    if fn == nil then
        return ReportFail("unbounded_retry.nymph", "nymph（当前版本未注册）")
    end
    local holder = HF.descend(fn, "GroundCheck")
    local spawn_aphid = holder ~= nil and HF.descend(holder, "SpawnAphid") or nil
    if G.type(spawn_aphid) ~= "function" then
        spawn_aphid = HF.descend(fn, "SpawnAphid")
    end
    if G.type(spawn_aphid) ~= "function" then
        return ReportFail("unbounded_retry.nymph", "SpawnAphid")
    end
    HF.report("unbounded_retry.nymph",
        HF.replace_upvalue(spawn_aphid, "FindSmallOffset", FixedFindSmallOffset))
end

--------------------------------------------------------------------------------
-- moonmaw_dragonfly
--------------------------------------------------------------------------------

local function MakeFixedTryEjectLavae(env)
    return function(inst, severed)
        local health = inst.components.health
        if health == nil or health:IsDead() then
            return
        end
        if env.NoLavae ~= nil and env.NoLavae(inst) then
            return
        end
        if inst.components.leader ~= nil and inst.components.leader:CountFollowers() ~= 0 then
            return
        end
        if env.EjectLavae == nil or inst.lavae == nil then
            return
        end

        local available = {}
        for i = 1, #inst.lavae do
            local lavae = inst.lavae[i]
            if lavae ~= nil and lavae.hidden ~= true then
                G.table.insert(available, i)
            end
        end
        if #available == 0 then
            return
        end

        if health:GetPercent() > .5 then
            env.EjectLavae(inst, available[G.math.random(#available)], severed)
        else
            local first = G.table.remove(available, G.math.random(#available))
            local second = nil
            if #available > 0 then
                second = G.table.remove(available, G.math.random(#available))
            end
            env.EjectLavae(inst, first, severed)
            if second ~= nil then
                env.EjectLavae(inst, second)
            end
        end
    end
end

local function PatchMoonmaw()
    local fn = HF.prefab_fn("moonmaw_dragonfly")
    if fn == nil then
        return ReportFail("unbounded_retry.moonmaw", "moonmaw_dragonfly")
    end
    local per_eject = HF.descend(fn, "PerEjectCheck")
    if G.type(per_eject) ~= "function" then
        return ReportFail("unbounded_retry.moonmaw", "PerEjectCheck")
    end
    local index, original = HF.find_upvalue(per_eject, "TryEjectLavae")
    if index == nil or G.type(original) ~= "function" then
        return ReportFail("unbounded_retry.moonmaw", "TryEjectLavae")
    end
    if PATCHED[original] ~= nil then
        HF.report("unbounded_retry.moonmaw", true)
        return
    end
    local fixed = MakeFixedTryEjectLavae(HF.upvalue_values(original))
    PATCHED[fixed] = true
    G.debug.setupvalue(per_eject, index, fixed)
    HF.report("unbounded_retry.moonmaw", true)
end

--------------------------------------------------------------------------------
-- viperfruit
--------------------------------------------------------------------------------

local function MakeFixedSpawnFriend(env)
    return function(eater, count)
        if eater == nil or not eater:IsValid() then
            return
        end

        local speed = env.easing ~= nil and env.easing.linear(3, 7, 3, 10) or 5

        for _ = 1, 8 do
            local pt = eater:GetPosition()
            pt.x = pt.x + G.math.random(-3, 3)
            pt.z = pt.z + G.math.random(-3, 3)

            local on_ground = G.TheWorld.Map:IsAboveGroundAtPoint(pt.x, 0, pt.z)
            local on_platform = G.TheWorld.Map:GetPlatformAtPoint(pt.x, pt.z) ~= nil
            if on_ground or on_platform then
                local x, y, z = eater.Transform:GetWorldPosition()
                local projectile = G.SpawnPrefab("viperprojectile")
                if projectile == nil then
                    return
                end
                projectile.Transform:SetPosition(x, y, z)
                projectile:AddTag("canthit")
                projectile:AddTag("friendly")
                projectile.max_worms = 6
                projectile.eater = eater
                projectile:ListenForEvent("onremove", function()
                    if eater ~= nil and eater:IsValid() then
                        eater.pending_viperling_spawns =
                            G.math.max(0, (eater.pending_viperling_spawns or 1) - 1)
                    end
                end)
                projectile.components.complexprojectile:SetHorizontalSpeed(speed + G.math.random(4, 9))
                projectile.components.complexprojectile:Launch(pt, eater, eater)
                return
            end
        end
        -- 找不到落点：放弃，绝不递归
    end
end

local function PatchViperFruit()
    local fn = HF.prefab_fn("viperfruit") or HF.prefab_fn("viperfruit_lesser")
    if fn == nil then
        return ReportFail("unbounded_retry.viperfruit", "viperfruit")
    end
    local oneaten = HF.descend(fn, "oneatenfn")
    if G.type(oneaten) ~= "function" then
        return ReportFail("unbounded_retry.viperfruit", "oneatenfn")
    end
    local replace = HF.descend(oneaten, "ReplaceFriend")
    if G.type(replace) ~= "function" then
        return ReportFail("unbounded_retry.viperfruit", "ReplaceFriend")
    end
    local index, original = HF.find_upvalue(replace, "SpawnFriend")
    if index == nil or G.type(original) ~= "function" then
        return ReportFail("unbounded_retry.viperfruit", "SpawnFriend")
    end
    if PATCHED[original] ~= nil then
        HF.report("unbounded_retry.viperfruit", true)
        return
    end
    local fixed = MakeFixedSpawnFriend(HF.upvalue_values(original))
    PATCHED[fixed] = true
    G.debug.setupvalue(replace, index, fixed)
    HF.report("unbounded_retry.viperfruit", true)
end

--------------------------------------------------------------------------------
-- 注册
--------------------------------------------------------------------------------

AddPrefabPostInit("widowwebspawner", function(inst)
    if not HF.is_master() then return end
    HF.try("unbounded_retry.widowweb", PatchWidowWeb)
end)

AddPrefabPostInit("riceplantspawner", function(inst)
    if not HF.is_master() then return end
    HF.try("unbounded_retry.riceplant", PatchRicePlant)
end)

AddPrefabPostInit("nymph", function(inst)
    if not HF.is_master() then return end
    HF.try("unbounded_retry.nymph", PatchNymph)
end)

AddPrefabPostInit("moonmaw_dragonfly", function(inst)
    if not HF.is_master() then return end
    HF.try("unbounded_retry.moonmaw", PatchMoonmaw)
end)

local function ViperFruitPatched(inst)
    if not HF.is_master() then return end
    HF.try("unbounded_retry.viperfruit", PatchViperFruit)
end
AddPrefabPostInit("viperfruit", ViperFruitPatched)
AddPrefabPostInit("viperfruit_lesser", ViperFruitPatched)

AddComponentPostInit("um_pestilencecontroller", function(self)
    if not HF.is_master() then return end
    HF.try("unbounded_retry.pestilence", function()
        local spawn_nymph = self.SpawnNymph
        local spawn_posse = spawn_nymph ~= nil and HF.descend(spawn_nymph, "SpawnPosse") or nil
        if G.type(spawn_posse) ~= "function" then
            return ReportFail("unbounded_retry.pestilence", "SpawnPosse（当前版本未挂载）")
        end
        HF.report("unbounded_retry.pestilence",
            HF.replace_upvalue(spawn_posse, "FindSmallOffset", FixedFindSmallOffset))
    end)
end)
