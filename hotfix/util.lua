-- 公共工具：日志、结果汇报、upvalue 存取、事件表遍历
local G = GLOBAL
local HF = G.UMHOTFIX

local function SafeToString(v)
    local ok, s = G.pcall(G.tostring, v)
    if ok then return s end
    return "<?>"
end

local function Format(fmt, ...)
    if G.select("#", ...) > 0 then
        local ok, s = G.pcall(G.string.format, fmt, ...)
        if ok then return s end
    end
    return SafeToString(fmt)
end

function HF.log(fmt, ...)
    G.print("[UMHotfix] " .. Format(fmt, ...))
end

function HF.debug_log(fmt, ...)
    if HF.verbose then
        HF.log(fmt, ...)
    end
end

-- 汇报一次补丁结果；同一 key 只在第一次成功/失败时打印，避免刷屏
function HF.report(key, ok, detail)
    local first = HF.results[key] == nil
    HF.results[key] = ok and "ok" or "fail"
    if first then
        local suffix = detail ~= nil and (" - " .. SafeToString(detail)) or ""
        if ok then
            HF.log("已应用: %s%s", key, suffix)
        else
            HF.log("未应用: %s%s", key, suffix)
        end
    end
    return ok
end

-- 执行一段补丁代码并捕获异常，返回是否成功
function HF.try(key, fn, ...)
    local ok, err = G.pcall(fn, ...)
    if not ok then
        HF.report(key, false, err)
        return false
    end
    HF.report(key, true)
    return true
end

function HF.is_master()
    local world = G.TheWorld
    return world ~= nil and world.ismastersim == true
end

-- 读取一个函数的所有 upvalue：name -> { index, value }
function HF.upvalues(fn)
    local map = {}
    if G.type(fn) ~= "function" then return map end
    for i = 1, 64 do
        local name, value = G.debug.getupvalue(fn, i)
        if name == nil then break end
        map[name] = { index = i, value = value }
    end
    return map
end

-- 读取一个函数的所有 upvalue：name -> value（用于取原函数依赖的模块局部函数）
function HF.upvalue_values(fn)
    local map = {}
    if G.type(fn) ~= "function" then return map end
    for i = 1, 64 do
        local name, value = G.debug.getupvalue(fn, i)
        if name == nil then break end
        map[name] = value
    end
    return map
end

-- 按名字查找 upvalue，返回 index, value
function HF.find_upvalue(fn, name)
    if G.type(fn) ~= "function" then return nil end
    for i = 1, 64 do
        local n, value = G.debug.getupvalue(fn, i)
        if n == nil then break end
        if n == name then
            return i, value
        end
    end
end

-- 按名字替换 upvalue（同一模块内的闭包共享同一个 upvalue cell）
function HF.replace_upvalue(fn, name, value)
    local i = HF.find_upvalue(fn, name)
    if i == nil then return false end
    G.debug.setupvalue(fn, i, value)
    return true
end

-- 取 upvalue 的值
function HF.descend(fn, name)
    local i, value = HF.find_upvalue(fn, name)
    if i == nil then return nil end
    return value
end

-- 取已注册 prefab 的构造函数
function HF.prefab_fn(name)
    local prefabs = G.Prefabs
    local prefab = prefabs ~= nil and prefabs[name] or nil
    return prefab ~= nil and prefab.fn or nil
end

-- 遍历 RNE 组件里所有事件表，返回 { entry = {...}, key = "baseevents" }
function HF.event_entries(self)
    local lists =
    {
        "baseevents", "wildevents", "secondarywildevents", "oceanevents",
        "fullmoonevents", "newmoonevents", "caveevents", "secondarycaveevents",
    }
    local out = {}
    for _, key in G.ipairs(lists) do
        local list = self[key]
        if G.type(list) == "table" then
            for _, entry in G.ipairs(list) do
                if G.type(entry) == "table" and G.type(entry.fn) == "function" then
                    G.table.insert(out, { key = key, entry = entry })
                end
            end
        end
    end
    return out
end
