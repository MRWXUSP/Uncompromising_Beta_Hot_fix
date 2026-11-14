-- 修复：DoLesserThreat 的 0 延迟无限自递归（潜伏问题）
--
-- 原代码（components/randomnightevents.lua:1207）：
--     if self.weightheodds >= 0.83 and not threat == "vortex" and ... then
--     ...
--     else
--         player:DoTaskInTime(0, function() DoLesserThreat(player, threat) end)
--     end
--
-- 两个问题：
--   1) Lua 里 `not threat == "x"` 实际是 `(not threat) == "x"`，恒为 false，
--      六个分支全部不可达，必然落到 else；
--   2) else 用 DoTaskInTime(0) 把自己排回去，形成每帧执行、永不停止的递归链。
--
-- 说明：当前测试版里调用它的六个事件（SpawnShadowVortex 等）在事件表里
-- 已被注释掉，且 randomnightevents 组件本身也没有被 AddComponent，
-- 因此这是「潜伏」bug。本补丁会在运行时扫描事件表，一旦这些函数被重新
-- 启用就会自动接管；找不到目标时只记录日志，不做任何改动。

local G = GLOBAL
local HF = G.UMHOTFIX

if not HF.flags.fix_lesser_threat then
    HF.report("lesser_threat", true, "配置已关闭")
    return
end

-- threat 参数 -> 次级事件函数名（取自原代码的六个分支）
local THREAT_TO_FUNC =
{
    vortex = "SpawnLesserShadowVortex",
    grabby = "SpawnLesserShadowGrabby",
    weaver = "SpawnLesserMindWeavers",
    ticks = "SpawnLesserNervousTicks",
    crawlers = "SpawnLesserNightCrawlers",
    seekers = "SpawnLesserFuelSeekers",
}

local function FindDoLesserThreat(self)
    for _, item in G.ipairs(HF.event_entries(self)) do
        local index, value = HF.find_upvalue(item.entry.fn, "DoLesserThreat")
        if index ~= nil and G.type(value) == "function" then
            return item.entry.fn, index, value
        end
    end
    return nil
end

local function Apply(self)
    if self._umhotfix_lesser_threat then
        return
    end

    local holder, index, original = FindDoLesserThreat(self)
    if holder == nil then
        HF.report("lesser_threat", true, "当前版本未启用相关事件（无需处理）")
        return
    end

    local env = HF.upvalues(original)
    local spawners = {}
    for threat, funcname in G.pairs(THREAT_TO_FUNC) do
        local entry = env[funcname]
        if entry ~= nil and G.type(entry.value) == "function" then
            spawners[threat] = entry.value
        end
    end

    if G.next(spawners) == nil then
        -- 连次级事件函数都拿不到：退化为「什么都不做」，至少终止递归
        local function NoOp(player, threat) end
        G.debug.setupvalue(holder, index, NoOp)
        self._umhotfix_lesser_threat = true
        HF.report("lesser_threat", true, "只终止递归（未找到次级事件函数）")
        return
    end

    local function FixedDoLesserThreat(player, threat)
        if player == nil or not player:IsValid() then
            return
        end
        if not G.TheWorld.state.isnight then
            return
        end

        local choices = {}
        for key, fn in G.pairs(spawners) do
            if key ~= threat then
                G.table.insert(choices, fn)
            end
        end
        if #choices == 0 then
            return
        end

        -- 只生成一次，绝不递归
        choices[G.math.random(#choices)](player)
    end

    G.debug.setupvalue(holder, index, FixedDoLesserThreat)
    self._umhotfix_lesser_threat = true
    HF.report("lesser_threat", true)
end

AddComponentPostInit("randomnightevents", function(self)
    if not HF.is_master() then
        return
    end
    HF.try("lesser_threat", Apply, self)
end)
