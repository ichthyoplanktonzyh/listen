# Phone provider v1

Phone Timeline production is an optional fourth R4 stage. It runs only when a
caller selects `--phone`; otherwise the operation explicitly abstains.

The normalized result schema is `listen_gen.phone-result.v1` and contains a
non-empty monotonic list of audio-observed phone spans, a phone set, and exact
provider/model/config provenance. Gen maps each span to the exact package Word
Timeline by temporal overlap. Every emitted package phone has a non-null
`word_ref`; invalid, unanchored, or unusable output degrades the phone stage and
preserves all upstream resources.

Adapters:

- `fixture`: deterministic local qualification evidence used by tests;
- `command`: a direct argv provider with one `{media}` placeholder;
- `wav2vec2-ctc`: the first-class local sidecar compatible with Core's existing
  `{phones: [...]}` wav2vec2 output. It receives explicit Python, sidecar,
  model directory, model id, and model revision inputs.

All subprocess adapters use bounded output, positive timeouts, cancellation
propagation, and process-group reaping. Provider stderr, argv, paths, raw
payloads, and secrets are never copied into warnings or packages. The command
adapter binds path-free executable, script/model argument, placeholder,
opaque-argument, and timeout identities into `config_sha256`; the CTC adapter
binds runtime, sidecar, and model byte identities. Both reject mutation during
a run. No adapter downloads a model or fabricates phones from spelling.
