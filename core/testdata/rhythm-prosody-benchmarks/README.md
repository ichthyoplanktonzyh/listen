# Rhythm/prosody scoring fixtures

This folder supplies redistributable synthetic inputs for existing scoring
tools. It contains no LibriTTS audio or full Helsinki Prosody corpus.
Keep downloaded corpora outside Git.

Run the fixture smoke from `core/`:

```sh
python3 scripts/evaluate-helsinki-prosody.py \
  --labels testdata/rhythm-prosody-benchmarks/fixture-helsinki.txt \
  --lltimeline-manifest testdata/rhythm-prosody-benchmarks/fixture-manifest.jsonl \
  --min-scored-sentences 1 \
  --min-anchor-f1 1.0 \
  --min-boundary-f1 1.0 \
  --fail-on-quality-gate
```

The scorer consumes label and LLTimeline inputs. Its help describes optional
local-corpus preparation and thresholds. `benchmark-roles.json` names the
existing evidence roles; it does not define a current release checklist.
Weak-label regression and synthetic gate success are not human-gold quality or
proof of product usefulness.
