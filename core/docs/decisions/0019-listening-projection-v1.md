# ADR 0019: listening-projection-v1 — First Evidence Projection Algorithm

- Date: 2026-07-07
- Status: Accepted for Phase 3.5 Slice 6
- Context: ADR 0017 decision 4 (due obligation: real evidence projection replaces the
  upgrade-confirmation direct write); ADR 0015 (evidence → projection → effective ← override);
  shared context invariants 5/16/17; owner decision 2026-07-07 (option A, graded trust in
  self-reports — recorded below)

## Context

Since 3.4.4 every listening-relevant event lands in the append-only `learning_observations`
stream, but the listening projection slot is still written only by compat paths. Three standing
rules collide on the most common user action, the "认识/不认识" tap:

1. Current behavior: marking flows through the legacy status compat sync, so a "认识" tap
   directly yields listening `acquired` — self-report is trusted outright.
2. Invariant 16: a listening `acquired` conclusion can only be *independently* supported by
   `assistance = none` task successes; the transcript is on screen during marking.
3. Invariant 17: one authoritative algorithm writer per (target, capability).

**Owner decision (2026-07-07): option A — graded trust.** Self-reports keep their current
weight until unassisted task evidence exists for the word; task evidence then outranks
self-reported success, while self-reported *failure* is always accepted immediately.
This is a recorded, deliberate concession to invariant 16: the invariant governs task
evidence; explicit user self-report is a distinct signal class whose full strictness
(option B) was rejected as interaction-layer leakage, and the override route (option C)
was rejected as overloading override's "exception declaration" semantics.

## Decision

### 1. Algorithm: pure, conservative, confirmation-gated

`listening_projection_v1(observations) -> Option<CapabilityProjection>` lives in domain as a
single definition point, versioned `listening-projection-v1`; all constants are
`heuristic_proxy`. Event classes over listening observations, newest first:

```text
decisive   assistance == none events only:
             upgrade_confirmation success   (the sanctioned acquisition event)
             task failure                   (dictation / review lapse)
             task success                   (decisive only AFTER a confirmation
                                             exists: re-strengthens / breaks
                                             failure streaks; before the first
                                             confirmation it is supporting)
supporting context markings (both directions), assisted practice,
           partial outcomes — status-quo behavior unchanged
```

Rule table (deterministic, explainable — the displayed reasons are the inputs):

```text
no decisive events              → None (projection untouched)
latest = confirmation success   → acquired      conf 0.85
latest = task success (post-
         confirmation)          → acquired      conf 0.85
latest = task failure:
    a confirmation exists and this is a single-lapse streak
                                → acquired      conf 0.40  (SRS lapse convention:
                                  weakened, not flipped)
    otherwise                   → not_acquired  conf 0.85  (a word only ever
                                  supported by marking/import flips on one real
                                  listening failure — the "看得懂听不出"
                                  discovery, the product's point)
```

Why confirmation-gated: raw successes feeding acquisition directly would bypass the 3.4
suggestion pipeline (5 distinct recognition contexts → suggestion → user confirm), which is
the deliberate product bar for upgrades. The evidence stream feeds that pipeline; the
confirmation is where acquisition is concluded — now derived from the stream instead of the
removed direct write.

How option A lands: the self-report surfaces keep their current writers. Context-marking
taps never changed word status and still don't (supporting evidence + recognition pipeline).
The word-panel status setter flows through the legacy compat writer, which the ladder in
decision 3 constrains: "认识" cannot overturn a task-grade evidence conclusion, while
"不认识" (downgrade) is always accepted.

`confidence` and `evidence_as_of_ms` (decisive event timestamp) populate the seam fields
reserved in the 3.4.x refinement; source is `EvidenceProjection`.

Anchoring notes: the asymmetric lapse rule mirrors SRS practice (a single lapse triggers
relearning, not a knowledge verdict — cf. SM-2/FSRS lapse handling); confirmation-gated
acquisition matches mastery-criterion conventions (multiple successes plus an explicit
graduation step). Numeric confidence values are unvalidated `heuristic_proxy` pending 3.5
Slice 9 manual product QA.

### 2. Trigger: synchronous recompute on every listening observation append

`append_channelized_observation` recomputes and writes the listening projection (bounded
read, newest 200 observations) and then refreshes the legacy status compat view. No batch
job, no new write surface: every writer already funnels through this helper (ADR 0017).
Recompute also runs under an active user override — the override still wins at read time
(invariant 5 is about the *effective* view), but the projection layer stays current.

Recency guard: if the current projection was written by a non-evidence writer (compat
downgrade, import) *after* the newest decisive evidence, the recompute abstains — the newer
manual signal wins until newer evidence arrives.

### 3. Writer ladder replaces ad-hoc exclusivity

Priority for the listening projection slot: **override (read-time) > task-grade evidence >
legacy compat / import > weakened evidence**. Concretely:

- The legacy status compat sync (and the external-import path that shares it) no longer
  *upgrades* (writes `acquired` over) a listening projection whose source is
  `EvidenceProjection` with confidence ≥ 0.85. Downgrades and clears are always allowed
  (failure-direction self-report is accepted immediately), and weakened conclusions
  (conf 0.40) may be overwritten by explicit user judgment — no failure ratchet.
- After every compat sync the legacy status column is re-derived from the profile, so a raw
  status write that the ladder rejected cannot leak into the user-facing view.
- **The upgrade-confirmation direct projection write is removed for listening** (the ADR
  0017 decision 4 obligation): confirmation appends its `upgrade_confirmation` observation
  and the recompute derives `acquired` from the stream. For any non-listening suggestion
  capability the direct write remains, explicitly transitional, until that channel gets its
  own projection algorithm.

### 4. Accepted behavior changes (user-visible, deliberate)

- A word whose listening status came only from marking/import now flips to
  `KnownNotRecognized` after a single failed unassisted task (dictation/review lapse).
  Previously review failures never moved status. This replaces the 3.4-era caution — which
  existed because no principled projection algorithm did — with the evidence-honest verdict,
  guarded by the single-lapse rule for confirmed words.
- Re-declaring "认识" through the status setter after a task failure no longer flips the
  word back to acquired; the reading channel still records the self-report, and the
  suggestion pipeline remains the path to reconciliation.

## Consequences

- The projection is a recomputable pure function: algorithm changes reproject history
  (invariant 3) by bumping the version.
- Marking-only vocabularies behave exactly as before (the algorithm abstains; the compat
  writer keeps ownership until real task evidence exists).
- Single-failure flips for marking-supported words will surface in review sessions; Slice 9
  manual QA must sanity-check the flip rate before the phase closes.
- Reading/speaking/writing channels remain compat/import-written; each needs its own
  algorithm before evidence can own them.

## Rejected Alternatives

- **Strict invariant 16 (option B)** — marking "认识" would no longer make a word acquired;
  honest but leaks model strictness into the one-tap interaction (invariant 18 violation in
  spirit); rejected by owner.
- **Self-report as override (option C)** — overloads override semantics and makes the
  highest-frequency action an "exception declaration"; rejected by owner.
- **Batch/async projection** — no consumer needs staleness tolerance; synchronous recompute
  on a bounded read is simpler and testable.
- **Time-windowed evidence decay** — cut per the refinement review (override aging was
  already cut); revisit only with real usage data.
