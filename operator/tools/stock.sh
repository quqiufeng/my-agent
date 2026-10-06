#!/usr/bin/env bash
# tools/stock.sh — 股票行情/估值/财务（同花顺金融数据 API / fuyao.aicubes.cn）
# @desc 股票查询：行情快照 / 历史K线 / 估值 / 财务指标（同花顺数据源）
# @usage tools/stock.sh <名称或代码> | kline <名称或代码> [天数] | value <名称或代码> | fin <名称或代码> [报告期如2024-4] | list
# @rule **股票**：说“看下/查下 <股票名或代码> 行情/股价”→ `tools/stock.sh <名称或代码>`；“走势/K线”→ `kline <名称或代码> [天数]`；“估值/市盈率/市净率”→ `value <名称或代码>`；“财务/利润/ROE/毛利率”→ `fin <名称或代码> [报告期]`；“自选股”→ `list`。回微信时说清名称、数值与口径。
# @order 16
set -uo pipefail
BASE="https://fuyao.aicubes.cn"

# 凭据（~/.env 的 FUYAO_API_KEY）
[ -f "$HOME/.env" ] && { set -a; . "$HOME/.env"; set +a; }
KEY="${FUYAO_API_KEY:-}"
[ -n "$KEY" ] || { echo "缺少 FUYAO_API_KEY（请在 ~/.env 配置，见 fuyao.aicubes.cn 的 API Key 管理）" >&2; exit 3; }
command -v jq >/dev/null || { echo "需要 jq" >&2; exit 3; }

urlenc() {
    local s="$1" o="" c h i; local LC_ALL=C
    for ((i=0; i<${#s}; i++)); do c="${s:i:1}"
        case "$c" in [a-zA-Z0-9.~_-]) o+="$c";; *) printf -v h '%%%02X' "'$c"; o+="$h";; esac
    done
    printf '%s' "$o"
}
api() { curl -s --max-time 12 -H "X-api-key: $KEY" "$BASE$1"; }

# 名称/代码 -> "thscode\t名称\tasset_type"（优先 a-share 股票，其次第一个）
resolve() {
    local kw="$1" resp
    resp="$(api "/api/meta/tickers/search?q=$(urlenc "$kw")&limit=10")"
    printf '%s' "$resp" | jq -r '
        ([.data.item[]? | select(.asset_type=="a-share")][0] // .data.item[0] // empty)
        | if . == null then empty else "\(.thscode)\t\(.name)\t\(.asset_type)" end'
}

quote() {
    local thscode="$1" name="$2" asset="$3" resp ep line ts_ms ts
    case "$asset" in
        a-share-index) ep="/api/a-share-index/prices/snapshot" ;;
        *)             ep="/api/a-share/prices/snapshot" ;;
    esac
    resp="$(api "$ep?thscodes=$(urlenc "$thscode")")"
    if [ "$(printf '%s' "$resp" | jq -r '.code // 1')" != "0" ]; then
        case "$ep" in
            */a-share-index/*) ep="/api/a-share/prices/snapshot" ;;
            *)                 ep="/api/a-share-index/prices/snapshot" ;;
        esac
        resp="$(api "$ep?thscodes=$(urlenc "$thscode")")"
    fi
    if [ "$(printf '%s' "$resp" | jq -r '.code // 1')" != "0" ]; then
        echo "$thscode: 取行情失败（$(printf '%s' "$resp" | jq -r '.message // "?"')）"; return 1
    fi
    line="$(printf '%s' "$resp" | jq -r --arg n "$name" --arg ts "$thscode" '
        .data.item[0] |
        (if (.price_change>0) then "▲" elif (.price_change<0) then "▼" else "" end) as $a |
        "\($n)(\($ts))  现价 \(.last_price)  \($a)\(.price_change) (\((.price_change_ratio_pct*100|round/100))%)  开\(.open_price) 高\(.high_price) 低\(.low_price) 昨收\(.prev_price)"')"
    ts_ms="$(printf '%s' "$resp" | jq -r '.data.timestamp // empty')"
    if [ -n "$ts_ms" ]; then ts="$(date -d "@$((ts_ms/1000))" '+%Y-%m-%d %H:%M' 2>/dev/null)"; fi
    printf '%s  [%s]\n' "$line" "${ts:-未知}"
}

cmd="${1:-}"
case "$cmd" in
    ""|-h|--help|help)
        echo "用法: stock.sh <名称或代码>   |   stock.sh list" ;;
    list)
        F="${STOCK_LIST:-$HOME/.myagent_stocks.txt}"
        [ -s "$F" ] || { echo "自选股表为空: $F"; exit 0; }
        while IFS= read -r line; do
            [ -z "$line" ] && continue; case "$line" in \#*) continue;; esac
            res="$(resolve "$line")"; [ -z "$res" ] && { echo "$line: 未找到"; continue; }
            IFS=$'\t' read -r code name asset <<< "$res"
            quote "$code" "$name" "$asset"
        done < "$F" ;;
    *)
        res="$(resolve "$cmd")"
        [ -z "$res" ] && { echo "未找到: $cmd"; exit 1; }
        IFS=$'\t' read -r code name asset <<< "$res"
        quote "$code" "$name" "$asset" ;;
esac
