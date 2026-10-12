#!/usr/bin/env bash
# tools/dev.sh — 自我开发：项目结构/规范 + 新建「网页能力」工具（基于专用 Chrome 免授权 + CDP/DOM）
# @desc 本项目结构与规范；新能力=一个**走专用 Chrome(免授权登录)+CDP/DOM 的网页工具**（能力来自网页，安全）；支持新建/索引/提交(可回滚)/重启
# @usage tools/dev.sh info | caps | list | new <name> | index | commit [msg] | push | restart
# @rule **需求现有工具满足不了时**：`tools/dev.sh info` 读规范 → `tools/dev.sh new <name>` 生成网页工具模板（里层用专用 Chrome + `ak.cdp` 做 DOM 操作）→ 填逻辑 → `commit`（可回滚）→ `restart` 生效。**能力只来自网页（免授权 Chrome + CDP/DOM）**，不写碰本机任意资源的脚本，也不做浏览器扩展。
# @order 1
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
OP="/opt/my-agent/operator"
REPO="/opt/my-agent"
TOOLS="$DIR"

gcommit() {
  git -C "$REPO" add -A >/dev/null 2>&1
  if git -C "$REPO" -c user.name=myagent -c user.email=myagent@local \
       commit -m "$1" >/dev/null 2>&1; then echo "已提交: $1"; else echo "(无改动可提交)"; fi
}

info() {
cat <<'EOF'
# my-agent 结构与自我扩展规范

## 是什么
入口(语音/微信/定时，只产文本) → opencode 大脑 → 白名单工具 operator/tools/*.sh → 本机操作。
已有能力清单见 operator/CAPABILITIES.md（`tools/dev.sh caps`）。本文件教你怎么**扩展**它。

## 自我扩展：只做「网页能力」
现有能力不够时，**新能力 = 一个走网页的工具**：
- 底座 = 我们的**专用 Chrome：固定端口 9222、免授权、已登录**（`tools/chrome_debug.sh`）；
- 手段 = **CDP/DOM**（`ak.cdp`：goto/eval/click/fill/text/query/cookies/gemini…）；
- **能力来源 = 网页**（读页面内容、登录态下的接口/交互），**不碰**本机任意文件/进程/网络权限 → 安全；
- **不做浏览器扩展**，也不写会执行任意系统命令的脚本。

## 目录
operator/tools/*.sh     白名单工具（新能力写这里）
operator/CAPABILITIES.md 已有能力清单（进大脑上下文）
operator/TOOLS.md       工具表（由 plugin.sh 从 tools/*.sh 元数据生成）
operator/plugin.sh      `plugin.sh index` 重建 TOOLS.md
operator/opencode.json  权限（bash 仅 tools/*；MCP chrome-devtools）
agentkit/               统一库：窗口/OCR/输入/映射/CDP/语音
agentkit/tools/*.js     CDP 桥（cdp.js/cdpd.js/gemini.js）
operator/report/        Kami 排版 HTML→PNG/PDF（render.sh）

## 开发一个新「网页能力」
1. `tools/dev.sh new <name>`            生成 operator/tools/<name>.sh（含元数据 + 专用Chrome + ak.cdp 骨架）
2. 填逻辑：`ss -ltn|grep :9222 || chrome_debug.sh` → `ak.cdp.goto(url)` → `ak.cdp.eval/click/...` → 处理结果
3. `tools/dev.sh commit "feat(tool): <name> ..."`（自动/可回滚）
4. `tools/dev.sh index`（重建 TOOLS.md）→ `tools/dev.sh restart`（大脑生效）
5. 要共享：`tools/dev.sh push`

### 工具脚本骨架
#!/usr/bin/env bash
# tools/<name>.sh — 一句话
# @desc 用途（网页能力）
# @usage tools/<name>.sh <参数>
# @rule 说“<触发词>” → 用 tools/<name>.sh
# @order 50
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
ss -ltn 2>/dev/null | grep -q ':9222 ' || "$DIR/chrome_debug.sh" >/dev/null 2>&1
luajit -e 'package.path="/opt/my-agent/?.lua;/opt/my-agent/?/init.lua;"..package.path
local ak=require("agentkit"); ak.cdp.goto("https://…"); os.execute("sleep 2")
print(ak.cdp.eval("document.body.innerText"))'

## 常用积木
- 网页：固定端口 Chrome（chrome_debug.sh）+ `ak.cdp`（或大脑 MCP）；cookie+curl：cookie.sh/fetch.sh
- 出图：operator/report/render.sh in.html out.png（Kami，参考 report/*.lua）
- 发微信：tools/wechat_send.sh / wechat_send_file.sh
- 语音：ak.voice（tts/asr）
EOF
}

new_tool() {
  local n="${1:?用法: dev.sh new <name>}"
  local f="$TOOLS/$n.sh"
  [ -e "$f" ] && { echo "已存在: $f" >&2; exit 1; }
  cat > "$f" <<EOF
#!/usr/bin/env bash
# tools/$n.sh — 一句话说明（网页能力）
# @desc <用途：通过专用 Chrome(免授权登录)+CDP/DOM 从网页获取/操作>
# @usage tools/$n.sh <参数>
# @rule 说“<触发词>” → 用 \`tools/$n.sh\`
# @order 50
set -uo pipefail
DIR="\$(cd "\$(dirname "\$0")" && pwd)"
# 确保专用 Chrome（固定端口 9222、免授权、已登录）
ss -ltn 2>/dev/null | grep -q ':9222 ' || "\$DIR/chrome_debug.sh" >/dev/null 2>&1
# 通过 CDP/DOM 操作网页（能力来源=网页）
luajit -e 'package.path="/opt/my-agent/?.lua;/opt/my-agent/?/init.lua;"..package.path
local ak=require("agentkit")
ak.cdp.goto("<URL>"); os.execute("sleep 2")
print(ak.cdp.eval("document.body.innerText.slice(0,500)"))'
EOF
  chmod 755 "$f"
  echo "已创建: $f"
  gcommit "feat(tool): scaffold $n"
}

case "${1:-info}" in
  info) info ;;
  caps) cat "$OP/CAPABILITIES.md" ;;
  list) ls -1 "$TOOLS"/*.sh | sed 's#.*/##' | sort ;;
  new)  new_tool "${2:-}" ;;
  index) "$OP/plugin.sh" index; gcommit "chore(tools): regenerate TOOLS.md" ;;
  commit) gcommit "${2:-chore(dev): update}" ;;
  push) git -C "$REPO" push origin HEAD ;;
  restart) "$OP/start.sh" ;;
  *) echo "用法: dev.sh info | caps | list | new <name> | index | commit [msg] | push | restart" >&2; exit 2 ;;
esac
