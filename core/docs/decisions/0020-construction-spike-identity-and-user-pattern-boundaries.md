# ADR 0020: Construction Spike Identity and User Pattern Boundaries

- Date: 2026-07-10
- Status: Accepted for Phase 3.4.3 spike; not a production persistence decision
- Context: Phase 3.4.x shared context invariant 11/12/13 and the 3.4.3 gold fixture

## Context

Sentence learning needs both reusable abstractions and the concrete sentences a learner saves,
replays, and turns into personal templates. Treating either as the other loses essential facts:
an abstract construction cannot preserve a media/source snapshot, while a saved sentence cannot
serve as the canonical identity for all structurally related sentences.

The owner decision for this spike is that a learner may derive a personal template from any
`SentenceExemplar`, including one that has no system construction analysis. The system may
suggest a link, but that link cannot be a prerequisite or overwrite user wording.

## Decision

1. The spike has four distinct types.

   ```text
   SentenceExemplar       concrete material; identity includes source snapshot + text
   Construction           manually curated language-scoped abstraction
   ConstructionOccurrence rebuildable annotation of one exemplar
   UserSentencePattern    user-owned template with retained source snapshot
   ```

2. Canonical construction identity is explicitly `(language, key, schema_version)`. The
   fingerprint helper is stable for this tuple, but the key is curator-owned. There is no
   cross-language canonical identity and no text/LLM/parser-derived canonical key.

3. Every construction declares its own variant policy for tense, voice, polarity, and clause
   type. A dimension is either `collapsed` for that construction or `separate`, in which case
   an occurrence must match the construction's declared canonical value. No global merge rule is
   introduced.

4. Occurrences own token spans and slot bindings. They may overlap or nest, and a sentence may
   have multiple occurrences. Duplicate identity is `(exemplar, construction, span)`; there is
   no singular primary construction.

5. Construction capability keeps the compact `recognition` / `production` assessments. Evidence
   records modality: recognition evidence is reading or listening; production evidence is
   speaking or writing. This preserves a future channel-specific projection option.

6. `UserSentencePattern` requires its source exemplar and text snapshot, but
   `system_construction_id` is optional. It is a user asset, not a writable projection of an
   automatic occurrence.

7. No production SQLite schema, repository, API, import/export, LLTimeline field, or Flutter UI
   is added from this spike.

## Evidence

`testdata/construction-spike/gold-fixture-v1.json` contains English, Chinese, and Japanese
manual gold examples. It covers a collapsed English tense/voice/polarity/question variant, a
nested one-sentence/multiple-construction example, a Chinese 把 construction, a Japanese
obligation construction, and a Japanese personal template from an exemplar with no system
occurrence. `domain::construction` validates the fixture and negative variant-policy behavior.

## Consequences

- The production codebase gains a small pure domain seam and an executable guardrail, not a new
  durable asset subsystem.
- Automatic providers can later produce candidate occurrences only after a provider/lifecycle and
  quality plan exists.
- The next product experiment should start with user-owned capture, not a canonical library:
  save a sentence snapshot and derive/edit a personal pattern from it. A system construction link
  can be shown only as an optional suggestion after the manual workflow proves useful.
