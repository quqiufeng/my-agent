local Xdo = require("xdo")

local pattern = os.getenv("OPENCODE_WINDOW_PATTERN") or "OC"
local msg = arg[1] or "继续"
local minimize = os.getenv("OPENCODE_MINIMIZE") ~= "0"
local dry = os.getenv("DRY_RUN") == "1"

local d, err = Xdo.new()
if not d then io.stderr:write("xdo: ", err, "\n"); os.exit(1) end

local wins = d:find(pattern)
if #wins == 0 then
    io.stderr:write("找不到标题匹配 " .. pattern .. " 的窗口\n")
    d:close()
    os.exit(1)
end

local w = wins[1]
if not w.geom then
    io.stderr:write("窗口没有几何信息\n")
    d:close()
    os.exit(1)
end

if dry then
    print(string.format("dry-run: %s (%d) %dx%d @%d,%d", w.name, w.id, w.geom.w, w.geom.h, w.geom.x, w.geom.y))
    print("dry-run: " .. msg)
    d:close()
    os.exit(0)
end

if not d:activate(w.id) then
    io.stderr:write("激活窗口失败\n")
    d:close()
    os.exit(1)
end

d:click(w.id, 50, 39)
d:click(w.id, math.floor(w.geom.w / 5), w.geom.h - 120)
d:type(0, msg)
d:key(0, "Return")
if minimize then d:minimize(w.id) end
d:close()
print("已向窗口 " .. w.id .. " 发送: " .. msg)
