local DIR = (arg[0] or ""):match("^(.*)/") or "."
package.path = DIR .. "/?.lua;" .. package.path

local function q(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local home = os.getenv("HOME") or "/root"
local VOCAB = os.getenv("VOCAB_FILE") or (home .. "/.myagent_vocab.txt")
local CARD = os.getenv("VOCAB_CARD") or "/tmp/myagent_card.png"
local VW = tonumber(os.getenv("VOCAB_W")) or 1000
local VH = tonumber(os.getenv("VOCAB_H")) or 600
local GEO = os.getenv("VOCAB_GEO") or (VW .. "x" .. VH .. "+120+120")
local SESS = os.getenv("VOCAB_TMUX") or "vocab"

local SEED = [[
apple	苹果
banana	香蕉
weather	天气
travel	旅行
friend	朋友
happy	高兴
music	音乐
coffee	咖啡
window	窗户
mountain	山
river	河
language	语言
practice	练习
improve	提高
remember	记得
morning	早上
question	问题
answer	回答
future	未来
change	改变
]]

local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("*a"); f:close(); return s
end

local function write_file(path, s)
    local f = io.open(path, "w")
    if f then f:write(s); f:close() end
end

local function seed()
    write_file(VOCAB, SEED)
    print("[vocab] 已生成默认词表: " .. VOCAB)
end

local function lines()
    local s = read_file(VOCAB)
    if not s or s == "" then return {} end
    local t = {}
    for line in (s .. "\n"):gmatch("(.-)\n") do
        if line ~= "" then t[#t + 1] = line end
    end
    return t
end

local function render(word, sub, color)
    os.execute("luajit " .. q(DIR .. "/card.lua") .. " " .. q(CARD) .. " " ..
        q(word) .. " " .. q(sub) .. " " .. VW .. " " .. VH ..
        " 0x0b1f12 0xf4f4f4 " .. q(color or "0x9fe0b0") .. " 2>/dev/null")
end

local function lev(a, b)
    local n, m = #a, #b
    local d = {}
    for i = 0, n do d[i] = { [0] = i } end
    for j = 0, m do d[0][j] = j end
    for i = 1, n do
        for j = 1, m do
            local c = (a:sub(i, i) == b:sub(j, j)) and 0 or 1
            local v = d[i - 1][j] + 1
            if d[i][j - 1] + 1 < v then v = d[i][j - 1] + 1 end
            if d[i - 1][j - 1] + c < v then v = d[i - 1][j - 1] + c end
            d[i][j] = v
        end
    end
    return d[n][m]
end

local function match_en(said, expect)
    local a = (said or ""):lower():gsub("[^a-z]", "")
    local e = expect:lower():gsub("[^a-z]", "")
    if a == "" or e == "" then return false end
    if a == e then return true end
    if a:find(e, 1, true) then return true end
    local d = lev(a, e)
    if #e >= 6 and d <= 2 then return true end
    if d <= 1 then return true end
    return false
end

local function capture(lang)
    local fake = os.getenv("VOCAB_FAKE")
    if fake and fake ~= "" then return fake end
    local p = io.popen("SENSEVOICE_LANG=" .. q(lang or "auto") ..
        " timeout 25 /opt/my-agent/voice/listen.sh --once --no-forward 2>/dev/null")
    if not p then return "" end
    local last = ""
    for line in p:lines() do
        local t = line:match("^%[识别%]%s*(.*)$")
        if t and t ~= "" then last = t end
    end
    p:close()
    return last
end

local function cleanup()
    os.execute("pkill -f " .. q("display -update 1 " .. CARD) .. " 2>/dev/null")
    os.execute("pkill -f " .. q("display.*" .. CARD:match("([^/]+)$")) .. " 2>/dev/null")
    os.remove(CARD)
end

local function run(rounds)
    rounds = tonumber(rounds) or 99999
    if #lines() == 0 then seed() end
    os.execute("pkill -f " .. q("display -update 1 " .. CARD) .. " 2>/dev/null")
    render("Ready?", "看单词，大声读出来（练发音）")
    os.execute("setsid display -update 1 -geometry " .. q(GEO) .. " " .. q(CARD) ..
        " >/dev/null 2>&1 &")
    math.randomseed(os.time())

    for n = 1, rounds do
        local t = lines()
        if #t == 0 then break end
        local line = t[math.random(#t)]
        local en, zh = line:match("^(.-)\t(.*)$")
        if not en then en, zh = line, "" end
        if en ~= "" then
            render(en, "读一遍这个单词（练发音）")
            print("[vocab] Q" .. n .. ": " .. en .. "（" .. zh .. "）")
            local said = capture("en")
            if match_en(said, en) then
                print("[vocab]   → 发音✓ 下一个")
                render(en, "✓ 发音正确   下一个 →", "0x7fe07f")
                os.execute("sleep 1.6")
            else
                print("[vocab]   → 发音✗ (你说: " .. (said ~= "" and said or "无") .. ") 弹释义卡")
                render(en, "✗ 你读: " .. (said ~= "" and said or "没听清") .. "     " .. en .. " = " .. zh, "0xe08f8f")
                os.execute("sleep 5")
            end
        end
    end
    cleanup()
end

local cmd = arg[1] or "status"

if cmd == "seed" or cmd == "init" then
    seed()
elseif cmd == "add" then
    local en, zh = arg[2], arg[3]
    if not en or en == "" or not zh or zh == "" then
        io.stderr:write("用法: vocab.sh add <英文> <中文>\n"); os.exit(2)
    end
    local f = assert(io.open(VOCAB, "a"))
    f:write(en, "\t", zh, "\n"); f:close()
    print("已加入: " .. en .. " - " .. zh)
elseif cmd == "list" then
    if #lines() == 0 then seed() end
    for i, line in ipairs(lines()) do
        print(string.format("%6d\t%s", i, line))
    end
elseif cmd == "start" then
    if os.execute("command -v tmux >/dev/null 2>&1") ~= 0 then
        io.stderr:write("需要 tmux\n"); os.exit(1)
    end
    if os.execute("tmux has-session -t " .. q(SESS) .. " 2>/dev/null") == 0 then
        print("记单词已在运行"); os.exit(0)
    end
    local inner = "cd " .. q(DIR) .. " && DISPLAY=:0 ./vocab.sh run 2>&1 | tee /tmp/vocab.log"
    os.execute("tmux new-session -d -s " .. q(SESS) .. " " .. q(inner))
    os.execute("sleep 1")
    print("已开始记单词（看屏幕卡片读单词：读对进下一个，读错弹释义卡）")
elseif cmd == "stop" then
    os.execute("tmux kill-session -t " .. q(SESS) .. " 2>/dev/null")
    cleanup()
    print("已停止记单词")
elseif cmd == "run" then
    run(arg[2])
elseif cmd == "status" then
    if os.execute("tmux has-session -t " .. q(SESS) .. " 2>/dev/null") == 0 then
        print("记单词：运行中")
    else
        print("记单词：未运行")
    end
else
    io.stderr:write("用法: vocab.sh start|stop|status | add <英文> <中文> | list | seed\n")
    os.exit(2)
end
