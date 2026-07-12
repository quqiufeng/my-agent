-- 工具栏图标位置缓存（相对于窗口左上角 0,0）
-- 每次只需要获取一次窗口位置 wx,wy，加上相对坐标即可
-- 窗口移动后缓存依然有效

local M = {}

local CACHE_FILE = os.getenv("HOME") .. "/.wechat_toolbar_cache.json"

function M.save(icons)
    local data = {
        icons   = icons,
        updated_at = os.date("%Y-%m-%dT%H:%M:%S"),
    }
    local f = io.open(CACHE_FILE, "w")
    if f then
        f:write(require("cjson").encode(data))
        f:close()
        return true
    end
    return false
end

function M.load()
    local f = io.open(CACHE_FILE, "r")
    if not f then return nil end
    local ok, data = pcall(require("cjson").decode, f:read("*a"))
    f:close()
    if not ok or not data then return nil end
    return data.icons
end

function M.clear()
    os.execute("rm -f " .. CACHE_FILE)
end

return M
