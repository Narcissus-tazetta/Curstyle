#!/bin/bash
# 配布 zip に EdDSA 署名を付けて docs/appcast.xml を更新する(Sparkle 同梱の generate_appcast を使う)。
#   scripts/update-appcast.sh X.Y.Z
# 秘密鍵は環境変数 SPARKLE_PRIVATE_ED_KEY(CI)か、無ければ keychain のアカウント "curstyle"(手元)から読む。
# リリースノートは release-notes/vX.Y.Z.md を更新ダイアログに埋め込む。
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?version required (X.Y.Z)}"
SCRATCH="${SCRATCH_PATH:-.build}"
TOOL="$SCRATCH/artifacts/sparkle/Sparkle/bin/generate_appcast"
ZIP="dist/Curstyle-macos-v${VERSION}.zip"
NOTES="release-notes/v${VERSION}.md"
APPCAST="${APPCAST_PATH:-docs/appcast.xml}"
REPO_URL="https://github.com/Narcissus-tazetta/Curstyle"
# 手元の検証で、配布先を GitHub 以外(ローカルの HTTP サーバー)に向けるための上書き。
DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX:-$REPO_URL/releases/download/v${VERSION}/}"

for f in "$TOOL" "$ZIP" "$NOTES"; do
  [[ -e "$f" ]] || {
    echo "見つからない: $f" >&2
    exit 1
  }
done

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp "$ZIP" "$STAGE/"
# generate_appcast は拡張子違いの同名ファイルをそのアーカイブのリリースノートとして使う。
cp "$NOTES" "$STAGE/Curstyle-macos-v${VERSION}.md"
# 既存の appcast があれば、それに項目を足す形で更新される。
[[ -f "$APPCAST" ]] && cp "$APPCAST" "$STAGE/appcast.xml"

ARGS=(
  --download-url-prefix "$DOWNLOAD_URL_PREFIX"
  --embed-release-notes
  --link "$REPO_URL"
  -o "$STAGE/appcast.xml"
)
if [[ -n "${SPARKLE_PRIVATE_ED_KEY:-}" ]]; then
  printf '%s' "$SPARKLE_PRIVATE_ED_KEY" | "$TOOL" --ed-key-file - "${ARGS[@]}" "$STAGE"
else
  "$TOOL" --account curstyle "${ARGS[@]}" "$STAGE"
fi

mkdir -p "$(dirname "$APPCAST")"
cp "$STAGE/appcast.xml" "$APPCAST"
echo "更新した: $APPCAST"
