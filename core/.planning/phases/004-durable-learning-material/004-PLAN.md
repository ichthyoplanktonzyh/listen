# Durable Learning Material Plan

> Status: complete. See [004-CLOSEOUT.md](004-CLOSEOUT.md). Consumer pinning is
> the remaining cross-repository handoff, not Core implementation work.

## Domain And Application

1. Define validated Learning Material, Material Revision, document-text asset,
   media-rendition asset and composition-shape types.
2. Derive deterministic initial material/revision/asset identities and reject
   empty or duplicate compositions.
3. Add create, append, read, historical-revision, retained-list, retain,
   unretain and media-resolution use cases behind a material repository port.
4. Resolve media inputs through the media repository and never accept or expose
   a local path at the material boundary.

## Persistence

1. Add SQLite v59 tables and constraints for materials, immutable revisions,
   typed assets and media bindings.
2. Backfill every pre-existing media row while preserving timestamps,
   availability and membership.
3. Commit initial creation, revision append/current-pointer advance and media
   bindings atomically with rollback coverage.
4. Synchronize material membership to all bound legacy media rows in the same
   transaction without touching revisions, resources or learner state.

## HTTP And Contract

1. Add retained list/create, material read, revision append/read, membership
   retain/unretain and media-resolution routes through application use cases.
2. Use flat `asset_type` wire variants and required-but-nullable membership
   evidence; reject unknown types and invalid ownership honestly.
3. Keep method/path parity, OpenAPI `3.2.0` and generated TypeScript identity in
   lockstep.

## Acceptance

- text-only, media-only and mixed materials persist and reload after restart;
- equal creation retries converge; conflicting or foreign revisions fail;
- explicit false creates Temporary Material, while omitted/null retain uses the
  retained default;
- retained list excludes temporary materials without making them unreadable;
- media resolution returns the current material revision with no local path;
- membership changes are idempotent and preserve the full material graph and
  learner-owned data;
- media re-registration preserves material identity, revision and progress;
- focused, workspace, strict lint, migration, HTTP, contract and diff gates
  pass without credentials or paid model calls.

## Handoff

Publish immutable `3.2.0` contract/runtime artifacts from the merged clean
commit. Hand the consumer exact tag, commit, versions, URLs and SHA-256 values.
The consumer may then make Learning Material the Personal Library authority and
join media rendition availability through media identity during migration.
