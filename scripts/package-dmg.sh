#!/usr/bin/env bash
# 打包可分发的 catland.app + DMG（不走 App Store）。
#
#   scripts/package-dmg.sh            # 按本机架构打包（Apple 芯片 → arm64，Intel → x86_64）
#   scripts/package-dmg.sh x86_64     # 指定架构（arm64 | x86_64）
#
# App 内自带运行时，用户什么都不用装：
#   Contents/Resources/sidecar/bin/node   官方 Node 二进制（版本锁定，校验 SHA256）
#   Contents/Resources/sidecar/src        sidecar 源码（Node 26 直接运行 .ts）
#   Contents/Resources/sidecar/node_modules 仅生产依赖（含随包的 catbus-cli 与对应架构的原生模块）
# 产物：dist/catland-<版本>-macos-<架构>.dmg 及 .sha256
#
# 签名：ad-hoc（没有 Apple 开发者证书、未公证）。用户首次打开需要在「系统设置 → 隐私与安全性」点「仍要打开」，
# 或执行 xattr -dr com.apple.quarantine /Applications/Catland.app（README 有说明）。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCH="${1:-$(uname -m)}"
# 官方 Node 二进制的 SHA256 取自 https://nodejs.org/dist/v$NODE_VERSION/SHASUMS256.txt
NODE_VERSION="26.0.0"
case "$ARCH" in
  arm64) NODE_ARCH=arm64; NPM_CPU=arm64; NODE_SHA="dcee8564c1a9342f9594dd5e52d533894dfef6b85aa771bbbb870baa3c403235" ;;
  x86_64) NODE_ARCH=x64; NPM_CPU=x64; NODE_SHA="f488ab543fe202d8a2d56e661682117d3c56903a2bf64f2ec1ff7bd421cfd875" ;;
  *) echo "unknown arch: $ARCH (arm64 | x86_64)" >&2; exit 2 ;;
esac
VERSION="$(/usr/bin/sed -n 's/^ *CFBundleShortVersionString: *"\(.*\)"/\1/p' "$ROOT/apps/macos/project.yml")"
CACHE="$ROOT/.cache"
WORK="$ROOT/build/package-$ARCH"
DIST="$ROOT/dist"
APP="$WORK/export/Catland.app"
DMG="$DIST/catland-$VERSION-macos-$ARCH.dmg"

step() { printf '\n\033[1;35m==> %s\033[0m\n' "$*"; }

rm -rf "$WORK" && mkdir -p "$WORK" "$CACHE" "$DIST"

step "1/6 Node $NODE_VERSION ($NODE_ARCH)"
TARBALL="node-v$NODE_VERSION-darwin-$NODE_ARCH.tar.gz"
if [[ ! -f "$CACHE/$TARBALL" ]]; then
  curl -fsSL "https://nodejs.org/dist/v$NODE_VERSION/$TARBALL" -o "$CACHE/$TARBALL.part"
  mv "$CACHE/$TARBALL.part" "$CACHE/$TARBALL"
fi
echo "$NODE_SHA  $CACHE/$TARBALL" | shasum -a 256 -c -
tar -xzf "$CACHE/$TARBALL" -C "$WORK"
NODE_BIN="$WORK/node-v$NODE_VERSION-darwin-$NODE_ARCH/bin/node"

step "2/6 sidecar（仅生产依赖，$NPM_CPU 原生模块）"
SIDE="$WORK/sidecar"
mkdir -p "$SIDE/bin"
cp -R "$ROOT/apps/sidecar/src" "$ROOT/apps/sidecar/package.json" "$ROOT/apps/sidecar/package-lock.json" "$SIDE/"
(cd "$SIDE" && npm ci --omit=dev --no-audit --no-fund --cpu="$NPM_CPU" --os=darwin --loglevel=error)
cp "$NODE_BIN" "$SIDE/bin/node"
rm -f "$SIDE/package-lock.json"

step "3/6 xcodebuild Release ($ARCH)"
(cd "$ROOT/apps/macos" && xcodegen generate --quiet)
xcodebuild -project "$ROOT/apps/macos/Catland.xcodeproj" -scheme Catland -configuration Release \
  -derivedDataPath "$WORK/DerivedData" ARCHS="$ARCH" ONLY_ACTIVE_ARCH=NO build -quiet
mkdir -p "$WORK/export"
cp -R "$WORK/DerivedData/Build/Products/Release/Catland.app" "$APP"

step "4/6 内置 sidecar 与 Node"
cp -R "$SIDE" "$APP/Contents/Resources/sidecar"
# 发布版不指向开发机上的源码目录
/usr/libexec/PlistBuddy -c "Delete :CatlandSidecarDir" "$APP/Contents/Info.plist" 2>/dev/null || true

step "5/6 ad-hoc 签名"
find "$APP/Contents/Resources/sidecar" -type f \( -name "*.node" -o -name "*.dylib" \) -exec codesign --force --sign - {} \;
codesign --force --sign - "$APP/Contents/Resources/sidecar/bin/node"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

step "6/6 DMG"
STAGE="$WORK/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "catland" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -quiet "$DMG"
(cd "$DIST" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")

echo
echo "✓ $(du -h "$DMG" | cut -f1)  $DMG"
cat "$DMG.sha256"
