#!/bin/bash
# Curstyle.app を組み立てて署名する(インストールはしない)。
#   scripts/build-app.sh          ローカルビルド。バージョンは Support/Info.plist のまま、自動更新は無効。
#   scripts/build-app.sh X.Y.Z    配布用ビルド。バージョンを刻み、Sparkle の更新先と公開鍵を入れる。
# 環境変数:
#   ARCH_MODE         native(既定)| arm64 | universal
#   SCRATCH_PATH      SwiftPM のビルド先(既定 .build)
#   APP_PATH          出力する .app(既定 $SCRATCH_PATH/Curstyle.app)
#   SPARKLE_FEED_URL  配布用ビルドの更新先(既定は main の docs/appcast.xml)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
ARCH_MODE="${ARCH_MODE:-native}"
SCRATCH="${SCRATCH_PATH:-.build}"
APP="${APP_PATH:-$SCRATCH/Curstyle.app}"
FEED_URL="${SPARKLE_FEED_URL:-https://raw.githubusercontent.com/Narcissus-tazetta/Curstyle/main/docs/appcast.xml}"

case "$ARCH_MODE" in
native) ARCH_FLAGS=() EXPECTED_ARCHS="$(uname -m)" ;;
arm64) ARCH_FLAGS=(--arch arm64) EXPECTED_ARCHS="arm64" ;;
universal) ARCH_FLAGS=(--arch arm64 --arch x86_64) EXPECTED_ARCHS="x86_64 arm64" ;;
*)
  echo "ARCH_MODE は native / arm64 / universal のどれか: $ARCH_MODE" >&2
  exit 1
  ;;
esac

# 配布用ビルドだけ番号を導出する。先に検証して、ビルドの後で形式エラーに気づく無駄を避ける。
if [[ -n "$VERSION" ]]; then
  BUILD_NUMBER="$(bash scripts/derive_build_number.sh "$VERSION")"
fi

build() {
  swift build -c release --scratch-path "$SCRATCH" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} "$@"
}
build --product CurstyleApp
build --product curstyle
BIN="$(build --show-bin-path)"

ACTUAL_ARCHS="$(lipo -archs "$BIN/CurstyleApp")"
if [[ "$ACTUAL_ARCHS" != "$EXPECTED_ARCHS" ]]; then
  echo "CurstyleApp のアーキテクチャが '$ACTUAL_ARCHS'(期待: '$EXPECTED_ARCHS')" >&2
  exit 1
fi

SPARKLE_FRAMEWORK="$SCRATCH/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ ! -d "$SPARKLE_FRAMEWORK" ]]; then
  echo "Sparkle.framework が見つからない: $SPARKLE_FRAMEWORK" >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Library/LaunchAgents" "$APP/Contents/Resources"
cp "$BIN/CurstyleApp" "$APP/Contents/MacOS/CurstyleApp"
# ヘルパーの実体。ターミナルから `Curstyle.app/Contents/MacOS/curstyle restore` のようにも使える。
cp "$BIN/curstyle" "$APP/Contents/MacOS/curstyle"
cp -R "$BIN/Curstyle_CursorKit.bundle" "$APP/Contents/Resources/"
cp -R "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/io.github.narcissus-tazetta.curstyle.helper.plist "$APP/Contents/Library/LaunchAgents/"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Icon Composer の .icon は actool でしかコンパイルできない。Assets.car は macOS 26 の Liquid Glass 用、AppIcon.icns は旧 OS 用。
ICON_TMP="$(mktemp -d)"
xcrun actool Support/AppIcon.icon --compile "$ICON_TMP" --platform macosx --minimum-deployment-target 14.0 \
  --app-icon AppIcon --output-partial-info-plist "$ICON_TMP/partial.plist" > /dev/null
cp "$ICON_TMP/AppIcon.icns" "$ICON_TMP/Assets.car" "$APP/Contents/Resources/"
rm -rf "$ICON_TMP"

# SwiftPM が付ける rpath は実行ファイルの隣を見るので、Frameworks/ を見る rpath を足す。署名より前でないと壊れる。
if ! otool -l "$APP/Contents/MacOS/CurstyleApp" | grep -q "@executable_path/../Frameworks"; then
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/CurstyleApp"
fi

if [[ -n "$VERSION" ]]; then
  PLIST="$APP/Contents/Info.plist"
  PB=/usr/libexec/PlistBuddy
  "$PB" -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
  "$PB" -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"
  "$PB" -c "Add :SUFeedURL string $FEED_URL" "$PLIST"
  "$PB" -c "Add :SUPublicEDKey string $(tr -d '[:space:]' < Support/sparkle-public-key.txt)" "$PLIST"
fi

# ad-hoc 署名。内側から順に署名する(アプリ本体に --deep は使わない)。
# Sparkle は XPC や Updater.app を中に持つので、フレームワークだけ --deep で入れ子ごと署名する。
codesign --force --deep --sign - "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign - --identifier io.github.narcissus-tazetta.curstyle.cli "$APP/Contents/MacOS/curstyle"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"

# SwiftPM の Bundle.module はビルド時の絶対パスにも頼るので、ビルドしたマシンでは .app の中身が欠けても動いて見える。
# 埋め込まれるパスは --show-bin-path と別の場所(中間ディレクトリ)なので、ビルド先にある全コピーを退避してから、
# .app 単体でリソースを読めること(diagnose が L10n を通る)を確かめる。
HIDDEN_LIST="$(mktemp)"
restore_bundles() {
  while IFS= read -r hidden; do mv "$hidden" "${hidden%.hidden}"; done < "$HIDDEN_LIST"
  rm -f "$HIDDEN_LIST"
}
trap restore_bundles EXIT
while IFS= read -r bundle; do
  mv "$bundle" "$bundle.hidden"
  echo "$bundle.hidden" >> "$HIDDEN_LIST"
done < <(find "$SCRATCH" -name Curstyle_CursorKit.bundle -type d -prune)
if [[ ! -s "$HIDDEN_LIST" ]]; then
  echo "ビルド先に Curstyle_CursorKit.bundle が見つからない" >&2
  exit 1
fi
# diagnose はヘッドレスの CI では環境のせいで非ゼロ終了しうるので、終了コードではなくクラッシュ(シグナル終了か fatal error)だけを見る。
SMOKE_OUT="$(mktemp)"
set +e
"$APP/Contents/MacOS/curstyle" diagnose > "$SMOKE_OUT" 2>&1
SMOKE_RC=$?
set -e
if [[ "$SMOKE_RC" -ge 128 ]] || grep -q "Fatal error" "$SMOKE_OUT"; then
  echo "ビルド先のバンドルを隠すと curstyle diagnose がクラッシュする(リソースの同梱漏れ) rc=$SMOKE_RC" >&2
  cat "$SMOKE_OUT" >&2
  exit 1
fi
echo "スモークテスト: curstyle diagnose rc=$SMOKE_RC(クラッシュなし)"
rm -f "$SMOKE_OUT"

echo "組み立てた: $APP (${VERSION:-ローカルビルド}, $ACTUAL_ARCHS)"
