# Generator protocol request

> **Owner-approved App request.** This describes App needs, not a generator
> release or evidence of completed end-to-end integration.

The App launches the executable directly, never through a shell, with the
normal `package from-media` arguments plus opt-in `--machine-events`. stdout is
NDJSON. Every line uses schema `listen_gen.machine-event.v1`, a monotonic
`sequence`, `tool`, and `event`.

The first event is `protocol` and declares capabilities. Subsequent supported
events are `started`, `phase`, `completed`, `failed`, and `cancelled`. Phase names are `validating`, `probing_media`,
`normalizing_audio`, `transcribing`, and `building_package`. Completion exposes
`package_sha256`, `media_fingerprint`, resource inventory, and warnings; it
does not expose the output path. Failure exposes only stable `code` and a
redacted `message`.

SIGINT/SIGTERM must produce cancelled semantics, terminate provider/media-tool
descendants, and clean temporary audio and incomplete output. The App owns the
final temporary package path and removes it after Core import, cancellation,
or failure. For a protocol-invalid or unresponsive generator, the App escalates
INT to TERM and finally KILL to reclaim the direct generator PID; that fallback
does not claim to reclaim an independently sessioned descendant. The App also
hashes the completed archive bytes and rejects a terminal `package_sha256` that
does not match. Provider credentials remain process-local and never appear in
events, logs, package provenance, or App state.
