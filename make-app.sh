#!/bin/sh
# SwiftPM の release ビルドから Curstyle.app を組み立て、~/Applications に置く(自動更新は無効のローカルビルド)。
# ~/Desktop などの保護フォルダに置いたままだと、launchd から起動したヘルパーが TCC の確認待ちで止まる。
set -e
cd "$(dirname "$0")"

scripts/build-app.sh
BUILD=.build/Curstyle.app

DEST="$HOME/Applications/Curstyle.app"
mkdir -p "$HOME/Applications"
# 起動中なら終わらせてから置き換える。ヘルパー(curstyle)は launchd が KeepAlive で起動し直す。
pkill -x CurstyleApp 2>/dev/null || true
rm -rf "$DEST"
cp -R "$BUILD" "$DEST"
echo "置いた: $DEST"
