local DIR = (arg[0] or ""):match("^(.*)/") or "."
package.path = DIR .. "/?.lua;" .. package.path
local termexec = require("termexec")

local HOST = os.getenv("SMALLPC_HOST") or "quqiufeng@192.168.1.105"

local function q(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function remote(script, timeout)
    return termexec.run("ssh -o BatchMode=yes -o ConnectTimeout=5 " ..
        q(HOST) .. " " .. q(script), timeout)
end

local function finish(rc, output)
    io.write(output or "")
    if rc == nil then io.stderr:write("命令超时\n"); os.exit(1) end
    os.exit(rc == 0 and 0 or 1)
end

local cmd = arg[1]
if cmd == "start" then
    local rc, out = remote([=[
set -u
if pgrep -f 'scrcpy.*--audio-source=playback' >/dev/null 2>&1; then
    echo "scrcpy 音频已在运行"
    exit 0
fi
SERIAL="$(adb devices | awk '$2=="device" && $1 !~ /:/ {print $1; exit}')"
[ -n "$SERIAL" ] || { echo "未发现 USB 手机设备" >&2; exit 1; }
AUTH="$(ps -eo args | grep '[X]org' | sed -n 's/.*-auth \([^ ]*\).*/\1/p' | head -1)"
[ -n "$AUTH" ] || { echo "找不到 XAUTHORITY" >&2; exit 1; }
export DISPLAY=:0 XAUTHORITY="$AUTH" XDG_RUNTIME_DIR="/run/user/$(id -u)"
nohup scrcpy -s "$SERIAL" --no-window --no-video \
    --audio-source=playback --audio-codec=opus --audio-buffer=200 \
    > /tmp/scrcpy-audio.log 2>&1 </dev/null &
echo $! > /tmp/scrcpy-audio.pid
sleep 3
if kill -0 "$(cat /tmp/scrcpy-audio.pid)" 2>/dev/null; then
    echo "已启动手机音频 → 小音响（$SERIAL）"
else
    echo "启动失败：" >&2
    tail -8 /tmp/scrcpy-audio.log >&2
    exit 1
fi
]=], 40)
    finish(rc, out)
elseif cmd == "stop" then
    local rc, out = remote([=[
if [ -f /tmp/scrcpy-audio.pid ]; then
    kill "$(cat /tmp/scrcpy-audio.pid)" 2>/dev/null || true
    rm -f /tmp/scrcpy-audio.pid
fi
pkill -f 'scrcpy.*--audio-source=playback' 2>/dev/null || true
echo "已停止手机音频转发（手机播放不受影响）"
]=], 30)
    finish(rc, out)
elseif cmd == "status" then
    local rc, out = remote([=[
if pgrep -f 'scrcpy.*--audio-source=playback' >/dev/null 2>&1; then
    echo "音频转发: 运行中 (PID $(pgrep -f 'scrcpy.*--audio-source=playback' | head -1))"
else
    echo "音频转发: 已停止"
fi
adb devices | awk 'NR==1{next} NF{print "手机: "$1" "$2}'
]=], 30)
    finish(rc, out)
else
    io.stderr:write("用法: tools/phone_audio.sh start|stop|status\n")
    os.exit(2)
end
