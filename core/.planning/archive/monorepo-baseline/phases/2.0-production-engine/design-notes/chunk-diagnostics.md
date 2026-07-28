# Chunk Boundary Diagnostics

Chunk boundary diagnostics explain why the acoustic-first partitioner
selected or rejected every possible boundary between adjacent words.

The normal playback UI continues to consume:

```text
GET /v1/subtitles/{track_id}/chunk-partitions
```

Developers can inspect the matching diagnostic output with:

```text
GET /v1/subtitles/{track_id}/chunk-diagnostics
```

When a listener hears a pause that the partitioner misses, inspect the timing
input first:

```text
GET /v1/subtitles/{track_id}/word-timing-diagnostics
```

It reports every final inter-word gap plus the timing source and provider on
both sides. This distinguishes a timing/refinement miss from a partition-score
decision.

The diagnostic endpoint uses the same track-source configuration as the
product partition. In particular, punctuation from a known ASR-generated track
is treated as inferred evidence and cannot force a boundary by itself.

Each sentence response contains:

- `partition`: the unchanged product-facing `SentenceChunkPartition`;
- `candidates`: every possible adjacent-word boundary;
- `raw_score` and `selection_threshold`;
- `selected` and `forced`;
- `primary_source`;
- `evidence`, including acoustic gaps, punctuation, phrase protection,
  pre-boundary lengthening, filled-pause hesitation, readability fit, fragment
  penalties, and length fallback.

V4 learned evidence also reports model probability, bounded score delta,
provider ID, model revision, and license. It is present only for ambiguous
rule-based candidates where the optional model is allowed to contribute.

Example:

```bash
curl -H "Authorization: Bearer $LLPLAYER_TOKEN" \
  "http://127.0.0.1:$LLPLAYER_PORT/v1/subtitles/$TRACK_ID/chunk-diagnostics" |
  jq '.[0].candidates[] | {left_token_index, right_token_index, raw_score, selected, evidence}'
```

Use the version-controlled calibration fixture at
`testdata/chunk/v2-golden.json` when changing V2 scores or thresholds. New
cases should capture an identifiable listening condition and state the expected
display chunks. C3 cases live in `testdata/chunk/v3-rich-acoustic.json`, and C4
learned-provider cases live in `testdata/chunk/v4-learned-prosodic.json`.
Rich-acoustic analyzers add provider-attributed evidence to candidates rather
than changing the stable display partition contract.
