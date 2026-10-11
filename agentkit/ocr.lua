-- agentkit/ocr.lua — PP-OCRv4（C++ 库，LuaJIT FFI 直调）
-- 依赖：libocr_simple.so + onnxruntime + models
--   需先加载 onnxruntime（libocr_simple 运行期依赖它），再加载 OCR 库。
local ffi = require("ffi")
local cjson = require("cjson")

ffi.cdef[[
typedef struct ocr_simple_t ocr_simple_t;
ocr_simple_t* ocr_simple_create(const char* det, const char* rec, const char* dict);
char*         ocr_simple_run(ocr_simple_t* h, const char* image_path);
void          ocr_simple_free(char* s);
void          ocr_simple_destroy(ocr_simple_t* h);
]]

local M = {}

local ORT = os.getenv("AGENTKIT_ORT")
    or "/data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib/libonnxruntime.so.1"
local LIB = os.getenv("AGENTKIT_OCR_LIB")
    or "/opt/WordCard/voice/libs/libocr_simple.so"
local MODELS = os.getenv("AGENTKIT_OCR_MODELS")
    or "/opt/WordCard/models/ocr/"

local lib, handle

function M.ready()
    if handle then return true end
    -- onnxruntime 必须先于 OCR 库载入（全局符号）
    pcall(function() ffi.load(ORT, true) end)
    lib = ffi.load(LIB)
    handle = lib.ocr_simple_create(
        MODELS .. "ch_PP-OCRv4_det_infer.onnx",
        MODELS .. "ch_PP-OCRv4_rec_infer.onnx",
        MODELS .. "ppocr_keys_v1.txt")
    return handle ~= nil
end

-- 返回文本框数组：{ {x,y,w,h,text}, ... }（坐标为图片内像素）
function M.run(image_path)
    if not M.ready() then return {} end
    local p = lib.ocr_simple_run(handle, image_path)
    if p == nil then return {} end
    local s = ffi.string(p)
    lib.ocr_simple_free(p)
    local ok, res = pcall(cjson.decode, s)
    if not ok or type(res) ~= "table" then return {} end
    return res
end

-- 全文（按框 y,x 排序，空格连接）
function M.text(image_path)
    local boxes = M.run(image_path)
    table.sort(boxes, function(a, b)
        if math.abs(a.y - b.y) > 6 then return a.y < b.y end
        return a.x < b.x
    end)
    local parts = {}
    for _, b in ipairs(boxes) do parts[#parts + 1] = b.text end
    return table.concat(parts, " "), boxes
end

return M
