#!/usr/bin/env bash
# @desc 刷新萤石摄像头直播地址（纯 API）：用 ~/.env 的 appKey/appSecret 换 token → 取 HLS 播放地址（protocol=2）→ 写入指定文件；若设备加密已开启，自动用验证码关闭后重试
# @usage tools/ezviz_url.sh [序列号] [输出文件]   # 默认 802657358 → /tmp/myagent_ezviz.url；门口 815311181 → /tmp/myagent_door.url
# @rule 萤石某路黑屏/过期时 → 重新跑本工具生成该路地址；app 重连即自动跟随（app 各路读各自文件：客厅 /tmp/myagent_ezviz.url、门口 /tmp/myagent_door.url）
# @order 42
set -uo pipefail
SERIAL="${1:-802657358}"
OUT="${2:-${EZVIZ_URL_FILE:-/tmp/myagent_ezviz.url}}"
ENVF="${EZVIZ_ENV:-$HOME/.env}"
API="https://open.ys7.com"

# 载入凭据（~/.env 用单引号，安全）
[ -f "$ENVF" ] && set -a && . "$ENVF" && set +a
: "${EZVIZ_APPKEY:?缺 EZVIZ_APPKEY（~/.env）}"
: "${EZVIZ_APPSECRET:?缺 EZVIZ_APPSECRET（~/.env）}"
command -v jq >/dev/null || { echo "需要 jq" >&2; exit 3; }

PROTO="${EZVIZ_PROTOCOL:-2}"   # 1=EZOPEN 2=HLS 3=RTMP 4=HTTP-FLV

TOK="$(curl -s -X POST "$API/api/lapp/token/get" \
  -d "appKey=$EZVIZ_APPKEY" -d "appSecret=$EZVIZ_APPSECRET" | jq -r '.data.accessToken // empty')"
[ -n "$TOK" ] || { echo "取 token 失败（appKey/appSecret?）" >&2; exit 1; }

live() {
  curl -s -X POST "$API/api/lapp/v2/live/address/get" \
    -d "accessToken=$TOK" -d "deviceSerial=$SERIAL" -d "channelNo=1" \
    -d "protocol=$PROTO" -d "quality=1" -d "expireTime=604800"
}

RESP="$(live)"
CODE="$(printf '%s' "$RESP" | jq -r '.code')"

# 设备视频加密开启(60019)：用该设备验证码关闭后重试
if [ "$CODE" = "60019" ]; then
  VC="$(grep -E "^EZVIZ_CODE_${SERIAL}=" "$ENVF" 2>/dev/null | head -1 | sed -E "s/^[^=]*=//; s/['\"]//g")"
  if [ -n "$VC" ]; then
    curl -s -X POST "$API/api/lapp/device/encrypt/off" \
      -d "accessToken=$TOK" -d "deviceSerial=$SERIAL" -d "validateCode=$VC" >/dev/null
    RESP="$(live)"; CODE="$(printf '%s' "$RESP" | jq -r '.code')"
  fi
fi

if [ "$CODE" = "200" ]; then
  URL="$(printf '%s' "$RESP" | jq -r '.data.url')"
  [ -n "$URL" ] && [ "$URL" != "null" ] || { echo "返回空地址: $RESP" >&2; exit 1; }
  printf '%s\n' "$URL" >"$OUT"
  echo "$URL"
  exit 0
fi
echo "取流失败: $RESP" >&2
exit 1
