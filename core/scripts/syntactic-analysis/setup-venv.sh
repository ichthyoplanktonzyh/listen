#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
venv="${LLPLAYERNEXT_SYNTACTIC_VENV:-$HOME/Library/Caches/LLPlayerNext/research/syntactic-analysis}"
python="${PYTHON:-/opt/homebrew/bin/python3.11}"

if [[ ! -x "$python" ]]; then
  python="$(command -v python3.11 || command -v python3)"
fi

"$python" -m venv "$venv"
"$venv/bin/python" -m pip install --upgrade pip
"$venv/bin/python" -m pip install -r "$root/scripts/syntactic-analysis/requirements.txt"

if [[ "${LLPLAYERNEXT_DOWNLOAD_SYNTACTIC_MODELS:-0}" == "1" ]]; then
  STANZA_RESOURCES_DIR="$venv/models/stanza" \
    "$venv/bin/python" -c 'import os, stanza; stanza.download("en", package="ewt", model_dir=os.environ["STANZA_RESOURCES_DIR"])'
  "$venv/bin/python" -m spacy download en_core_web_sm
fi

echo "Syntactic research environment ready: $venv"
echo "Models are opt-in. Set LLPLAYERNEXT_DOWNLOAD_SYNTACTIC_MODELS=1 to download both candidates."
