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

legacy scripts/timeline-production       external offline producer
          |                                       |
 versioned LLTimeline --migration--> deterministic .listenpkg
                                                   |
                                      bounded Core import
```

`domain` owns stable concepts. `application` owns use cases and ports.
`api-http` adapts loopback HTTP/SSE/WebSocket requests. Persistence and provider
crates implement ports. Python tooling produces/evaluates resources but is not
embedded in the lightweight consumer runtime.

The portable content-resource contract lives under
`contracts/content-package/v1`. A deterministic `.listenpkg` ZIP binds one
Content Document descriptor to immutable, raw-byte-SHA-addressed resource
files. Its common typed envelope carries subject, closed hash dependencies,
provenance, quality, and a kind-specific payload. At least one Subtitle Text
Track is required in v1; every Analysis Resource is optional so the package can
represent partial generation honestly. Package data excludes core-local
identity and lifecycle state as well as all learner facts.

`content-package` owns bounded directory/ZIP inspection, raw-byte identity
verification, compatibility checks, and typed decoding. The application
adapter projects supported package resources into candidate-only Core records
and reports unsupported-but-preserved resources explicitly. A dedicated
`ContentPackageImportRepository` operation commits the track, metadata,
resources, and corpus projection in one transaction. Reimport skips existing
identities, never creates or changes an active selection, and rejects a
resource identity already owned by another track or media item. This operation
is separate from legacy LLTimeline import, whose lifecycle policy may activate
resources.

The first generation split is the reusable whole-media path from media bytes
through ASR Subtitle Text Track and Word Timeline to a native `.listenpkg`.
Provider/model execution, media preprocessing, and batch generation belong on
the external producer side of that boundary. The existing whole-media
transcription runtime and `scripts/timeline-production` remain legacy migration
paths until production cutover is verified; they are not the target interface
for new generation work. Learner-recording transcription, realtime
conversation, and learner-dependent or genuinely realtime LLM behavior remain
Core responsibilities.

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

Foundation learning preparation is a separate application module rather than a
new generic background-job kind. Its interface accepts an exact media,
SubtitleTrack selection plus the recommended-foundation intent. Audio-stream
selection belongs to upstream ASR or separately confirmed phone analysis, not
this text-derived plan. A fixed typed plan owns the three required fast slots: WordTimeline,
ChunkTimeline, and SenseGroup. Dedicated SQLite runs use revision
compare-and-swap and an active-target partial unique index for durable
single-flight; startup recovery, cancellation, retry, plan/input fingerprints,
and artifact references remain preparation-specific.
The local-runtime coordinator validates the current media and subtitle
fingerprints before local writes. It reuses a valid active resource or creates
an idempotent preparation candidate, then atomically activates that candidate
only when the resource family has no active selection. Existing user or
higher-quality active resources are never replaced. ChunkTimeline depends only
on the exact WordTimeline selected by the run; SenseGroup is independent and
can complete even when word timing fails. Separate text and phrase-analysis
fingerprints prevent unrelated phrase updates from invalidating WordTimeline
while still invalidating ChunkTimeline and SenseGroup when their true inputs
change.

Views A and B are deterministic projections from a ready WordTimeline and the
current language capability; they are readiness outputs, not durable resource
slots. The current projection implementation is English-only and reports
unsupported or unknown languages honestly. SoundLine remains an independent
best-effort acoustic enrichment path and does not block foundation readiness.
View C depends on separately confirmed Phoneme Analysis and is outside this
plan. Cancellation intent retries revision conflicts until it is durable.

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
