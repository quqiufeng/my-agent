#!/usr/bin/env bash
# tools/dash.sh — 股票大屏：汇总指数 + 自选股 + 主指数K线，渲染白底多面板大屏图并发微信
# @desc 股票大屏（指数头+自选股+小K线，白底多面板）
# @usage tools/dash.sh [--to 会话] [--show]
# @rule **股票大屏**：说“股票大屏 / 行情大屏 / 看盘 / 大盘和自选股汇总”→ `tools/dash.sh`（生成大屏图并发来源会话）。要在大屏上直接看加 `--show`。
# @order 17
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

TO=""; SHOW=0
while [ $# -gt 0 ]; do
    case "$1" in
        --to) TO="${2:-}"; shift 2 ;;
        --show) SHOW=1; shift ;;
        *) shift ;;
    esac
done

[ -f "$HOME/.env" ] && { set -a; . "$HOME/.env"; set +a; }
KEY="${FUYAO_API_KEY:-}"
[ -n "$KEY" ] || { echo "缺少 FUYAO_API_KEY" >&2; exit 3; }
command -v jq >/dev/null || { echo "需要 jq" >&2; exit 3; }
BASE="https://fuyao.aicubes.cn"

urlenc() { local s="$1" o="" c h i; local LC_ALL=C
    for ((i=0;i<${#s};i++)); do c="${s:i:1}"
        case "$c" in [a-zA-Z0-9.~_-]) o+="$c";; *) printf -v h '%%%02X' "'$c"; o+="$h";; esac
    done; printf '%s' "$o"; }
api() { curl -s --max-time 12 -H "X-api-key: $KEY" "$BASE$1"; }

resolve() {
    local kw="$1" resp
    resp="$(api "/api/meta/tickers/search?q=$(urlenc "$kw")&limit=10")"
    printf '%s' "$resp" | jq -r '
        ([.data.item[]? | select(.asset_type=="a-share" or .asset_type=="a-share-index")][0]
         // .data.item[0] // empty)
        | if . == null then empty else "\(.thscode)\t\(.name)\t\(.asset_type)" end'
}
snapshot() { # $1 thscode $2 asset -> "price\tchg\tpct\topen\thigh\tlow"
    local ts="$1" asset="$2" ep resp
    case "$asset" in a-share-index) ep="/api/a-share-index/prices/snapshot" ;; *) ep="/api/a-share/prices/snapshot" ;; esac
    resp="$(api "$ep?thscodes=$(urlenc "$ts")")"
    if [ "$(printf '%s' "$resp" | jq -r '.code // 1')" != "0" ]; then
        case "$ep" in */a-share-index/*) ep="/api/a-share/prices/snapshot" ;; *) ep="/api/a-share-index/prices/snapshot" ;; esac
        resp="$(api "$ep?thscodes=$(urlenc "$ts")")"
    fi
    printf '%s' "$resp" | jq -r '.data.item[0] // empty |
        "\(.last_price)\t\(.price_change)\t\(.price_change_ratio_pct)\t\(.open_price)\t\(.high_price)\t\(.low_price)"'
}

DATA=/tmp/myagent_dash.tsv; : > "$DATA"

# 指数（IDX 名称 现价 涨跌 涨跌幅 今开 最高 最低）
for nm in ${DASH_INDICES:-上证指数 深证成指 创业板指 沪深300}; do
    res="$(resolve "$nm")"; [ -z "$res" ] && continue
    IFS=$'\t' read -r code name asset <<< "$res"
    row="$(snapshot "$code" "$asset")"; [ -z "$row" ] && continue
    printf 'IDX\t%s\t%s\n' "$name" "$row" >> "$DATA"
done

# 主指数K线（K 名称 收盘1,收盘2,...）
KDAYS="${DASH_KDAYS:-40}"
END=$(( $(date +%s) * 1000 )); START=$(( ($(date +%s) - KDAYS * 86400) * 1000 ))
kresp="$(api "/api/a-share-index/prices/historical?thscode=000001.SH&interval=1d&start=$START&end=$END&adjust=forward")"
[ "$(printf '%s' "$kresp" | jq -r '.code // 1')" != "0" ] && \
    kresp="$(api "/api/a-share/prices/historical?thscode=000001.SH&interval=1d&start=$START&end=$END&adjust=forward")"
closes="$(printf '%s' "$kresp" | jq -r '[.data.item[].close_price] | map(tostring) | join(",")')"
[ -n "$closes" ] && printf 'K\t上证指数\t%s\n' "$closes" >> "$DATA"

# 自选股（WL 名称 现价 涨跌 涨跌幅）
WL="${STOCK_LIST:-$HOME/.myagent_stocks.txt}"
if [ ! -s "$WL" ]; then printf '贵州茅台\n宁德时代\n比亚迪\n招商银行\n中国平安\n' > "$WL"; fi
while IFS= read -r line; do
    [ -z "$line" ] && continue; case "$line" in \#*) continue ;; esac
    res="$(resolve "$line")"; [ -z "$res" ] && continue
    IFS=$'\t' read -r code name asset <<< "$res"
    row="$(snapshot "$code" "$asset")"; [ -z "$row" ] && continue
    p="$(printf '%s' "$row" | cut -f1)"; c="$(printf '%s' "$row" | cut -f2)"; pc="$(printf '%s' "$row" | cut -f3)"
    printf 'WL\t%s\t%s\t%s\t%s\n' "$name" "$p" "$c" "$pc" >> "$DATA"
done < "$WL"

[ -s "$DATA" ] || { echo "没有数据（检查自选股/网络）" >&2; exit 1; }

OUT="/tmp/myagent_dash_$(date +%Y%m%d_%H%M%S).png"
luajit "$DIR/dash.lua" "$OUT" "$DATA" "${DASH_W:-1600}" "${DASH_H:-1000}" "行情大屏" || exit 1
echo "大屏已生成: $OUT"

[ "$SHOW" = "1" ] && display -window root "$OUT" >/dev/null 2>&1 &

if [ -n "$TO" ]; then "$DIR/wechat_send_file.sh" "$OUT" --to "$TO"; echo "已发到微信「$TO」"
else "$DIR/wechat_send_file.sh" "$OUT"; echo "已发到微信文件传输助手"; fi
