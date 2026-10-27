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
# 签名与公证（和 IntelliJ IDEA 等正规 App 一样，用户下载后双击即可打开）：
#   1. 钥匙串里有「Developer ID Application」证书时自动使用（也可用 CATLAND_SIGN_IDENTITY 指定）
#   2. App 内每个可执行文件（Node、原生模块）逐个签名：强化运行时 + 时间戳；Node 额外带 JIT 授权
#   3. App 提交 Apple 公证并钉上票据 → 生成带安装窗口排版的 DMG → DMG 签名、公证、钉票据
#   4. spctl / stapler 验证，失败即退出
#   公证凭证：xcrun notarytool store-credentials catland-notary …（只存钥匙串，脚本只引用名字）
# 没有证书时退回 ad-hoc 签名并跳过公证（自己构建自用即可；分发给别人会被 Gatekeeper 拦）。
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
IDENTITY="${CATLAND_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}"
NOTARY_PROFILE="${CATLAND_NOTARY_PROFILE:-catland-notary}"
PY="${CATLAND_PYTHON:-$HOME/miniconda3/envs/catlands/bin/python}"
VERSION="$(/usr/bin/sed -n 's/^ *CFBundleShortVersionString: *"\(.*\)"/\1/p' "$ROOT/apps/macos/project.yml")"
CACHE="$ROOT/.cache"
WORK="$ROOT/build/package-$ARCH"
DIST="$ROOT/dist"
APP="$WORK/export/Catland.app"
DMG="$DIST/catland-$VERSION-macos-$ARCH.dmg"

step() { printf '\n\033[1;35m==> %s\033[0m\n' "$*"; }

rm -rf "$WORK" && mkdir -p "$WORK" "$CACHE" "$DIST"

step "1/8 Node $NODE_VERSION ($NODE_ARCH)"
TARBALL="node-v$NODE_VERSION-darwin-$NODE_ARCH.tar.gz"
if [[ ! -f "$CACHE/$TARBALL" ]]; then
  curl -fsSL "https://nodejs.org/dist/v$NODE_VERSION/$TARBALL" -o "$CACHE/$TARBALL.part"
  mv "$CACHE/$TARBALL.part" "$CACHE/$TARBALL"
fi
echo "$NODE_SHA  $CACHE/$TARBALL" | shasum -a 256 -c -
tar -xzf "$CACHE/$TARBALL" -C "$WORK"
NODE_BIN="$WORK/node-v$NODE_VERSION-darwin-$NODE_ARCH/bin/node"

step "2/8 sidecar（仅生产依赖，$NPM_CPU 原生模块）"
SIDE="$WORK/sidecar"
mkdir -p "$SIDE/bin"
cp -R "$ROOT/apps/sidecar/src" "$ROOT/apps/sidecar/package.json" "$ROOT/apps/sidecar/package-lock.json" "$SIDE/"
(cd "$SIDE" && npm ci --omit=dev --no-audit --no-fund --cpu="$NPM_CPU" --os=darwin --loglevel=error)
cp "$NODE_BIN" "$SIDE/bin/node"
rm -f "$SIDE/package-lock.json"

step "3/8 xcodebuild Release ($ARCH)"
(cd "$ROOT/apps/macos" && xcodegen generate --quiet)
xcodebuild -project "$ROOT/apps/macos/Catland.xcodeproj" -scheme Catland -configuration Release \
  -derivedDataPath "$WORK/DerivedData" ARCHS="$ARCH" ONLY_ACTIVE_ARCH=NO build -quiet
mkdir -p "$WORK/export"
cp -R "$WORK/DerivedData/Build/Products/Release/Catland.app" "$APP"

step "4/8 内置 sidecar 与 Node"
cp -R "$SIDE" "$APP/Contents/Resources/sidecar"
# 发布版不指向开发机上的源码目录
/usr/libexec/PlistBuddy -c "Delete :CatlandSidecarDir" "$APP/Contents/Info.plist" 2>/dev/null || true

notarize() { # $1 = 要提交的文件（zip / dmg）
  local out id status
  out="$(xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json)"
  id="$(echo "$out" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
  status="$(echo "$out" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])')"
  echo "  notarization $id: $status"
  if [[ "$status" != "Accepted" ]]; then
    xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" || true
    exit 1
  fi
}

if [[ -n "$IDENTITY" ]]; then
  step "5/8 Developer ID 签名：$IDENTITY"
  SIGN=(codesign --force --timestamp --options runtime --sign "$IDENTITY")
  # 先签内层：所有 Mach-O（原生模块、动态库），Node 单独带 JIT 授权，最后签 App 本体
  while IFS= read -r -d '' f; do
    if file -b "$f" | grep -q "Mach-O" && [[ "$f" != "$APP/Contents/Resources/sidecar/bin/node" && "$f" != "$APP/Contents/MacOS/"* ]]; then
      "${SIGN[@]}" "$f"
    fi
  done < <(find "$APP/Contents/Resources" -type f \( -name "*.node" -o -name "*.dylib" -o -perm -u+x \) -print0)
  "${SIGN[@]}" --entitlements "$ROOT/packaging/node.entitlements" "$APP/Contents/Resources/sidecar/bin/node"
  "${SIGN[@]}" --entitlements "$ROOT/packaging/Catland.entitlements" "$APP"
  codesign --verify --deep --strict --verbose=1 "$APP"

  step "6/8 App 公证 + 钉票据"
  ditto -c -k --keepParent "$APP" "$WORK/Catland.zip"
  notarize "$WORK/Catland.zip"
  xcrun stapler staple -q "$APP"
else
  step "5/8 没有 Developer ID 证书：ad-hoc 签名（不公证）"
  find "$APP/Contents/Resources/sidecar" -type f \( -name "*.node" -o -name "*.dylib" \) -exec codesign --force --sign - {} \;
  codesign --force --sign - "$APP/Contents/Resources/sidecar/bin/node"
  codesign --force --deep --sign - "$APP"
fi

step "7/8 DMG（带安装窗口排版）"
rm -f "$DMG"
"$PY" -m dmgbuild -s "$ROOT/packaging/dmg_settings.py" -D app="$APP" "catland" "$DMG" >/dev/null
if [[ -n "$IDENTITY" ]]; then
  codesign --force --timestamp --sign "$IDENTITY" "$DMG"
  notarize "$DMG"
  xcrun stapler staple -q "$DMG"

  step "8/8 验证（Gatekeeper 视角）"
  spctl --assess --type execute --verbose=2 "$APP"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
  xcrun stapler validate -q "$APP" && xcrun stapler validate -q "$DMG" && echo "  stapled tickets: ok"
fi
(cd "$DIST" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")

echo
echo "✓ $(du -h "$DMG" | cut -f1)  $DMG"
cat "$DMG.sha256"
