local voice = os.getenv("VOICE_DIR") or "/opt/my-agent/voice"
local flag = "/tmp/myagent_english_mode"
local sess = os.getenv("ENGLISH_TMUX") or "english"

local function q(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function run(cmd)
    return os.execute(cmd) == 0
end

local function has_session()
    return run("tmux has-session -t " .. q(sess) .. " 2>/dev/null")
end

local function has_tutor()
    -- [v] 防止 pgrep 匹配到自身 sh -c 命令行
    return run("pgrep -f " .. q("[v]oice.sh tutor") .. " >/dev/null 2>&1")
end

local cmd = arg[1] or "status"

if cmd == "start" then
    if has_session() then print("陪练已在运行"); os.exit(0) end
    if has_tutor() then print("陪练已在运行"); os.exit(0) end
    local inner = "cd " .. q(voice) .. " && DISPLAY=:0 ./voice.sh tutor 2>&1 | tee /tmp/english.log"
    run("tmux new-session -d -s " .. q(sess) .. " " .. q(inner))
    os.execute("sleep 2")
    print("已开启英语陪练（直接说英文即可，回复会朗读）；tmux attach -t " .. sess .. " 可看实时识别")
elseif cmd == "stop" then
    os.execute("tmux kill-session -t " .. q(sess) .. " 2>/dev/null")
    os.execute("pkill -f " .. q("[v]oice.sh tutor") .. " 2>/dev/null")
    os.remove(flag)
    print("已关闭英语陪练")
elseif cmd == "status" then
    if has_session() or has_tutor() then
        print("陪练：运行中")
    else
        print("陪练：未运行")
    end
else
    io.stderr:write("用法: english.sh start|stop|status\n")
    os.exit(2)
end
