# Local Runtime Module Interface

Status: accepted for Phase 2.24

Date: 2026-07-14

## Decision

Create a workspace crate named `local-runtime`. It owns local model/resource
lifecycle, background speech jobs, process execution, tool discovery, temporary
workspaces, checksums, downloads, and transport-neutral job events.

`api-http` remains the composition and transport adapter. Route modules may
construct runtime commands and map runtime facts to the existing HTTP/OpenAPI/SSE
contracts, but they do not implement job state machines, install/download flows,
or child-process workflows.

## Considered shapes

### 1. Independent `local-runtime` crate — selected

- **Depth:** one interface hides queueing, cancellation, cleanup, executable
  discovery, model installation, checksums, and failure mapping.
- **Locality:** all local-machine policy is in one crate instead of being spread
  through HTTP routes and coordinators.
- **Dependency direction:** depends on application ports, domain contracts, and
  the versioned event contract; it has no Axum or HTTP request/response types.
- **Test surface:** production process/download adapters can be replaced by
  deterministic in-memory adapters at the coordinator boundary.
- **Reuse:** a future mobile/desktop FFI composition can invoke the same runtime
  without importing an HTTP server.

### 2. Runtime modules inside `application` — rejected

This would pull Tokio process, filesystem layout, HTTP download, and platform
tool discovery into the use-case layer. Those are local infrastructure policies,
not application rules, and would reverse the existing dependency direction.

### 3. Keep runtime in `api-http` and split files — rejected

Mechanical file splitting improves navigation but leaves transport coupled to
queue state, process execution, download policy, and cleanup. It does not create
a semantic boundary and cannot be reused without Axum composition.

## Public capability interface

`local-runtime` exposes four cohesive coordinators:

- `TranscriptionCoordinator`: transcription model catalog/install and text-line
  job lifecycle.
- `PhoneticAnalysisCoordinator`: phonetic model/install and analysis job
  lifecycle.
- `SpeechBatchCoordinator`: whole-track pronunciation/timing batch lifecycle.
- `SoundLineCoordinator`: best-effort audible-structure enrichment lifecycle.

Commands and returned job/model facts are transport-neutral serializable values.
The crate exposes no Axum type, status code, route DTO, or `ApiState`.

Shared local infrastructure is owned by internal runtime modules rather than
borrowed from one workflow by another:

- `ProcessRunner`: production Tokio adapter and deterministic fake adapter.
- `ArtifactDownloader`: production HTTP/file adapter and deterministic fake
  adapter.
- tool discovery and forced-alignment resolution;
- temporary workspace and checksum primitives.

These seams are justified by two adapters (production and deterministic test)
and hide failure/cancellation complexity. Pure speech algorithms remain direct
functions and do not receive adapter traits.

## Event ownership

The existing `api-events` crate remains the versioned cross-process event
contract. `local-runtime` emits those transport-neutral envelopes/facts;
`api-http` only exposes them through SSE. This preserves wire names and payload
shapes while preventing runtime code from depending on SSE.

## Replacement rule

Coordinator implementations move out of `api-http`; old modules are deleted in
the same change. Temporary pass-through coordinator wrappers are not allowed.
