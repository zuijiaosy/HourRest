#!/bin/zsh
# 运行核心逻辑单测。只装了 Command Line Tools（没有 Xcode）时，Testing.framework 不在默认搜索路径里，这里补上。
set -euo pipefail
cd "$(dirname "$0")/.."
DEV="$(xcode-select -p)/Library/Developer"
FW="$DEV/Frameworks"
if [[ -d "$FW/Testing.framework" && ! -d "$(xcode-select -p)/Platforms" ]]; then
  exec swift test -Xswiftc -F -Xswiftc "$FW" -Xlinker -rpath -Xlinker "$FW" -Xlinker -rpath -Xlinker "$DEV/usr/lib" "$@"
fi
exec swift test "$@"
