# RhythmFrame QA Annotations

Phase 2.20 evaluates whether `sound_analysis.rhythm_frame` helps explain why a
sentence is hard to hear. Phone PER remains evidence quality; this folder is for
rhythm-first listening quality.

## Files

| File | Purpose |
|---|---|
| `annotation.schema.json` | Machine-readable shape for manual QA JSONL rows |
| `sample-annotations.jsonl` | Small documented example; not a benchmark |
| `fixture-manifest.jsonl` | Committed synthetic scorer/gate regression manifest |
| `fixture-rhythm.lltimeline.json` | Minimal committed LLTimeline with two `rhythm_frame` sentences |
| `fixture-annotations.jsonl` | Matching committed manual labels for strict gate smoke tests |
| `annotations.jsonl` | Optional local/manual labels consumed by the scorer; may be absent |

`annotations.jsonl` can reference local-only media/artifacts. Keep copyrighted
media and generated full timelines out of git.

## Generate A Template

```bash
python3 scripts/evaluate-rhythm-frame.py \
  --manifest testdata/sound-line-real-media/manifest.jsonl \
  --emit-template > testdata/rhythm-frame-qa/annotations.local.jsonl
```

Current Phase 2.17 artifacts may predate `rhythm_frame`; those rows will show
`system.status = "missing_rhythm_frame"` until the case is regenerated.

## Generate A Duration/RMS Comparison Template

Phase 2.20 route correction compares the current CTC-derived `RhythmFrame`
against active WordTimeline duration/rate and per-word RMS energy evidence before
changing the product generator:

```bash
python3 scripts/prepare-rhythm-acoustic-qa.py \
  --manifest testdata/sound-line-real-media/manifest.jsonl \
  --case-id p217-brooklyn-news-001 \
  --limit 10 \
  --emit-template > testdata/rhythm-frame-qa/acoustic-comparison.local.jsonl
```

Rows include the normal manual-label fields plus `system_compare`. Duration/rate
and RMS candidates are `heuristic_proxy` evidence for manual QA, not product
truth.

## Committed Fixture Smoke

The synthetic fixture is intentionally small and redistributable. It keeps the
scorer, strict annotation validation, and quality gate CLI path testable without
requiring local media regeneration:

```bash
python3 scripts/evaluate-rhythm-frame.py \
  --manifest testdata/rhythm-frame-qa/fixture-manifest.jsonl \
  --annotations testdata/rhythm-frame-qa/fixture-annotations.jsonl \
  --strict-annotations \
  --min-rhythm-coverage 1.0 \
  --min-annotated-sentences 2 \
  --min-overall-useful-rate 1.0 \
  --max-hotspot-misleading-rate 0.0 \
  --max-hotspot-unsupported-rate 0.0 \
  --fail-on-quality-gate
```

## Score

```bash
python3 scripts/evaluate-rhythm-frame.py \
  --manifest testdata/sound-line-real-media/manifest.jsonl \
  --annotations testdata/rhythm-frame-qa/annotations.local.jsonl
```

Use strict validation before treating manual labels as a gate:

```bash
python3 scripts/evaluate-rhythm-frame.py \
  --manifest testdata/sound-line-real-media/manifest.jsonl \
  --annotations testdata/rhythm-frame-qa/annotations.local.jsonl \
  --strict-annotations
```

The JSON output always includes `annotation_validation` and
`summary.manual_qa`, so invalid score labels, duplicate sentence annotations,
unknown sentence IDs, and aggregate `correct / misleading / unsupported` counts
are visible even in non-strict exploratory runs.

## Quality Gates

Quality gates are optional until enough local artifacts are refreshed and
manual labels exist. They are intended for closeout/CI-style checks:

```bash
python3 scripts/evaluate-rhythm-frame.py \
  --manifest testdata/sound-line-real-media/manifest.jsonl \
  --annotations testdata/rhythm-frame-qa/annotations.local.jsonl \
  --strict-annotations \
  --min-rhythm-coverage 1.0 \
  --min-annotated-sentences 10 \
  --min-overall-useful-rate 0.7 \
  --max-hotspot-misleading-rate 0.1 \
  --max-hotspot-unsupported-rate 0.2 \
  --fail-on-quality-gate
```

The output includes `quality_gates.passed` and one entry per configured gate.
With `--fail-on-quality-gate`, failures exit with code `4`.

## Manual Rubric

Use the same score vocabulary for hotspot and overall judgments:

| Score | Meaning |
|---|---|
| `correct` | Audible evidence and learner-facing explanation both fit |
| `useful_but_incomplete` | Points to the right region but misses relevant detail |
| `unclear` | Not clearly wrong, but not useful enough |
| `misleading` | Points to the wrong word, sound, or reason |
| `unsupported` | Text-predicted but not supported by the audio |

Mark `phone_detail_needed` when a default rhythm explanation is not enough and
phone-level evidence should be opened to explain the issue.
