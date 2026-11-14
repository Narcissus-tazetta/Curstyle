#!/bin/bash
# dist の zip から Homebrew cask を作り、Narcissus-tazetta/homebrew-tap の Casks/curstyle.rb を更新する。
#   scripts/publish-homebrew-cask.sh X.Y.Z
# push には HOMEBREW_TAP_TOKEN(tap リポジトリへの書き込み権限)が要る。tap は LiveWallpaper と共用なので README は触らない。
# zap に Application Support を入れないのは、テーマ適用中は標準カーソルのスナップショットが復元に必要で、消すと戻せなくなるため。
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?version required (X.Y.Z)}"
ZIP="dist/Curstyle-macos-v${VERSION}.zip"
TAP_REPO="Narcissus-tazetta/homebrew-tap"
: "${HOMEBREW_TAP_TOKEN:?HOMEBREW_TAP_TOKEN is required}"
[[ -f "$ZIP" ]] || {
  echo "zip not found: $ZIP" >&2
  exit 1
}

SHA256="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
# Intel 版は配っていないので、arm64 以外の Mac に入れさせない。
ARCH_LINE='  depends_on arch: :arm64'
if [[ "${ARCH_MODE:-arm64}" == "universal" ]]; then ARCH_LINE=''; fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
git clone --depth 1 "https://x-access-token:${HOMEBREW_TAP_TOKEN}@github.com/${TAP_REPO}.git" "$WORK/tap"
mkdir -p "$WORK/tap/Casks"

cat > "$WORK/tap/Casks/curstyle.rb" <<RUBY
cask "curstyle" do
  version "${VERSION}"
  sha256 "${SHA256}"

  url "https://github.com/Narcissus-tazetta/Curstyle/releases/download/v#{version}/Curstyle-macos-v#{version}.zip"
  name "Curstyle"
  desc "Custom cursor themes for macOS"
  homepage "https://github.com/Narcissus-tazetta/Curstyle"

  depends_on macos: :sonoma
${ARCH_LINE}

  app "Curstyle.app"

  zap trash: [
    "~/Library/Preferences/io.github.narcissus-tazetta.curstyle.plist",
    "~/Library/Saved Application State/io.github.narcissus-tazetta.curstyle.savedState",
  ]

  caveats <<~EOS
    Curstyle is not notarized. If macOS blocks the first launch, open
    System Settings → Privacy & Security and choose "Open Anyway".
  EOS
end
RUBY

cd "$WORK/tap"
git config user.name github-actions
git config user.email github-actions@github.com
git add Casks/curstyle.rb
if git diff --cached --quiet; then
  echo "tap は最新"
else
  git commit -m "chore(cask): curstyle ${VERSION}"
  git push origin HEAD
fi
