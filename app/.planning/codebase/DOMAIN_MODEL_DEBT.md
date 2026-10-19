# Domain Model Debt Backlog

## Purpose

This backlog governs the remaining transport-shape leakage after the strict
MVVM baseline at commit `85f736f`. It is intentionally a gradual migration,
not authorization for a repository-wide model rewrite.

The target dependency path is:

`Service/API DTO -> Repository mapping -> immutable domain model -> ViewModel -> View`

`test/architecture_layering_test.dart` records the current debt as exact
per-file counts. That baseline is a one-way ratchet: a change may remove debt
only when it lowers the recorded count in the same change, and it may never add
or restore an occurrence.

## Inventory by feature

### 1. Core session and backend events (first)

Current leakage:

- `CoreSessionRepository.events()` exposes `Stream<Map<String, dynamic>>`.
- `CoreSessionController` and `BackendEventCoordinator` receive and parse raw
  event maps.
- `lib/models/backend_event.dart` combines wire parsing with the client model.

Introduce a transport-owned event DTO/parser at the service boundary and make
the repository expose typed `BackendEvent` values. This is first because the
event stream is a central dependency with a small, well-defined seam.

### 2. Vocabulary and learning

Current leakage:

- lexical upsert values and observation `source` metadata cross repository
  interfaces as maps;
- external vocabulary imports retain `List<Map<String, dynamic>>` in state;
- occurrence/source maps pass through learning controllers, coordinators,
  navigation callbacks, and vocabulary/reading widgets;
- vocabulary detail widgets still receive map-shaped entries, occurrences, and
  history.

Candidate types:

- `LexicalEntryDraft` for create/update input;
- `LexicalSourceRef` for provenance currently carried by `source`;
- `VocabularyImportDocument` and `VocabularyImportRow`;
- `OccurrenceRef` (including media fingerprint and slice coordinates).

Migrate one vertical path at a time: occurrence playback, lexical source and
upsert, external import, then legacy vocabulary detail views.

### 3. Reading, writing, speaking, and manual review

Current leakage:

- task repositories accept map-shaped `target` values;
- `WritingTaskController` constructs its target JSON;
- `ManualReviewController` constructs a timeline payload and the repository
  accepts it unchanged.

Candidate types:

- a sealed `TaskTarget` family shared only where semantics really match;
- `WordTimelineRevisionDraft` for manual-review edits.

Start with one task kind and reuse the type only after the second migration
proves the abstraction. Do not introduce a generic property-bag wrapper.

### 4. Realtime conversation

Current leakage:

- connection headers are represented by a raw map;
- session and turn persistence APIs accept raw maps;
- the controller assembles session and learner-turn JSON.

Candidate types:

- `RealtimeConnectionConfig` with an explicit authorization value;
- `RealtimeSessionDraft` and `RealtimeTurnDraft`.

Keep WebSocket protocol encoding in the data/service layer. The controller
should express conversation intent and state, not wire keys.

### 5. Media, subtitle, and timeline

Current leakage:

- media-session load accepts a map-shaped LLTimeline document;
- media coordination reads nested metadata maps;
- slice playback and route callbacks transport occurrence maps;
- timeline models under `lib/models/timeline` contain extensive wire parsing.

Candidate types:

- `LLTimelineImportDocument`/DTO at the transport edge;
- `MediaIdentity` and the shared `OccurrenceRef` domain value.

Do this after occurrence playback is typed so media work does not create a
second competing occurrence representation.

### 6. Model-folder separation (last, incremental)

Many files under `lib/models` combine immutable client values with
`fromJson`/`toJson` and raw maps. As each feature above is migrated:

- place wire-only DTOs/parsers under `lib/data/models/<feature>`;
- keep portable domain/client values free of wire keys and transport imports;
- map DTOs to domain values in repositories;
- move a whole feature slice only when its call sites and tests migrate with it.

Do not mechanically relocate every model before feature boundaries are typed.

## Acceptance criteria for each vertical slice

A slice is complete only when all of the following hold:

1. Its repository public API contains neither raw transport maps nor a
   transport DTO.
2. Services parse/encode DTOs; repositories map DTOs to immutable domain values.
3. Controllers and presentation consume domain values and no longer know wire
   keys.
4. Mapping tests cover a representative payload, missing/optional fields, and
   malformed or unknown values where compatibility requires a decision.
5. Relevant controller/widget tests still cover success, failure, and stale or
   asynchronous completion behavior.
6. The exact architecture ratchet is lowered in the same change for every
   removed occurrence; no unrelated baseline is raised.
7. Formatting, the architecture test, strict static analysis, and the relevant
   feature/full test suite pass.

## Migration order

1. Typed core backend event stream.
2. Shared occurrence playback value, then its route/widget callbacks.
3. Vocabulary learning source/upsert and external import documents.
4. One semantic task target, followed by the remaining task kinds.
5. Manual-review timeline revision input.
6. Realtime connection/session/turn inputs.
7. LLTimeline media import and metadata.
8. Incremental DTO/domain folder separation for the migrated features.

## Non-goals

- No all-at-once rename or relocation of `lib/models`.
- No backend payload or protocol change as part of this cleanup.
- No generic `JsonMap` typedef presented as a domain abstraction.
- No new repository layer solely to hide an unchanged raw map.
- No unrelated UI or state-management redesign.
