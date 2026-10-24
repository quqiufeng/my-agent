local DIR = (arg[0] or ""):match("^(.*)/") or "."
package.path = DIR .. "/?.lua;" .. package.path
local termexec = require("termexec")

local HOST = os.getenv("SMALLPC_HOST") or "quqiufeng@192.168.1.105"
local PORT = os.getenv("SMALLPC_CDP_PORT") or "9222"

local function q(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function urlencode(s)
    return (s:gsub("[^%w%-%._~]", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local function remote(script, timeout)
    return termexec.run("ssh -o BatchMode=yes -o ConnectTimeout=5 " ..
        q(HOST) .. " " .. q(script), timeout)
end

if arg[1] ~= "open" then
    io.stderr:write("用法: tools/living_chrome.sh open <http/https URL>\n")
    os.exit(2)
end
local url = arg[2] or ""
if url == "" then
    io.stderr:write("用法: tools/living_chrome.sh open <http/https URL>\n")
    os.exit(2)
end
if not url:match("^https?://") then
    io.stderr:write("只允许 http/https URL\n")
    os.exit(2)
end

local check = "curl -fsS --max-time 2 http://127.0.0.1:" .. PORT .. "/json/version >/dev/null 2>&1"
local rc = remote(check, 20)
if rc ~= 0 then
    local start = [=[
set -e
PORT=]=] .. PORT .. [=[
AUTH="$(ps -eo args | grep '[X]org' | sed -n 's/.*-auth \([^ ]*\).*/\1/p' | head -1)"
[ -n "$AUTH" ] || { echo '找不到 Xorg XAUTHORITY' >&2; exit 1; }
sudo -n env DISPLAY=:0 XAUTHORITY="$AUTH" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus" \
  runuser -u "$(id -un)" -- nohup google-chrome \
  --remote-debugging-port="$PORT" --remote-allow-origins='*' \
  --user-data-dir="$HOME/.chrome-debug" \
  --no-first-run --no-default-browser-check about:blank \
  >/tmp/living-chrome.log 2>&1 </dev/null &
for i in $(seq 1 20); do
  curl -fsS --max-time 1 "http://127.0.0.1:$PORT/json/version" >/dev/null 2>&1 && exit 0
  sleep 0.5
done
echo "小机箱 Chrome 调试端口未启动，见 /tmp/living-chrome.log" >&2
tail -5 /tmp/living-chrome.log >&2
exit 1
]=]
    local rc2, out = remote(start, 40)
    if rc2 == nil or rc2 ~= 0 then
        io.write(out or "")
        io.stderr:write("小机箱 Chrome 调试端口未启动\n")
        os.exit(1)
    end
end

local api = "http://127.0.0.1:" .. PORT .. "/json/new?" .. urlencode(url)
local rc3, resp = remote("curl -fsS -X PUT " .. q(api), 30)
if rc3 == nil or rc3 ~= 0 then
    io.write(resp or "")
    io.stderr:write("打开页面失败\n")
    os.exit(1)
end

local id = resp and resp:match('"id"%s*:%s*"([^"]+)"') or nil
if id and id ~= "" then
    remote("curl -fsS " .. q("http://127.0.0.1:" .. PORT .. "/json/activate/" .. id) ..
        " >/dev/null 2>&1", 20)
end
print("已打开: " .. url)
