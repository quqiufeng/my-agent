#!/usr/bin/env bash
# tools/vocab.sh — 记单词：屏幕弹英文单词，你大声读出来；读对进下一个，读错弹带中文释义的卡片
# @desc 记单词（弹卡片→读单词判发音→✓下一个 / ✗弹释义卡帮助记忆）
# @usage tools/vocab.sh start|stop|status | add <英文> <中文> | list
# @rule **记单词**：说“记单词 / 背单词 / 开始背单词”→ `tools/vocab.sh start`；“停了/结束背单词”→ `stop`；要加词 → `add <英文> <中文>`。开始后弹卡片，你读单词：**读对进下一个；读错弹带中文翻译的卡片帮助记忆**。
# @order 15
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
export DISPLAY="${DISPLAY:-:0}"

VOCAB="${VOCAB_FILE:-$HOME/.myagent_vocab.txt}"
CARD="${VOCAB_CARD:-/tmp/myagent_card.png}"
VW="${VOCAB_W:-1000}"; VH="${VOCAB_H:-600}"
GEO="${VOCAB_GEO:-${VW}x${VH}+120+120}"
SESS="${VOCAB_TMUX:-vocab}"

seed_vocab() {
    cat > "$VOCAB" <<'EOF'
apple	苹果
banana	香蕉
weather	天气
travel	旅行
friend	朋友
happy	高兴
music	音乐
coffee	咖啡
window	窗户
mountain	山
river	河
language	语言
practice	练习
improve	提高
remember	记得
morning	早上
question	问题
answer	回答
future	未来
change	改变
EOF
    echo "[vocab] 已生成默认词表: $VOCAB"
}

# 渲染卡片：$1 大字（英文），$2 小字（提示/结果），$3 小字颜色(hex，可选)
render() {
    luajit "$DIR/card.lua" "$CARD" "$1" "$2" "$VW" "$VH" \
        0x0b1f12 0xf4f4f4 "${3:-0x9fe0b0}" 2>/dev/null
}

# Levenshtein 编辑距离
lev() {
    awk -v s="$1" -v t="$2" 'BEGIN{
        n=length(s); m=length(t);
        for(i=0;i<=n;i++) d[i,0]=i;
        for(j=0;j<=m;j++) d[0,j]=j;
        for(i=1;i<=n;i++) for(j=1;j<=m;j++){
            c=(substr(s,i,1)==substr(t,j,1))?0:1;
            v=d[i-1,j]+1; if(d[i,j-1]+1<v) v=d[i,j-1]+1;
            if(d[i-1,j-1]+c<v) v=d[i-1,j-1]+c;
            d[i,j]=v;
        }
        print d[n,m];
    }'
}
# 发音匹配（英文）：识别结果与单词一致 / 包含 / 编辑距离很小
match_en() {
    local a e
    a="$(printf '%s' "$1" | tr 'A-Z' 'a-z' | tr -cd 'a-z')"
    e="$(printf '%s' "$2" | tr 'A-Z' 'a-z' | tr -cd 'a-z')"
    [ -z "$a" ] && return 1
    [ "$a" = "$e" ] && return 0
    case "$a" in *"$e"*) return 0;; esac
    local d; d="$(lev "$a" "$e")"
    [ "${#e}" -ge 6 ] && [ "$d" -le 2 ] && return 0
    [ "$d" -le 1 ] && return 0
    return 1
}

# 采集一句话（$1=语言），返回识别文本
capture() {
    [ -n "${VOCAB_FAKE:-}" ] && { echo "$VOCAB_FAKE"; return; }
    SENSEVOICE_LANG="${1:-auto}" timeout 25 /opt/my-agent/voice/listen.sh --once --no-forward 2>/dev/null \
        | sed -n 's/^\[识别\] //p' | tail -1
}

run() {
    [ -s "$VOCAB" ] || seed_vocab
    local rounds="${1:-99999}"
    pkill -f "display -update 1 $CARD" 2>/dev/null

    render "Ready?" "看单词，大声读出来（练发音）"
    display -update 1 -geometry "$GEO" "$CARD" >/dev/null 2>&1 &
    viewer=$!
    cleanup() {
        [ -n "${viewer:-}" ] && kill "$viewer" 2>/dev/null
        pkill -f "display.*$(basename "$CARD")" 2>/dev/null
        rm -f "$CARD"
    }
    trap cleanup EXIT INT TERM

    local n=0
    while [ "$n" -lt "$rounds" ]; do
        n=$((n+1))
        local line en zh
        line="$(shuf -n1 "$VOCAB" 2>/dev/null || head -1 "$VOCAB")"
        en="$(printf '%s' "$line" | cut -f1)"
        zh="$(printf '%s' "$line" | cut -f2)"
        [ -z "$en" ] && continue

        render "$en" "读一遍这个单词（练发音）"
        echo "[vocab] Q$n: $en（$zh）"

        local said_en
        said_en="$(capture en)"
        if match_en "$said_en" "$en"; then
            echo "[vocab]   → 发音✓ 下一个"
            render "$en" "✓ 发音正确   下一个 →" "0x7fe07f"
            sleep 1.6
        else
            echo "[vocab]   → 发音✗ (你说: ${said_en:-无}) 弹释义卡"
            render "$en" "✗ 你读: ${said_en:-没听清}     $en = $zh" "0xe08f8f"
            sleep 5
        fi
    done
}

case "${1:-status}" in
    seed|init) seed_vocab ;;
    add)
        [ -z "${2:-}" ] || [ -z "${3:-}" ] && { echo "用法: vocab.sh add <英文> <中文>" >&2; exit 2; }
        printf '%s\t%s\n' "$2" "$3" >> "$VOCAB"; echo "已加入: $2 - $3" ;;
    list)
        [ -s "$VOCAB" ] || seed_vocab
        nl -ba "$VOCAB" ;;
    start)
        command -v tmux >/dev/null || { echo "需要 tmux"; exit 1; }
        tmux has-session -t "$SESS" 2>/dev/null && { echo "记单词已在运行"; exit 0; }
        tmux new-session -d -s "$SESS" "cd '$DIR' && DISPLAY=:0 './vocab.sh' run 2>&1 | tee /tmp/vocab.log"
        sleep 1; echo "已开始记单词（看屏幕卡片读单词：读对进下一个，读错弹释义卡）" ;;
    stop)
        tmux kill-session -t "$SESS" 2>/dev/null
        pkill -f "display.*$(basename "$CARD")" 2>/dev/null
        rm -f "$CARD"; echo "已停止记单词" ;;
    run) shift; run "$@" ;;
    status)
        if tmux has-session -t "$SESS" 2>/dev/null; then echo "记单词：运行中"; else echo "记单词：未运行"; fi ;;
    *)
        echo "用法: vocab.sh start|stop|status | add <英文> <中文> | list | seed" >&2; exit 2 ;;
esac
