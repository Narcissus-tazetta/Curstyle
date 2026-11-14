#!/bin/bash
# 配布物(dist/Curstyle-macos-vX.Y.Z.zip と .dmg)を作る。zip は Sparkle と Homebrew 用、dmg は手動ダウンロード用。
#   scripts/package.sh X.Y.Z
# ARCH_MODE(既定 arm64)と SCRATCH_PATH は build-app.sh と同じ。Intel は未検証なので universal は明示したときだけ。
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?version required (X.Y.Z)}"
export ARCH_MODE="${ARCH_MODE:-arm64}"
DIST=dist
APP="$DIST/Curstyle.app"
ZIP="$DIST/Curstyle-macos-v${VERSION}.zip"
DMG="$DIST/Curstyle-macos-v${VERSION}.dmg"

rm -rf "$DIST"
mkdir -p "$DIST"
APP_PATH="$APP" scripts/build-app.sh "$VERSION"

# Sparkle が展開して Info.plist を読むので、親フォルダごと固めた zip にする。
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname Curstyle -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

ls -lh "$ZIP" "$DMG"
