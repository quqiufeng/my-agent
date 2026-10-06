#!/usr/bin/env bash
# tools/note.sh — 备忘 / 待办（存 ~/.myagent_notes，纯文本）
# @rule **备忘/待办**：说“记一下…/备忘…/待办…”→ `note.sh add "…"`；“有什么待办/列出备忘”→ `note.sh list`；“完成第 N 条/删第 N 条”→ `note.sh done N`；“清空”→ `clear`。
# @order 12
# 用法:
#   tools/note.sh add <文本>   # 记一条
#   tools/note.sh list         # 列出（带序号）
#   tools/note.sh done <n>     # 删第 n 条
#   tools/note.sh clear        # 清空
set -uo pipefail
F="${MYAGENT_NOTES:-$HOME/.myagent_notes}"
touch "$F" 2>/dev/null || true

cmd="${1:-list}"; shift || true
case "$cmd" in
    add|记|新)
        [ -z "${*:-}" ] && { echo "用法: note.sh add <文本>" >&2; exit 2; }
        printf '%s\t%s\n' "$(date '+%m-%d %H:%M')" "$*" >> "$F"
        echo "已记下: $*"
        ;;
    list|ls|列|待办)
        if [ ! -s "$F" ]; then echo "（没有备忘）"; exit 0; fi
        n=0
        while IFS= read -r line; do
            n=$((n+1))
            t="${line%%$'\t'*}"; c="${line#*$'\t'}"
            printf '%2d. [%s] %s\n' "$n" "$t" "$c"
        done < "$F"
        ;;
    done|rm|del|完成|删)
        idx="${1:-}"
        [[ "$idx" =~ ^[0-9]+$ ]] || { echo "用法: note.sh done <序号>" >&2; exit 2; }
        awk -v k="$idx" 'BEGIN{n=0} {n++; if(n!=k) print}' "$F" > "$F.tmp" && mv "$F.tmp" "$F"
        echo "已删除第 $idx 条"
        ;;
    clear|清空)
        : > "$F"; echo "已清空备忘"
        ;;
    *)
        echo "用法: note.sh add <文本> | list | done <n> | clear" >&2; exit 2
        ;;
esac
