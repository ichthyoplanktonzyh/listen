# Personal Expression Lifecycle Policy

Status: accepted domain policy for
[core issue #84](https://github.com/ichthyoplanktonzyh/listen-core/issues/84).
The implementation authority is
[ADR 0035](../decisions/0035-personal-expression-archive-before-erasure.md).

This policy replaces ordinary destructive removal with archive/restore while
keeping Personal Expression itself as a learner-facing capability. It does not
change the current Rust, SQLite, HTTP, or OpenAPI behavior in this documentation
slice.

## Lifecycle

```text
active ── archive ──> archived
   ^                    │
   └────── restore ─────┘
```

`active` and `archived` are states of the same User Sentence Pattern identity.
Archive does not create a replacement asset, version, or attempt. Restore does
not copy or renumber the retained history.

## Archive invariants

- Pattern identity and every immutable version remain stable.
- Personal Expression attempts and their links to semantic Pattern Production
  attempts remain queryable for historical explanation.
- Source snapshots, self-assessments, assistance facts, and historical metrics
  remain intact.
- Default active list/search/suggestion views exclude archived patterns.
- Explicit archived views and full-fidelity export include lifecycle state.
- Revise and new-attempt commands reject archived patterns.
- Restore makes the same identity eligible for active views and new work.
- Archive schedules no implicit deletion and is never described as erasure.

Read models may exclude archived patterns from prospective recommendations, but
must not rewrite historical conclusions as though the pattern or its uses never
existed.

## Deprecated DELETE compatibility handoff

The current
`DELETE /v1/personal-expression/patterns/{pattern_id}` route has destructive
cascade semantics and remains current runtime fact until later implementation
slices change the contract. Its migration rules are:

1. introduce additive archive/restore operations and lifecycle state;
2. mark DELETE deprecated in the canonical contract without changing its
   meaning;
3. move `listen-app` and all internal callers to archive/restore and ship the
   replacement journey;
4. verify no supported consumer depends on DELETE;
5. remove DELETE only with an explicit breaking contract release and migration
   notes.

The compatibility endpoint is neither the recommended removal path nor a
privacy guarantee. Documentation and UI must not present it as Personal Content
Erasure.

## Erasure is a separate policy

Personal Content Erasure is intentionally outside #84's archive implementation.
A future design must enumerate authoritative records, local files, derived
indexes, exports, migration recovery copies, and backup retention before it can
make an erasure promise. It must specify impact preview, partial-failure and
retry semantics, surviving non-sensitive audit facts, and its relationship to
append-only learning history.

## Follow-up PR slices

1. **App-originated contract request:** specify the active/archived journey,
   operations, visible states, errors, retry, privacy copy, and compatibility
   deadline.
2. **Contract design:** add archive/restore schemas and operations, deprecate
   DELETE, classify the contract version, and validate examples before runtime
   implementation.
3. **Implementation:** add state, migration, archive/restore repository and
   application behavior, active/archived queries, HTTP adapters, command
   rejection for archived patterns, and cascade-regression tests.
4. **Consumer handoff:** ship the app's active/archived views, restore action,
   copy, compatibility deadline, and pinned artifact update.
5. **Export:** preserve lifecycle state, versions, attempts, snapshots, and
   semantic-attempt links. If import is later requested, design it contract
   first rather than assuming a round-trip endpoint exists.
6. **Legacy removal:** inventory supported callers and remove DELETE only in a
   breaking release.
7. **Future erasure:** open a separate design/ADR covering all personal-content
   authorities, derived data, files, and backups.
