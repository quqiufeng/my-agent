-- Google AI Mode 问答流程
-- 1. 新空白标签 → 2. 输入问题 → 3. 搜索 → 4. 等回答 → 5. 获取内容

local ffi = require("ffi")
ffi.cdef[[int usleep(unsigned int);]]
local chrome = require("wechat_ocr.chrome")

chrome.new_tab()
ffi.C.usleep(1000000)

-- 输入问题 + 回车搜索
chrome.type("chrome mcp 有什么好玩的 玩法")
ffi.C.usleep(500000)
os.execute("xdotool key Return 2>/dev/null")
ffi.C.usleep(5000000)

-- 截图 + OCR 读结果
chrome.screenshot("/tmp/google_ai_result.png")

local cjson = require("cjson")
local lib = ffi.load("libwechat_ocr_core.so")
ffi.cdef[[
    typedef struct ocr_engine_t ocr_engine_t;
    ocr_engine_t* ocr_create(const char*,const char*,const char*);
    char* ocr_capture_file(ocr_engine_t*, const char*, int, int);
    void ocr_free_string(char*);
    void ocr_destroy(ocr_engine_t*);
]]
local e = lib.ocr_create("/opt/my-agent/wechat-ocr/models/ch_PP-OCRv4_det_infer.onnx",
                          "/opt/my-agent/wechat-ocr/models/ch_PP-OCRv4_rec_infer.onnx",
                          "/opt/my-agent/wechat-ocr/ppocr_keys_v1.txt")
if e and e ~= ffi.NULL then
    local s = lib.ocr_capture_file(e, "/tmp/google_ai_result.png", 0, 0)
    if s and s ~= ffi.NULL then
        local d = cjson.decode(ffi.string(s))
        lib.ocr_free_string(s)
        print("\n=== 搜索结果 ===")
        for _, b in ipairs(d.boxes or {}) do
            if #b.text > 3 then print(b.text) end
        end
    end
    lib.ocr_destroy(e)
end
print("\n完成")
