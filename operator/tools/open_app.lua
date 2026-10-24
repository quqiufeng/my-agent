local app = arg[1] or ""

local cmds = {
    chrome = "google-chrome",
    ["google-chrome"] = "google-chrome",
    terminal = "xterm",
    xterm = "xterm",
    files = "nautilus",
    nautilus = "nautilus",
    editor = "code",
    code = "code",
    wechat = "/opt/wechat/wechat",
}

local cmd = cmds[app]
if not cmd then
    io.stderr:write("不支持的应用: " .. (app == "" and "空" or app) ..
        "（可用: chrome terminal files editor wechat）\n")
    os.exit(2)
end

os.execute("setsid " .. cmd .. " >/dev/null 2>&1 &")
os.execute("sleep 1")
print("已打开 " .. app)
