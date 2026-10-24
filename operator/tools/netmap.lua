local DIR = (arg[0] or ""):match("^(.*)/") or "."
package.path = DIR .. "/?.lua;" .. package.path
local cjson = require("cjson")

local OP = DIR .. "/.."
local OUT_JSON = os.getenv("DEVICE_REGISTRY") or (OP .. "/devices.json")
local OUT_MD = os.getenv("NETWORK_DOC") or (OP .. "/NETWORK.md")
local OUT_ENV = os.getenv("DEVICE_ENV") or (OP .. "/devices.env")
local HOME = os.getenv("HOME") or "/root"

local function q(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end
local function sh(cmd)
    local p = io.popen(cmd .. " 2>/dev/null")
    local s = p and (p:read("*a") or "") or ""
    if p then p:close() end
    return s
end
local function trim(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
local function exists(path)
    local f = io.open(path, "rb"); if not f then return false, 0 end
    local n = f:seek("end") or 0; f:close(); return n > 0, n
end
local function envval(key)
    if os.getenv(key) and os.getenv(key) ~= "" then return os.getenv(key) end
    local f = io.open(HOME .. "/.env", "r")
    if not f then return "" end
    local got = ""
    for line in f:lines() do
        if line:sub(1, #key + 1) == key .. "=" then
            got = trim(line:sub(#key + 2))
            if (got:sub(1,1) == "'" and got:sub(-1) == "'") or (got:sub(1,1) == '"' and got:sub(-1) == '"') then
                got = got:sub(2, -2)
            end
            break
        end
    end
    f:close()
    return got
end
local function write_file(path, text)
    local f = assert(io.open(path, "w")); f:write(text); f:close()
end

local function local_net()
    local o = sh("ip -4 -o addr show")
    local iface, ip, cidr
    for line in o:gmatch("[^\n]+") do
        local i, a, c = line:match(":%s+([%w_.-]+)%s+inet%s+([%d%.]+)/(%d+)")
        if i and a and a ~= "127.0.0.1" and not i:match("^lxc") and not i:match("^Meta") then
            iface, ip, cidr = i, a, tonumber(c); break
        end
    end
    if not ip then return nil end
    local oct = {}
    for p in ip:gmatch("%d+") do oct[#oct+1] = p end
    local prefix = table.concat({oct[1], oct[2], oct[3]}, ".")
    return { iface = iface, ip = ip, cidr = cidr or 24, prefix = prefix,
             subnet = prefix .. ".0/" .. tostring(cidr or 24) }
end

local function arp_map()
    local m = {}
    for line in sh("ip -4 neigh show"):gmatch("[^\n]+") do
        local ip, mac = line:match("^([%d%.]+)%s+dev%s+%S+%s+lladdr%s+([%x:]+)")
        if ip and mac then m[ip] = mac:lower() end
    end
    return m
end

local function gateway()
    local g = sh("ip route show default"):match("default%s+via%s+([%d%.]+)")
    return g or "192.168.1.1"
end

local function active_sweep(net)
    local script = 'ip="$1"; for p in 80 443 22 554 2020 5005 12200 5555; do timeout 0.25 bash -c "echo >/dev/tcp/$ip/$p" 2>/dev/null && echo "$ip" && break; done'
    return sh("seq 1 254 | xargs -P 64 -I{} sh -c " .. q(script) .. " _ " .. q(net.prefix .. ".{}"))
end

local function hostname(ip)
    local o = trim(sh("getent hosts " .. q(ip) .. " | head -1"))
    local h = o:match("%s+([%w_.-]+)$")
    if h and h ~= "" and h ~= ip then return h end
    return ""
end

local function title(ip)
    local o = sh("curl -sS -m 2 -L " .. q("http://" .. ip .. "/") .. " 2>/dev/null | tr '\\n' ' ' | sed -n 's/.*<title[^>]*>\\([^<]*\\)<\\/title>.*/\\1/p' | head -1")
    return trim(o):sub(1, 80)
end

local function ports(ip)
    local out = {}
    for _, p in ipairs({22, 80, 443, 554, 2020, 5005, 12200, 5555}) do
        if os.execute("timeout 0.25 bash -c " .. q("echo >/dev/tcp/" .. ip .. "/" .. p) .. " >/dev/null 2>&1") == 0 then
            out[#out + 1] = p
        end
    end
    return out
end

local OUI = {
    ["a0:36:79"] = "中国电信光猫",
    ["00:be:d5"] = "H3C",
    ["a8:6b:ad"] = "Sony",
    ["24:97:ed"] = "极空间",
    ["f8:c9:03"] = "TP-Link",
    ["8c:3d:16"] = "小机箱",
    ["04:5d:4b"] = "Intel",
}
local KNOWN_IP = {
    ["192.168.1.1"]   = { id = "gateway", name = "光猫", type = "gateway" },
    ["192.168.1.52"]  = { id = "ap", name = "H3C AP", type = "ap" },
    ["192.168.1.10"]  = { id = "main-pc", name = "主电脑", type = "computer" },
    ["192.168.1.101"] = { id = "sony-tv", name = "Sony 电视", type = "tv" },
    ["192.168.1.53"]  = { id = "nas", name = "极空间 NAS", type = "nas" },
    ["192.168.1.111"] = { id = "tplink-camera", name = "TP-Link 摄像头", type = "camera" },
}
local KNOWN_MAC = {
    ["8c:3d:16:62:3c:1e"] = { id = "small-pc", name = "小机箱", type = "computer" },
    ["a0:36:79:d5:35:e0"] = { id = "gateway", name = "光猫", type = "gateway" },
    ["00:be:d5:22:7b:3c"] = { id = "ap", name = "H3C AP", type = "ap" },
    ["a8:6b:ad:30:71:d9"] = { id = "sony-tv", name = "Sony 电视", type = "tv" },
    ["24:97:ed:30:7e:3f"] = { id = "nas", name = "极空间 NAS", type = "nas" },
    ["f8:c9:03:2d:55:45"] = { id = "tplink-camera", name = "TP-Link 摄像头", type = "camera" },
}

local function vendor(mac)
    if not mac then return "" end
    return OUI[mac:sub(1, 8)] or ""
end

local function tplink_source()
    local rtsp = envval("TPLINK_RTSP")
    local host, port, path = "192.168.1.111", "554", "/stream1"
    if rtsp ~= "" then
        local h, p, pa = rtsp:match("^rtsp://[^@]+@([^:/]+):(%d+)(/.*)$")
        if h then host, port, path = h, p, pa end
    end
    return { kind = "rtsp", env = "TPLINK_RTSP", host = host, port = tonumber(port) or 554, path = path }
end

local function ezviz_source(kind)
    local door = kind == "menkou"
    return { kind = "hls", url_file = door and "/tmp/myagent_door.url" or "/tmp/myagent_ezviz.url",
             refresh = "camera.sh --ezviz " .. kind, serial = door and "815311181" or "802657358" }
end

local function build()
    local net = local_net()
    if not net then error("找不到局域网接口") end
    local gw = gateway()
    local neigh = arp_map()
    local live = {}
    for ip in active_sweep(net):gmatch("[^\n]+") do live[ip] = true end
    live[gw] = true
    for ip in pairs(neigh) do live[ip] = true end
    local arr = {}
    local seen = {}
    local function add(ip, mac, info)
        if seen[ip] then return end
        seen[ip] = true
        local name = info and info.name or ""
        if name == "" then
            name = hostname(ip)
            if name == "" then name = vendor(mac) ~= "" and (vendor(mac) .. " 设备") or "未识别设备" end
        end
        local typ = info and info.type or "unknown"
        local p = ports(ip)
        if title(ip) ~= "" then name = name .. " · " .. title(ip) end
        arr[#arr + 1] = { id = info and info.id or ("host-" .. ip:gsub("%.", "-")),
            name = name, type = typ, ip = ip, mac = mac or "", online = true, ports = p }
    end
    for ip in pairs(live) do
        local info = KNOWN_IP[ip]
        local mac = neigh[ip]
        if mac and KNOWN_MAC[mac] then info = KNOWN_MAC[mac] end
        add(ip, mac, info)
    end
    -- 已知但暂时不在线的设备
    for _, ip in ipairs({"192.168.1.52", "192.168.1.111"}) do
        if not seen[ip] then
            local info = KNOWN_IP[ip]
            arr[#arr + 1] = { id = info.id, name = info.name, type = info.type, ip = ip,
                mac = (ip == "192.168.1.111" and "f8:c9:03:2d:55:45" or "00:be:d5:22:7b:3c"),
                online = false, ports = {} }
            seen[ip] = true
        end
    end
    -- 小机箱：按 MAC 找 IP；找不到也保留
    local small_ip, small_mac = nil, "8c:3d:16:62:3c:1e"
    for ip, mac in pairs(neigh) do if mac == small_mac then small_ip = ip end end
    if not small_ip then
        for _, d in ipairs(arr) do if d.id == "small-pc" then small_ip = d.ip end end
    end
    if not small_ip then
        arr[#arr + 1] = { id = "small-pc", name = "小机箱", type = "computer", ip = "", mac = small_mac,
            online = false, ports = {} }
    end

    local local_mac = trim(sh("cat /sys/class/net/" .. net.iface .. "/address 2>/dev/null"))
    if local_mac ~= "" then
        for _, d in ipairs(arr) do if d.id == "main-pc" then d.mac = local_mac end end
    end

    local tp = tplink_source()
    local devices = {}
    for _, d in ipairs(arr) do
        if d.id == "tplink-camera" then d.video, d.audio = tp, tp end
        devices[#devices + 1] = d
    end

    local function add_device(t)
        for _, d in ipairs(devices) do if d.id == t.id then return end end
        devices[#devices + 1] = t
    end
    local ok_k, _ = exists("/tmp/myagent_ezviz.url")
    local ok_d, _ = exists("/tmp/myagent_door.url")
    add_device({ id = "ezviz-living", name = "EZVIZ 客厅", type = "camera", ip = "", mac = "",
        online = ok_k, ports = {}, video = ezviz_source("keting"), audio = ezviz_source("keting") })
    add_device({ id = "ezviz-door", name = "EZVIZ 门口", type = "camera", ip = "", mac = "",
        online = ok_d, ports = {}, video = ezviz_source("menkou"), audio = ezviz_source("menkou") })
    add_device({ id = "usb-camera", name = "本机 USB 摄像头", type = "camera", ip = "", mac = "",
        online = true, ports = {},
        video = { kind = "v4l2", device = "/dev/video" .. (envval("CAM_USB_INDEX") ~= "" and envval("CAM_USB_INDEX") or "0") },
        audio = { kind = "alsa", device = envval("VOICE_MIC_DEV") ~= "" and envval("VOICE_MIC_DEV") or "plughw:2,0" } })
    add_device({ id = "smallpc-mic", name = "小机箱麦克风", type = "microphone", ip = small_ip or "",
        mac = small_mac, online = small_ip ~= nil, ports = {},
        audio = { kind = "remote_alsa", host = "small-pc", note = "小机箱 Comica USB，需开机/SSH" } })

    table.sort(devices, function(a, b)
        local order = { gateway=1, ap=2, ["main-pc"]=3, ["small-pc"]=4, ["sony-tv"]=5, nas=6, ["tplink-camera"]=7 }
        local oa, ob = order[a.id] or 99, order[b.id] or 99
        if oa ~= ob then return oa < ob end
        return a.id < b.id
    end)

    return {
        version = 2,
        generated = os.date("%Y-%m-%d %H:%M:%S"),
        network = { interface = net.iface, ip = net.ip, subnet = net.subnet, gateway = gw },
        devices = devices,
    }
end

local function md(reg)
    local out = { "# 设备网络拓扑（自动生成）", "",
        "> 由 `tools/netmap.sh scan` 生成；更新时间：" .. reg.generated,
        "> 本机：" .. (reg.network.ip or "?") .. " / " .. (reg.network.subnet or "?") ..
        "，网关：" .. (reg.network.gateway or "?"), "" }
    out[#out+1] = "## 拓扑"
    out[#out+1] = "```text"
    out[#out+1] = "光猫 " .. (reg.network.gateway or "?")
    out[#out+1] = "  └─ AP/交换机"
    for _, d in ipairs(reg.devices) do
        if d.type ~= "microphone" then
            local ip = d.ip ~= "" and d.ip or (d.online and (d.type == "camera" and "云端/HLS" or "本机") or "（未在线/未知）")
            out[#out+1] = "       ├─ " .. d.name .. "  " .. ip
        end
    end
    out[#out+1] = "```"
    out[#out+1] = ""
    out[#out+1] = "## 设备"
    out[#out+1] = "| ID | 名称 | IP | MAC | 类型 | 在线 | 端口 |"
    out[#out+1] = "|---|---|---|---|---|---|---|"
    for _, d in ipairs(reg.devices) do
        out[#out+1] = string.format("| %s | %s | %s | %s | %s | %s | %s |",
            d.id, d.name, d.ip ~= "" and d.ip or "-", d.mac ~= "" and d.mac or "-", d.type,
            d.online and "是" or "否", table.concat(d.ports or {}, ","))
    end
    out[#out+1] = ""
    out[#out+1] = "## 音视频源"
    out[#out+1] = "| 设备 | 视频源 | 音频源 |"
    out[#out+1] = "|---|---|---|"
    local function src(s)
        if not s then return "-" end
        if s.kind == "hls" then return "HLS 文件 " .. s.url_file .. "（自动刷新）" end
        if s.kind == "rtsp" then return "RTSP " .. s.host .. ":" .. tostring(s.port) .. s.path .. "（凭据 " .. s.env .. "）" end
        if s.kind == "v4l2" then return "V4L2 " .. s.device end
        if s.kind == "alsa" then return "ALSA " .. s.device end
        if s.kind == "remote_alsa" then return "小机箱 ALSA（" .. s.note .. "）" end
        return s.kind
    end
    for _, d in ipairs(reg.devices) do
        if d.video or d.audio then
            out[#out+1] = "| " .. d.name .. " | " .. src(d.video) .. " | " .. src(d.audio) .. " |"
        end
    end
    out[#out+1] = ""
    return table.concat(out, "\n")
end

local function env_file(reg)
    local lines = { "# 自动生成 by tools/netmap.sh；不包含密码", "CAM1_LABEL='USB'" }
    for _, d in ipairs(reg.devices) do
        if d.video and d.video.kind == "hls" then
            local n = d.id == "ezviz-living" and 2 or 3
            lines[#lines+1] = "CAM"..n.."_LABEL=" .. q(d.name)
            lines[#lines+1] = "CAM"..n.."_URL_FILE=" .. q(d.video.url_file)
        elseif d.video and d.video.kind == "rtsp" then
            lines[#lines+1] = "CAM4_LABEL=" .. q(d.name)
            lines[#lines+1] = "CAM4_HOST=" .. q(d.video.host)
            lines[#lines+1] = "CAM4_PORT=" .. tostring(d.video.port)
            lines[#lines+1] = "CAM4_PATH=" .. q(d.video.path)
        end
    end
    return table.concat(lines, "\n") .. "\n"
end

local function scan()
    local reg = build()
    write_file(OUT_JSON, cjson.encode(reg) .. "\n")
    write_file(OUT_MD, md(reg))
    write_file(OUT_ENV, env_file(reg))
    local online = 0
    for _, d in ipairs(reg.devices) do if d.online then online = online + 1 end end
    print("设备 " .. #reg.devices .. " 个，在线 " .. online .. " 个")
    for _, d in ipairs(reg.devices) do
        print(string.format("  %-14s %-18s %-16s %s", d.id, d.ip ~= "" and d.ip or "-", d.name, d.online and "在线" or "离线"))
    end
    print("已更新: " .. OUT_JSON)
    print("已更新: " .. OUT_MD)
    print("已更新: " .. OUT_ENV)
end

local function show()
    local f = io.open(OUT_JSON, "r")
    if not f then io.stderr:write("还没有扫描结果，先运行: tools/netmap.sh scan\n"); os.exit(1) end
    local raw = f:read("*a"); f:close()
    local ok, reg = pcall(cjson.decode, raw)
    if not ok then io.stderr:write("devices.json 解析失败\n"); os.exit(1) end
    print(md(reg))
end

local function sources()
    local f = io.open(OUT_JSON, "r")
    if not f then io.stderr:write("还没有扫描结果，先运行: tools/netmap.sh scan\n"); os.exit(1) end
    local raw = f:read("*a"); f:close()
    local ok, reg = pcall(cjson.decode, raw)
    if not ok then io.stderr:write("devices.json 解析失败\n"); os.exit(1) end
    for _, d in ipairs(reg.devices) do
        if d.video then print("VIDEO\t" .. d.id .. "\t" .. d.name .. "\t" .. cjson.encode(d.video)) end
        if d.audio then print("AUDIO\t" .. d.id .. "\t" .. d.name .. "\t" .. cjson.encode(d.audio)) end
    end
end

local cmd = arg[1] or "scan"
if cmd == "scan" then scan()
elseif cmd == "show" then show()
elseif cmd == "sources" then sources()
else
    io.stderr:write("用法: netmap.sh scan | show | sources\n")
    os.exit(2)
end
