# Runtime architecture

This document describes the implementation's module and process boundaries.
[CONTEXT-MAP.md](../../CONTEXT-MAP.md) describes semantic ownership;
[MODEL.md](../../MODEL.md) describes product direction. Neither declares every
planned capability implemented. Current scope is in [STATE.md](../../STATE.md).

## Modules and contracts

| Module | Implementation authority |
|---|---|
| `app/` | Flutter presentation, interaction state, playback, native integration, and desktop assembly |
| `core/crates/domain/` | Domain types and repository interfaces |
| `core/crates/application/` | Use cases and learner/material policies |
| `core/crates/persistence-sqlite/` | SQLite repositories and migrations |
| `core/crates/api-http/` | Authenticated loopback HTTP/event adapter and process composition |
| Other Core adapter/runtime crates | Provider implementations, local services, and bounded process execution |
| `gen/src/listen_gen/` | Material production, provider execution, qualification, and package construction |
| `core/contracts/` | Canonical OpenAPI, event, and Content Package schemas |
| `tools/` | Shared source snapshot, setup, verification, and release assembly |

Core dependency direction is `domain <- application <- adapters`. Persistence
implements repository interfaces. HTTP handlers adapt requests to use cases;
provider details stay behind application interfaces. App consumes typed API
results and owns UI state; it does not own Core's persistence policy.

## Processes

```text
Flutter App -- authenticated loopback HTTP/events --> Core api-http
     |
     +-- verified Python zipapp + machine events --> Gen
                                                      |
                                                      +--> optional provider processes

Gen package --> Core validation / installation / explicit adoption --> App reads
```

App launches the Core sidecar, validates startup identity and compatibility,
and owns its lifecycle. Core binds a random loopback port with an API token.
See [api_service.dart](../../app/lib/services/api_service.dart) and
[Core composition](../../core/crates/api-http/src/main.rs).

App verifies Gen's manifest and artifact hashes before execution. Release
builds use the generated embedded lock and bundled zipapp; debug builds also
support explicitly generated development inputs. Gen progress, cancellation,
and terminal outcomes cross the [machine-event protocol](../protocols/gen-machine-events.md).
See [release verification](../../app/lib/services/listen_gen_release_service.dart)
and [process execution](../../app/lib/services/listen_gen_process_service.dart).

Gen emits a Content Package. Core owns package validation, candidate
installation, and explicit Learning Edition adoption. App consumes the adopted
material through Core; it does not interpret raw provider payloads as canonical
learning material. See the [v3 contract](../../core/contracts/content-package/v3/README.md).

Optional realtime voice services run separately from Gen. Their setup and
lifecycle are described in the [local speech guide](../development/local-speech.md).

## Persistence and boundaries

Core owns durable domain storage and migrations. App also has local preferences,
asset bindings, and support files. Keep learner facts distinct from replaceable
media, generated resources, caches, and projections. UI scope reduction must
not silently erase durable facts or rewrite published package identities.

Managed files use platform application-support locations, with explicit
isolated paths for tests. User-selected source assets may remain external;
missing media is not permission to delete learning history. Credentials never
belong in ordinary settings reads, logs, packages, or documentation examples.

## Build identity

Development uses one identified working-tree snapshot. Releases use one clean
committed export for Core, Gen, and App and verify generated locks and packaged
bytes. Native runtime tools are prepared inputs with notices, not checked-in
binaries. The product is a single App bundle; model weights and some optional
provider/Python dependencies are separate runtime requirements.
See [DEVELOPMENT.md](../../DEVELOPMENT.md) and
[distribution](../development/dev-preview-distribution.md).
