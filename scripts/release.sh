#!/bin/zsh
# 打包发布用的通用二进制（Apple 芯片 + Intel），输出 build/HourRest-<版本>.zip。
# 版本号取自 Resources/Info.plist 的 CFBundleShortVersionString。
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
APP="build/HourRest.app"
ZIP="build/HourRest-$VERSION.zip"

for ARCH in arm64 x86_64; do
  swift build -c release --triple "$ARCH-apple-macosx14.0"
done
ARM="$(swift build -c release --triple arm64-apple-macosx14.0 --show-bin-path)/HourRest"
X86="$(swift build -c release --triple x86_64-apple-macosx14.0 --show-bin-path)/HourRest"

rm -rf "$APP" "$ZIP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "$ARM" "$X86" -output "$APP/Contents/MacOS/HourRest"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"

ditto -c -k --keepParent "$APP" "$ZIP"
lipo -archs "$APP/Contents/MacOS/HourRest"
echo "已生成 $ZIP"
