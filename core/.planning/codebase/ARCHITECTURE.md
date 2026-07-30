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

Installable dictionary assets resolve through `learning-resource-runtime`.
The installer and all dictionary readers share its environment override,
default directory, opaque filename derivation, and file-replacement signature.
The legacy CMUdict-only path override remains the highest-priority compatibility
input for that resource.
Parsed indexes are replaceable caches: an asset installed, replaced, removed,
or damaged after process start is reflected by subsequent lookups without a
restart.

Local semantic-embedding upgrades build under an isolated candidate directory.
The runtime records a size-and-SHA-256 inventory for the complete candidate,
moves it to an immutable version directory, reloads it from that final path,
and only then atomically publishes the active manifest. Ordinary download,
validation, or activation failure preserves the last-good provider, readiness,
and index fingerprint while retaining separate failed-candidate provenance.
Restart removes partial candidates and restores only the manifest-selected
version; legacy flat caches remain readable until the first successful upgrade.

Sound-line jobs probe the media's audio-stream inventory before extracting
evidence. A sole audio stream resolves deterministically to ffmpeg audio index
zero; media with multiple streams requires an explicit ffmpeg-relative index.
The resolved index remains in the durable job and completion event. A missing
selection, stale selection, or failed probe produces a stable failure code and
cannot create ready listening evidence from an arbitrary default stream.
Every generated sound-line candidate also records that index in its timeline
metrics, so exported analysis remains self-describing without a job lookup.
Missing source timings or a failed candidate commit leaves the durable job
failed and emits no completion event; cancellation remains a distinct durable
terminal state.

Provider credential creation first persists a reserved cleanup reference,
writes the OS keychain, then atomically activates the profile reference while
removing that reservation and enqueuing any stale credential. Reservations
abandoned by a crashed process are promoted at startup. Cleanup is idempotent
and retryable, so an unavailable keychain cannot make an already committed
profile mutation appear to have failed or permanently lose the stale reference.
Realtime profiles may also be honestly keyless. The
`local_cascade_realtime` adapter accepts only loopback WebSocket endpoints and
does not reserve a keychain reference; remote realtime factories still reject a
missing credential.

An optional local ASR → LLM → TTS sidecar is supervised by `local-runtime`.
The composition root enables it only through explicit environment
configuration. Runtime policy appends realtime-mode and loopback-bind
arguments, waits until `/v1/pool` reports an available initialized pipeline,
captures only a bounded stderr tail, and terminates/reaps the process group on
shutdown. Realtime routes see only the application adapter seam and never child
process details.

The optional syntax runtime installs upgrades into isolated versioned release
directories. A candidate must start, probe successfully, and match the
qualified delivery identity before `SyntaxCapabilityManager` durably publishes
its active-directory journal and switches the in-memory provider pointer.
Ordinary candidate failures preserve the last-good provider and readiness;
candidate failure provenance and deferred old-release cleanup remain in an
internal runtime journal rather than the learner-facing capability contract.

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

LLTimeline import uses its own application-owned unit-of-work port. Application
validation and projection assembly finish before the adapter starts writing;
SQLite then commits optional detached media identity, subtitle track, resource
metadata, independent timeline families and active selections, and corpus rows
in one transaction. Any resource or corpus write failure rolls back the whole
import, so there is no ambiguous post-commit reindex state. The import builds
corpus rows from the same canonical rhythm derivation used by later rebuilds,
refreshes legacy active-word compatibility rows inside the transaction, and
rejects resource IDs already owned by another track or media item.

Detached LLTimeline import creates a synthetic `lltimeline://` identity with
`MediaAvailability::Missing`; document path metadata remains a provenance
snapshot and is never exposed as a live playback source. Explicit import for a
registered media item preserves that media item's current availability, so
attaching text/analysis cannot silently repair source loss.

## Contract Boundary

OpenAPI and resource/event schemas are core-owned. Route parity validates
method+path coverage. Contract and runtime archives include manifests,
core commit, versions, and hashes. `listen-app` consumes releases through its
lock file; no compile-time source dependency exists.
