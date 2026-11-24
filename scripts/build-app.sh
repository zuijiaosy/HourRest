#!/bin/zsh
# 编译 release 版并打包成 build/HourRest.app（ad-hoc 签名，本机使用）。
# 用法：./scripts/build-app.sh            → 只打包
#       ./scripts/build-app.sh --install  → 打包后复制到 /Applications
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/HourRest"
APP="build/HourRest.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/HourRest"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
echo "已生成 $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x HourRest 2>/dev/null || true
  rm -rf /Applications/HourRest.app
  cp -R "$APP" /Applications/
  echo "已安装到 /Applications/HourRest.app"
fi
