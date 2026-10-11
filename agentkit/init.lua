-- agentkit/init.lua — 统一交互层：窗口 + OCR 定位点击（区域锚定 + 校验 + 重试）
local x11 = require("agentkit.x11")
local ocr = require("agentkit.ocr")
local voice = require("agentkit.voice")

local M = { x11 = x11, ocr = ocr, voice = voice }
local Window = x11.Window

local function tmpdir()
    local d = os.getenv("AGENTKIT_TMP") or "/tmp/agentkit"
    os.execute("mkdir -p " .. d)
    return d
end

-- 对窗口内区域做 OCR，返回带“窗口相对坐标”的框（gx,gy）
function Window:ocr(region)
    region = region or { 0, 0, self.w, self.h }
    local p = string.format("%s/ocr_%d_%06d.png", tmpdir(), self.id % 1000000,
                            math.floor(math.random() * 1e6))
    self:capture_region(region[1], region[2], region[3], region[4], p)
    local boxes = ocr.run(p)
    for _, b in ipairs(boxes) do
        b.gx = b.x + region[1]
        b.gy = b.y + region[2]
    end
    return boxes, p
end

function Window:find_text(text, region, opts)
    opts = opts or {}
    local boxes = self:ocr(region)
    for _, b in ipairs(boxes) do
        local t = b.text or ""
        if (opts.exact and t == text) or (not opts.exact and t:find(text, 1, true)) then
            return b
        end
    end
    return nil
end

-- 区域锚定的 OCR 文本点击：找不到则重试
function Window:click_text(text, region, opts)
    opts = opts or {}
    local n = opts.retries or 3
    for _ = 1, n do
        local b = self:find_text(text, region, opts)
        if b then
            self:click(b.gx + math.floor(b.w / 2), b.gy + math.floor(b.h / 2))
            return true, b
        end
        os.execute("sleep " .. (opts.wait or 0.4))
    end
    return false
end

-- 只对文本做定位（返回窗口相对中心坐标）
function Window:locate_text(text, region, opts)
    local b = self:find_text(text, region, opts)
    if not b then return nil end
    return { x = b.gx + math.floor(b.w / 2), y = b.gy + math.floor(b.h / 2), box = b }
end

-- 适配器（按需加载）
function M.app(name)
    return require("agentkit.adapters." .. name)
end

-- 控件映射（每个按钮/图标一个命名区域）
function M.map(app)
    return require("agentkit.map").load(app)
end

-- 录制器：边执行边记录，固化为可回放脚本
function M.record(app)
    return require("agentkit.record").new(app)
end

-- 批量执行 + 批量记录（生成结果集）
M.batch = require("agentkit.batch")

return M
