#!/usr/bin/env bash
# tools/dev.sh — 自我开发：项目结构/规范 + 新建/加载 Chrome 扩展（自我扩展能力，自动提交可回滚）
# @desc 本项目结构与插件规范；自我开发的新能力**只做 Chrome 扩展**（沙箱、按 manifest 授权）；支持新建/加载扩展、自动 git 提交（可回滚）、重建索引、重启
# @usage tools/dev.sh info | list | ext new <name> | ext list | ext load <name> | ext dir <name> | index | commit [msg] | push | restart
# @rule **需求现有工具满足不了时**：`tools/dev.sh info` 读规范 → **新建 Chrome 扩展**（`ext new <name>` → 填 content/background → `ext load <name>` 生效）。**只允许用浏览器扩展扩展能力**。改动会自动 `git commit`（可回滚）；要同步远端再 `push`。
# @order 1
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
OP="/opt/my-agent/operator"
REPO="/opt/my-agent"
TOOLS="$DIR"
EXT="${AGENTKIT_EXT_DIR:-$OP/extensions}"     # 扩展放仓库内（可 git 回滚）
CORE="$REPO/agentkit"

gcommit() {  # 自动提交（可回滚）
  git -C "$REPO" add -A >/dev/null 2>&1
  if git -C "$REPO" -c user.name=myagent -c user.email=myagent@local \
       commit -m "$1" >/dev/null 2>&1; then echo "已提交: $1"; else echo "(无改动可提交)"; fi
}

info() {
cat <<'EOF'
# my-agent 结构与自我扩展规范

## 是什么
入口(语音/微信/定时，只产文本) → opencode 大脑 → 白名单工具 operator/tools/*.sh → 本机操作。
铁律：入口只产文本 · 单脑 · 能力=白名单脚本。

## 自我扩展：只做 Chrome 扩展
现有能力不够时，**新增能力=一个 Chrome 扩展（MV3）**，跑在专用 Chrome 里：
- 沙箱在浏览器内、只按 manifest 声明权限；
- 用于网页自动化/抓取/注入/调 NAS 网页端等 **web 域**任务；
- 不给机器任意 shell/文件/进程权限（安全边界）。
- 扩展放在 `operator/extensions/<name>/`（**在仓库内 → 自动 git 提交，可回滚**）。

## 目录
operator/tools/*.sh     白名单工具
operator/extensions/*/  自我开发的 Chrome 扩展
operator/plugin.sh      扫描 tools/*.sh → 生成 TOOLS.md
operator/opencode.json  权限（bash 仅 tools/*；MCP chrome-devtools）
agentkit/               统一库（LuaJIT+FFI）
operator/report/        Kami 排版 HTML→PNG/PDF
agentkit/tools/*.js     CDP 桥

## 开发一个扩展（闭环）
1. tools/dev.sh ext new <name>      生成 operator/extensions/<name>/（自动 git commit）
2. 填 manifest 权限 + content.js/background.js
3. tools/dev.sh commit "feat(ext): <name> ..."   提交改动（可回滚：git revert/checkout）
4. tools/dev.sh ext load <name>     用专用 Chrome(9222) 带 --load-extension 重启 → 生效
5. tools/dev.sh push                同步到 GitHub

### manifest.json（MV3 最小）
{ "manifest_version":3,"name":"<name>","version":"0.1",
  "permissions":["storage","scripting","activeTab"],
  "host_permissions":["<all_urls>"],
  "background":{"service_worker":"background.js"},
  "content_scripts":[{"matches":["<all_urls>"],"js":["content.js"]}] }

## 常用积木
- 网页：固定端口 Chrome（tools/chrome_debug.sh）+ CDP DOM（ak.cdp / MCP）；或 cookie+curl（cookie.sh/fetch.sh）
- 出图：operator/report/render.sh in.html out.png（Kami）
- 发微信：tools/wechat_send.sh / wechat_send_file.sh
- 语音：agentkit.voice（tts/asr）
EOF
}

ext_new() {
  local n="${1:?用法: dev.sh ext new <name>}"
  local d="$EXT/$n"
  mkdir -p "$EXT"
  [ -e "$d" ] && { echo "已存在: $d" >&2; exit 1; }
  mkdir -p "$d"
  cat > "$d/manifest.json" <<EOF
{
  "manifest_version": 3,
  "name": "$n",
  "version": "0.1",
  "description": "my-agent extension: $n",
  "permissions": ["storage", "scripting", "activeTab"],
  "host_permissions": ["<all_urls>"],
  "background": { "service_worker": "background.js" },
  "content_scripts": [
    { "matches": ["<all_urls>"], "js": ["content.js"], "run_at": "document_idle" }
  ],
  "action": { "default_title": "$n" }
}
EOF
  printf '// background.js — %s 后台逻辑（chrome.runtime.onMessage 等）\n' "$n" > "$d/background.js"
  printf '// content.js — %s 页面注入（DOM 操作/采集）\n' "$n" > "$d/content.js"
  echo "已创建扩展: $d"
  gcommit "feat(ext): scaffold $n"
  echo "编辑 content.js/background.js 后: tools/dev.sh ext load $n"
}

ext_load() {
  local n="${1:?用法: dev.sh ext load <name>}"
  local d="$EXT/$n"
  [ -d "$d" ] || { echo "无此扩展: $d" >&2; exit 1; }
  local port="${2:-9222}"
  local profile="$HOME/.chrome-debug-profile"
  local loads=(); for x in "$EXT"/*/; do [ -f "$x/manifest.json" ] && loads+=("${x%/}"); done
  local extarg; extarg="$(IFS=,; echo "${loads[*]}")"
  for pid in $(ps -eo pid,comm | awk '$2=="chrome"{print $1}'); do kill -9 "$pid" 2>/dev/null; done
  sleep 2
  local P XA; P=$(pgrep -x pcmanfm-qt | head -1)
  XA=$(tr '\0' '\n' < "/proc/$P/environ" 2>/dev/null | sed -n 's/^XAUTHORITY=//p')
  setsid env DISPLAY=:0 XAUTHORITY="$XA" google-chrome \
    --remote-debugging-port="$port" --user-data-dir="$profile" \
    --load-extension="$extarg" --disable-extensions-except="$extarg" \
    --no-first-run --no-default-browser-check >/tmp/opencode/chrome_ext.log 2>&1 </dev/null &
  sleep 5
  ss -ltn 2>/dev/null | grep -q ":$port " && echo "Chrome 已带扩展启动（端口 $port；加载 ${#loads[@]} 个）" \
    || { echo "启动失败，见 /tmp/opencode/chrome_ext.log" >&2; exit 1; }
}

case "${1:-info}" in
  info) info ;;
  list) ls -1 "$TOOLS"/*.sh | sed 's#.*/##' | sort ;;
  index) "$OP/plugin.sh" index; gcommit "chore(tools): regenerate TOOLS.md" ;;
  commit) gcommit "${2:-chore(dev): update}" ;;
  push) git -C "$REPO" push origin HEAD ;;
  restart) "$OP/start.sh" ;;
  ext)
    case "${2:-}" in
      new)  ext_new "${3:-}" ;;
      load) ext_load "${3:-}" "${4:-9222}" ;;
      list) ls -1d "$EXT"/*/ 2>/dev/null | xargs -n1 basename 2>/dev/null || echo "(无)" ;;
      dir)  echo "$EXT/${3:?用法: dev.sh ext dir <name>}" ;;
      *) echo "用法: dev.sh ext new|load|list|dir <name>" >&2; exit 2 ;;
    esac ;;
  *) echo "用法: dev.sh info | list | ext new|load|list|dir <name> | index | commit [msg] | push | restart" >&2; exit 2 ;;
esac
