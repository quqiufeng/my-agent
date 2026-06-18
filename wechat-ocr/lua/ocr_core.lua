-- LuaJIT FFI bindings for libwechat_ocr_core.so
local ffi = require("ffi")

ffi.cdef[[
    typedef struct ocr_engine_t ocr_engine_t;

    ocr_engine_t* ocr_create(const char* det_model_path,
                              const char* rec_model_path,
                              const char* dict_path);

    char* ocr_capture(ocr_engine_t* engine);
    void ocr_free_string(char* str);
    void ocr_destroy(ocr_engine_t* engine);
    const char* ocr_last_error(ocr_engine_t* engine);
]]

local lib = ffi.load("libwechat_ocr_core.so")

local M = {}

-- Create OCR engine
function M.create(det_model, rec_model, dict)
    local engine = lib.ocr_create(det_model, rec_model, dict)
    if engine == nil then
        return nil, "Failed to create OCR engine"
    end
    return engine
end

-- Capture screen, find WeChat window, OCR it
-- Returns:
--   on success: {win={x=..., y=..., w=..., h=...}, boxes={{x=..., y=..., w=..., h=..., text="..."}, ...}}
--   on failure: nil, error_msg
function M.capture(engine)
    local c_str = lib.ocr_capture(engine)
    if c_str == nil then
        local err = lib.ocr_last_error(engine)
        return nil, ffi.string(err)
    end

    local json_str = ffi.string(c_str)
    lib.ocr_free_string(c_str)

    local cjson = require("cjson")
    local ok, result = pcall(cjson.decode, json_str)
    if not ok then
        return nil, "JSON parse error: " .. tostring(result)
    end

    return result
end

-- Destroy OCR engine
function M.destroy(engine)
    if engine then
        lib.ocr_destroy(engine)
    end
end

return M
