---
status: accepted
---

# Personal Expression uses archive before erasure

## Context

A User Sentence Pattern is a learner-owned, versioned asset whose Personal
Expression uses contribute durable learning history. The existing DELETE
operation cascades its immutable versions and Personal Expression attempts, but
does not erase all linked semantic attempts, recordings, files, judgments,
derived indexes, or backups. Treating that operation as privacy erasure would
therefore destroy some history while giving a false assurance about the rest.

## Decision

User Sentence Patterns use an explicit archive/restore lifecycle:

- archiving preserves the pattern identity, every immutable version, Personal
  Expression attempt, source snapshot, semantic-attempt link, and historical
  or Coach interpretation;
- archived patterns are absent from default active lists, search results,
  suggestions, and new learning actions;
- archived patterns reject revision and new Personal Expression attempts;
- restoring re-enables the same pattern identity and complete version history;
- full-fidelity export retains the lifecycle state and preserved history; if a
  future import contract is introduced, it must preserve that lifecycle.
  Archive never starts an implicit retention or deletion timer.

The legacy User Sentence Pattern DELETE operation is deprecated, not redefined.
While it remains in a published contract it keeps its documented destructive
meaning and must be clearly identified as legacy. New clients and internal
workflows use archive/restore. Removing DELETE requires an explicit breaking
contract-version decision after the app has shipped the replacement journey;
it cannot silently become archive or be relabeled as privacy erasure.

Personal Content Erasure is a separate future irreversible workflow and is not
implemented by this decision. It requires an impact preview and an explicit
scope covering pattern content, linked semantic tasks, recordings and files,
judgments, derived indexes, exports, and backup retention. Its design must also
decide whether and how erasure creates an exception to append-only learning
history while retaining only the minimum non-sensitive tombstone or audit facts
that policy requires.

## Consequences

Archive protects explainability and makes ordinary removal reversible, but it
does not satisfy a request to erase personal content. During migration, the
legacy DELETE risk remains available only for compatibility and must not be
used by new product journeys. Implementation proceeds as separate slices:

1. receive the app-owned archive/restore journey and data/operation request,
   then design OpenAPI, compatibility, version, error, and retry semantics;
2. implement the accepted contract through domain, application, persistence,
   HTTP, migration, and tests;
3. coordinate the app's archived/restore journey and pinned artifact update;
4. preserve lifecycle state and history through export; design import only
   after its own contract request;
5. remove DELETE only in an explicitly breaking contract migration;
6. design Personal Content Erasure under a separate issue and ADR.

## Rejected alternatives

- **Keep cascade DELETE as ordinary removal.** It destroys durable learning
  history and still fails to erase all sensitive content.
- **Silently change DELETE into archive.** Existing callers reasonably rely on
  the published destructive meaning; changing it in place hides a semantic
  incompatibility.
- **Treat archive as privacy erasure.** Hiding an asset while retaining its
  content and history is deliberately reversible and cannot satisfy an
  irreversible erasure request.
