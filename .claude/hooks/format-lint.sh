#!/bin/zsh
# PostToolUse: 編集したファイルを整形し、lint の指摘があれば exit 2 で Claude に返す。
file=$(/usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("file_path",""))')
[[ -f "$file" ]] || exit 0
case "$file" in
  *.swift)
    xcrun swift-format format --in-place "$file" || exit 2
    out=$(xcrun swift-format lint "$file" 2>&1)
    ;;
  *.c|*.h)
    clang-format -i "$file" || exit 2
    out=""
    ;;
  *) exit 0 ;;
esac
if [[ -n "$out" ]]; then
  print -r -- "$out" >&2
  exit 2
fi
exit 0
