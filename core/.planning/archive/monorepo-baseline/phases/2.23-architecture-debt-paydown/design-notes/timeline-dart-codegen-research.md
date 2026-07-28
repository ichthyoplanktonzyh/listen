# Timeline Dart Model Codegen Research

Date: 2026-07-02

Scope: `apps/desktop/lib/models/timeline.dart` and adjacent timeline/LLTimeline
JSON parsing. This is a phase note only; it is not an ADR and does not decide a
migration.

## Current State

- `timeline.dart` is a large hand-written model file with many `fromJson`
  factories, custom `Duration(milliseconds: ...)` conversion, typed wrappers for
  loose JSON envelopes, and backwards-compatible defaults for older resources.
- The parser intentionally tolerates optional fields such as `sound_analysis`,
  `rhythm_frame`, document-level `rhythm_frames`, metrics/evidence objects, and
  older phone/timeline resources.
- LLTimeline fixtures do not map one-to-one to a single Flutter document class:
  `LLTimelineDocument` currently owns metadata, active IDs, document-level rhythm
  frames, and artifacts, while tests parse top-level `segments`,
  `word_timelines`, and `phone_timelines` through their existing typed resource
  models.

## json_serializable

Potential benefits:

- Removes repetitive `as String` / list mapping boilerplate for stable leaf DTOs.
- Makes field renames and required-vs-optional decisions more explicit.
- Can use custom converters for millisecond `Duration`, metrics/evidence
  envelopes, and nested timeline resources.

Costs and risks:

- Requires adding `build_runner` and generated `*.g.dart` files, increasing
  dependency and build workflow surface.
- Custom converters would still be needed for most non-trivial fields, so the
  largest compatibility decisions would not disappear.
- Generated strictness can accidentally remove current soft-default behavior
  unless every legacy/default path is modeled deliberately.

## freezed

Potential benefits:

- Adds immutable value classes, `copyWith`, equality, and sealed unions if the
  model starts representing variant resource states.
- Pairs well with `json_serializable` for newly designed DTOs.

Costs and risks:

- Heavier migration than `json_serializable` alone and more generated code.
- The current model is mostly parsed-and-rendered resource data, not a domain
  layer that heavily uses value equality or unions.
- Freezed would force a broad style shift inside a file that currently carries
  many compatibility adapters.

## Suggested Migration Shape If Owner Chooses Codegen

1. Keep the new fixture-driven contract tests as the gate before any migration.
2. Start with one small leaf family, such as `RhythmReference` /
   `RhythmFrameQuality` or a future new DTO, and prove converters/defaults keep
   old fixtures green.
3. Avoid migrating all of `timeline.dart` in one phase. Split the file by
   resource family first if generated parts would make review harder.
4. Treat removal of handwritten tolerance as a contract change, not a cleanup.

Open owner decision: whether the maintenance win is worth the generated-code
workflow. The conservative default is contract tests first, codegen only after a
small pilot demonstrates that compatibility semantics stay explicit.
