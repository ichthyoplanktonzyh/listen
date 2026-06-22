# ADR 0012: Multilingual Learning Abstraction

## Status

Accepted. Validated in
[`2.5.5-language-learning-abstraction-validation`](../../.planning/phases/2.5.5-language-learning-abstraction-validation/2.5.5-CLOSEOUT.md);
to be implemented in
[`2.6-multilingual-learning-foundation`](../../.planning/phases/2.6-multilingual-learning-foundation/2.6-PLAN.md).

This ADR records the architecture decision that turns LLPlayerNext from an
English-first listening learner into a language-pluggable one. It supersedes the
implicit English assumptions behind `TXT-001` (English tokenization),
`tokenize_english()`, the `language=en` client hardcoding, and the lemma-centric
vocabulary identity.

## Context

The product was built English-first: subtitle tokenization, the lexical learning
unit (≈ English lemma), dictionary/pronunciation, and diagnosis all assumed
English. Phase 2.6 expands to multilingual, with English + Chinese as the first
real implementation/acceptance languages and a top-15 learning-language envelope
as the architectural target.

Before writing any multilingual code, Phase 2.5.5 validated the proposed
abstraction two ways:

1. **Against real second-language-acquisition (SLA) research** rather than
   engineering aesthetics — to confirm the model is not invented.
2. **By typological falsification** against the most distant top-15 learning
   languages (Japanese, Arabic) — to confirm it extends without per-language
   special-case branching.

The validation confirmed the spine is SLA-grounded and produced three concrete
revisions (R0/R1/R2). This ADR fixes the resulting contract so Phase 2.6 and all
later language additions build on it.

## Decision

### Core model

1. **Listening-first.** The product model is
   `audio -> listening units -> meaning candidates -> lexical/text explanation`,
   not `text -> token -> dictionary -> meaning`. Text, dictionary, grammar and
   subtitles are explanation/calibration layers over an `audio -> meaning` core.
2. **Three distinct units**, cut along independent linguistic axes:
   - `Token` — subtitle display/click unit (writing-system axis).
   - `LexicalUnit` — vocabulary/learning object (lexis/morphology axis).
   - `ListeningUnit` — auditory unit in real speech (phonology/prosody axis).
   These axes do not predict each other (e.g. Chinese: hard script, simple
   morphology; Turkish: easy script, hard morphology), so the three must not be
   collapsed.
3. **Single language invariant = the comprehension axis.** The global vocabulary
   status enum (`Unclassified / UnknownMeaning / KnownNotRecognized /
   KnownRecognized`) is language-agnostic and reusable, because it sits on the
   meaning × sound comprehension axis (Field's decoding vs meaning-building),
   which holds for any language. It stays the stable durable asset.
4. **Everything structural is variant**, declared per language via a
   `LanguageLearningProfile` + capability matrix and resolved through providers
   (tokenizer, lexical normalizer, dictionary, pronunciation, diagnosis rules).
   Unsupported capabilities **degrade cleanly**, they do not fail.
5. **Status ≠ diagnosis reason.** The persisted status enum is invariant; the
   derived diagnosis *reason* taxonomy is per-profile and extensible
   (en: `weak_form`/`liaison`; zh: `tone_confusion`/`word_boundary`/`homophone`;
   ja: `pitch_accent`).

### Revisions forced by falsification

6. **R0 — open `kind` taxonomies.** `tokenization`, `lexical_units`,
   `listening_units`, `rhythm_prosody`, `morphology` use namespaced strings
   (`core.*` + `<lang>.*`) with clean degradation on unknown kinds, **not**
   exhaustive enums with exhaustive `match`. Japanese `mora`/`mora_timed` and
   Arabic clitic tokenization / templatic morphology all fall outside the
   original closed sets; a closed enum would force editing shared code for every
   new language, contradicting the clean-degradation principle.
7. **R1 — listening observations may anchor to a `ListeningUnit`**, not only a
   `LexicalUnit`. Tone/pitch minimal-pair failures (Mandarin tone, Japanese
   は し 箸/橋 pitch accent) are contrasts at the auditory-unit level and are not
   a property of any single word.
8. **R2 — `normalized_key` is provider-opaque.** It is the output of a
   per-profile normalizer with **no substring / affix-stripping assumption**,
   because Arabic non-concatenative roots (k-t-b for kataba/kitaab/kutub) are not
   surface substrings. `LexicalUnit` identity therefore splits into two
   orthogonal axes: granularity (`char/word/phrase/morpheme`) × normalization
   (`surface/lemma/citation/root`).

### Diagnosis and scope

9. **L1 → L2 diagnosis seam.** Listening difficulty is a function of the learner
   first language, not the target language alone (Best PAM; Flege SLM; Cutler L1
   segmentation transfer). The diagnosis signature reserves
   `(L1, L2_unit, status, context)`. In v1 the L1 is nullable, unread by rules,
   and not persisted in schema.
10. **`ListeningUnit` is a view, not a new table** (in Phase 2.6). The sound side
    remains owned by the existing `WordTimeline` / `ChunkTimeline` /
    `PhoneTimeline` resources; `ListeningUnit` is a typed cross-language view over
    them plus the profile, not a parallel store.
11. **Top-15 learning-language envelope.** The architecture is validated to be
    correct for the top-15 learning languages and their typological clusters.
    Smaller languages are explicitly not committed ("可加可不加").

## Consequences

- **Positive**
  - Adding a language is (provider + profile) work isolated behind stable
    interfaces; it does not require editing existing language code, because the
    `kind` taxonomies are open and unknown kinds degrade.
  - The crown-jewel vocabulary asset (status + history + source snapshot) stays
    language-stable while explanations become language-aware.
  - The model is defensible against real SLA, not just internally elegant.
  - Distant top-15 languages (Japanese mora/pitch, Arabic templatic morphology)
    were shown to fit on paper before any code, at the cost of a document.
- **Negative**
  - Open string taxonomies trade compile-time exhaustiveness for runtime
    degradation; a known-kind registry is needed for spelling discipline.
  - `normalized_key` being opaque means vocabulary identity cannot be derived
    generically; each language needs a normalizer (heavy for Arabic).
  - `ListeningUnit`-anchored observations add a second anchor target the schema
    must eventually express (deferred past 2.6, only the seam is reserved).

## Rejected Alternatives

- **English/Chinese double special-casing** (`if en -> lemma; if zh -> char`).
  Rejected: it does not generalize and produces special-case branches the
  validation set (es/fr/de/ru) and probes (ja/ar) explicitly stress-test against.
- **Closed `kind` enums.** Rejected by R0: every new language would edit shared
  enums and their `match` arms, the opposite of clean degradation.
- **Persisting `ListeningUnit` as a new table in 2.6.** Rejected: it duplicates
  the existing Word/Chunk/Phone timeline resources (drift, double maintenance),
  and for Chinese there is no audio producer yet, so the table would be empty.
- **L2-only diagnosis.** Rejected: it omits the L1 filtering that SLA places at
  the center of *why this learner* failed to hear something.

## Future Path

- **Non-English audio → listening-unit production** (Chinese ASR / forced
  alignment / tone detection, then other languages) is a separate future
  production-engine program; Phase 2.6 only makes the consumer side
  listening-ready and language-pluggable.
- **Hindi (Devanagari abugida)** is the next writing-system probe; it should get
  a paper falsification before Hindi is implemented.
- **L1 × L2 contrastive difficulty tables** may later populate the L1 seam with
  real per-pair diagnosis weighting.
