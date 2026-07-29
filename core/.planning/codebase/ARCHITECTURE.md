# Architecture

## System Shape

```text
contracts / HTTP / events
          |
       api-http
          |
      application
       /   |    \
 domain  repositories  provider traits
          |              |
 persistence-sqlite   *-provider adapters

scripts/timeline-production and evaluation tools
          |
 versioned LLTimeline/resource artifacts
```

`domain` owns stable concepts. `application` owns use cases and ports.
`api-http` adapts loopback HTTP/SSE/WebSocket requests. Persistence and provider
crates implement ports. Python tooling produces/evaluates resources but is not
embedded in the lightweight consumer runtime.

Concrete LLM and realtime protocol selection is assembled in the HTTP
composition root through application-owned factories. Forced alignment uses an
application-owned provider interface with its Python process/JSON protocol
implemented by `local-runtime`; typed degradation and provider/model/protocol
provenance remain visible to the pipeline without making the main transcription
workflow fail. Cancellation is carried through that interface, kills and reaps
an active sidecar process, and is rechecked before each timeline, cue, or corpus
write. The descriptor fingerprints the sidecar and records the protocol,
torchaudio version, model bundle, and model asset.

## Runtime Boundary

`api-http` binds loopback on a random port and emits a structured startup
handshake containing address, bearer token, API version, contract version, and
runtime version. The app launches the pinned binary and rejects incompatible
handshakes before normal requests.

Speech-batch, sound-line, and LLM-batch lifecycle records use the shared
application `BackgroundJobStore` interface. SQLite is the production adapter;
state, progress, cancellation, retry lineage, interruption, and queued-job
recovery survive a service restart. Transcription jobs use their own
domain-specific SQLite compare-and-swap transitions because their import stage
is an explicit irreversible commit point.

Provider credential creation first persists a reserved cleanup reference,
writes the OS keychain, then atomically activates the profile reference while
removing that reservation and enqueuing any stale credential. Reservations
abandoned by a crashed process are promoted at startup. Cleanup is idempotent
and retryable, so an unavailable keychain cannot make an already committed
profile mutation appear to have failed or permanently lose the stale reference.

Before a schema upgrade, SQLite publishes a source-schema-versioned recovery
copy only after a same-directory temporary copy is synced. Hard-link
no-replace publication plus parent-directory sync prevents a partial copy from
being accepted as a valid backup, while later source versions receive their own
subtitle-preserving recovery point.

Subtitle import and language retokenization cross one repository unit-of-work
interface that atomically persists the authoritative track/sentences and
replaces the rebuildable corpus projection. Stable sentence identities are
updated in place so language correction does not delete subtitle data or
dependent facts.

## Contract Boundary

OpenAPI and resource/event schemas are core-owned. Route parity validates
method+path coverage. Contract and runtime archives include manifests,
core commit, versions, and hashes. `listen-app` consumes releases through its
lock file; no compile-time source dependency exists.
