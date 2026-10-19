#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
install_root="${LLPLAYERNEXT_SYNTAX_INSTALL_ROOT:-$HOME/Library/Application Support/LLPlayerNext/syntax/spacy-3.8.13-en_core_web_sm-3.8.0}"
python="${PYTHON:-/opt/homebrew/bin/python3.11}"

if [[ ! -x "$python" ]]; then
  python="$(command -v python3.11 || command -v python3)"
fi

mkdir -p "$install_root"
"$python" -m venv "$install_root/venv"
"$install_root/venv/bin/python" -m pip install --upgrade pip
"$install_root/venv/bin/python" -m pip install \
  -r "$root/scripts/syntactic-analysis/requirements-spacy-product.txt"
install -m 0644 \
  "$root/scripts/syntactic-analysis/syntax-sidecar.py" \
  "$install_root/syntax-sidecar.py"

probe="$({
  echo '{"protocol_version":1,"operation":"probe","request_id":"product-install-probe","provider":"spacy","language":"en"}'
} | "$install_root/venv/bin/python" "$install_root/syntax-sidecar.py" --provider spacy)"

PROBE="$probe" "$install_root/venv/bin/python" -c '
import json, os
payload = json.loads(os.environ["PROBE"])
assert payload["ok"] is True, payload
assert payload["capability"]["status"] == "ready", payload
descriptor = payload["capability"]["descriptor"]
assert descriptor["runtime_version"] == "3.8.13", descriptor
assert descriptor["model_version"] == "3.8.0", descriptor
assert descriptor["model_checksum_sha256"] == "adda6df4860f555a57e6e31635f233359ab471dafa177d58d96a8d4198450a7c", descriptor
'

echo "Optional spaCy syntax capability installed and verified."
echo "export LLPLAYERNEXT_SYNTAX_PYTHON='$install_root/venv/bin/python'"
echo "export LLPLAYERNEXT_SYNTAX_SIDECAR='$install_root/syntax-sidecar.py'"
echo "Remove those variables to disable it; delete this versioned directory to uninstall:"
echo "$install_root"
