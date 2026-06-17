#!/usr/bin/env bash
# Prepare the isolated Python research environment for acoustic forced alignment.
#
# This is a *research mode* setup: it does NOT ship in the app bundle (which is
# pure native). The venv lives under the user's cache directory and is only used
# by the transcription coordinator when it detects the venv exists. Ordinary
# users never see forced alignment; power users/developers opt in by running
# this script.
#
# Mirrors the pattern established by scripts/setup-zipa-research.sh.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
research_root="${LLPLAYERNEXT_FA_DIR:-$HOME/Library/Caches/LLPlayerNext/research/forced-align}"
venv="$research_root/venv"

uv_bin="${UV:-$(command -v uv || true)}"
python_bin="${PYTHON311:-$(command -v python3.11 || true)}"
[[ -n "$uv_bin" ]] || {
  echo "uv is required. Install via 'brew install uv' or https://docs.astral.sh/uv/" >&2
  exit 1
}
[[ -n "$python_bin" ]] || {
  echo "Python 3.11 is required. Install via 'brew install python@3.11'." >&2
  exit 1
}

mkdir -p "$research_root"

# (Re)create the venv if missing or if requirements changed.
marker="$venv/.fa-requirements-stamp"
needs_install=0
if [[ ! -x "$venv/bin/python" ]]; then
  needs_install=1
elif ! diff -q "$root/scripts/forced-align/requirements.txt" "$marker" >/dev/null 2>&1; then
  needs_install=1
fi

if [[ "$needs_install" -eq 1 ]]; then
  echo "Creating forced-align venv at $venv ..."
  "$uv_bin" venv --python "$python_bin" "$venv"
  "$uv_bin" pip install --python "$venv/bin/python" \
    -r "$root/scripts/forced-align/requirements.txt"
  cp "$root/scripts/forced-align/requirements.txt" "$marker"
else
  echo "forced-align venv already up to date at $venv"
fi

# Smoke-check that torchaudio can import and MMS_FA is reachable. The model
# weights are downloaded on first use by torchaudio (cached in the HF cache),
# so we only verify the package surface here.
"$venv/bin/python" - <<'PY'
import torchaudio
bundle = torchaudio.pipelines.MMS_FA
print(f"torchaudio {torchaudio.__version__} OK; MMS_FA sample_rate={bundle.sample_rate}")
PY

echo "Forced-align research environment prepared at $research_root"
echo "The transcription pipeline will auto-detect this venv on the next ASR job."
