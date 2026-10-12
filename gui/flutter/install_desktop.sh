#!/usr/bin/env bash
# install_desktop.sh — 安装桌面快捷方式 + 开机自启动（用户级，无需 sudo）
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
APP=agent
LAUNCH="$HERE/launch.sh"
ICON_SRC="$HERE/assets/icons/myagent.png"
ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"
APPS="$HOME/.local/share/applications"
DESK="$HOME/Desktop"
AUTO="$HOME/.config/autostart"
mkdir -p "$ICON_DIR" "$APPS" "$DESK" "$AUTO"
[ -f "$ICON_SRC" ] && cp "$ICON_SRC" "$ICON_DIR/$APP.png"

entry() {  # $1=目标路径
  cat > "$1" <<DESK
[Desktop Entry]
Type=Application
Name=agent
Comment=agent · 语音助手 摄像头
Exec=$LAUNCH
Icon=$APP
Terminal=false
Categories=Utility;
StartupNotify=false
DESK
}
entry "$APPS/$APP.desktop"; chmod 644 "$APPS/$APP.desktop"
entry "$DESK/$APP.desktop"; chmod 755 "$DESK/$APP.desktop"
gio set "$DESK/$APP.desktop" metadata::trusted true 2>/dev/null || true

cat > "$AUTO/$APP.desktop" <<AUTOENTRY
[Desktop Entry]
Type=Application
Name=agent
Comment=语音助手（开机自启）
Exec=$LAUNCH
Icon=$APP
X-GNOME-Autostart-enabled=true
Terminal=false
AUTOENTRY
chmod 644 "$AUTO/$APP.desktop"

update-desktop-database "$APPS" 2>/dev/null || true
echo "已安装：桌面快捷方式 + 开机自启"
ls -l "$DESK/$APP.desktop" "$APPS/$APP.desktop" "$AUTO/$APP.desktop" "$ICON_DIR/$APP.png" 2>/dev/null
