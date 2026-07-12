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
    -- 微信第一列图标
    Chats       = { name_cn = "聊天",     name_en = "Chats",      desc = "消息列表",   area = "col1", order = 1 },
    Chat        = { name_cn = "聊天",     name_en = "Chats",      desc = "消息列表",   area = "col1", order = 1 },
    Messages    = { name_cn = "聊天",     name_en = "Chats",      desc = "消息列表",   area = "col1", order = 1 },
    Contacts    = { name_cn = "通讯录",   name_en = "Contacts",   desc = "联系人列表", area = "col1", order = 2 },
    Friends     = { name_cn = "通讯录",   name_en = "Contacts",   desc = "联系人列表", area = "col1", order = 2 },
    Discover    = { name_cn = "发现",     name_en = "Discover",   desc = "发现页",     area = "col1", order = 3 },
    Moments     = { name_cn = "朋友圈",   name_en = "Moments",    desc = "朋友圈",     area = "col1", order = 3 },
    Me          = { name_cn = "我",       name_en = "Profile",    desc = "个人主页",   area = "col1", order = 4 },
    Profile     = { name_cn = "我",       name_en = "Profile",    desc = "个人主页",   area = "col1", order = 4 },
    Settings    = { name_cn = "设置",     name_en = "Settings",   desc = "设置页",     area = "col1", order = 5 },
    Wallet      = { name_cn = "钱包",     name_en = "Wallet",     desc = "支付/钱包",  area = "col1", order = 6 },
    Pay         = { name_cn = "钱包",     name_en = "Wallet",     desc = "支付/钱包",  area = "col1", order = 6 },
    Favorites   = { name_cn = "收藏",     name_en = "Favorites",  desc = "收藏夹",     area = "col1", order = 7 },
    Star        = { name_cn = "收藏",     name_en = "Favorites",  desc = "收藏夹",     area = "col1", order = 7 },
    More        = { name_cn = "更多",     name_en = "More",       desc = "更多功能",   area = "col1", order = 8 },
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
