# ADR 0030: Content Fit v3 Calibratable Feature Model

- Date: 2026-07-27
- Status: Accepted
- Supersedes: ADR 0018 sections 2–5 for the active scoring algorithm
- References: GitHub issue #94; ADR 0015; ADR 0018

## Context

Content Fit v2 separated meaning from sound and emitted explainable signals, but
its output came from fixed lexical-coverage thresholds plus unconditional sound
band escalations. It could not distinguish two learners with the same word
coverage but different phrase knowledge, could not express missing syntax or
timing evidence, and had no reproducible calibration export or v2 comparison.

The repository already contains the authoritative inputs needed for a stronger
baseline: word and phrase lexical profiles, active sense-group analyses,
validated syntax-derived metrics, Word/Chunk timelines, rhythm frames, and
durable comprehension/practice calibration counters. Replay and dictionary
lookup actions are not currently persisted with an authoritative media
identity.

## Decision

1. Keep `meaning` and `sound` as independent dimensions. Each v3 dimension
   emits a normalized score, a four-band result, and structured signals with
   per-signal score contributions.
2. Persist a `ContentFitFeatureSnapshot` inside the existing disposable
   profile cache. Optional evidence is nullable and `FeatureCoverage` names
   every missing feature; missing data is never substituted with zero.
3. Meaning uses learner-specific word and detected-phrase capability plus
   sense-group and syntax complexity. Sound uses listening capability, speech
   rate, weak/compressed speech, chunk length, pauses, timing quality, and any
   future authoritative replay/lookup facts.
4. Default weights and thresholds are explicit `heuristic_proxy` seeds. They
   are versioned as `content-fit-v3` and may be replaced only through an
   algorithm-version change backed by offline evidence.
5. Syntax complexity is computed from validated parser output when a
   syntax-backed sense-group analysis is created, then stored in that
   analysis's metrics. Content Fit never reparses an unversioned artifact.
6. Existing comprehension reports and scored practice attempts remain durable
   feedback. Calibration export keeps them solely in the observed label and
   recomputes uncalibrated v3 predictions, preventing target leakage.
7. `GET /v1/content-fit/calibration-samples` exports typed samples. The
   deterministic `content_fit_calibrate` domain example performs threshold
   search on a stable training split and reports holdout mean absolute band
   error against a frozen v2 prediction.
8. Replay and lookup features stay `null` until their actions carry an
   authoritative media identity. `DiagnosisViewed` and session completion are
   not accepted as substitutes.

## Consequences

- The same material can produce different results for learners with different
  word/phrase capability and feedback histories.
- Explanations are traceable to both raw values and numeric contributions,
  while coverage communicates uncertainty without inventing confidence.
- Existing SQLite profile JSON remains backward readable; v2 cache rows miss
  the v3 algorithm version and are recomputed.
- Real-world superiority over v2 is an evidence gate, not an implementation
  claim. The export and holdout report make that gate reproducible; until a
  representative labeled set exists, defaults remain `heuristic_proxy`.

## Rejected Alternatives

- Treating all sense groups as multi-word expressions: sense-group boundaries
  are prosodic/semantic grouping, not lexical phrase identity.
- Counting `DiagnosisViewed` as dictionary lookup or `ListeningCompleted` as
  replay: both change the meaning of existing facts.
- Giving new features zero default weight: that would expose a v3-shaped
  contract while retaining v2 behavior.
- Training a small model before a representative labeled corpus exists:
  threshold search is inspectable and sufficient for the current evidence
  class.
