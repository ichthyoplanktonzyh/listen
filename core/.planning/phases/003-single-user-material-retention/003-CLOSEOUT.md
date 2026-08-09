# Single-user Material Retention Closeout

## Outcome

Core now separates media registration from Personal Library membership.
Explicit temporary registration remains readable for progress and resources
but stays out of the library; retain and unretain are idempotent membership
operations. Unretaining preserves media identity, progress, subtitles,
resources and learner-owned records. SQLite v58 backfilled every pre-existing
media row as retained.

## Compatibility And Release

- API generation: `1`
- Contract: `3.1.0` (backward-compatible additive minor)
- Runtime: `0.7.0`
- Merge: `787da6f`
- Immutable release: `v0.7.0-phase1.1`
- Contract archive SHA-256:
  `055a194f317531983df9d9cf888e81467fee2fe3eb755defc20e916ccd30c8ec`
- macOS arm64 runtime archive SHA-256:
  `75645860174a7d58d15d2c5e4e13656153655a6eed2c559d81ccd37dbd99805a`

The registration request's omitted `retain` field keeps the old retained
default. Nullable `retained_at_ms` and additive membership routes let newer
consumers state temporary or retained intent explicitly.

## Validation

Domain, application, SQLite migration/repository, HTTP, OpenAPI parity,
generated-client, workspace, strict lint and release-artifact gates passed
without credentials or model credit before publication. Published manifests
bind the exact merge commit, versions and per-file hashes.

## Deferred

Generic text/media/mixed Learning Material, immutable material revisions and
material-authoritative membership moved to phase 004. Package Installation,
Learning Edition Adoption, RSS/Atom convergence and hosted catalog behavior
remain later Phase 1 slices.
