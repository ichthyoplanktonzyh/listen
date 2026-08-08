# ADR 0016: Sense Groups Are Text Annotations Separate from Prosodic Chunks

- Date: 2026-07-07
- Status: Accepted for Phase 3.4.2
- Context: Phase 3.4.x Learning Domain Model v2 shared context

## Context

The current `ChunkTimeline` segments sentences into groups using acoustic evidence: inter-word
pauses, pre-boundary lengthening, a learned prosodic model, and punctuation heuristics. Each
`ChunkTimelineChunk` carries a time range (`start_ms`, `end_ms`) derived from word timings and
serves as the primary unit for chunk replay, chunk dictation practice, and rhythm visualization.

However, what drives the chunk boundary is primarily how the speaker organized the speech signal,
not how the sentence should be grouped for comprehension. The two often align but diverge when:

- A speaker splits a semantic unit across two prosodic phrases (e.g., for emphasis or breath).
- Fast speech merges two small semantic units into one prosodic phrase.
- Hesitation, repair, or parenthetical insertion creates acoustic boundaries that do not correspond
  to semantic boundaries.

The Phase 3.x learning loop needs a semantic grouping layer for:

- Comprehension training: "group these words into meaning units as you listen."
- Semantic barrier diagnosis: locating which meaning unit the learner cannot process.
- Practice targets: dictation and cloze drills at the semantic-unit level.
- Future sense-group-level observation evidence (Phase 3.8+).

Renaming `ChunkTimeline` to `SenseGroup` would lose the acoustic/prosodic information that the
current system already captures. The review document (vocabulary-status-and-sense-group-modeling-review)
established that the two layers answer different questions and should coexist.

## Decision

### 1. SenseGroup is a sentence-level text annotation

A `SenseGroup` is a contiguous token span within a sentence that forms a coherent semantic
processing unit. Its identity is:

```text
(sentence_id, start_token_index, end_token_index)
```

A `SenseGroupAnalysis` is a complete segmentation of all sentences in a track into sense groups,
produced by a specific provider at a specific version. It follows the same lifecycle as other
timeline artifacts: `Candidate → Active → Archived`, with at most one active analysis per track.

### 2. SenseGroup does not store time ranges

SenseGroup is a text-only construct. It does not own `start_ms` / `end_ms`. When playback is
needed, the consumer derives a time range by projecting the token span through the active
`WordTimeline`:

```text
playback_range = (
  min(word_timings[start_token_index..=end_token_index].start_ms),
  max(word_timings[start_token_index..=end_token_index].end_ms)
)
```

This avoids duplicating timing data and ensures sense groups remain valid even when word timings
are re-estimated.

### 3. SenseGroup is not a global learning asset

Unlike `LexicalEntry`, a sense group occurrence (e.g., "the green apple" in a specific sentence)
does not automatically become a durable learning object with a capability profile. It is an
annotation that can serve as:

- A practice target (dictation, cloze).
- A playback region (loop, seek).
- A context carrier for learning observations.
- A comprehension training unit.

If a multi-word span is worth tracking as a reusable learning asset, it should be modeled as a
`LexicalEntry` with `kind: Phrase`, not as a persistent sense group.

### 4. Flat partition at target granularity

Each sentence is partitioned into a flat list of non-overlapping, contiguous sense groups. The
target granularity is 3–5 groups per sentence of typical length (10–20 words). A sentence shorter
than the minimum group size may produce a single group spanning the entire sentence.

Hierarchical syntactic structure (e.g., a full dependency parse tree) may be stored in the
analysis metadata (`metrics_json`) for future use, but the consumer-facing contract is the flat
list.

### 5. ChunkTimeline and SenseGroupAnalysis are independent layers

```text
SenseGroupAnalysis                 ChunkTimeline
  └── SenseGroup (token span)        └── ChunkTimelineChunk (time span)
       sentence_id                        sentence_id
       start_token_index                  start_word_index
       end_token_index                    end_word_index
       text                               start_ms, end_ms
       label (optional)                   boundary_sources
       sources                            confidence
```

They are stored in separate tables, managed by separate repository methods, and neither depends
on the other for correctness. A track may have an active `ChunkTimeline` without an active
`SenseGroupAnalysis`, or vice versa.

### 6. Alignment is deferred

Explicit alignment between sense groups and prosodic chunks (1:1, 1:N, N:1 mappings) is a
valuable but non-blocking feature. Phase 3.4.2 establishes the two layers independently. Alignment
computation and persistence will be addressed in a follow-up slice or phase once both layers are
stable and consumed in the product.

### 7. ChunkTimeline is not renamed in this phase

The existing `ChunkTimeline` name is retained. Renaming to `ProsodicGroupTimeline` requires:

- Evidence that the SenseGroup layer is stable and consumed.
- A mechanical rename plan for ~800 references across Rust and Flutter.
- Confirmation that the rename improves clarity without disrupting active development.

This decision will be re-evaluated at Phase 3.4.2 closeout based on accumulated evidence.

### 8. Provider-neutral analysis contract

The `SenseGroupAnalysis` contract does not depend on a specific parser. Each analysis records
`provider_id`, `provider_version`, and `algorithm` so different providers can coexist:

- **Rule-based fallback** (Phase 3.4.2): Punctuation + length limits + phrase protection.
  Always available, no external dependencies.
- **UD dependency parsing** (future): Via UDPipe or equivalent. Requires downloadable language
  model. Produces syntactic labels and head tokens.
- **LLM-based** (future): Cloud fallback for edge cases or languages without UD models.

The rule-based fallback is intentionally simple. Its purpose is to establish the full pipeline
(domain → persistence → application → API → Flutter) so that higher-quality providers can be
plugged in later without architectural changes.

### 9. User corrections are an overlay, never analysis mutations (2026-07-07 amendment)

Provider-generated analyses are rebuildable artifacts; user corrections are durable user assets
(shared-context invariant 13). The two must not share physical rows:

- A persisted `SenseGroupAnalysis` produced by a provider never contains `User`-sourced groups.
  Regenerating or replacing an analysis must not be able to destroy user work.
- When sense-group editing ships (a later phase — Phase 3.4.2 has no editing UI and therefore,
  per the field razor in the refinement review, builds no overlay machinery), user corrections
  are stored as a separate per-sentence overlay keyed by `(track_id, sentence_id)`, and read
  models merge overlay over the active analysis. `SenseGroupSource::User` is reserved for
  groups contributed by that overlay in merged read models.
- Schema v23 (Slice 3) must not preclude this: no schema element may assume that all groups of
  a sentence come from a single analysis row.

Reference: `.planning/discuss/learning-domain-model-v2-refinement-review.zh.md` §4.5.

## Consequences

- Consumers that need semantic grouping use `SenseGroupAnalysis`; consumers that need
  prosodic/audio grouping continue to use `ChunkTimeline`.
- Practice and diagnosis can target either layer independently.
- The schema grows by one table (`sense_group_analysis_runs`) following the established
  `{type}_timeline_runs` pattern.
- `LLTimelineDocument` gains optional `sense_group_analyses` and `active_sense_group_analysis_id`
  fields for import/export.
- The rule-based fallback provider provides baseline coverage. Quality improvements come from
  plugging in better providers, not from changing the domain contract.
- No existing behavior changes: ChunkTimeline generation, storage, and consumption are untouched.

## R3 Amendment (2026-08-08): Prosody Analysis is the prosodic-chunk semantic source

The whole-media generation cutover (R3, [001-ROADMAP.md](../../.planning/phases/001-offline-generation-split/001-ROADMAP.md))
resolves the prosodic-chunk side of this ADR against content-package v1:

- The single semantic source for the Prosodic Chunk foundation slot is the
  content-package v1 `prosody_analysis` resource, projected losslessly into the
  Core `ProsodyAnalysis` resource (word-anchored prominence, lexical stress,
  and utterance roles). This keeps the acoustic/prosodic layer independent
  from Sense Group exactly as this ADR decided.
- Prosodic chunk token spans are declared by Prosody Analysis. Only playback
  times are a **derived read-time projection** through the parent Word Timeline.
  Core never infers boundaries from prominence or utterance roles. The
  persisted `ChunkTimeline` is readable pending R5 but is not a foundation
  fallback.
- Imported prosody is candidate-only; foundation readiness reuses it without
  regenerating an equivalent resource and never activates it.
- No near-synonym type was added to preserve `ChunkTimeline`; the package
  dependency graph is the semantic source.

Historical decisions above remain the record for the phase in which they were
made; the amendment applies from R3 onward.
