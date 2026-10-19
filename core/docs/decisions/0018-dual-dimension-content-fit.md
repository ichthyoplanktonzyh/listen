# ADR 0018: Dual-Dimension Content Fit (Meaning Fit x Sound Fit)

- Date: 2026-07-07
- Status: Accepted for Phase 3.5; the `mean_chunk_length` input row that read
  the active `ChunkTimeline` is superseded by R5 (2026-08-09), which sources
  chunk length from the active Prosody Analysis declared token spans.
- Context: Phase 3.5 plan (`.planning/phases/3.5-difficulty-content-triage/3.5-PLAN.md`);
  learning domain model v2 shared context §14 (complexity layering, field razor);
  ADR 0015 (four-channel capability profile); ADR 0017 (channelized observations);
  AGENT.md "Algorithms And Metrics" rules

## Context

Phase 3.5 turns difficulty from a label into a content triage signal. The product decision
(recorded in the phase plan) is to implement dual-dimension difficulty directly, without a
prior differentiation experiment, in exchange for two hard conditions: every score must be
explainable (signals visible on tap), and every threshold is recorded as `heuristic_proxy`.

The existing `ContentDifficultyProfile` in `crates/domain/src/learning_loop.rs` is an unused
Phase 3.0.1 seam: single `fit: InputFit`, flat signal fields, a `DifficultyRepository` trait
with no implementation and no persisted rows anywhere. Reshaping it is non-destructive.

The four-channel capability model gives the two dimensions their inputs directly:

- **Meaning fit** asks: if the learner could read this transcript, would they understand it?
  Input: reading-channel effective assessments over transcript tokens.
- **Sound fit** asks: can the learner decode this audio by ear at this delivery?
  Input: listening-channel effective assessments (especially reading-acquired +
  listening-not-acquired, the "看得懂听不出" gap), plus delivery signals
  (speech rate, weak-form/compression density, chunk length).

## Research Notes (evidence classes per AGENT.md)

Anchors from published research; none maps exactly onto our measurements, so every derived
threshold below is `heuristic_proxy`, to be calibrated by `manual_product_qa` on the real
library (phase exit signal) and later by usage feedback:

- **Lexical coverage vs listening comprehension**: van Zeeland & Schmitt (2013, *Applied
  Linguistics*) found adequate listening comprehension around 95% lexical coverage, with
  meaningful comprehension for some listeners at 90%. For reading, Hu & Nation (2000) and
  Nation (2006) support ~98% for unassisted comprehension; Schmitt, Jiang & Grabe (2011)
  show a roughly linear coverage-comprehension relationship rather than a cliff.
- **Speech rate**: Tauroza & Allison (1990) report natural British English rates by genre
  (roughly 140 wpm lectures, ~160 wpm radio, ~200+ wpm conversation). Griffiths (1992) found
  L2 comprehension degrades significantly at fast rates (~200 wpm) versus moderate
  (~130–160 wpm).
- **Reduced/connected speech as an L2 listening bottleneck**: Brown (1990), Field (2008),
  and instruction studies on reduced forms (e.g., Ito 2006) support weak-form and reduction
  density as a genuine difficulty driver independent of vocabulary knowledge.
- **Aural vs written vocabulary gap**: Milton & Hopkins (2011) show phonological vocabulary
  size lags orthographic size, supporting the reading-acquired/listening-not-acquired gap as
  a real, measurable learner state (this is the product's core "golden target" material).

Known mapping caveats (recorded, not hidden):

1. Coverage research counts **word families over running words including function words**;
   our denominator is word tokens and our numerator is normalized-form lexical entries
   (closer to lemma-level). Family-level knowledge transfer makes our estimate conservative.
2. Research thresholds are about *comprehension adequacy*, not enjoyment or triage; bands
   are expectation management, not verdicts (phase guardrail).

## Decision

### 1. Profile shape: two dimensions, structured signals, honest evidence grade

`ContentDifficultyProfile` v2 (breaking rework of the unused shell; `subject_kind` stays a
string — `"media"` now, `"sentence"` reserved):

```text
ContentDifficultyProfile {
  subject_kind, subject_id, language
  meaning: DifficultyDimension { fit: InputFit, signals: Vec<FitSignal> }
  sound:   DifficultyDimension { fit: InputFit, signals: Vec<FitSignal> }
  assessed_token_ratio   f32   share of word tokens whose entry has any assessment
  evidence_grade         initial_estimate | usage_calibrated
  algorithm_version      "content-fit-v1"
  computed_at_ms, input_fingerprint
}
FitSignal { kind: FitSignalKind, value: f32, decisive: bool }
  // decisive = this signal selected or escalated the band (vs informational)
```

- `InputFit` (too_easy / comprehensible / challenging / too_hard) is reused per dimension.
- Signals are structured domain data, not prose; UI renders explanation text from them
  (invariant 18: model precision never leaks — the UI shows "为什么", never raw formulas).
- `evidence_grade` starts at `initial_estimate`; only the feedback-calibration slice may
  set `usage_calibrated`. `assessed_token_ratio` quantifies how much of the transcript the
  vocabulary profile actually covers, powering the honest-degradation UI state.

### 2. Signal set v1

| Dimension | Signal | Source | Notes |
|---|---|---|---|
| meaning | unknown_meaning_density | reading channel NotAcquired / word tokens | |
| meaning | unassessed_density | no assessment / word tokens | conservative: counts against coverage |
| sound | known_not_recognized_density | reading Acquired + listening NotAcquired / word tokens | golden-target signal |
| sound | speech_rate_wpm | active WordTimeline word count / speech time | speech time excludes inter-sentence gaps |
| sound | weak_form_density | document rhythm_frames weak groups / word tokens | absent frames → signal omitted |
| sound | compression_density | rhythm_frames compression spans / word tokens | absent frames → signal omitted |
| sound | mean_chunk_length | active ChunkTimeline | absent → omitted |

Personal decoding performance (practice history) is **not** a v1 signal input; it arrives via
the feedback-calibration slice as a recorded calibration term, keeping v1 deterministic from
material + profile alone. Resource quality stays a nullable seam (razor: no automatic writer
yet).

### 3. Banding v1 (all thresholds `heuristic_proxy`)

**Meaning fit** from meaning coverage `c = 1 − unknown_meaning_density − unassessed_density`:

```text
c ≥ 0.98 → too_easy       (≈ unassisted reading threshold)
c ≥ 0.95 → comprehensible (≈ adequate listening comprehension anchor)
c ≥ 0.90 → challenging    (partial comprehension zone)
c <  0.90 → too_hard
```

**Sound fit** is rule-based and monotonic, not a weighted score (explainability beats
pseudo-precision at this evidence level). Start from the band suggested by
known_not_recognized density, then escalate one band per triggered delivery signal, capped
at too_hard:

```text
base: knr < 0.02 → too_easy; < 0.05 → comprehensible; < 0.10 → challenging; else too_hard
escalate +1 band if speech_rate_wpm > 180   (fast-delivery anchor)
escalate +1 band if weak_form_density high  (constant defined with the implementation)
```

Every triggered rule emits its `FitSignal`, so the displayed reasons are exactly the inputs
that produced the band. Exact constants live in one domain module next to the banding
functions, named and versioned; changing any constant bumps `content-fit-v1` → v2.

### 4. Honest degradation instead of fake confidence

If `assessed_token_ratio` is below a minimum (constant with the implementation), the profile
still computes (conservative estimate) but the consumer-facing contract requires showing the
"词汇画像不足,先标注关键词" state and offering the cold-start marking flow. Fit values are
never hidden, never blocking (P3/P5 red lines: no material is locked or buried by fit).

### 5. Computation and caching

- Deterministic function of (timeline document, vocabulary profile snapshot, algorithm
  version); `input_fingerprint` hashes those identities. Cache in SQLite via the existing
  `DifficultyRepository` seam; recompute when the fingerprint mismatches.
- Media-level only in v1. Sentence-level profiles are deferred until a concrete consumer
  exists (razor); `subject_kind` already carries the seam.

### 6. Triage is a derived view

The three queues (泛听队列 / 精听靶单 / 暂缓区) are **derived** from fit bands — golden
target = meaning fit comprehensible-or-easier AND sound fit challenging-or-harder — plus
explicit user pins/dismissals stored as user intent. No routing state machine; ignoring the
triage changes nothing (phase exit signal: all features behave identically if fit is unused).

### 7. First evidence projection algorithm lands inside this phase

Per ADR 0017 decision 4, `listening-projection-v1` (consuming channelized
`learning_observations`) ships as a dedicated 3.5 slice with its own decision record, and the
upgrade-confirmation direct projection write is removed in that same slice. Fit v1 reads
effective assessments regardless of writer, so this slice is ordered after fit core but is
not a prerequisite for it.

## Consequences

- Fit v1 is fully deterministic and explainable; wrong bands are diagnosable from displayed
  signals and fixable by constant changes with an algorithm version bump.
- Conservative unassessed handling means sparse vocabulary profiles yield pessimistic
  meaning fit; the honest-degradation state plus cold-start flow is the designed remedy,
  not threshold fudging.
- Rule-based sound fit will misband edge cases (e.g., slow but heavily reduced speech);
  signals are preserved raw, so recalibration does not require recomputing sources.
- The unused single-dimension `ContentDifficultyProfile` shell is reshaped in place; no
  migration or data compatibility concern exists because nothing ever wrote it.

## Rejected Alternatives

- **Single combined difficulty score** — collapses exactly the distinction (meaning vs
  decoding) the product is built on; the golden-target query becomes inexpressible.
- **Weighted linear scoring with tuned coefficients** — pseudo-precision without training
  data; rule-based banding is honest about its evidence level and easier to explain.
- **Blocking/filtering by fit** — violates P3/P5 red lines; triage suggests, never gates.
- **Requiring the new projection algorithm before fit** — fit consumes effective
  assessments through the existing profile contract; sequencing projection first would
  stall the user-visible slice for no input-shape change.
