-- 永不妥协测试版热修补丁 / Uncompromising Beta Hotfix
-- 服务端热修：修复 Uncompromising Mode 中由递归 / 定时任务自我重排引起的
-- 内存泄漏、实体泄漏与卡顿问题。每一项修复都可以单独开关。

name = "永不妥协测试版热修补丁"

description = [[
Uncompromising Beta Hotfix

为《永不妥协》(Uncompromising Mode) 测试版提供的服务端热修补丁。

修复若干由「递归 / 定时任务自我重排」造成的内存泄漏、实体泄漏、栈溢出与卡顿问题。
每一项修复都可以在模组配置里单独开关，默认全部启用。

需要与 Uncompromising Mode 同时启用；本模组只有服务端需要安装。
]]

author = "Uncompromising Hotfix (community)"
version = "0.1.2"

api_version = 10

dst_compatible = true
dont_starve_compatible = false
reign_of_giants_compatible = false

-- 服务端模组：客户端不需要安装
client_only_mod = false
all_clients_require_mod = false
server_only_mod = true

-- 必须晚于 Uncompromising (priority = -10) 加载
-- mods.lua 按 priority 从高到低加载，-100 会排在最后，这样我们的
-- AddPrefabPostInit / AddComponentPostInit 才会排在 UM 的之后执行。
priority = -100

icon_atlas = "modicon.xml"
icon = "modicon.tex"

server_filter_tags = { "uncompromising", "hotfix", "memoryleak", "um" }

local function BinaryConfig(name, label, hover, default)
    return
    {
        name = name,
        label = label,
        hover = hover,
        options =
        {
            { description = "启用", data = true },
            { description = "禁用", data = false },
        },
        default = default,
    }
end

configuration_options =
{
    BinaryConfig("fix_woby_transform", "Woby 变身任务增殖",
        "修复大 Woby 饥饿时每秒成倍创建周期任务导致的内存暴涨。", true),

    BinaryConfig("fix_rne_entity_leak", "夜晚事件实体泄漏",
        "修复夜晚随机事件失败重试时先创建实体后校验坐标造成的实体泄漏。当前版本相关事件未启用，属潜伏修复。", true),

    BinaryConfig("fix_lesser_threat", "次级暗影事件递归",
        "修复 DoLesserThreat 的 0 延迟无限自递归。当前版本相关事件已被注释，属潜伏修复。", true),

    BinaryConfig("fix_unbounded_retry", "随机点重试无限递归",
        "修复蛛网生成器 / 稻株生成器 / 月蚀龙蝇 / 毒蛇果等随机点重试没有次数上限导致的栈溢出。", true),

    BinaryConfig("fix_immediate_call", "定时器立即调用",
        "修复 DoTaskInTime(delay, fn(x)) 被立即求值造成的问题（遗迹雕像、暗影跟随者、爆爆椒等）。", true),

    BinaryConfig("fix_task_handle_leak", "任务/引用表泄漏",
        "修复 Ocupus 触手表只增不减、猴子寻石芽周期任务句柄被覆盖等泄漏。", true),

    BinaryConfig("fix_shove_entity_leak", "击退实体泄漏",
        "修复幽灵推击 / 击退产生的 um_shoveentity 在目标提前死亡或消失后残留为隐形实体。", true),

    BinaryConfig("fix_pathfinding_wall_leak", "寻路墙残留",
        "修复 UMAddPathfindingWalls 在实体已被移除后仍写入寻路墙、留下永久不可通行点。", true),

    BinaryConfig("verbose_log", "调试日志",
        "在服务端日志里输出每个补丁的检测与执行结果。", false),
}
