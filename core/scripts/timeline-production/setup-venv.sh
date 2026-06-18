#!/usr/bin/env bash
set -euo pipefail

target_dir="${LLPLAYERNEXT_TIMELINE_PRODUCTION_DIR:-$HOME/Library/Caches/LLPlayerNext/research/timeline-production}"
script_dir="$(cd "$(dirname "$0")" && pwd)"

if ! command -v uv >/dev/null 2>&1; then
  echo "uv is required for the timeline production venv" >&2
  exit 1
fi

if ! command -v python3.11 >/dev/null 2>&1; then
  echo "python3.11 is required for the timeline production venv" >&2
  exit 1
fi

mkdir -p "$target_dir"
uv venv --python python3.11 "$target_dir/venv"
"$target_dir/venv/bin/python" -m pip install -r "$script_dir/requirements.txt"

cat <<EOF
Timeline production venv ready:
  $target_dir/venv

Run:
  $target_dir/venv/bin/python $script_dir/production_pipeline.py doctor
EOF
