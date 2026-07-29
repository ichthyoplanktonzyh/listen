# Local realtime cascade consumer handoff

Status: implemented in core, unreleased

Contract: `1.1.0`

## App contract changes

- Accept `local_cascade_realtime` in realtime provider profile DTOs.
- `secret` is optional when registering a realtime provider.
- A local profile should use `ws://127.0.0.1:<port>/v1/realtime`, omit
  `secret`, use server VAD, and disable manual-turn UI.
- `has_credential` is `false` for the local profile. No keychain placeholder is
  created.
- The startup `api.started` object now carries nullable
  `local_realtime_cascade_endpoint`. When present, the managed sidecar has
  passed its pool-readiness check; when absent, the app may still register an
  independently managed loopback sidecar.

The app must not consume this change as stable until core publishes an immutable
contract/runtime release and the app updates `backend.lock.json`.

## Explicit managed-sidecar configuration

Core starts no model by default. To opt in, the launcher supplies:

```text
LLPLAYERNEXT_LOCAL_REALTIME_EXECUTABLE=/absolute/path/to/speech-to-speech
LLPLAYERNEXT_LOCAL_REALTIME_ARGS_JSON=[
  "--device","mps",
  "--stt","parakeet-tdt",
  "--llm_backend","mlx-lm",
  "--model_name","mlx-community/Qwen3-4B-Instruct-2507-bf16",
  "--tts","qwen3",
  "--enable_live_transcription"
]
```

Optional overrides are
`LLPLAYERNEXT_LOCAL_REALTIME_ENDPOINT`,
`LLPLAYERNEXT_LOCAL_REALTIME_READINESS_URL`,
`LLPLAYERNEXT_LOCAL_REALTIME_STARTUP_TIMEOUT_SECS`, and
`LLPLAYERNEXT_LOCAL_REALTIME_SHUTDOWN_TIMEOUT_SECS`. Defaults are port 8765,
`/v1/realtime`, `/v1/pool`, 300 seconds, and 10 seconds.

Core appends the realtime mode and loopback bind arguments. Do not add
`--local_mac_optimal_settings`; the pinned upstream revision uses that flag to
leave realtime mode.

## Verification boundary

Core contract, codec, persistence, process lifecycle, and readiness tests are
deterministic. No model was downloaded and no live inference was run in this
slice. A release candidate still needs an explicitly authorized Apple Silicon
short-audio ASR → local LLM → TTS smoke.
