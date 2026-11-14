-- 修复：夜晚随机事件「先创建实体，后校验坐标」造成的实体泄漏（潜伏问题）
--
-- 原代码（components/randomnightevents.lua）里大量存在这种写法：
--     local gnomes = SpawnPrefab("gnome_organizer")   -- 先创建
--     if TheWorld.Map:IsPassableAtPoint(x1, 0, z1) then
--         gnomes.Transform:SetPosition(x1, y, z1)
--     else
--         player:DoTaskInTime(0.1, function(player) SpawnGnomes(player) end)  -- 旧实体没删
--     end
--
-- 校验失败时刚创建的实体不会被 Remove，会留在世界原点；
-- 而重试没有次数上限，玩家在船上/被围住时会每 0.1 秒稳定泄漏一个实体。
--
-- 修复方式：把「事件表里的 fn」替换成安全版本（先校验、后创建；有次数上限），
-- 对「被其它函数间接调用」的生成函数则替换调用者里的 upvalue。
--
-- 说明：当前测试版里 randomnightevents / randomnighteventscaves 组件都没有被
-- AddComponent（init_harder_weather.lua 中相关行已注释），所以本修复同样是
-- 潜伏修复；一旦组件被重新启用，这里的补丁会自动生效。

local G = GLOBAL
local HF = G.UMHOTFIX

if not HF.flags.fix_rne_entity_leak then
    HF.report("rne_entity_leak", true, "配置已关闭")
    return
end

-- 在玩家周围找一个满足条件的点（最多 10 次），不再无限递归
local function FindSpot(player, range, want_water)
    local x, y, z = player.Transform:GetWorldPosition()
    local map = G.TheWorld.Map
    for _ = 1, 10 do
        local x1 = x + G.math.random(-range, range)
        local z1 = z + G.math.random(-range, range)
        local passable = map:IsPassableAtPoint(x1, 0, z1)
        if (want_water and not passable) or ((not want_water) and passable) then
            return x1, y, z1
        end
    end
    return nil
end

local function SpawnAt(prefab, x, y, z)
    local ent = G.SpawnPrefab(prefab)
    if ent ~= nil and ent.Transform ~= nil then
        ent.Transform:SetPosition(x, y, z)
    end
    return ent
end

-- 事件表里直接注册的生成函数
local FixedEvents =
{
    SpawnGnomes = function(env)
        return function(player)
            if not G.TheWorld.state.isnight then
                return
            end
            player:DoTaskInTime(2 * G.math.random() * 0.3, function()
                local x, y, z = FindSpot(player, 10, false)
                if x ~= nil then
                    SpawnAt("gnome_organizer", x, y, z)
                end
            end)
        end
    end,

    SpawnLureplagueRat = function(env)
        return function(player)
            if not G.TheWorld.state.isnight then
                return
            end
            player:DoTaskInTime(2 * G.math.random() * 0.3, function()
                local x, y, z = FindSpot(player, 10, false)
                if x == nil then
                    return
                end
                local rat = SpawnAt("lureplague_rat", x, y, z)
                if rat ~= nil and rat.components.combat ~= nil then
                    rat.components.combat:SetTarget(player)
                end
            end)
        end
    end,
}

-- 被其它函数间接调用的生成函数：替换调用者里对应的 upvalue
local FixedUpvalues =
{
    LeifAttack =
    {
        "SpawnBirchNutters",
        function(env)
            return function(player)
                if not G.TheWorld.state.isnight then
                    return
                end
                player:DoTaskInTime(2 * G.math.random() * 0.3, function()
                    local x, y, z = FindSpot(player, 10, false)
                    if x == nil then
                        return
                    end
                    local nutters = SpawnAt("birchnutdrake", x, y, z)
                    if nutters == nil then
                        return
                    end
                    if env.DayBreak ~= nil then
                        env.DayBreak(nutters)
                    end
                    if nutters.components.combat ~= nil then
                        nutters.components.combat:SetTarget(player)
                    end
                end)
            end
        end,
    },

    SpawnSquids =
    {
        "SpawnSquidFunction",
        function(env)
            return function(player)
                if not G.TheWorld.state.isnight then
                    return
                end
                -- 鱿鱼要生成在水里：IsPassableAtPoint 为 false 才是水面
                local x, y, z = FindSpot(player, 12, true)
                if x == nil then
                    return
                end
                local squid = SpawnAt("squid", x, y, z)
                SpawnAt("splash_green", x, y, z)
                if squid ~= nil then
                    squid:PushEvent("spawn")
                    if squid.components.combat ~= nil then
                        squid.components.combat:SetTarget(player)
                    end
                end
            end
        end,
    },

    -- 只在洞穴组件里替换：主世界的 SpawnMonkeysFunction 是另一套逻辑
    SpawnMonkeys =
    {
        "SpawnMonkeysFunction",
        function(env)
            return function(player)
                if not G.TheWorld.state.iscavenight then
                    return
                end
                local x, y, z = FindSpot(player, 16, false)
                if x == nil then
                    return
                end
                local monkey = SpawnAt("chimp", x, y, z)
                if monkey ~= nil and env.DayBreak ~= nil then
                    env.DayBreak(monkey)
                end
            end
        end,
    },
}

local function Apply(self)
    local is_cave = self.inst ~= nil and self.inst:HasTag("cave")
    local changed = 0

    -- Lua 的 function 不能挂字段，用实体上的表记录已替换的函数
    local safe = self._umhotfix_safe_fns
    if safe == nil then
        safe = {}
        self._umhotfix_safe_fns = safe
    end

    for _, item in G.ipairs(HF.event_entries(self)) do
        local entry = item.entry

        -- 1) 直接注册的生成函数
        local factory = FixedEvents[entry.name]
        if factory ~= nil and not safe[entry.fn] then
            local fixed = factory(HF.upvalue_values(entry.fn))
            safe[fixed] = true
            entry.fn = fixed
            changed = changed + 1
        end

        -- 2) 间接调用的生成函数
        local up = FixedUpvalues[entry.name]
        if up ~= nil and (entry.name ~= "SpawnMonkeys" or is_cave) then
            local original = HF.descend(entry.fn, up[1])
            if G.type(original) == "function" and not safe[original] then
                local fixed = up[2](HF.upvalue_values(original))
                safe[fixed] = true
                if HF.replace_upvalue(entry.fn, up[1], fixed) then
                    changed = changed + 1
                end
            end
        end
    end

    if changed > 0 then
        HF.debug_log("rne_entity_leak: 本次替换 %d 个生成函数", changed)
    end
    return changed
end

local function Install(self, label)
    Apply(self)

    if self._umhotfix_rne_watch then
        return
    end
    self._umhotfix_rne_watch = true

    local inst = self.inst
    if inst == nil then
        return
    end

    -- 季节切换会重新注册事件（OnSeasonTick），需要重新套补丁
    inst:ListenForEvent("seasontick", function()
        inst:DoTaskInTime(0, function() Apply(self) end)
    end, G.TheWorld)

    -- 兜底：每分钟复核一次，防止其它路径重新注册原始函数
    inst:DoPeriodicTask(60, function()
        Apply(self)
    end)

    HF.report(label, true)
end

AddComponentPostInit("randomnightevents", function(self)
    if not HF.is_master() then
        return
    end
    HF.try("rne_entity_leak", Install, self, "rne_entity_leak")
end)

AddComponentPostInit("randomnighteventscaves", function(self)
    if not HF.is_master() then
        return
    end
    HF.try("rne_entity_leak.caves", Install, self, "rne_entity_leak.caves")
end)
