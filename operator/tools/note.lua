local home = os.getenv("HOME") or "/root"
local path = os.getenv("MYAGENT_NOTES") or (home .. "/.myagent_notes")
local cmd = arg[1] or "list"

local function read_all()
    local f = io.open(path, "r")
    if not f then return {} end
    local lines = {}
    for line in f:lines() do lines[#lines + 1] = line end
    f:close()
    return lines
end

local function write_all(lines)
    local f = assert(io.open(path, "w"))
    for _, line in ipairs(lines) do f:write(line, "\n") end
    f:close()
end

local function text_arg()
    local t = {}
    for i = 2, #arg do t[#t + 1] = arg[i] end
    return table.concat(t, " ")
end

if cmd == "add" or cmd == "记" or cmd == "新" then
    local text = text_arg()
    if text == "" then
        io.stderr:write("用法: note.sh add <文本>\n")
        os.exit(2)
    end
    local f = assert(io.open(path, "a"))
    f:write(os.date("%m-%d %H:%M"), "\t", text, "\n")
    f:close()
    print("已记下: " .. text)
elseif cmd == "list" or cmd == "ls" or cmd == "列" or cmd == "待办" then
    local lines = read_all()
    if #lines == 0 then print("（没有备忘）"); os.exit(0) end
    for i, line in ipairs(lines) do
        local t, c = line:match("^(.-)\t(.*)$")
        if not t then t, c = "", line end
        print(string.format("%2d. [%s] %s", i, t, c))
    end
elseif cmd == "done" or cmd == "rm" or cmd == "del" or cmd == "完成" or cmd == "删" then
    local idx = tonumber(arg[2])
    if not idx or idx < 1 or idx % 1 ~= 0 then
        io.stderr:write("用法: note.sh done <序号>\n")
        os.exit(2)
    end
    local lines, kept = read_all(), {}
    for i, line in ipairs(lines) do
        if i ~= idx then kept[#kept + 1] = line end
    end
    write_all(kept)
    print("已删除第 " .. idx .. " 条")
elseif cmd == "clear" or cmd == "清空" then
    local f = assert(io.open(path, "w"))
    f:close()
    print("已清空备忘")
else
    io.stderr:write("用法: note.sh add <文本> | list | done <n> | clear\n")
    os.exit(2)
end
