# Local Realtime Speech (Speech-to-Speech)

Runbook for the `local_cascade_realtime` voice provider: a fully local
VAD → STT → LLM → TTS pipeline that the app reaches over loopback without any
API key.

## What it is

- **Engine**: [`huggingface/speech-to-speech`](https://github.com/huggingface/speech-to-speech)
  (`pip install "speech-to-speech[paraformer]"`) — the same engine
  `qwen-audio-agent` integrates for its local voice frontend.
- **Wire**: listen-core's `LocalCascadeRealtimeAdapter` speaks that engine's
  Realtime WebSocket protocol. Core pins compatibility to
  `speech-to-speech@cc37fe84...` (ADR 0034); newer revisions are expected to
  stay compatible, but a revision change needs protocol fixture review.
- **Topology**: `listen-app` → `listen-core` (adapter + sessions) →
  `ws://127.0.0.1:8765/v1/realtime` (this service). `listen-gen` is not
  involved in realtime speech at all.

```text
ws://127.0.0.1:8765/v1/realtime   service WebSocket endpoint
http://127.0.0.1:8765/v1/pool     readiness pool document
```

## Start the service (manual mode)

Full-local default stack on Apple Silicon (parakeet-tdt ASR, MLX Qwen3-4B,
Qwen3-TTS, everything on MPS):

```bash
python3 tool/run_local_speech_to_speech.py --check     # installed?
python3 tool/run_local_speech_to_speech.py --install   # one-time install
python3 tool/run_local_speech_to_speech.py             # run in foreground
```

`--install` puts the service in its own venv at
`~/.listen/local-speech-venv` (homebrew Python is PEP 668 externally-managed)
and installs from the upstream **git HEAD**, because released PyPI versions
trail the CLI/protocol surface both this launcher and listen-core target.
`--install --pinned` installs the listen-core-audited revision instead;
`--install --revision <ref>` pins any commit.
The equivalent raw commands are under `--check`'s guidance and in the
launcher's docstring.

Overrides you may want: `--stt paraformer` (paraformer ASR instead of
parakeet), `--speaker Vivian --language chinese` (Qwen3-TTS voice/语言),
`--model <other-mlx-model>`. The launcher refuses any non-loopback `--host`:
the service is intentionally unauthenticated.

First start downloads several GB of model weights from HuggingFace by default.
Startup is slower than a conversation turn: the service must be up and its
`/v1/pool` must report a free unit before the app can connect.

### Pre-downloading models locally (ModelScope / Domestic Mirror)

To avoid network timeouts when accessing HuggingFace directly in regions with
restricted connectivity, you can download model weights in advance to
`~/.listen/local-speech-models/` via ModelScope. The launcher auto-detects
this directory by default (`--models-dir`):

```text
~/.listen/local-speech-models/
├── stt/parakeet         # Parakeet TDT (nvidia/parakeet-tdt-0.6b-v2)
├── llm/qwen3-4b         # MLX Qwen3-4B (mlx-community/Qwen3-4B-Instruct-2507-bf16)
└── tts/qwen3-6bit       # MLX Qwen3-TTS (mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-6bit)
```

Download command example:

```bash
# In the speech venv or python environment with modelscope installed:
pip install modelscope

python3 - << 'EOF'
import os
from modelscope.hub.snapshot_download import snapshot_download

base = os.path.expanduser("~/.listen/local-speech-models")
snapshot_download('nvidia/parakeet-tdt-0.6b-v2', local_dir=f"{base}/stt/parakeet")
snapshot_download('mlx-community/Qwen3-4B-Instruct-2507-bf16', local_dir=f"{base}/llm/qwen3-4b")
snapshot_download('mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-6bit', local_dir=f"{base}/tts/qwen3-6bit")
EOF
```

When `~/.listen/local-speech-models/` exists, `python3 tool/run_local_speech_to_speech.py`
and `--check` will automatically bind the local paths without downloading from HuggingFace.

## Verify it is ready

```bash
curl -s http://127.0.0.1:8765/v1/pool    # {"size":N,"in_use":M} with in_use < size
```

A running pool proves an initialized pipeline exists, **not** that a full
audio turn succeeds — that needs a real short spoken roundtrip in the app.

## Connect the app

1. Settings → Realtime voice → Protocol → **Local voice (Speech-to-Speech)**.
   The endpoint auto-fills to `ws://127.0.0.1:8765/v1/realtime`; the API key
   is optional and never touches the keychain.
2. Save; the profile appears (no "Key stored" chip — the backend skips the
   keychain for this adapter kind).
3. Conversation lobby → pick the voice → start. Server VAD drives turn
   boundaries; speaking over the reply interrupts it.

## Managed mode (the app's sidecar stays optional, but wired)

The app passes its whole environment through to the listen-core sidecar it
spawns, and core can spawn, readiness-probe (`/v1/pool`), and shut down the
speech service itself when started with `LLPLAYERNEXT_LOCAL_REALTIME_EXECUTABLE`
and `LLPLAYERNEXT_LOCAL_REALTIME_ARGS_JSON`. So launching the app with the
launcher's managed mode makes the whole pipeline follow the app's lifecycle:

```bash
python3 tool/run_local_speech_to_speech.py \
  --managed --app "$(which llplayer_next)" \
  --install --pinned      # once: install the listen-core-audited revision
```

`--managed` prints the exact environment it sets and then launches the app;
core owns spawn, `/v1/pool` readiness (waiting while the pipeline warms, up to
the configured startup timeout) and process-group shutdown.

**Version surface caveat.** Core's managed spawn appends `--mode realtime
--ws_host <loopback> --ws_port <port>` — the flag names of the pinned,
codec-audited revision (`cc37fe84...`, ADR 0034). Newer upstream moved to
`--host/--port`, so a newer install will fail managed startup. Use
`--install --pinned` for the audited surface; manual (foreground) mode works
with any revision because you choose the flags yourself.

## Troubleshooting

- **Endpoint unreachable**: the service is not running — start it first.
- **Readiness never passes**: the pool is empty or busy (`in_use == size`);
  watch the service's stderr for model download or OOM.
- **Connect timeout**: the profile's `timeout_ms` covers the WebSocket
  handshake; a cold first turn can be slow — retry after the service is warm.