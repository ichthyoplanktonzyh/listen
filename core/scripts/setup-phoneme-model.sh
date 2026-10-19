#!/usr/bin/env bash
# Download and set up the wav2vec2 phoneme recognition model for LLPlayerNext.
#
# Usage:
#   ./scripts/setup-phoneme-model.sh
#
# This downloads facebook/wav2vec2-lv-60-espeak-cv-ft (~1.26 GB) into
# the default model directory. Requires Python 3 with pip.

set -euo pipefail

MODEL_ID="facebook/wav2vec2-lv-60-espeak-cv-ft"
MODEL_DIR="${LLPLAYERNEXT_PHONEME_MODEL_DIR:-$HOME/Library/Application Support/LLPlayerNext/models/wav2vec2-phoneme}"

if [ -d "$MODEL_DIR" ] && [ -f "$MODEL_DIR/config.json" ]; then
    echo "Model already exists at: $MODEL_DIR"
    echo "To re-download, remove the directory first."
    exit 0
fi

echo "Downloading $MODEL_ID to: $MODEL_DIR"
echo "This is approximately 1.26 GB."

mkdir -p "$MODEL_DIR"

python3 -c "
from huggingface_hub import snapshot_download
snapshot_download(
    repo_id='$MODEL_ID',
    local_dir='$MODEL_DIR',
    local_dir_use_symlinks=False,
)
print('Download complete.')
" 2>&1 || {
    echo ""
    echo "If huggingface_hub is not installed, run:"
    echo "  pip3 install huggingface_hub"
    echo ""
    echo "Then re-run this script."
    exit 1
}

echo ""
echo "Setup complete. Model installed at:"
echo "  $MODEL_DIR"
echo ""
echo "The CTC phoneme provider will be available next time LLPlayerNext starts."
