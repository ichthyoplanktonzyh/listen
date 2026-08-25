#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app="${1:?usage: stage-macos-runtime.sh /path/to/listen.app [--optional]}"
mode="${2:-}"
optional=false
if [[ "$mode" == "--optional" ]]; then
  optional=true
elif [[ -n "$mode" ]]; then
  echo "Unknown option: $mode" >&2
  exit 2
fi

core_runtime="$root/.backend/runtime"
api_http="$core_runtime/bin/api-http"
runtime_destination="$app/Contents/Resources/runtime"

if [[ -x "$api_http" && -d "$core_runtime/runtime" ]]; then
  python3 "$root/tool/backend_artifacts.py" \
    --lock "${BACKEND_LOCK:-$root/backend.lock.json}" verify
  mkdir -p "$app/Contents/MacOS" "$runtime_destination"
  cp "$api_http" "$app/Contents/MacOS/api-http"
  chmod +x "$app/Contents/MacOS/api-http"
  cp -R "$core_runtime/runtime/." "$runtime_destination/"
  cp "$core_runtime/THIRD_PARTY_NOTICES.md" \
    "$runtime_destination/THIRD_PARTY_NOTICES.md"
elif [[ "$optional" == false ]]; then
  echo "Installed listen-core runtime is incomplete." >&2
  exit 1
else
  echo "Skipping listen-core staging: installed runtime is incomplete."
fi

gen_args=(
  python3 "$root/tool/listen_gen_artifacts.py" stage
  --destination "$runtime_destination/listen-gen"
)
if [[ "$optional" == true ]]; then
  gen_args+=(--optional)
fi
"${gen_args[@]}"
