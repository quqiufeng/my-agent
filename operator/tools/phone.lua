local ADB = os.getenv("ADB") or "adb"

local function q(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function cap(cmd)
    local p = io.popen(cmd .. " 2>/dev/null")
    local s = p and p:read("*a") or ""
    if p then p:close() end
    return (s:gsub("%s+$", ""))
end

local function run(cmd)
    return os.execute(cmd) == 0
end

local function require_device()
    if cap(ADB .. " get-state") == "device" then return true end
    local line = cap(ADB .. " devices | sed -n '2p'")
    if line:find("unauthorized", 1, true) then
        io.stderr:write("手机未授权：请在手机屏幕上点「允许 USB 调试」\n")
    else
        io.stderr:write("未检测到手机：请用数据线连接并开启 USB 调试\n")
    end
    os.exit(1)
end

local function need(n, usage)
    if #arg < n then io.stderr:write("用法: " .. usage .. "\n"); os.exit(2) end
end

local cmd = arg[1] or "status"
local start = 2
if cmd:sub(1, 1) == "-" then cmd = "status"; start = 1 end

local function av(i) return arg[i] end

if cmd == "status" then
    run(ADB .. " start-server >/dev/null 2>&1")
    local out = cap(ADB .. " devices -l | sed -n '2p'")
    if out == "" then print("未连接手机"); os.exit(1) end
    print(out)
    if cap(ADB .. " get-state") == "device" then
        print("型号: " .. cap(ADB .. " shell getprop ro.product.model"))
        print("安卓: " .. cap(ADB .. " shell getprop ro.build.version.release"))
        local size = cap(ADB .. " shell wm size"):gsub("^Physical size: ", "")
        print("分辨率: " .. size)
    end
elseif cmd == "screen" then
    require_device()
    local out = av(start) or ("/tmp/phone_" .. os.date("%Y%m%d_%H%M%S") .. ".png")
    if not run(ADB .. " exec-out screencap -p > " .. q(out)) then
        io.stderr:write("截屏失败\n"); os.exit(1)
    end
    local f = io.open(out, "rb")
    local sz = f and f:seek("end") or 0
    if f then f:close() end
    if not sz or sz == 0 then io.stderr:write("截屏失败（空文件）\n"); os.exit(1) end
    print(out)
elseif cmd == "tap" then
    require_device()
    need(start + 1, "phone.sh tap X Y")
    run(ADB .. " shell input tap " .. q(av(start)) .. " " .. q(av(start + 1)))
elseif cmd == "swipe" then
    require_device()
    need(start + 3, "phone.sh swipe X1 Y1 X2 Y2 [毫秒]")
    local ms = av(start + 4) or "300"
    run(ADB .. " shell input swipe " .. q(av(start)) .. " " .. q(av(start + 1)) ..
        " " .. q(av(start + 2)) .. " " .. q(av(start + 3)) .. " " .. q(ms))
elseif cmd == "text" then
    require_device()
    need(start, "phone.sh text \"文本\"")
    run(ADB .. " shell input text " .. q(av(start)))
elseif cmd == "type" then
    require_device()
    need(start, "phone.sh type \"文本\"")
    local text = av(start)
    local prev = cap(ADB .. " shell settings get secure default_input_method"):gsub("\r", "")
    run(ADB .. " shell ime enable com.android.adbkeyboard/.AdbIME >/dev/null 2>&1")
    run(ADB .. " shell ime set com.android.adbkeyboard/.AdbIME >/dev/null 2>&1")
    os.execute("sleep 1")
    local b64 = cap("printf '%s' " .. q(text) .. " | base64 -w0")
    run(ADB .. " shell am broadcast -a ADB_INPUT_B64 --es msg " .. q(b64) .. " >/dev/null 2>&1")
    os.execute("sleep 0.6")
    if prev ~= "" and prev ~= "com.android.adbkeyboard/.AdbIME" then
        run(ADB .. " shell ime set " .. q(prev) .. " >/dev/null 2>&1")
    end
elseif cmd == "key" then
    require_device()
    need(start, "phone.sh key KEYCODE")
    run(ADB .. " shell input keyevent " .. q(av(start)))
elseif cmd == "home" then
    require_device(); run(ADB .. " shell input keyevent KEYCODE_HOME")
elseif cmd == "back" then
    require_device(); run(ADB .. " shell input keyevent KEYCODE_BACK")
elseif cmd == "wake" then
    require_device(); run(ADB .. " shell input keyevent KEYCODE_WAKEUP")
elseif cmd == "open" then
    require_device()
    need(start, "phone.sh open <包名>")
    if not run(ADB .. " shell monkey -p " .. q(av(start)) ..
        " -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1") then
        io.stderr:write("启动失败：" .. av(start) .. "（用 find 确认包名）\n")
        os.exit(1)
    end
    print("已启动 " .. av(start))
elseif cmd == "find" then
    require_device()
    need(start, "phone.sh find <关键字>")
    local out = cap(ADB .. " shell pm list packages | sed 's/^package://' | grep -i -- " .. q(av(start)))
    print(out ~= "" and out or "无匹配")
elseif cmd == "apps" then
    require_device()
    print(cap(ADB .. " shell pm list packages -3 | sed 's/^package://'"))
elseif cmd == "install" then
    require_device()
    need(start, "phone.sh install <apk路径>")
    run(ADB .. " install -r " .. q(av(start)))
else
    io.stderr:write("未知子命令: " .. cmd ..
        "（status/screen/tap/swipe/text/type/key/home/back/wake/open/find/apps/install）\n")
    os.exit(2)
end
