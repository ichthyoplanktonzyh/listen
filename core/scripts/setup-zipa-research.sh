#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
research_root="${LLPLAYERNEXT_ZIPA_RESEARCH_DIR:-$HOME/Library/Caches/LLPlayerNext/research/zipa}"
code_dir="$research_root/code"
model_dir="$research_root/model"
venv="$research_root/venv"
code_revision="f96afe2842868bb1d3cea1efe191806fdcd3c955"
model_revision="9a8d85ba0d2adcbafe7087b82180d0e65c6f3426"
model_sha256="8f0505173e4606b4afe041f19477b38d6a72a98a19863562749066dc496e86ae"
tokens_sha256="f8e042a0c9130532b22d03ec7cae2f75a23fbec70c450c31a8efb51787b2b8fe"

if [[ "${LLPLAYERNEXT_ACCEPT_UNVERIFIED_ZIPA_MODEL_LICENSE:-0}" != "1" ]]; then
  echo "ZIPA model license metadata is unverified." >&2
  echo "For isolated research only, rerun with LLPLAYERNEXT_ACCEPT_UNVERIFIED_ZIPA_MODEL_LICENSE=1." >&2
  exit 1
fi

uv_bin="${UV:-$(command -v uv || true)}"
python_bin="${PYTHON311:-$(command -v python3.11 || true)}"
[[ -n "$uv_bin" ]] || {
  echo "uv is required." >&2
  exit 1
}
[[ -n "$python_bin" ]] || {
  echo "Python 3.11 is required." >&2
  exit 1
}

mkdir -p "$research_root" "$model_dir"
if [[ ! -d "$code_dir/.git" ]]; then
  git clone https://github.com/lingjzhu/zipa.git "$code_dir"
fi
git -C "$code_dir" fetch origin "$code_revision"
git -C "$code_dir" checkout --detach "$code_revision"

"$uv_bin" venv --python "$python_bin" "$venv"
"$uv_bin" pip install --python "$venv/bin/python" \
  -r "$root/testdata/phonetic-analysis/zipa-research-requirements-v1.txt"

download_verified() {
  local url="$1"
  local destination="$2"
  local expected="$3"
  local partial="$destination.partial"
  curl -fL --retry 3 -o "$partial" "$url"
  local actual
  actual="$(shasum -a 256 "$partial" | awk '{print $1}')"
  [[ "$actual" == "$expected" ]] || {
    rm -f "$partial"
    echo "Checksum mismatch for $destination" >&2
    exit 1
  }
  mv "$partial" "$destination"
}

download_verified \
  "https://huggingface.co/anyspeech/zipa-small-crctc-300k/resolve/$model_revision/model.int8.onnx" \
  "$model_dir/model.int8.onnx" \
  "$model_sha256"
download_verified \
  "https://huggingface.co/anyspeech/zipa-small-crctc-300k/resolve/$model_revision/tokens.txt" \
  "$model_dir/tokens.txt" \
  "$tokens_sha256"

"$venv/bin/python" "$root/scripts/phonetic-research-adapter.py" check-zipa \
  --variant int8 \
  --code-dir "$code_dir" \
  --model "$model_dir/model.int8.onnx" \
  --accept-unverified-model-license

echo "ZIPA isolated research environment prepared at $research_root"
