---
status: accepted
---

# Local realtime speech uses a pinned cascade sidecar

## Context

The realtime conversation boundary already supports remote speech-to-speech
providers, but a local ASR → LLM → TTS path has different security, lifecycle,
and wire semantics. Treating an OpenAI-shaped community server as fully OpenAI
compatible would hide material differences in turn control and transcript
events.

The audited upstream baseline is
`huggingface/speech-to-speech@cc37fe84fe08710e888ecc2eb5b468e41df74bca`.

## Decision

- Add a distinct `local_cascade_realtime` adapter. It may reuse individual wire
  shapes, but it reports its own protocol revision and capability descriptor.
- Local profiles are credential-free and their WebSocket and readiness URLs
  must be loopback. Remote realtime adapters continue to require a credential
  at connection construction.
- The managed sidecar is opt-in. Core never downloads a model or starts a paid
  remote backend implicitly. When explicitly configured, `local-runtime` owns
  spawn, bounded startup, `/v1/pool` readiness, process-group shutdown, and
  reaping. It appends `--mode realtime`, `--ws_host <loopback>`, and
  `--ws_port <port>` to override unsafe upstream defaults.
- `--local_mac_optimal_settings` is rejected because the audited upstream
  implementation forces `mode=local`, disabling the realtime WebSocket server.
- The first Apple Silicon bundle is expected to use Parakeet TDT ASR, an
  explicit local MLX LLM, and Qwen3-TTS. Model installation and a paid/live
  inference smoke remain separate, explicitly authorized operations.
- The adapter supports server VAD and response cancellation, but declares
  manual turns unsupported. Learner transcript deltas are full snapshots.
  Repeated assistant transcript `done` chunks are normalized into deltas plus
  one final transcript before `response.done`.
- Provider transcripts remain live presentation facts. ADR 0027 still requires
  per-turn local recording and completed local transcription before learner
  output becomes authoritative.

## Consequences

The OpenAPI contract advances compatibly to `1.1.0`: clients must accept the new
adapter kind and may omit `secret`. SQLite migration 53 makes `auth_ref`
nullable without fabricating a keychain entry.

Startup readiness proves that an initialized pipeline is available, not that a
full audio turn succeeds. Installation or upgrade qualification therefore
needs a separate short synthetic-turn smoke when model download and execution
are explicitly authorized.

The upstream commit is provenance, not a claim that every future upstream
revision is compatible. Changing it requires protocol fixture review.

## Rejected alternatives

- **Label the server OpenAI-compatible.** Rejected because manual commit and
  transcript event semantics differ.
- **Bind the sidecar to all interfaces.** Rejected because the local provider
  is intentionally unauthenticated.
- **Declare readiness on TCP connect or HTTP 200 alone.** Rejected because an
  empty or fully occupied pipeline pool cannot accept a session.
- **Run model downloads or live inference in normal tests.** Rejected because
  deterministic CI must remain credential-free and credit-free.
