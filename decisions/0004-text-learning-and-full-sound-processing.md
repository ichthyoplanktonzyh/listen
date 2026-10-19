# Allow text learning without TTS; require full processing when audio exists

> Status: accepted, 2026-09-08.

The universal audio requirement in [0003](0003-complete-learning-material-boundary.md)
made ordinary text learning depend on unnecessary TTS. Returning to arbitrary
optional speech enhancements would instead understate Listen's audio-learning
experience. We therefore retain the qualified Learning Material boundary but
make its obligations depend on whether audio exists, as defined in
[MODEL.md](../MODEL.md#complete-learning-material-contract).

## Decision

- Text-only materials support formal learning without requesting TTS.
  Structured Reading, text anchors, and Sense Groups are audio-independent;
  Sense Group reading/focus is not a sound-layer enhancement.
- Source audio requires the full material-side sound-processing scope. TTS is
  learner-requested, and its generated audio enters the same scope. There is no
  minimum speech tier followed by optional phone, acoustic, or structural work.
- Full processing covers the model's alignment, grouping, acoustic, rhythm,
  phone-evidence, and reference/prediction/actual-delivery comparison scope.
  It does not require every recording to exhibit every phenomenon. Missing,
  inapplicable, unsupported, failed, and evidence-insufficient results remain
  honest outcomes, not fabricated observations or silently successful work.
- Learners choose which results to use or reveal. Minimum Sufficient Scaffold
  remains an experience principle, separate from full material preparation.
- Text-only Language Slices and Personal Corpus Entries are valid. Adding
  compatible audio can support new listening episodes, but never rewrites
  earlier reading experience or silently transfers audio locators.
- Early Personal Corpus use is a freely browsable language space: inspect
  context/history, select entries for learning or review, then enter Activities.
  Automatic scheduling or next-experience recommendation is not required.

## Consequences

This partially supersedes 0003's universal Canonical Audio, TTS, and timed-text
requirements. It does not reinstate 0002's general optional-capability model:
audio already present in a material has a full processing obligation. Source
preview is still distinct from qualified formal learning, and Sentence
Translation, exact identity, provenance, and learner-fact preservation remain.

Gen's full production scope and Core/App readiness must be reconciled with the
model; existing optional stage switches or UI gates are implementation facts,
not product authority. This decision does not select providers, thresholds,
schemas, or retry policies and does not claim current implementation completion.
