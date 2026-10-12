#!/usr/bin/env bash
# tools/english_daily.sh — 每日英语：随机科技媒体文章 → Google AI 中英对照 → Kami 排版图 → 发微信
# @desc 从多家科技媒体(HN/Ars/TechCrunch/Verge/Wired/Engadget/Register/BBC/MIT)每天随机取一篇英文 → Gemini 中英对照+生词 → 图文发微信（图底含原文来源 URL）
# @usage tools/english_daily.sh [<主题> | --url <url>] [--words N] [--level B1-B2] [--display] [--to 会话] [--no-send]
# @rule 用户说“每日英语 / 英语短文 / 学英语 / 来篇英语文章” → `tools/english_daily.sh`（默认随机科技媒体，出图+发微信）；只要文本加 `--display`。
# @order 24
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
REPORT="/opt/my-agent/operator/report"
CORE_CDP="/opt/my-agent/agentkit/tools/cdp.js"

SOURCES=(
  "https://hnrss.org/frontpage"
  "https://feeds.arstechnica.com/arstechnica/index"
  "https://techcrunch.com/feed/"
  "https://www.theregister.com/headlines.atom"
  "https://www.engadget.com/rss.xml"
  "https://www.theverge.com/rss/index.xml"
  "https://www.wired.com/feed/rss"
  "http://feeds.bbci.co.uk/news/technology/rss.xml"
  "https://www.technologyreview.com/feed/"
)

TOPIC=""; URL=""; WORDS=180; LEVEL="B1-B2"; DISP=0; TO="文件传输助手"; SEND=1
while [ $# -gt 0 ]; do
  case "$1" in
    --url) URL="${2:-}"; shift 2 ;;
    --words) WORDS="${2:-180}"; shift 2 ;;
    --level) LEVEL="${2:-B1-B2}"; shift 2 ;;
    --display) DISP=1; SEND=0; shift ;;
    --to) TO="${2:-文件传输助手}"; shift 2 ;;
    --no-send) SEND=0; shift ;;
    *) [ -z "$TOPIC" ] && TOPIC="$1"; shift ;;
  esac
done

if [ -z "${XAUTHORITY:-}" ] && [ -z "${DISPLAY:-}" ]; then
  P=$(pgrep -x pcmanfm-qt | head -1)
  [ -n "$P" ] && XAUTHORITY=$(tr '\0' '\n' < "/proc/$P/environ" 2>/dev/null | sed -n 's/^XAUTHORITY=//p')
fi
export DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-}"
SS_LT() { ss -ltn 2>/dev/null | grep -q ':9222 '; }

EXTRACT='(()=>{const r=document.querySelector("article")||document.querySelector("main")||document.body;const ps=[...r.querySelectorAll("p")].map(p=>p.innerText.trim()).filter(t=>t.length>40);return ps.join("\n\n")})()'
FEED_URLS='const s=require("fs").readFileSync(0,"utf8");const items=[...s.matchAll(/<(?:item|entry)\b[\s\S]*?<\/(?:item|entry)>/gi)].map(m=>m[0]);let out=[];for(const it of items){const a=it.match(/<link[^>]*>([^<]+)<\/link>/i)||it.match(/<link[^>]*href="([^"]+)"/i);if(a)out.push(a[1].trim());}out=out.filter(u=>/^https?:/.test(u));console.log([...new Set(out)].join("\n"))'

extract_article() { node "$CORE_CDP" goto "$1" >/dev/null 2>&1; sleep 4; local t; t="$(node "$CORE_CDP" eval "$EXTRACT" 2>/dev/null)"; [ "$(printf '%s' "$t" | wc -c)" -ge 700 ] && printf '%s' "$t"; }

# 输出：正文 + 末尾一行 "SRCURL <url>"
get_passage() {
  if [ -n "$URL" ]; then
    SS_LT || "$DIR/chrome_debug.sh" >/dev/null 2>&1
    extract_article "$URL"; echo; echo "SRCURL $URL"; return
  fi
  if [ -n "$TOPIC" ]; then
    curl -s --max-time 20 "https://en.wikipedia.org/w/api.php?action=query&format=json&prop=extracts&explaintext=1&exlimit=1&titles=$(printf '%s' "$TOPIC" | jq -sRr @uri)&redirects=1" | jq -r '.query.pages[].extract // empty' 2>/dev/null
    echo "SRCURL https://en.wikipedia.org/wiki/$TOPIC"; return
  fi
  SS_LT || "$DIR/chrome_debug.sh" >/dev/null 2>&1
  local feed u txt
  while IFS= read -r feed; do
     [ -z "$feed" ] && continue
     while IFS= read -r u; do
        [ -z "$u" ] && continue
        txt="$(extract_article "$u")"
        [ -n "$txt" ] && { printf '%s' "$txt"; echo; echo "SRCURL $u"; return; }
     done < <(curl -sL --max-time 20 "$feed" | node -e "$FEED_URLS" 2>/dev/null | head -4)
  done < <(printf '%s\n' "${SOURCES[@]}" | shuf | head -4)
}

RAW="$(get_passage)"
SRC="$(printf '%s' "$RAW" | sed -n 's/^SRCURL //p' | head -1)"
PASS="$(printf '%s' "$RAW" | grep -v '^SRCURL ' | head -c 4000)"
PASS="$(printf '%s' "$PASS" | awk -v n="$WORDS" '{for(i=1;i<=NF;i++){printf "%s ",$i; if(++c>n){print ""; exit}}}')"
[ "$(printf '%s' "$PASS" | wc -w)" -ge 40 ] || { echo "未取到英文文章" >&2; exit 1; }
echo "来源: $SRC" >&2

STAMP="$(date +%Y%m%d_%H%M%S)"; OUT="/tmp/myagent_en_${STAMP}"
PROMPT='You are an English-learning assistant. Given the English passage, output ONLY minified JSON (no markdown, no extra words) with shape {"title_en":"","title_zh":"","paras":[{"en":"...","zh":"..."}],"vocab":[{"word":"...","zh":"..."}]}. Split into 2-4 paragraphs, translate each to natural Simplified Chinese, pick 6-8 useful words (level '"$LEVEL"') with short Chinese meanings. Passage: '"$PASS"
timeout 120 node /opt/my-agent/agentkit/tools/gemini.js "$PROMPT" > "$OUT.json" 2>/dev/null
sed -i 's/^```[a-z]*//; s/```$//' "$OUT.json" 2>/dev/null
grep -q '"paras"' "$OUT.json" || { echo "翻译失败（无 JSON）" >&2; exit 1; }

luajit "$REPORT/english_article.lua" "$OUT.html" "$OUT.txt" "$OUT.json" "$SRC"
if [ "$DISP" = 1 ]; then cat "$OUT.txt"; exit 0; fi
cat "$OUT.txt"
"$REPORT/render.sh" "$OUT.html" "$OUT.png" 820 >/dev/null 2>&1
echo "图片: $OUT.png"
if [ "$SEND" = 1 ]; then
  [ -s "$OUT.png" ] && { "$DIR/wechat_send_file.sh" "$OUT.png" --to "$TO" >/dev/null 2>&1 && echo "已发图片 → $TO"; }
fi
