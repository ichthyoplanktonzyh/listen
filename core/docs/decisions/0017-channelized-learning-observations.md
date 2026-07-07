# ADR 0017: Channelized Append-Only Learning Observations

- Date: 2026-07-07
- Status: Accepted for Phase 3.4.4
- Context: Phase 3.4.x Learning Domain Model v2 shared context §5.3/§14; refinement review
  (`.planning/discuss/learning-domain-model-v2-refinement-review.zh.md`) §4.2/§4.3/§4.8;
  ADR 0015 decision 5 (existing evidence remains durable)

## Context

ADR 0015 separated capability projections from evidence but deliberately deferred the evidence
layer itself. Today the `observation → projection` arrow does not exist:

- `LexicalObservation` is a two-value, latest-wins record keyed by `(entry, sentence)`. A new
  result at the same context silently replaces history.
- It records no capability channel, no task type, no assistance conditions, and no surface form.
- Successful practice produces **no** observation at all; only failures are recorded.
- `LearningEvent` is an append-only journal, but its payload is untyped JSON aimed at telemetry
  and session narration, not a queryable per-(target, capability) evidence store.
- The projection slot is currently written only by manual/compat paths (legacy sync, import,
  upgrade confirmation). Every day this continues, the future evidence-projection algorithm's
  merge semantics get harder to define.

Phase 3.5 (meaning fit / sound fit) needs channelized evidence as input. Evidence not recorded
now is unrecoverable later; per the refinement review's layered-complexity principle, evidence-layer
richness is cheap and irreversible, so it lands before any consumer algorithm.

## Decision

### 1. New `LearningObservation` is append-only and channelized

```text
LearningObservation {
  id                    fingerprint of (target, task, outcome, source ref, occurred_at);
                        outcome participates because context marking reuses a
                        stable source ref — two judgments in the same
                        millisecond must stay two rows
  lexical_entry_id      current mastery-target identity
  sense_id              optional, reserved (ADR 0015 decision 4)
  capability            reading | listening | speaking | writing
  task_type             context_marking | cloze | dictation | subtitle_fade |
                        shadowing | review_recall | upgrade_confirmation
  outcome               success | partial | failure
  assistance            none | partial_text | full_text
  surface_form          optional form as encountered ("went", not "go")
  sentence_id           optional context
  media_id              optional context
  origin                user_marking | practice_task | review_task | legacy_backfill
  source_ref            optional practice/review attempt id or legacy observation id
  occurred_at_ms
}
```

Append-only: no upsert, no latest-wins replacement. Two attempts at the same word in the same
sentence are two rows. Deleting a lexical entry cascades (evidence without its target has no
consumer and no identity to reattach).

`surface_form` exists because listening capability does not transfer across inflected forms the
way reading does ("went"/"go" share no phonology). Lemma-level aggregation must be able to see
which form was actually heard (refinement review §4.3).

### 2. Task-to-channel mapping v1

Writers map deterministically; the mapping lives in one domain function and is versioned by this
ADR, not scattered across call sites:

| Writer | task_type | capability | assistance | outcome |
|---|---|---|---|---|
| User context marking | context_marking | listening | full_text (transcript visible) | recognized → success, not_recognized → failure |
| Practice Cloze | cloze | listening | full_text (text shown, target blanked) | Correct → success, Partial → partial, Incorrect → failure, Skipped → none |
| Practice Dictation | dictation | listening | none | same as cloze |
| Practice SubtitleFade | subtitle_fade | listening | partial_text | same |
| Practice Shadowing | shadowing | speaking | full_text | same |
| Review rating | review_recall | listening | none (audio-first queue) | Again → failure, Hard → partial, Good/Easy → success |
| Upgrade confirmation | upgrade_confirmation | suggestion's capability | none | success |

Honest limitations, recorded rather than hidden:

- This is a v1 static mapping. Cloze conflates meaning recall with listening; if 3.5+ evidence
  shows the conflation matters, the mapping version bumps and old rows keep their recorded values.
- Per shared-context invariant 16, only `assistance = none` observations can later support a
  listening `acquired` conclusion on their own; assisted successes are supporting evidence.

### 3. Successful practice now produces evidence

The failure-only asymmetry is removed: anchored lexical targets on a Correct/Partial attempt get
success/partial observations. The legacy `LexicalObservation` write path is unchanged (it still
feeds sentence-level diagnosis); the new table is written alongside it.

### 4. Projection writer exclusivity (shared-context invariant 17)

The projection slot for one `(target, capability)` has exactly one authoritative algorithm writer.
Current declared writers, unchanged by this phase:

- `legacy-status-compat-v1` / v22 backfill (`LegacyLearningStatusMigration` source)
- portable/external import (`Import` source)
- upgrade confirmation (`EvidenceProjection` source, `UPGRADE_EVIDENCE_CLASS`)

Upgrade confirmation is hereby declared a **transitional** direct writer: from this phase it also
appends an `upgrade_confirmation` observation, so that when a real evidence-projection algorithm
arrives it can consume the full observation stream and the direct projection write is removed in
the same change. No other new projection writers may be added before that algorithm exists.

### 5. Legacy backfill with explicit provenance

Migration backfills one `LearningObservation` per existing `LexicalObservation` row
(`capability = listening`, `task_type = context_marking`, `assistance = full_text`,
`origin = legacy_backfill`, `source_ref = legacy observation id`). Because the legacy table was
latest-wins and mixed user markings with practice failures, backfilled rows are marked
`legacy_backfill` rather than pretending to be precise user markings (invariant 14 analogue).

### 6. Portable assets carry observations additively

`VocabularyAssetBundle` gains an optional `learning_observations` field (serde default, bundle
version stays 6). Import appends rows whose ids are not present locally; append-only identity makes
merge trivial and conflict-free. Bundles from older exporters simply omit the field.

### 7. No read API, no Flutter surface, no decision changes

Per the field razor: writers are automatic (all server-side inside existing flows), and the
consumer is Phase 3.5. This phase adds no HTTP endpoints, no UI, and does not change diagnosis,
suggestions, or any user-visible behavior. Repository read methods exist for tests and for 3.5.

## Consequences

- Phase 3.5 gets channelized, append-only, surface-form-aware evidence from day one of its work.
- Evidence volume grows with practice; the table is insert-only with a
  `(lexical_entry_id, capability, occurred_at_ms)` index. No cleanup policy is defined yet —
  revisit when 3.5 defines its evidence window.
- Double-write with legacy `LexicalObservation` persists until diagnosis migrates to the new
  store (a later, separate decision).
- The static task mapping will be wrong in edge cases before it is right; rows record what the
  mapping said at write time, and `task_type`/`assistance` preserve enough rawness to remap.

## Rejected Alternatives

- **Extend `LexicalObservation` in place** — its `(entry, sentence)` latest-wins identity is the
  defect; changing identity semantics of an existing table is a destructive rewrite (violates
  ADR 0015 decision 5).
- **Use `LearningEvent` as the evidence store** — untyped JSON payloads, subject-keyed rather than
  target/capability-keyed; querying per-word listening history would mean scanning a journal.
- **Generic `learning_object_id` polymorphic target now** — no non-lexical writer exists
  (constructions are a 3.4.3 spike); premature genericity. Adding a parallel column or table for
  construction observations later is additive.
- **Ship the first projection algorithm in the same phase** — needs research grounding
  (AGENT.md algorithm rules) and 3.5's fit definitions; recording evidence must not wait for it.
