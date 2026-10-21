# Rhythm-frame QA inputs

This directory contains existing scorer inputs:

- `annotation.schema.json`: the manual-label format;
- `sample-annotations.jsonl`: a small format example;
- `fixture-manifest.jsonl`, `fixture-rhythm.lltimeline.json`,
  `fixture-no-phone-rhythm.lltimeline.json`, and `fixture-annotations.jsonl`:
  synthetic inputs for scorer and validation regression tests.

The fixture manifest names this README as a `qa_notes` file, so it must remain
present. It is a fixture companion, not a phase plan or acceptance report.

Run the deterministic smoke from `core/`:

```sh
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

Inspect the script's `--help` and JSON schema for optional manual-data commands
and exact fields. Synthetic fixtures prove tool behavior, not learner benefit
or model quality. Keep local media and generated full timelines outside Git.
