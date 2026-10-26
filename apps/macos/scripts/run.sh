#!/bin/bash
# 构建并启动调试版 catland（会先结束正在运行的实例）。
set -e
cd "$(dirname "$0")/.."
xcodegen generate >/dev/null
xcodebuild -project Catland.xcodeproj -scheme Catland -configuration Debug -derivedDataPath build/DerivedData build | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
mkdir -p build
[ -x build/catland-debug ] || swiftc -O scripts/catland-debug.swift -o build/catland-debug
[ -x build/shot-window ] || swiftc -O scripts/shot-window.swift -o build/shot-window
pkill -f "Catland.app/Contents/MacOS/Catland" || true
sleep 1
open build/DerivedData/Build/Products/Debug/Catland.app
