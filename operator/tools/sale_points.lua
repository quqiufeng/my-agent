local home = os.getenv("HOME") or "/root"
local dir = os.getenv("DOUYIN_DIR") or (home .. "/douyin/base")

local function read(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local function print_section(title, path, transform)
    io.write("\n================ ", title, " ================\n")
    local s = read(path)
    if not s then return end
    if transform then
        for line in (s .. "\n"):gmatch("(.-)\n") do
            io.write(line:gsub("^%d+_%d+%.mp4%s*", ""), "\n")
        end
    else
        io.write(s)
        if s:sub(-1) ~= "\n" then io.write("\n") end
    end
end

local readme = read(dir .. "/README.md")
if readme then
    io.write(readme)
    if readme:sub(-1) ~= "\n" then io.write("\n") end
end

print_section("卖点 (sale_points.txt)", dir .. "/sale_points.txt")
print_section("参考口播文案（账号真实稿，模仿其语气/结构；ASR 初稿，勿照抄错别字与品牌名）", dir .. "/文案_音频.txt", true)
