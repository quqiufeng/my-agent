#!/usr/bin/env bash
# tools/find_file.sh — 按文件名关键词搜索本机文件 + WebDAV，返回匹配（本地路径 或 可下载 URL）
# 用法: find_file.sh <关键词> [数量=15]
# 本地范围: $HOME、/tmp、/data（跳过噪声目录）
# WebDAV 范围: $WEBDAV_SEARCH（冒号分隔，默认 $WEBDAV_MUSIC）——歌曲库 + 美剧/电影等媒体目录
set -uo pipefail

# WebDAV 凭据
[ -f "$HOME/.env" ] && { set -a; . "$HOME/.env"; set +a; }

KW="${1:-}"
if [ -z "$KW" ]; then echo "用法: find_file.sh <关键词> [数量]" >&2; exit 2; fi
LIMIT="${2:-15}"
case "$LIMIT" in ''|*[!0-9]*) LIMIT=15 ;; esac

# ── 本地 ────────────────────────────────────────────────────
ROOTS=("$HOME")
[ -d /tmp ]  && ROOTS+=("/tmp")
[ -d /data ] && ROOTS+=("/data")

mapfile -t LOCAL < <(
    timeout 25 find "${ROOTS[@]}" -type f -iname "*${KW}*" \
        -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/.cache/*' \
        -not -path '*/.local/share/Trash/*' -not -path '*/snap/*' \
        -not -path '*/build/*' -not -path '*/build_*/*' \
        -not -path '*/models/*' -not -path '*/__pycache__/*' \
        -not -path '*/.venv/*' -not -path '*/venv/*' -not -path '*/.npm/*' \
        -not -path '*/.cargo/*' -not -path '*/.rustup/*' \
        -printf '%T@\t%p\n' 2>/dev/null | sort -rn | cut -f2-
)

# ── WebDAV（歌曲库 + 媒体根目录，可匹配文件与目录名）────────
# 搜索目录用 WEBDAV_SEARCH（冒号分隔）覆盖，默认 WEBDAV_MUSIC
DLIST=()
if [ -n "${WEBDAV_URL:-}" ]; then
    IFS=':' read -r -a DROOTS <<< "${WEBDAV_SEARCH:-${WEBDAV_MUSIC:-}}"
    for root in "${DROOTS[@]}"; do
        [ -z "$root" ] && continue
        XML="$(curl -sS -m 25 -u "${WEBDAV_USER:-}:${WEBDAV_PASS:-}" \
            -X PROPFIND -H 'Depth: 1' "${WEBDAV_URL}${root}/" 2>/dev/null || true)"
        while IFS= read -r href; do
            [ -z "$href" ] && continue
            [ "$href" = "$root/" ] && continue
            base="${href%/}"; raw="${base##*/}"
            dec="$(printf '%b' "${raw//%/\\x}")"          # 百分号解码
            if printf '%s' "$dec" | grep -qiF -- "$KW"; then
                DLIST+=("${WEBDAV_URL}${href}")            # 可直接下载的 URL
            fi
        done < <(printf '%s' "$XML" | grep -oP '(?<=<[Dd]:href>)[^<]+')
    done
fi

# ── 合并输出 ────────────────────────────────────────────────
ALL=("${DLIST[@]}" "${LOCAL[@]}")
if [ "${#ALL[@]}" -eq 0 ]; then
    echo "没找到包含「${KW}」的文件"
    exit 1
fi
printf '%s\n' "${ALL[@]}" | head -n "$LIMIT"
