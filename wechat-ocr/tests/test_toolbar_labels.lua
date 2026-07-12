#!/usr/bin/env luajit
-- VLM 识别第三列格式工具栏图标英文名

package.path = "/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;/opt/my-agent/wechat-ocr/lua/?.lua;" .. (package.path or "")
package.cpath = "/usr/local/lualib/?.so;" .. (package.cpath or "")

local ffi = require("ffi")
ffi.cdef[[
    void usleep(unsigned int);
    typedef struct ocr_engine_t ocr_engine_t;
    ocr_engine_t* ocr_create(const char*, const char*, const char*);
    char*         ocr_capture(ocr_engine_t*);
    void          ocr_free_string(char*);
    void          ocr_destroy(ocr_engine_t*);
    int  joycaption_init(const char*, const char*, int);
    const char* joycaption_analyze(const char*, const char*);
    void joycaption_free();
]]

local MODEL = "/data/models/Qwen2.5-VL-3B-Instruct-Q4_K_M.gguf"
local MMPROJ = "/data/models/mmproj-Qwen2.5-VL-3B-Instruct-Q8_0.gguf"
local LIBJOY = "/opt/my-agent/joycaption-wrapper/libjoycaption.so"

local function printf(...) io.write(string.format(...)); io.flush() end

-- 激活微信
os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
ffi.C.usleep(500000)

-- 窗口几何
local geo = io.popen("xdotool getactivewindow getwindowgeometry 2>/dev/null"):read("*a")
local wx = tonumber(geo:match("Position: (%d+)"))
local wy = tonumber(geo:match(",(%d+)"))
local ww = tonumber(geo:match("Geometry: (%d+)"))
local wh = tonumber(geo:match("x(%d+)"))
if not wx then printf("❌ 获取窗口失败\n"); os.exit(1) end
printf("窗口: (%d,%d) %dx%d\n", wx, wy, ww, wh)

-- 第三列用 OCR 获取边界
local function get_col3_bounds()
    local lib = ffi.load("libwechat_ocr_core.so")
    local e = lib.ocr_create(
        "/opt/my-agent/wechat-ocr/models/ch_PP-OCRv4_det_infer.onnx",
        "/opt/my-agent/wechat-ocr/models/ch_PP-OCRv4_rec_infer.onnx",
        "/opt/my-agent/wechat-ocr/ppocr_keys_v1.txt")
    if e and e ~= ffi.NULL then
        local s = lib.ocr_capture(e)
        if s and s ~= ffi.NULL then
            local d = require("cjson").decode(ffi.string(s))
            lib.ocr_free_string(s)
            lib.ocr_destroy(e)
            return d.win.x - wx, d.win.w
        end
        lib.ocr_destroy(e)
    end
    return 0, ww
end

local col3_x, col3_w = get_col3_bounds()
printf("第三列: x=%d w=%d\n", col3_x, col3_w)

-- 裁剪工具栏区域（底部 ~430px 处，高 55px）
local tool_y = wh - 430
os.execute(string.format("import -window root -crop %dx%d+%d+%d +repage '/tmp/wx_toolbar.png' 2>/dev/null",
    col3_w, 55, wx + col3_x, wy + tool_y))

-- 加载 VLM
printf("加载 VLM...\n")
local libjoy = ffi.load(LIBJOY)
local ok = libjoy.joycaption_init(MODEL, MMPROJ, 1)
if ok ~= 0 then
    printf("❌ VLM 加载失败\n")
    os.exit(1)
end
printf("✅ VLM 加载成功\n\n")

-- 识别
local prompt = [[You are looking at the formatting toolbar of a WeChat chat window.
List each icon from left to right. For each one give:
- Number (1, 2, 3...)
- English name of what it represents (e.g., "Bold", "Italic", "Emoji", "Image", etc.)
- Brief visual description

Format: "1. Bold - B icon"
]]

local result = ffi.string(libjoy.joycaption_analyze("/tmp/wx_toolbar.png", prompt))
printf("=== 工具栏图标 ===\n%s\n", result)

-- VLM 英文名 → 实际功能映射表
local toolbar_map = {
    Emoji   = "表情",
    Cube    = "发送收藏",
    Folder  = "发送文件",
    Scissors= "截图",
    Chat    = "聊天记录",
    Phone   = "通话",
}
printf("\n=== 名称映射 ===\n")
for line in result:gmatch("[^\n]+") do
    local name = line:match("^%d+%.%s*(%w+)")
    if name then
        local cn = toolbar_map[name] or ("?" .. name)
        printf("  %s → %s\n", name, cn)
    end
end

libjoy.joycaption_free()
