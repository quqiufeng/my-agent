local DIR = (arg[0] or ""):match("^(.*)/") or "."
package.path = DIR .. "/?.lua;" .. package.path
require("dotenv").load()

local function q(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local kw = arg[1]
if not kw or kw == "" then
    io.stderr:write("用法: find_file.sh <关键词> [数量]\n")
    os.exit(2)
end
local limit = tonumber(arg[2]) or 15

local home = os.getenv("HOME") or "/root"
local roots = { home }
if os.execute("test -d /tmp") == 0 then roots[#roots + 1] = "/tmp" end
if os.execute("test -d /data") == 0 then roots[#roots + 1] = "/data" end

local exclude = {
    "*/.git/*", "*/node_modules/*", "*/.cache/*", "*/.local/share/Trash/*",
    "*/snap/*", "*/build/*", "*/build_*/*", "*/models/*", "*/__pycache__/*",
    "*/.venv/*", "*/venv/*", "*/.npm/*", "*/.cargo/*", "*/.rustup/*",
}

local parts = { "timeout", "25", "find" }
for _, r in ipairs(roots) do parts[#parts + 1] = q(r) end
parts[#parts + 1] = "-type"; parts[#parts + 1] = "f"
parts[#parts + 1] = "-iname"; parts[#parts + 1] = q("*" .. kw .. "*")
for _, e in ipairs(exclude) do
    parts[#parts + 1] = "-not"; parts[#parts + 1] = "-path"; parts[#parts + 1] = q(e)
end
parts[#parts + 1] = "-printf"; parts[#parts + 1] = q("%T@\\t%p\\n")

local cmd = table.concat(parts, " ") .. " 2>/dev/null | sort -rn | cut -f2-"
local p = io.popen(cmd)
local local_files = {}
if p then
    for line in p:lines() do local_files[#local_files + 1] = line end
    p:close()
end

local dav = {}
local base_url = (os.getenv("WEBDAV_URL") or ""):gsub("/+$", "")
local search = os.getenv("WEBDAV_SEARCH") or os.getenv("WEBDAV_MUSIC") or ""
if base_url ~= "" and search ~= "" then
    for root in search:gmatch("[^:]+") do
        if root ~= "" then
            local url = base_url .. root .. "/"
            local prop = io.popen("curl -sS -m 25 --netrc-file " ..
                q(home .. "/.webdav_netrc") .. " -X PROPFIND -H 'Depth: 1' " ..
                q(url) .. " 2>/dev/null")
            local xml = prop and prop:read("*a") or ""
            if prop then prop:close() end
            for href in xml:gmatch("<[Dd]:href>([^<]+)</[Dd]:href>") do
                if href ~= root .. "/" then
                    local base = href:gsub("/$", "")
                    local raw = base:match("([^/]+)$") or ""
                    local dec = raw:gsub("%%(%x%x)", function(h)
                        return string.char(tonumber(h, 16))
                    end)
                    if dec:lower():find(kw:lower(), 1, true) then
                        dav[#dav + 1] = base_url .. href
                    end
                end
            end
        end
    end
end

local all = {}
for _, v in ipairs(dav) do all[#all + 1] = v end
for _, v in ipairs(local_files) do all[#all + 1] = v end

if #all == 0 then
    print("没找到包含「" .. kw .. "」的文件")
    os.exit(1)
end

for i = 1, math.min(limit, #all) do print(all[i]) end
