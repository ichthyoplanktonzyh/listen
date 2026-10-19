# Rhythm / Prosody Benchmarks

This folder contains redistributable fixtures and instructions for Phase 2.20
stress/rhythm benchmark adapters.

It does not contain LibriTTS audio or full Helsinki Prosody data. Keep downloaded
corpora outside git.

## Helsinki Prosody Adapter

`scripts/evaluate-helsinki-prosody.py` scores `sound_analysis.rhythm_frame`
against Helsinki Prosody labels:

| Helsinki Label | RhythmFrame Field | Meaning |
|---|---|---|
| word prominence `1` / `2` | `stress_anchors` | public weak-label check for prominent listening anchors |
| word boundary `2` by default | `phrase_boundaries` | public weak-label check for major phrase/rhythm breaks |

These labels are automatic silver labels, not human gold. Use them for
regression and drift checks. Product usefulness still requires manual
RhythmFrame QA in `testdata/rhythm-frame-qa/`.

The scorer output includes `benchmark_context` so downstream reports do not
mistake this weak-label benchmark for a gold standard. It records:

- evidence class: `silver_label`
- benchmark role: `weak_prosody_regression`
- Helsinki prominence/boundary label meanings
- Talman et al. 2019 reported BERT text-model prominence baselines:
  `0.832` 2-way accuracy and `0.686` 3-way accuracy
- caveats explaining that those accuracies are calibration context, not directly
  comparable to LLPlayerNext end-to-end audio RhythmFrame F1

`score_summary.predicted_boundary_evidence_counts` reports how predicted
RhythmFrame boundaries were justified, for example `pause` versus
`pre_boundary_lengthening`. This is diagnostic only; it helps identify whether a
new boundary feature over-segments or never fires.

## Benchmark Roles

`benchmark-roles.json` defines the Phase 2.20 benchmark role convention:

| Role | Evidence class | Closeout use |
|---|---|---|
| `evidence_quality` | `gold` / `coverage` | supporting context |
| `weak_prosody_regression` | `silver_label` | regression signal |
| `human_prosody_gold` | `gold` | optional calibration |
| `product_listening_qa` | `manual_product_qa` | release gate |
| `robustness_probe` | `silver_label` / `coverage` | future probe |

The key rule is intentional: product closeout should not rest only on
`silver_label` or `heuristic_proxy` scores. Helsinki/LibriTTS can catch drift,
but manual product QA is still required for learner-facing usefulness.

## Fixture Smoke

The committed fixture validates parser, scoring, and CLI quality gates without
requiring downloaded corpora:

```bash
python3 scripts/evaluate-helsinki-prosody.py \
  --labels testdata/rhythm-prosody-benchmarks/fixture-helsinki.txt \
  --lltimeline-manifest testdata/rhythm-prosody-benchmarks/fixture-manifest.jsonl \
  --min-scored-sentences 1 \
  --min-anchor-f1 1.0 \
  --min-boundary-f1 1.0 \
  --fail-on-quality-gate
```

## Local Data Smoke

After cloning Helsinki Prosody locally, label-only summary can be run without
LibriTTS audio:

```bash
python3 scripts/evaluate-helsinki-prosody.py \
  --prosody-dir ~/prosody \
  --split dev \
  --limit 100
```

## Prepare Local LibriTTS Baselines

If LibriTTS is still compressed, prepare a small local-only batch directly from
the split archive:

```bash
python3 scripts/prepare-helsinki-libritts-benchmark.py \
  --prosody-dir /Users/shadow/prosody \
  --libritts-archive /Users/shadow/Downloads/dev-clean.tar.gz \
  --split dev \
  --limit 20 \
  --output-dir .tmp/helsinki-libritts-rhythm-dev
```

The script extracts only selected `.wav` files into `.tmp/.../audio`, writes
baseline `.lltimeline.json` files into `.tmp/.../timelines`, and emits:

```text
.tmp/helsinki-libritts-rhythm-dev/manifest.jsonl
```

That manifest can be used both by the local API refresh runner and by the
Helsinki scorer. Before refresh, the scorer should report
`missing_rhythm_frame`:

```bash
python3 scripts/evaluate-helsinki-prosody.py \
  --prosody-dir /Users/shadow/prosody \
  --split dev \
  --limit 20 \
  --lltimeline-manifest .tmp/helsinki-libritts-rhythm-dev/manifest.jsonl
```

To score generated LLTimeline artifacts from another pipeline, provide a local
manifest mapping each Helsinki `source_file` to the generated artifact:

```json
{"source_file":"1272_128104_000001_000000.txt","sentence_id":"s1","lltimeline":{"local_path":".tmp/libritts-rhythm/1272_128104_000001_000000.lltimeline.json"}}
```

Then run:

```bash
python3 scripts/evaluate-helsinki-prosody.py \
  --prosody-dir ~/prosody \
  --split dev \
  --lltimeline-manifest .tmp/libritts-rhythm/manifest.jsonl \
  --min-scored-sentences 100
```

## Boundary And Prominence Thresholds

Defaults:

- `--prominence-threshold 1`: label `1` and `2` count as gold anchors.
- `--boundary-threshold 2`: only strong word-boundary label `2` counts as a
  gold phrase boundary.

This matches Phase 2.20's current product direction: stress anchors may include
primary and secondary prominent words, while phrase-boundary display should avoid
over-cutting minor boundaries.
