# ADR 0015: Lexical Capability, Evidence, and Override Are Separate

- Date: 2026-07-06
- Status: Accepted for Phase 3.4.1
- Supersedes: ADR 0012 decision 3 (single global `LearningStatus` as the durable comprehension-axis asset)
- Context: Phase 3.4.x Learning Domain Model v2 shared context

## Context

The current durable lexical state is a nullable three-value enum:

```text
null
unknown_meaning
known_not_recognized
known_recognized
```

It was intentionally designed as a language-agnostic meaning × sound comprehension axis. This was
useful while the product only needed to distinguish unknown meaning from known-but-not-heard and
known-and-heard.

The Phase 3 learning loop now records practice attempts, review attempts, per-sentence recognition
observations, deduplicated recognition evidence, and user-confirmed upgrade suggestions. The single
enum can no longer represent the facts without loss:

- reading and listening can develop independently;
- speaking and writing are productive capabilities with no place in the old enum;
- no evidence is different from evidence of non-acquisition;
- one context result is different from a durable capability assessment;
- a system inference is different from a user declaration;
- a lexical form may later split into multiple senses.

Keeping the enum as the authority would force later phases to invent hidden conventions, such as
treating `null` and `unknown` as the same value or using review success to silently mutate a global
state. Those conventions would corrupt diagnosis and portable learning history.

## Decision

### 1. Four capability dimensions

Lexical capability uses four independent, language-agnostic dimensions:

```text
reading
listening
speaking
writing
```

No mandatory implication is encoded between dimensions. Product heuristics may propose relationships,
but the domain does not assume, for example, that listening acquisition implies reading acquisition or
that writing acquisition implies speaking acquisition.

### 2. Assessment is tri-state, not boolean

Each dimension uses:

```text
unassessed
not_acquired
acquired
```

`unassessed` means the system has no current conclusion. It must not be rendered, queried, diagnosed,
or exported as `not_acquired`.

The user-facing control may remain a simple acquired/not-acquired choice. Clearing a choice returns the
user override to absent; it does not manufacture a negative assessment.

### 3. Evidence, projection, override, and effective state are separate

The model has four conceptual layers:

```text
observation/evidence
        ↓
system projection
        ↓
effective assessment
        ↑
optional user override
```

- **Evidence** records what happened in a task and context.
- **Projection** is a versioned system conclusion derived from evidence or legacy migration.
- **Override** is an explicit user declaration for one capability dimension.
- **Effective assessment** is a read model: override when present, otherwise projection, otherwise
  `unassessed`.

An override never deletes evidence. New evidence never silently overwrites an override. A system may
generate a suggestion asking the user to change an override.

### 4. Initial target identity

Phase 3.4.1 attaches lexical capability to the existing `LexicalEntry`. Contracts reserve an optional
future sense identity, but the phase does not introduce full `LexicalSense` persistence or word-sense
disambiguation.

This is an explicit staging choice. It avoids pretending that lemma-level state is permanently
sufficient while keeping the first migration bounded.

### 5. Existing evidence remains durable

Existing `LexicalObservation`, `PracticeAttempt`, `ReviewAttempt`, recognition evidence, and upgrade
suggestion records are not rewritten or discarded.

Existing `RecognizedInContext` / `NotRecognizedInContext` facts are listening-capability evidence.
Adapters may expose them through the new projection seam. A later phase may unify physical evidence
storage, but Phase 3.4.1 does not require a destructive event-table rewrite.

### 6. Legacy migration mapping

Schema v21 legacy state is projected into the new dimensions as follows:

| Legacy value | Reading | Listening | Speaking | Writing |
|---|---|---|---|---|
| `null` | unassessed | unassessed | unassessed | unassessed |
| `unknown_meaning` | not_acquired | unassessed | unassessed | unassessed |
| `known_not_recognized` | acquired | not_acquired | unassessed | unassessed |
| `known_recognized` | acquired | acquired | unassessed | unassessed |

Backfilled assessments carry an explicit `legacy_learning_status_migration` source. They are
projections, not user overrides, even when the old state originally came from a user selection: the old
record does not contain per-channel intent precise enough to reconstruct four declarations.

### 7. Conservative legacy compatibility view

During the compatibility window, an effective capability profile may be exposed as legacy state using
only these rules:

```text
reading=not_acquired
  -> unknown_meaning

reading=acquired + listening=not_acquired
  -> known_not_recognized

reading=acquired + listening=acquired
  -> known_recognized

all other combinations
  -> null / unclassified
```

Speaking and writing do not affect the legacy view. Inexpressible combinations stay unclassified rather
than being coerced into a false linear state.

### 8. Additive migration and authority switch

Schema v22 adds capability persistence. It does not drop or reinterpret the physical
`lexical_entries.status` column in place.

The rollout stages are:

1. add domain types and pure compatibility functions;
2. add v22 persistence and backfill;
3. add dual-read/compatibility write adapters;
4. migrate diagnosis, API, assets, and Flutter consumers;
5. switch new capability storage to authority;
6. retire physical legacy storage only in a later explicit cleanup decision.

Git rollback is not a database downgrade strategy. Migration safety relies on the existing pre-migration
backup path plus v21-to-v22 recovery tests.

### 9. Portable assets preserve semantic source

The next vocabulary asset bundle shape must distinguish:

- capability dimension;
- assessment;
- projection source and algorithm version when applicable;
- user override when present;
- timestamps needed for conflict resolution.

Import must not let an older migrated projection overwrite a newer local override. Old bundles remain
importable through the same legacy mapping. A new bundle presented to software that cannot understand
its version must fail explicitly rather than silently dropping channel data.

### 10. Diagnosis consumes effective capabilities plus context evidence

- Meaning-barrier rules use reading capability as the initial text-mediated lexical knowledge signal.
- Speech-recognition-barrier rules use listening capability and sentence-specific listening evidence.
- `unassessed` produces insufficient information, not a barrier.
- Context evidence can explain a failure even when a durable listening assessment is acquired; it does
  not automatically downgrade the durable profile.

This preserves the distinction between “usually can hear it” and “did not hear it in this sentence.”

## Consequences

### Positive

- The model represents the common reading-known/listening-not-acquired profile directly.
- Missing speaking/writing evidence remains honest instead of becoming false negative data.
- Review and practice evidence can improve projections without mutating user declarations.
- Phase 3.5 can compute meaning fit and sound fit from distinct signals.
- Future speaking, writing, and lexical-sense work has a stable extension seam.
- Legacy data and APIs can migrate incrementally while main remains runnable.

### Negative

- State reads become a projection instead of a single-column lookup.
- Conflict resolution and portable asset merge rules become more explicit and more complex.
- During migration, legacy and new representations coexist and require drift tests.
- Old status history cannot be perfectly reconstructed as per-channel override history.

## Rejected Alternatives

### Four booleans

Rejected because `false` cannot distinguish no evidence from confirmed non-acquisition.

### Four nullable booleans

Rejected as the public domain vocabulary because it hides semantics in null/false conventions and makes
source/projection/override layering awkward. Storage may use compact encodings, but contracts use named
assessments.

### Keep `LearningStatus` and add speaking/writing flags

Rejected because reading/listening remain incorrectly coupled and the system still cannot distinguish
unassessed from negative evidence.

### Derive all state live from attempts

Rejected for the initial migration. Existing user choices, imports, sparse evidence, query performance,
and offline portable assets require a durable current projection/override layer. Evidence remains the
reason for the projection, not the only query surface.

### Treat migrated old status as four user overrides

Rejected because the old interaction did not capture four independent declarations. Doing so would
invent user intent and make later evidence unable to improve migrated values without appearing to
override the user.

### Implement LexicalSense in the same phase

Rejected because sense identity, dictionary alignment, WSD, and merge behavior are a separate large
domain problem. Phase 3.4.1 reserves the seam without making capability migration depend on it.

## Compatibility with ADR 0012

ADR 0012 remains authoritative for:

- Token / LexicalUnit / ListeningUnit separation;
- provider-opaque normalization;
- language profiles and clean capability degradation;
- status versus language-specific diagnosis reasons;
- the future L1-to-L2 diagnosis seam.

This ADR supersedes only the decision that one linear `LearningStatus` is the stable durable
cross-language comprehension asset. The new cross-language invariant is the capability dimension and
assessment vocabulary, with evidence and override kept separate.
