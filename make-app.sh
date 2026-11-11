#!/bin/sh
# SwiftPM の release ビルドから Curstyle.app を組み立て、~/Applications に置く。
# ~/Desktop などの保護フォルダに置いたままだと、launchd から起動したヘルパーが TCC の確認待ちで止まる。
set -e
cd "$(dirname "$0")"

swift build -c release --product CurstyleApp
swift build -c release --product curstyle

BUILD=.build/Curstyle.app
rm -rf "$BUILD"
mkdir -p "$BUILD/Contents/MacOS" "$BUILD/Contents/Library/LaunchAgents" "$BUILD/Contents/Resources"
cp .build/release/CurstyleApp "$BUILD/Contents/MacOS/CurstyleApp"
# ヘルパーの実体。ターミナルから `Curstyle.app/Contents/MacOS/curstyle restore` のようにも使える。
cp .build/release/curstyle "$BUILD/Contents/MacOS/curstyle"
cp -R .build/release/Curstyle_CursorKit.bundle "$BUILD/Contents/Resources/"
cp Support/Info.plist "$BUILD/Contents/Info.plist"
cp Support/io.github.narcissus-tazetta.curstyle.helper.plist "$BUILD/Contents/Library/LaunchAgents/"
printf 'APPL????' > "$BUILD/Contents/PkgInfo"

# ad-hoc 署名。内側の実行ファイルから順に署名する(--deep は使わない)。
codesign --force --sign - --identifier io.github.narcissus-tazetta.curstyle.cli "$BUILD/Contents/MacOS/curstyle"
codesign --force --sign - "$BUILD"

DEST="$HOME/Applications/Curstyle.app"
mkdir -p "$HOME/Applications"
# 起動中なら終わらせてから置き換える。ヘルパー(curstyle)は launchd が KeepAlive で起動し直す。
pkill -x CurstyleApp 2>/dev/null || true
rm -rf "$DEST"
cp -R "$BUILD" "$DEST"
echo "置いた: $DEST"
