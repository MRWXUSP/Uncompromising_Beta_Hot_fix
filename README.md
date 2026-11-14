# 永不妥协测试版热修补丁 / Uncompromising Beta Hotfix

> 服务端热修补丁，用于修复 [Uncompromising Mode](https://steamcommunity.com/sharedfiles/filedetails/?id=2039181790)
> 测试版中由「递归 / 定时任务自我重排」引起的内存泄漏、实体泄漏、栈溢出与卡顿问题。
> 每一项修复都可以在模组配置中单独开关。

---

## 1. 这个模组做什么

不是玩法改动，而是对 UM 现有代码打运行时补丁：

| 开关 | 修复内容 | 当前测试版状态 |
|------|----------|----------------|
| **Woby 变身任务增殖** | 大 Woby 饥饿触发变身时，`TriggerTransformation` 每秒新建一条周期任务且从不取消，任务数指数增长；改为同一时间只保留一条 | ✅ 生效 |
| **夜晚事件实体泄漏** | 夜晚随机事件里「先 `SpawnPrefab` 后校验坐标」，失败重试时旧实体不删除，会不断在世界原点堆积；改为先校验后创建、并限制重试次数 | ⚠️ 潜伏（相关事件/组件在当前版本被注释，补丁会在重新启用时自动生效） |
| **次级暗影事件递归** | `DoLesserThreat` 中 `not threat == "x"` 优先级错误导致所有分支不可达，必然落到 `DoTaskInTime(0)` 自递归，整夜每帧空转；改为正确的比较并只生成一次 | ⚠️ 潜伏（调用它的六个事件已被注释） |
| **随机点重试无限递归** | 蛛网生成器、稻株生成器、月蚀龙蝇、毒蛇果、树精等「随机点找不到就 `return 自己()`」没有次数上限，恶劣地形下栈溢出；改为有限次循环/兜底坐标 | ✅ 生效（nymph/毒疫控制器为潜伏） |
| **定时器立即调用** | `DoTaskInTime(0, fn(x))` 会在注册前就执行 `fn(x)`，把「延迟」变成同步递归（遗迹雕像、暗影跟随者），或产生 `nil` 回调（爆爆椒）；改为传函数引用/闭包 | ✅ 生效 |
| **任务/引用表泄漏** | Ocupus 触手引用表只增不减、`boatcheck` 周期任务句柄被覆盖；猴子寻石芽任务反复创建旧句柄失联；定期清理 + 单例化 | ✅ 生效 |

> 详细的问题定位、代码片段与修复原理见仓库根目录的 `递归内存泄漏扫描报告.md`。

---

## 2. 安装（本地测试）

### 2.1 目录结构

```
UncompromisingBetaHotfix/
├── modinfo.lua          -- 模组信息与配置项
├── modmain.lua          -- 入口，读取配置并加载 hotfix/
├── modicon.tex / .xml   -- 模组图标（UM Beta 封面 + 标题文字，512x512）
├── preview.png          -- 创意工坊预览图（同封面，1024x1024，无侧边文字）
├── hotfix/
│   ├── util.lua                -- 日志 / upvalue 工具
│   ├── fix_woby.lua            -- ① Woby 变身任务
│   ├── fix_lesser_threat.lua   -- ② 次级暗影递归
│   ├── fix_rne_leak.lua        -- ③ 夜晚事件实体泄漏
│   ├── fix_unbounded_retry.lua -- ④ 随机点重试递归
│   ├── fix_immediate_call.lua  -- ⑤ 定时器立即调用
│   └── fix_task_handle_leak.lua-- ⑥ 任务/引用表泄漏
└── tools/make_icon.py   -- 图标生成脚本（不需要随模组发布）
```

### 2.2 放到 mods 目录

把整个 `UncompromisingBetaHotfix` 文件夹复制到：

```
<你的 DST 安装目录>/mods/UncompromisingBetaHotfix
```

同时把 UM 本体（仓库里的 `3193922031` 文件夹）也放进 `mods/`，例如：

```
mods/
├── UncompromisingBetaHotfix/
└── uncompromising/            (即 3193922031 的内容，文件夹名随意)
```

### 2.3 启用

1. 启动游戏 → 模组 → 勾选 **永不妥协测试版热修补丁**（本地模组，图标是 UM Beta 封面 + 大字「热修补丁」）；
2. 同时勾选 Uncompromising Mode；
3. 开一个测试世界（**建议创造模式 + 被骑乘的大 Woby / 遗迹雕像 / 洞穴**）。

> 模组是 `server_only_mod`，只有房主/服务器需要安装，客户端不需要订阅。
> 若使用专用服务器，把两个文件夹都放进服务器 `mods/`，并在
> `dedicated_server_mods_setup.lua` / `modoverrides.lua` 中启用即可。

---

## 3. 配置项

模组配置里每一项都可以单独开关，默认全开：

```
√ Woby 变身任务增殖
√ 夜晚事件实体泄漏
√ 次级暗影事件递归
√ 随机点重试无限递归
√ 定时器立即调用
√ 任务/引用表泄漏
□ 调试日志        ← 打开后服务端日志会输出每个补丁的结果
```

打开「调试日志」后，在服务端日志里搜索 `[UMHotfix]` 即可看到：

```
[UMHotfix] 已应用: woby_transform
[UMHotfix] 已应用: immediate.ruinsstatues
[UMHotfix] 未应用: rne_entity_leak - 当前版本未启用相关事件（无需处理）
[UMHotfix] 加载完成（version 0.1.1）
```

---

## 4. 建议的测试步骤

| 修复 | 怎么测 | 预期 |
|------|--------|------|
| Woby 变身任务 | 用 Walter，让大 Woby 饥饿降到 30% 以下并保持 1 分钟（可反复触发）；观察服务端内存/FPS | 不再出现「每秒任务数翻倍」；日志里只有一条 `woby_transform` |
| 遗迹雕像 | 洞穴遗迹里靠近 `ruins_statue_*`，等待 0.1~0.4 秒 | 雕像附近生成一个拖拽怪刷新点；不再卡住/栈溢出 |
| 暗影跟随者 | 洞穴里靠近爬行恐惧/恐怖尖喙，使其追击并远离目标 | 传送有延迟（不会瞬移报错），且不会每秒重复传送 |
| 爆爆椒 | 吃「爆爆椒」（stuffed_peeper_poppers） | 不再出现 `attempt to call a nil value` 的 Lua 报错 |
| 蛛网生成器 | 开新世界进巨大树森林（巨型树任务） | 全世界生成不再卡住；新世界能正常加载 |
| 稻株生成器 | 开新世界进沼泽（稻株地） | 同上 |
| 月蚀龙蝇 | 打到残血并清掉可见熔岩虫 | 不再出现「PANIC / 无限重试」，正常喷出熔岩虫或直接进入下一阶段 |
| 毒蛇果 | 在船上/虚空边吃毒蛇果 | 不再卡顿/无限制重试；最多 8 次尝试后放弃 |
| Ocupus | 出海让 Ocupus 咬船，反复脱离/再交战 | 触手表长度会回落，`boatcheck` 只有一条 |
| 猴子寻石芽 | 带走石芽后反复上下线/让猴子睡觉再醒来 | 不会积累多条 3 秒周期任务 |

> 注意：`夜晚事件`、`次级暗影`、`nymph`、`rnelevitator` 这几项在当前 UM 测试版里
> 本身就没有被启用（相关 `AddComponent` / 事件表条目被注释），所以补丁不会产生
> 可见变化，只会在日志里显示「未应用 / 无需处理」。这是预期行为，不是补丁失效。

---

## 5. 验证状态

本模组在仓库里自带一套**离线逻辑测试**（用 lupa 在 Lua 运行时里模拟 DST 的实体/世界接口，
逐个补丁注入假实体后调用，验证「补丁是否生效、是否不再递归、是否只生成一次」）：

```
_leakscan/run_tests.py   →   RESULT passed=26 failed=0
```

覆盖：Woby 任务单例、Ocupus 句柄、猴子任务、遗迹雕像、蛛网/稻株/龙蝇/毒蛇果、
次级暗影递归、暗影跟随者、爆爆椒 nil 回调、夜晚事件实体泄漏（含季节重注册路径）。

> 离线测试只能验证补丁逻辑本身；**还没有在真实 DST 客户端/服务器里跑过**。
> 建议第一次测试时打开「调试日志」，确认日志里出现 `[UMHotfix] 加载完成` 和
> 你关心的 `已应用: ...` 行，再按第 4 节逐项测试。

---

## 6. 实现说明与限制

- **为什么 `priority = -100`**：DST 按 `modinfo.priority` 从高到低加载模组。UM 是
  `-10`，本模组 `-100` 最后加载，因此 `AddPrefabPostInit` / `AddComponentPostInit`
  的回调排在 UM 的回调之后执行，才能用 `inst:DoPeriodicTask` 包住 UM 之后注册的任务。
- **不修改 UM 源文件**：所有修复都在运行时完成。
  - 能拿到实例的（Woby、Ocupus、猴子、暗影跟随者、毒疫控制器）：在 postinit 里包实例方法；
  - 模块级局部函数（蛛网/稻株/龙蝇/毒蛇果）：用 `debug.getupvalue` / `debug.setupvalue`
    替换闭包共享的 upvalue cell；
  - 事件表里的函数（夜晚事件）：替换 `self.baseevents` 等表里的 `fn`，并在季节切换后复核。
- **局限**：
  1. 补丁依赖 UM 当前的函数/局部变量命名（如 `SpawnCocoon`、`DoPortCheck`、
     `SpawnFriend`）。若 UM 后续重命名，补丁会在日志里报「未应用」并自动跳过，
     不会导致崩溃；届时需要按新名字更新本模组。
  2. 用 `debug` 库改写 upvalue 属于「热修」手段，开启调试日志可以看到每一步结果；
     若某个补丁未生效，请把日志发给开发者。
  3. `randomnightevents*`、`um_pestilencecontroller`、`nymph`、`rnelevitator` 在当前
     测试版中未启用，相关补丁属于「提前修好，等系统重新上线」。若你手动启用了
     这些系统，补丁会自动接管。

---

## 7. 致谢

- 问题定位：`递归内存泄漏扫描报告.md`（同目录上级）
- 图标：以 UM Beta 封面（`tools/um_beta_cover.png`）为底，叠加「热修补丁」标题；
  生成脚本 `tools/make_icon.py`，输出 512x512 DXT5 KTEX。
  注意：Klei 的 KTEX 像素行按**自下而上**存储，编码前需要先垂直翻转每一级 mip，
  否则游戏里会显示成上下颠倒（“反的”）。
- 代码归属：所有被修复的逻辑均来自 Uncompromising Mode，本模组仅做运行时热修，
  不包含/不重新分发 UM 的原始源码。
