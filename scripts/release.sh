#!/bin/zsh
# 打包发布用的通用二进制（Apple 芯片 + Intel），输出 build/HourRest-<版本>.dmg。
# dmg 里放 HourRest.app 和「应用程序」快捷方式，打开后拖过去即可安装。
# 版本号取自 Resources/Info.plist 的 CFBundleShortVersionString。
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
APP="build/HourRest.app"
DMG="build/HourRest-$VERSION.dmg"
STAGE="build/dmg"

for ARCH in arm64 x86_64; do
  swift build -c release --triple "$ARCH-apple-macosx14.0"
done
ARM="$(swift build -c release --triple arm64-apple-macosx14.0 --show-bin-path)/HourRest"
X86="$(swift build -c release --triple x86_64-apple-macosx14.0 --show-bin-path)/HourRest"

rm -rf "$APP" "$DMG" "$STAGE"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "$ARM" "$X86" -output "$APP/Contents/MacOS/HourRest"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"

mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "HourRest $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGE"
lipo -archs "$APP/Contents/MacOS/HourRest"
echo "已生成 $DMG"
