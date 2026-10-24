-- device_registry.lua — 读取 netmap.sh 生成的 devices.json
local DIR = (arg[0] or ""):match("^(.*)/") or "."
package.path = DIR .. "/?.lua;" .. package.path
local cjson = require("cjson")
local M = {}

local PATH = os.getenv("DEVICE_REGISTRY") or (DIR .. "/../devices.json")
local cache, cache_mtime

function M.path() return PATH end

function M.load()
    local f = io.open(PATH, "r")
    if not f then return nil end
    local raw = f:read("*a"); f:close()
    local ok, data = pcall(cjson.decode, raw)
    if not ok or type(data) ~= "table" or not data.devices then return nil end
    cache = data
    return data
end

function M.get(id)
    local d = M.load(); if not d then return nil end
    for _, v in ipairs(d.devices) do if v.id == id then return v end end
    return nil
end

local roles = {
    keting = "ezviz-living", ["客厅"] = "ezviz-living",
    menkou = "ezviz-door", ["门口"] = "ezviz-door",
    tplink = "tplink-camera",
    usb = "usb-camera",
}

function M.device(role) return M.get(roles[role] or role) end
function M.video(role) local d = M.device(role); return d and d.video or nil end
function M.audio(role) local d = M.device(role); return d and d.audio or nil end
function M.network() local d = M.load(); return d and d.network or nil end

return M
