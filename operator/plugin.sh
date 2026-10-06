#!/usr/bin/env bash
# operator/plugin.sh — 轻插件：扫描 tools/*.sh 的元数据，生成 TOOLS.md（工具清单 + 规则）
# 用法:
#   plugin.sh index          # 重新生成 operator/TOOLS.md（新增/删除工具后跑）
#   plugin.sh list           # 列出工具与说明
#   plugin.sh new <name>     # 生成一个新工具模板（带元数据头）
#
# 元数据写在每个 tools/<name>.sh 的头部注释里（都可选）:
#   # @desc  一句话用途
#   # @usage tools/<name>.sh <参数>
#   # @rule  给大脑的行为规则（一句话，可写多行）
#   # @order 数字（规则排序，越小越前）
# 缺省时从首个注释行 `# tools/<name>.sh — 说明` 与 `# 用法:` 行推断。
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLS="$DIR/tools"
OUT="$DIR/TOOLS.md"

get_meta() {
    local v
    v="$(sed -n "s/^# *@$2:[[:space:]]*//p" "$1" | head -1)"
    [ -z "$v" ] && v="$(sed -n "s/^# *@$2[[:space:]]\+//p" "$1" | head -1)"
    printf '%s' "$v"
}
get_desc() {
    local d; d="$(get_meta "$1" desc)"
    if [ -z "$d" ]; then
        d="$(grep -m1 '^# *\(operator/\)\?tools/' "$1" 2>/dev/null \
            | sed -E 's/^# *(operator\/)?tools\/[a-z0-9_]*\.sh//; s/^[[:space:]:-]+//; s/^—//; s/^：//; s/^[[:space:]]+//; s/[[:space:]]*$//')"
    fi
    [ -z "$d" ] && d="(无说明)"
    printf '%s' "$d"
}
get_usage() {
    local u; u="$(get_meta "$1" usage)"
    [ -z "$u" ] && u="$(grep -m1 '^# *用法' "$1" 2>/dev/null | sed -E 's/^# *用法[:：]?[[:space:]]*//')"
    [ -z "$u" ] && u="tools/$(basename "$1")"
    printf '%s' "$u"
}

case "${1:-index}" in
    list)
        for f in "$TOOLS"/*.sh; do printf '%-16s %s\n' "$(basename "$f")" "$(get_desc "$f")"; done
        ;;
    new)
        name="${2:-}"
        [ -z "$name" ] && { echo "用法: plugin.sh new <name>" >&2; exit 2; }
        t="$TOOLS/$name.sh"
        [ -e "$t" ] && { echo "已存在: $t" >&2; exit 1; }
        cat > "$t" <<EOF
#!/usr/bin/env bash
# @desc 一句话说明
# @usage tools/$name.sh <参数>
# set -uo pipefail
# TODO: 实现
EOF
        chmod +x "$t"
        echo "已创建 $t ；补好 @desc/@usage 后跑 plugin.sh index（并重启大脑）"
        ;;
    index)
        {
            echo "<!-- 自动生成 by operator/plugin.sh index —— 请勿手改；新增工具后重跑即可 -->"
            echo "# 工具与技能（白名单）"
            echo
            echo "**只能**调用下列 \`operator/tools/*.sh\`。除此之外的任何命令、文件读写、网络一律禁止。"
            echo "一条指令只调一个工具；禁止用 \`&&\`、\`;\`、\`|\`、重定向拼接（会被 guard 拦截）。"
            echo
            echo "| 工具 | 用途 | 用法 |"
            echo "|------|------|------|"
            for f in $(ls "$TOOLS"/*.sh 2>/dev/null | sort); do
                printf '| `tools/%s` | %s | `%s` |\n' "$(basename "$f")" "$(get_desc "$f")" "$(get_usage "$f")"
            done
            echo
            echo "## 通用规则"
            echo
            echo "1. 禁止读写项目源码、改系统配置、装/删软件、关机重启。"
            echo "2. 需要给非默认会话发消息时，先确认对方身份，避免误发。"
            echo "3. 不认识的请求 → 回复“这个我暂时不支持”，不要尝试绕过白名单。"
            echo "4. **浏览器只用于网页任务**：读网页/交互走 chrome-devtools MCP，禁止用 OCR 识别网页；纯信息类（时间、算数、常识）不要动用浏览器。"
            echo
            echo "## 各工具使用规则"
            echo
            # 收集带 @rule 的工具，按 @order（缺省 999）排序
            tmp="$(mktemp)"
            for f in "$TOOLS"/*.sh; do
                rule="$(get_meta "$f" rule)"
                [ -z "$rule" ] && continue
                order="$(get_meta "$f" order)"; [ -z "$order" ] && order=999
                printf '%s\t%s\n' "$order" "$rule" >> "$tmp"
            done
            n=0
            while IFS=$'\t' read -r _o rule; do
                n=$((n+1)); printf '%d. %s\n' "$n" "$rule"
            done < <(sort -n "$tmp")
            rm -f "$tmp"
            echo
            echo "_（本文件由 plugin.sh 生成，被 opencode 通过 instructions 自动加载；改工具后重跑 index 即可。）_"
        } > "$OUT"
        echo "已生成 $OUT（$(ls "$TOOLS"/*.sh | wc -l) 个工具）"
        ;;
    *)
        echo "用法: plugin.sh index | list | new <name>" >&2; exit 2
        ;;
esac
