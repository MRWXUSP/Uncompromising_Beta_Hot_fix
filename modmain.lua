-- 永不妥协测试版热修补丁 / Uncompromising Beta Hotfix
--
-- 加载顺序说明：
--   mods.lua 按 modinfo.priority 从高到低加载 mod。
--   Uncompromising 的 priority = -10，本模组 -100，因此本模组最后加载：
--     * 本模组的 AddPrefabPostInit / AddComponentPostInit 排在 UM 之后执行
--     * 本模组可以安全地包装 UM 已经注册好的回调
--
-- 本文件只负责读取配置、建立公共表，然后加载 hotfix/ 下的各个修复模块。

local G = GLOBAL

local HF =
{
    modname = modname,
    version = "0.1.2",
    flags = {},
    results = {},
    verbose = GetModConfigData("verbose_log") == true,
}
G.UMHOTFIX = HF

local function Flag(name)
    -- 二进制配置：关闭时返回 false，其余情况（true/nil）默认启用
    return GetModConfigData(name) ~= false
end

HF.flags =
{
    fix_woby_transform = Flag("fix_woby_transform"),
    fix_rne_entity_leak = Flag("fix_rne_entity_leak"),
    fix_lesser_threat = Flag("fix_lesser_threat"),
    fix_unbounded_retry = Flag("fix_unbounded_retry"),
    fix_immediate_call = Flag("fix_immediate_call"),
    fix_task_handle_leak = Flag("fix_task_handle_leak"),
    fix_shove_entity_leak = Flag("fix_shove_entity_leak"),
    fix_pathfinding_wall_leak = Flag("fix_pathfinding_wall_leak"),
}

modimport("hotfix/util")

-- Uncompromising 的标记物；没装 UM 时本模组没有任何意义，直接提示。
if G.UM_CONFIG == nil and G.UMCommonFns == nil then
    HF.log("未检测到 Uncompromising Mode，本模组不会生效。")
    return
end

modimport("hotfix/fix_woby")
modimport("hotfix/fix_lesser_threat")
modimport("hotfix/fix_rne_leak")
modimport("hotfix/fix_unbounded_retry")
modimport("hotfix/fix_immediate_call")
modimport("hotfix/fix_task_handle_leak")
modimport("hotfix/fix_shove_entity")
modimport("hotfix/fix_pathfinding_wall")

HF.log("加载完成（version %s）", HF.version)
