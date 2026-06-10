#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
runtime="${1:-$root/third_party/runtime/macos-arm64}"

for binary in whisper-cli ffmpeg ffprobe; do
  [[ -x "$runtime/$binary" ]]
  file "$runtime/$binary" | grep -q "arm64"
  if otool -L "$runtime/$binary" | grep -Eq '@rpath|/opt/homebrew|/usr/local'; then
    echo "$binary depends on a non-system dynamic library" >&2
    exit 1
  fi
done
"$runtime/ffmpeg" -version | head -1 | grep -q "ffmpeg version"
"$runtime/ffmpeg" -version | grep -qi "configuration:.*--disable-gpl"
"$runtime/ffmpeg" -version | grep -qi "configuration:.*--disable-nonfree"
"$runtime/ffprobe" -version | head -1 | grep -q "ffprobe version"
"$runtime/whisper-cli" --help >/dev/null 2>&1
node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' \
  "$root/third_party/runtime/manifest.json"
echo "ASR runtime and license configuration verified."
