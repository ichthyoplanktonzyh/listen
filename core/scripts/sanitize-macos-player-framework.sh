#!/usr/bin/env bash
set -euo pipefail

app="${1:?usage: sanitize-macos-player-framework.sh /path/to/App.app}"
mdk="$app/Contents/Frameworks/mdk.framework/Versions/A/mdk"

if [[ ! -f "$mdk" ]]; then
  echo "Missing bundled mdk framework: $mdk" >&2
  exit 1
fi

for path in /opt/homebrew/lib /usr/local/lib; do
  if otool -l "$mdk" | grep -Fq "path $path "; then
    install_name_tool -delete_rpath "$path" "$mdk"
  fi
done

if otool -l "$mdk" | grep -Eq 'path /(opt/homebrew|usr/local)/lib '; then
  echo "Bundled mdk framework still references a package-manager library path." >&2
  exit 1
fi

echo "Sanitized bundled mdk framework search paths."
