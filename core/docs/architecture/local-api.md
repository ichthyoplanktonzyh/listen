# Local API Lifecycle And Security

The M1 HTTP adapter is a desktop sidecar transport for `AppServices`. It is not
the shared core itself and it never controls playback.

## Startup

1. Resolve the database path. On macOS the default is
   `~/Library/Application Support/LLPlayerNext/llplayernext.sqlite`.
2. Create the data directory, back up an older schema, and run migrations.
3. Generate a random 256-bit bearer token unless `LLPLAYERNEXT_API_TOKEN` is
   explicitly supplied by the parent process.
4. Bind an OS-assigned port on `127.0.0.1` only.
5. Write one JSON `api.started` line containing version, platform, address,
   token, and database path. The parent desktop process reads this handshake.

The token is process-scoped and must not be written into application settings.
All routes except `/v1/health` require `Authorization: Bearer <token>`. The
service does not configure CORS, so browser pages receive no cross-origin
permission in addition to lacking the token.

## Shutdown

The service accepts Ctrl-C/SIGINT for graceful shutdown, finishes accepted
requests, then writes an `api.stopped` JSON line. The desktop parent should
first request graceful termination and may force termination after its own
timeout.

## Errors And Versions

HTTP routes are under `/v1`. Every API error contains a stable `code`, a
user-facing `message`, a `correlation_id`, and `retryable`. The OpenAPI contract
is maintained in `contracts/openapi/v1.yaml`; event envelopes use an independent
integer schema version in `contracts/events/v1.schema.json`.

Milestone 1.5 adds vocabulary-book, word-detail, portable export/import, and
media-availability routes under the same compatible `/v1` namespace. Exported
assets never include media bytes or require media files during import.

Milestone 1.6 adds external word-list import and independent learning-content
updates. Dictionary lookup now returns an ordered bundle of registered Provider
results; one Provider failure does not fail the whole lookup.

## Deliberate Exclusions

Play, pause, seek, position events, subtitle cursor updates, and loop control
stay inside the Flutter desktop client. Sending those high-frequency operations
through HTTP would add latency and couple the domain service to a player.
# Milestone 1.9 Additions

`/v1/pronunciation/*` exposes provider capabilities, canonical lookup, sentence
analysis, and rule metadata. Track-level pronunciation and word-timing routes
support lazy or batch generation. Playback-frequency current-word selection
stays inside the Flutter client after the timing timeline is loaded.

`/v1/speech/jobs` provides non-blocking track-wide pronunciation-analysis and
word-timing jobs. Jobs report progress, can be cancelled or retried, and write
only to rebuildable speech caches. Provider unavailable/degraded and cache
invalidation events use the existing versioned event stream.
