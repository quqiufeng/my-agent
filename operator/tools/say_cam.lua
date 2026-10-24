local DIR = (arg[0] or ""):match("^(.*)/") or "."
package.path = DIR .. "/?.lua;" .. package.path
require("dotenv").load(os.getenv("EZVIZ_ENV") or ((os.getenv("HOME") or "/root") .. "/.env"))

local cjson = require("cjson")

local function q(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function urlencode(s)
    return (s:gsub("[^%w%-%._~]", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local API = "https://open.ys7.com"
local src, wav = "keting", nil

for _, a in ipairs(arg) do
    if a == "keting" or a == "客厅" then src = "802657358"
    elseif a == "menkou" or a == "门口" then src = "815311181"
    elseif a:match("%.wav$") or a:match("%.mp3$") or a:match("%.aac$") then wav = a
    elseif a:match("^%d+$") then src = a
    end
end

if not wav then
    io.stderr:write("用法: say_cam.sh [keting|menkou|<序列号>] <音频.wav>\n")
    os.exit(2)
end

local f = io.open(wav, "rb")
if not f then io.stderr:write("无音频: " .. wav .. "\n"); os.exit(2) end
local size = f:seek("end")
f:close()
if not size or size == 0 then io.stderr:write("无音频: " .. wav .. "\n"); os.exit(2) end

local appkey = os.getenv("EZVIZ_APPKEY") or ""
local secret = os.getenv("EZVIZ_APPSECRET") or ""
local body = "appKey=" .. urlencode(appkey) .. "&appSecret=" .. urlencode(secret)

local p = io.popen("curl -s -X POST " .. q(API .. "/api/lapp/token/get") .. " -d " .. q(body))
local raw = p and p:read("*a") or ""
if p then p:close() end
local ok, res = pcall(cjson.decode, raw)
local tok = ok and res and res.data and res.data.accessToken or nil
if not tok or tok == "" then io.stderr:write("取 token 失败\n"); os.exit(1) end

local up = "curl -s -X POST " .. q(API .. "/api/lapp/voice/upload") ..
    " -F " .. q("accessToken=" .. tok) .. " -F " .. q("voiceFile=@" .. wav)
p = io.popen(up)
raw = p and p:read("*a") or ""
if p then p:close() end
ok, res = pcall(cjson.decode, raw)
local voice_url = ok and res and res.data and res.data.url or nil
if not voice_url or voice_url == "" then io.stderr:write("上传失败\n"); os.exit(1) end

local send = "curl -s -X POST " .. q(API .. "/api/lapp/voice/send") ..
    " --data-urlencode " .. q("accessToken=" .. tok) ..
    " -d " .. q("deviceSerial=" .. src) ..
    " -d 'channelNo=1'" ..
    " --data-urlencode " .. q("fileUrl=" .. voice_url)
p = io.popen(send)
raw = p and p:read("*a") or ""
if p then p:close() end
ok, res = pcall(cjson.decode, raw)
if ok and res and (res.code == "200" or res.code == 200) then
    print("已让设备播放")
else
    local code = ok and res and res.code or "?"
    local msg = ok and res and res.msg or "响应解析失败"
    io.stderr:write("失败: " .. tostring(code) .. " " .. tostring(msg) .. "\n")
    os.exit(1)
end
