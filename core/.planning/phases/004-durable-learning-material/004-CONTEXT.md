# Durable Learning Material Context

## Product Phase

This Core phase is the next repository slice of Product Alpha Phase 1,
Single-user Core Loop Alpha, defined in the canonical `listen` project. Phase
003 made membership explicit for the current media path; this phase establishes
the generic learner-facing material identity required by raw text, media and
mixed compositions.

## Starting Constraint

`MediaItem` remains a device-local rendition record with a file path. It cannot
become the durable material aggregate without conflating learner ownership,
composition, revision identity and local availability. Content Package v2
already names Material Revision and Media Rendition but intentionally performs
no local persistence, installation or adoption.

## Slice Boundary

- Add a path-free Learning Material aggregate with explicit Personal Library
  membership and an immutable current Material Revision.
- Represent exact document text and references to registered media through a
  closed typed asset union; derive text, audio, video or mixed shape.
- Create deterministic initial identities so equal retries converge.
- Append immutable revisions and atomically advance the current pointer while
  preserving material identity, creation time and membership.
- Bind media renditions to their material atomically and resolve material by
  media identity.
- Make material membership authoritative while synchronizing the legacy media
  library projection transactionally for compatible consumers.
- Backfill every existing media item into one equivalent material/revision
  graph without changing its membership or timestamps.
- Expose the lifecycle as an additive, path-free HTTP/OpenAPI contract.

## Compatibility

The HTTP surface is backward-compatible and additive, so contract `3.2.0`
keeps API generation `1` and runtime `0.7.0`. SQLite v59 is a forward migration.
Existing media routes remain available and their membership evidence remains
synchronized from the material authority.

## Non-goals

- no file copying, moving, deletion or Managed Asset Store policy;
- no Source Identity, subscription or hosted catalog persistence;
- no Package Installation or Learning Edition Adoption;
- no automatic resource activation or learner-state ownership by packages;
- no network acquisition, live model, credential or paid inference.
