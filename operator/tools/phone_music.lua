local DIR = (arg[0] or ""):match("^(.*)/") or "."
package.path = DIR .. "/?.lua;" .. package.path
local termexec = require("termexec")

local HOST = os.getenv("SMALLPC_HOST") or "quqiufeng@192.168.1.105"
local PKG = "com.luna.music"

local function q(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function remote(script, timeout)
    return termexec.run("ssh -o BatchMode=yes -o ConnectTimeout=5 " ..
        q(HOST) .. " " .. q(script), timeout)
end

local function finish(rc, out)
    io.write(out or "")
    if rc == nil then io.stderr:write("命令超时\n"); os.exit(1) end
    os.exit(rc == 0 and 0 or 1)
end

local cmd = arg[1]
if cmd == "play" then
    local rc = os.execute(q(DIR .. "/phone_audio.sh") .. " start")
    if rc ~= 0 then os.exit(1) end

    local script = [=[
set -u
SERIAL="$(adb devices | awk '$2=="device" && $1 !~ /:/ {print $1; exit}')"
[ -n "$SERIAL" ] || { echo "未发现 USB 手机设备" >&2; exit 1; }
if ! adb -s "$SERIAL" shell pm list packages | grep -q '^package:]=] .. PKG .. [=[$'; then
    echo "手机未安装汽水音乐（]=] .. PKG .. [=[）" >&2
    exit 1
fi
adb -s "$SERIAL" shell input keyevent 224 >/dev/null 2>&1 || true
adb -s "$SERIAL" shell wm dismiss-keyguard >/dev/null 2>&1 || true
adb -s "$SERIAL" shell monkey -p ']=] .. PKG .. [=[' -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 2
adb -s "$SERIAL" shell cmd media_session dispatch play >/dev/null 2>&1 || true
sleep 1
echo "已打开汽水音乐，声音走小音响（$SERIAL）"
]=]
    local rc2, out = remote(script, 60)
    finish(rc2, out)
elseif cmd == "stop" then
    local rc = os.execute(q(DIR .. "/phone_audio.sh") .. " stop")
    os.exit(rc == 0 and 0 or 1)
else
    io.stderr:write("用法: tools/phone_music.sh play|stop\n")
    os.exit(2)
end
