#!/usr/bin/env bash
# tools/quote_web.sh — 看行情：浏览器打开搜狐行情页（个股/指数），全屏截图发微信
# @desc 看行情（浏览器打开搜狐行情页并全屏截图发微信）
# @usage tools/quote_web.sh [名称或代码] [--to 会话]
# @rule **看行情/看盘/大盘**：说“看下<股票>行情 / 大盘怎么样 / 看盘 / 行情截图”→ `tools/quote_web.sh [名称或代码]`（不传=上证指数）。它会用浏览器打开搜狐行情页并全屏截图发来源会话。
# @order 18
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
export DISPLAY="${DISPLAY:-:0}"

TO=""; KW=""
while [ $# -gt 0 ]; do
    case "$1" in
        --to) TO="${2:-}"; shift 2 ;;
        *) [ -z "$KW" ] && KW="$1"; shift ;;
    esac
done

# 解析代码（用 fuyao 检索）→ 搜狐 URL
SOHU="https://q.stock.sohu.com/zs/000001/index.shtml"   # 默认上证指数
if [ -n "$KW" ]; then
    KEY="$(sed -n 's/^FUYAO_API_KEY=//p' "$HOME/.env" 2>/dev/null | head -1 | tr -d "'\"")"
    if [ -n "$KEY" ]; then
        enc="$(printf '%s' "$KW" | jq -sRr @uri 2>/dev/null)"
        resp="$(curl -s --max-time 12 -H "X-api-key: $KEY" \
            "https://fuyao.aicubes.cn/api/meta/tickers/search?q=$enc&limit=10")"
        read -r ts ticker asset <<< "$(printf '%s' "$resp" | jq -r '
            ([.data.item[]?|select(.asset_type=="a-share" or .asset_type=="a-share-index")][0] // .data.item[0] // empty)
            | if .==null then "" else "\(.thscode) \(.ticker) \(.asset_type)" end')"
        if [ -n "${ticker:-}" ]; then
            case "$asset" in
                a-share-index) SOHU="https://q.stock.sohu.com/zs/${ticker}/index.shtml" ;;
                *)             SOHU="https://q.stock.sohu.com/cn/${ticker}/index.shtml" ;;
            esac
        fi
    fi
fi
echo "打开: $SOHU"

# 在现有 Chrome 里打开（已有实例会新开标签）
setsid google-chrome "$SOHU" >/dev/null 2>&1 &
sleep 8
cid="$(xdotool search --name 'Google Chrome' 2>/dev/null | head -1)"
[ -n "$cid" ] && xdotool windowactivate --sync "$cid"   # 把 Chrome 提到前台再截屏
sleep 3

# 全屏截图（优先系统 Print 自动存图，失败用 import）
OUT="/tmp/myagent_quote_$(date +%Y%m%d_%H%M%S).png"
if command -v import >/dev/null; then
    import -window root "$OUT" 2>/dev/null || true
fi
if [ ! -s "$OUT" ]; then echo "截图失败" >&2; exit 1; fi
echo "截图: $OUT"

if [ -n "$TO" ]; then "$DIR/wechat_send_file.sh" "$OUT" --to "$TO"; echo "已发到微信「$TO」"
else "$DIR/wechat_send_file.sh" "$OUT"; echo "已发到微信文件传输助手"; fi
