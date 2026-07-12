-- ============================================================
-- 图标识别 → 功能映射表
-- LLM 识别出图标名字 → 确认/纠错 → 对应操作
-- ============================================================
-- 用法:
--   local icons = require("wechat_ocr.icon_actions")
--   local action = icons.lookup("Chats")  -- 返回 { name="聊天", click=function, ... }
--   local ok, suggestion = icons.verify("Chats", "speech bubble")
-- ============================================================

local M = {}

-- 默认映射表: LLM 识别名称 → 确认后的标准功能
-- key: LLM 可能输出的名称（模糊匹配）
-- value: { name_cn, name_en, desc, click_handler }
M.defaults = {
    -- 微信第一列图标（从上到下 8 个，含头像）
    Avatar      = { name_cn = "头像",     name_en = "Avatar",     desc = "个人头像",   area = "col1", order = 1 },
    WeChat      = { name_cn = "微信",     name_en = "WeChat",     desc = "消息列表",   area = "col1", order = 2 },
    Chats       = { name_cn = "微信",     name_en = "WeChat",     desc = "消息列表",   area = "col1", order = 2 },
    Messages    = { name_cn = "微信",     name_en = "WeChat",     desc = "消息列表",   area = "col1", order = 2 },
    Contacts    = { name_cn = "通讯录",   name_en = "Contacts",   desc = "联系人列表", area = "col1", order = 3 },
    Friends     = { name_cn = "通讯录",   name_en = "Contacts",   desc = "联系人列表", area = "col1", order = 3 },
    Favorites   = { name_cn = "收藏",     name_en = "Favorites",  desc = "收藏夹",     area = "col1", order = 4 },
    Star        = { name_cn = "收藏",     name_en = "Favorites",  desc = "收藏夹",     area = "col1", order = 4 },
    Moments     = { name_cn = "朋友圈",   name_en = "Moments",    desc = "朋友圈",     area = "col1", order = 5 },
    Channels    = { name_cn = "视频号",   name_en = "Channels",   desc = "视频号",     area = "col1", order = 6 },
    Search      = { name_cn = "搜一搜",   name_en = "Search",     desc = "搜一搜",     area = "col1", order = 7 },
    MiniProgram = { name_cn = "小程序",   name_en = "MiniProgram",desc = "小程序面板", area = "col1", order = 8 },
    Panel       = { name_cn = "小程序",   name_en = "MiniProgram",desc = "小程序面板", area = "col1", order = 8 },

    -- 微信第三列格式工具栏图标
    Emoji       = { name_cn = "表情",     name_en = "Emoji",      desc = "插入表情",   area = "toolbar", order = 1 },
    Cube        = { name_cn = "发送收藏", name_en = "Cube",       desc = "发送收藏内容", area = "toolbar", order = 2 },
    Folder      = { name_cn = "发送文件", name_en = "Folder",     desc = "发送文件",   area = "toolbar", order = 3 },
    Scissors    = { name_cn = "截图",     name_en = "Scissors",   desc = "截图",       area = "toolbar", order = 4 },
    Chat        = { name_cn = "聊天记录", name_en = "Chat",       desc = "聊天记录",   area = "toolbar", order = 5 },
    Phone       = { name_cn = "通话",     name_en = "Phone",      desc = "语音通话",   area = "toolbar", order = 6 },
}

-- 用户可覆盖的映射表
M.custom = {}

--- 查找图标对应的功能
function M.lookup(name)
    if not name then return nil end
    local key = name:gsub("^%s*(.-)%s*$", "%1"):gsub("[-_]", " ")
    -- 先查用户自定义
    for pattern, v in pairs(M.custom) do
        if key:lower() == pattern:lower() or key:lower():find(pattern:lower(), 1, true) then
            return v
        end
    end
    -- 再查默认
    for pattern, v in pairs(M.defaults) do
        if key:lower() == pattern:lower() or key:lower():find(pattern:lower(), 1, true) then
            return v
        end
    end
    return nil
end

--- 验证 LLM 返回的识别结果
--- @param name string LLM 识别的名称
--- @param visual string 视觉描述（可选）
--- @return boolean 是否匹配到已知功能
--- @return table|nil 匹配到的功能记录
function M.verify(name, visual)
    local entry = M.lookup(name)
    if entry then
        return true, entry
    end
    -- 尝试从 visual 中匹配
    if visual then
        entry = M.lookup(visual)
        if entry then return true, entry end
    end
    return false, nil
end

--- 批量验证一排图标
--- @param llm_results table { { name, desc, y }, ... }
--- @return table { { name_cn, name_en, desc, y, matched }, ... }
function M.verify_batch(llm_results)
    local out = {}
    for _, r in ipairs(llm_results) do
        local ok, entry = M.verify(r.name, r.desc)
        table.insert(out, {
            name_cn  = entry and entry.name_cn or ("?" .. (r.name or "unknown")),
            name_en  = entry and entry.name_en or (r.name or "unknown"),
            desc     = entry and entry.desc or (r.desc or ""),
            y        = r.y,
            matched  = ok,
        })
    end
    return out
end

--- 添加/覆盖映射
function M.register(name, config)
    M.custom[name] = config
end

return M
