# ADR 0021: Semantic Attempt / Judgment / Observation / Capability Separation

- Date: 2026-07-12
- Status: Accepted for Phase 3.11
- Context: Phase 3.11–3.18 shared context §3.1/§3.6/§3.7; final discussion
  (`.planning/discuss/four-channel-product-and-vendor-neutral-llm-final.zh.md`) §5/§6/§9;
  Phase 3.11 evidence matrix (`3.11-EVIDENCE-MATRIX.md`); ADR 0015 (evidence → projection →
  effective ← override), ADR 0017 (channelized lexical observations), ADR 0020 (construction
  spike identity)

## Context

Phases 3.13–3.18 will add reading, speaking, and writing tasks driven by an external LLM. Before
any of that lands, four kinds of fact must be separated so that swapping model or provider cannot
rewrite history, and so that a segment-level activity cannot silently mutate word- or
construction-level capability:

```text
clip / sentence / construction attempt
    != SemanticJudgment (one automatic per-point verdict over one response)
    != target-level LearningObservation (ADR 0017, lexical only today)
    != capability projection / override (ADR 0015)
```

Today only listening has an evidence→projection path (ADR 0019). `LearningObservation` is lexical
and closed-enum (ADR 0017); `PracticeAttempt` assumes a single deterministic answer with
correct/partial/incorrect grading. Neither can carry a rubric-scored semantic response, and
forcing one to would conflate "this activity has no lexical evidence" with "this word was
skipped". This ADR fixes the fact layer with no external LLM, no Studio UI, and no projection.

## Decision

### 1. A dedicated semantic task family, not an extension of `PracticeKind`

`SemanticTaskKind` is a new closed enum — `reading_comprehension`, `l1_retelling`,
`l2_retelling`, `role_reply`, `dictogloss`, `summary`, `pattern_production` — with its own
`semantic_task_attempts` table. `PracticeKind`, `PracticeAttempt`, and the ADR 0017 mapping are
untouched.

Rejected: extending `PracticeKind` (its `observation_spec_for_practice` exhaustive match would
force each semantic kind to return `None`, collapsing "unrelated to lexical evidence" and
"skipped/unevaluated" into one path — the exact conflation this phase exists to prevent; and
`expected_answer`/`evaluation` are meaningless for rubric-scored responses). Rejected: an open
`kind` string (a task may exist only after an evidence-matrix row decides its channel and write
boundary; extension is enum + matrix row + this ADR's version, mirroring ADR 0017). The attempt
reuses domain `PracticeTarget`/`PracticeAnchor` for locating and snapshotting, so no parallel
locator type is introduced.

### 2. Rubric is the fixed scoring scale; identity is (segment, purpose, version)

`SemanticRubric` snapshots its source segment (transcript + time range; media/track are optional
context, never identity), a language pair, and required/optional `RubricPoint`s whose `point_id`
is stable within a version. Identity fingerprints (media, range, purpose, language pair, source
hash): the same segment used for retelling versus summary is two different rubrics, and their
judgments are never comparable. Manual revision appends a higher `version` carrying a revision
note; earlier versions are never rewritten, and a revision that changes the source snapshot is
rejected (a different segment is a new rubric, not a rebase).

### 3. Judgment is per-point, first-class abstain, fully provenanced

`SemanticJudgment` records, for one response revision: per-point `covered | partial | missing |
uncertain`, supporting spans that must locate exactly inside the response transcript, both the
rubric-source and response transcript sha256, and generator/model/prompt/schema provenance.
`abstain` (unreliable transcript, empty response, refusal, other) is a first-class outcome that
carries no point verdicts — unevaluated is separated from failure and never enters a failure
tally. A non-abstaining judgment must judge every rubric point exactly once. Two judgments are
directly comparable only when they cite the same rubric identity, version, and source hash and
neither abstained. Re-judging (e.g. after a model upgrade) inserts a new judgment; history is
never overwritten.

### 4. Adjudication corrects one assertion; it is not a capability override

`JudgmentAdjudication` records a user confirming or correcting one judged point. It is append-only
and never mutates the judgment row (a persistence test pins byte-identity before/after). Per final
§5, adjudicating "point 3 was actually covered" is a correction of one automatic assertion that a
future projection may consume as corrected attempt evidence — it is categorically not a
`(target, capability)` override under ADR 0015, and this phase adds no path from adjudication to
any capability slot.

### 5. This phase writes no `LearningObservation` and no projection

Every task in the matrix records a **clip-level fact only**. The one task that naturally anchors a
target — `pattern_production` — is deferred to Phase 3.16, because ADR 0020 decision 7 keeps
constructions with no production persistence; its attempt stores an opaque anchor snapshot and
writes no construction observation. Consequently Phase 3.11 introduces **no new
`LearningObservation` writer and no capability projection writer**. Target-level observation
remains reachable only by the ADR 0017 rule (task explicitly anchors a lexical target and the
result proves recognition/production of it), which no 3.11 task satisfies. Reading/speaking/
writing projection stays with Phase 3.17.

Negative guarantees, each pinned by a test:

- an L1-retelling flow leaves `learning_observations`, `lexical_capability_history`,
  `lexical_capability_states`, and `upgrade_suggestions` empty;
- a shadowing `Completed` attempt (ADR-0017 boundary, Phase 3.8) produces no semantic attempt or
  judgment — imitation completion is never constructed-speaking success;
- adjudication leaves the original judgment byte-identical.

### 6. Append-only persistence, self-sufficient after media deletion

`semantic_rubrics`, `semantic_task_attempts`, `semantic_judgments`, and `judgment_adjudications`
(schema v35) forbid UPDATE and DELETE via triggers. There is intentionally no foreign key to
media: snapshots must keep explaining history after the source is deleted (a test deletes the
media row and reloads the full chain). In-progress attempt persistence (saving dictogloss draft 1
before draft 2 exists) is deferred to the first Studio consumer that needs it; the additive path
is a new status value plus a response-append table, not relaxing these guards.

### 7. Portable/export boundary: not in the vocabulary bundle

Rubrics, attempts, judgments, and adjudications are clip-anchored task facts, not vocabulary
assets. They are **not** added to `VocabularyAssetBundle` (ADR 0017 decision 6 kept that bundle
for lexical assets). If cross-device migration of semantic facts is ever needed, it gets a
dedicated bundle rather than overloading the vocabulary channel. This keeps the seam decision
(shared context §3.6) honest: no asset-identity generalization ships without a real consumer.

### 8. Transitional authority handoff

From this ADR, the shared-context §3.7 transitional rule (implementers may only record attempt
facts when evidence attribution is unclear) is superseded by this document for semantic tasks: the
four-layer boundaries above are now the authority.

## Consequences

- Phases 3.13–3.15 get a fixed, offline-testable scoring scale and a comparable-judgment property
  from day one; they add task-specific rubric generation and UI, not new fact-layer types.
- No LLM, network, or model is required for any 3.11 contract test; the gold fixture
  (`testdata/semantic-task/gold-fixture-v1.json`) carries a good/poor/abstain judgment set plus an
  adjudication and validates fully offline.
- When Phase 3.12 adds providers and 3.12.1 grants judge qualification, `source_kind=llm_judgment`
  and `validation_class` remain orthogonal (final §8): a judgment's generator provenance and its
  evidence class are separate fields, and neither alone unlocks a capability conclusion.
- The static task family will be wrong at some edges before it is right; because attempts and
  judgments retain raw provenance and conditions, remapping is additive (new enum value + matrix
  row + ADR version bump), never a history rewrite.

## Rejected Alternatives

- **Extend `PracticeKind` / `PracticeAttempt`** — conflates "no lexical evidence" with "skipped",
  and the deterministic-answer grading model cannot carry per-point judgments (decision 1).
- **Open `kind` string** — lets a task enter storage before an evidence-matrix decision on its
  channel and write boundary (decision 1).
- **One attempt per capability for L2 retelling** — the response is a single performance; the
  dual listening×speaking reading is an interpretation layer (final §3.1), so it stays one attempt
  with a two-channel explanation, not two attempts.
- **Ship the first semantic projection algorithm here** — needs research grounding, judge
  qualification (3.12.1), and 3.17's writer-exclusivity decision; recording facts must not wait
  for it, and must not pre-commit to it.
