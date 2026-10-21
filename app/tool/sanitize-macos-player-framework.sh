#!/usr/bin/env bash
set -euo pipefail

app="${1:?usage: sanitize-macos-player-framework.sh /path/to/App.app}"
mdk="$app/Contents/Frameworks/mdk.framework/Versions/A/mdk"

if [[ ! -f "$mdk" ]]; then
  echo "Missing bundled mdk framework: $mdk" >&2
  exit 1
fi

load_commands=""
read_load_commands() {
  local message="$1"
  if ! load_commands="$(otool -l "$mdk")"; then
    echo "$message" >&2
    return 1
  fi
}

has_rpath() {
  local path="$1"
  [[ "$load_commands" == *"path $path "* ]]
}

read_load_commands "Could not inspect bundled mdk framework load commands."

for path in /opt/homebrew/lib /usr/local/lib; do
  while has_rpath "$path"; do
    previous_load_commands="$load_commands"
    if ! install_name_tool -delete_rpath "$path" "$mdk"; then
      echo "Could not remove bundled mdk framework search path: $path" >&2
      exit 1
    fi
    read_load_commands \
      "Could not re-inspect bundled mdk framework after removing $path."
    if [[ "$load_commands" == "$previous_load_commands" ]]; then
      echo "install_name_tool did not remove bundled mdk framework search path: $path" >&2
      exit 1
    fi
  done
done

if has_rpath /opt/homebrew/lib || has_rpath /usr/local/lib; then
  echo "Bundled mdk framework still references a package-manager library path." >&2
  exit 1
fi

echo "Sanitized bundled mdk framework search paths."
