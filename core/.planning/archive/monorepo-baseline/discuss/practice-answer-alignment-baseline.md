# Practice Answer Alignment Baseline

Last updated: 2026-07-28.

This note records the evidence boundary for the deterministic portion of issue
#98. It is not a completion claim for open-ended retelling, translation, or
composition evaluation.

## Evidence class and intended use

- Evidence class: `heuristic_proxy`.
- Intended use: explain insertion, deletion, substitution, exact match, and
  provider-backed single-token lemma equivalence in bounded practice answers.
- Not valid for: semantic equivalence, key meaning-unit coverage, fluency,
  confidence-based judgment, or automatic assessment of open-ended answers.

Global edit-distance alignment is used only to prevent one missing or extra
token from shifting every later comparison. Exact and provider-backed
lemma-equivalent pairs have zero edit cost; insertion, deletion, and
substitution each have unit cost. These costs select an explainable alignment;
they are not exposed as a learner-quality metric or tuned as task-specific
thresholds.

Dictation remains surface-strict after the learning-language tokenizer's
punctuation/case normalization. Cloze, subtitle-fade, and text-submitted
shadowing may accept a lemma-equivalent single token when a configured
language provider resolves both forms. Multi-token contraction expansion and
acceptable-answer lists are not claimed by this baseline.

A configured normalization provider error aborts evaluation before attempt,
observation, review, or calibration facts are written. An absent provider
keeps deterministic exact matching available and is recorded in the versioned
evaluation trace through the configured-provider list.

## Follow-up required for issue #98

- explicit acceptable-answer variants;
- open-ended rubric and meaning-unit contracts;
- optional embedding/LLM semantic judgment with abstention and versioned
  confidence/provenance;
- representative golden fixtures and product QA for each open-ended task kind.
