-- WeChat OCR Monitor (LuaJIT)
-- Captures full screen, finds WeChat by white background, OCRs, filters by position

package.path = "/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;" .. (package.path or "")
package.cpath = "/usr/local/lualib/?.so;" .. (package.cpath or "")

-- Also add local lua/ dir
local script_dir = debug.getinfo(1, "S").source:match("@?(.*/)") or ""
package.path = script_dir .. "?.lua;" .. package.path

local ocr_core = require("ocr_core")
local ffi = require("ffi")
ffi.cdef[[void usleep(unsigned int usec);]]

-- Configuration
local DET_MODEL  = "models/ch_PP-OCRv4_det_infer.onnx"
local REC_MODEL  = "models/ch_PP-OCRv4_rec_infer.onnx"
local DICT_PATH  = "ppocr_keys_v1.txt"
local INTERVAL_MS = 3000

-- Find project root (dir containing models/)
local function find_root()
    local s = script_dir
    local parent = s:match("(.*/)lua/")
    if parent then return parent end
    -- Try going up from script dir
    for _ = 1, 3 do
        local ok = os.execute("test -f \"" .. s .. "../models/ch_PP-OCRv4_det_infer.onnx\"")
        if ok then return s .. "../" end
        s = s .. "../"
    end
    return script_dir
end
local ROOT = find_root()

-- ======== POSITION-BASED FILTERING ========

-- Find sidebar/chat gap by analyzing text box x-positions
local function find_split(boxes, win_w)
    if not boxes or #boxes == 0 then
        return math.floor(win_w * 0.45)
    end
    local xs = {}
    for _, b in ipairs(boxes) do
        table.insert(xs, b.x + b.w / 2)
    end
    table.sort(xs)

    local split = math.floor(win_w * 0.45)
    local max_gap = 0
    for i = 2, #xs do
        local gap = xs[i] - xs[i-1]
        local center = (xs[i] + xs[i-1]) / 2
        if gap > max_gap and center > win_w * 0.30 and center < win_w * 0.60 then
            max_gap = gap
            split = math.floor(center)
        end
    end
    return split
end

local debug_once = false
local function filter_chat(boxes, win_w, win_h)
    local split = find_split(boxes, win_w)
    local right = math.floor(win_w * 0.88)
    local top = 35
    local bot = win_h - 200

    if not debug_once then
        io.stderr:write(string.format("[Debug] win=%dx%d split=%d(%.0f%%) boxes=%d\n",
            win_w, win_h, split, split/win_w*100, #boxes))
        io.stderr:flush()
        debug_once = true
    end

    local lines = {}
    for _, b in ipairs(boxes) do
        local cx = b.x + b.w/2
        local cy = b.y + b.h/2
        if cx >= split and cx <= right and cy >= top and cy <= bot then
            table.insert(lines, b.text)
        end
    end
    return table.concat(lines, "\n")
end

-- ======== MAIN LOOP ========

local function main()
    io.write("=== WeChat OCR Monitor (LuaJIT) ===\n")
    io.write("Root: " .. ROOT .. "\n")
    io.write("Model: " .. ROOT .. DET_MODEL .. "\n")
    io.write("Dict:  " .. ROOT .. DICT_PATH .. "\n")
    io.write("\n")
    io.flush()

    local engine, err = ocr_core.create(
        ROOT .. DET_MODEL,
        ROOT .. REC_MODEL,
        ROOT .. DICT_PATH
    )
    if not engine then
        io.stderr:write("FATAL: create failed: " .. tostring(err) .. "\n")
        os.exit(1)
    end
    io.write("OCR engine ready\n")
    io.write("First capture may take 10-20s (CUDA warmup)...\n")
    io.write("Monitoring... (Ctrl+C to stop)\n")
    io.write("==================================\n")
    io.flush()

    local prev = ""
    local cycle = 0

    while true do
        local t0 = os.clock()

        local data, err = ocr_core.capture(engine)
        if data then
            local win = data.win
            local boxes = data.boxes or {}
            if win and win.w and win.w > 0 then
                local text = filter_chat(boxes, win.w, win.h)
                if text ~= "" and text ~= prev then
                    cycle = cycle + 1
                    if prev == "" then
                        io.write("[Initial]\n")
                        io.write(text .. "\n")
                    else
                        local common = 0
                        local m = math.min(#prev, #text)
                        while common < m and prev:byte(common+1) == text:byte(common+1) do
                            common = common + 1
                        end
                        if common < #text then
                            local new = text:sub(common+1)
                            new = new:match("^[\n\r]*(.*)") or new
                            if #new > 3 then
                                io.write("[New] cycle=" .. cycle .. "\n")
                                io.write(new .. "\n")
                                io.write("---\n")
                            end
                        end
                    end
                    prev = text
                    io.flush()
                end
            end
        else
            if err then
                io.stderr:write("[Err] " .. err .. "\n")
                io.stderr:flush()
            end
        end

        local elapsed = (os.clock() - t0) * 1000
        local sleep = math.max(200, INTERVAL_MS - math.floor(elapsed))
        ffi.C.usleep(sleep * 1000)
    end
end

-- Run with error handling
local ok, err = pcall(main)
if not ok then
    io.stderr:write("FATAL: " .. tostring(err) .. "\n")
    os.exit(1)
end
