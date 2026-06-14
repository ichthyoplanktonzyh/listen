# Chunk Boundary Diagnostics

Chunk boundary diagnostics explain why the V2 acoustic-first partitioner
selected or rejected every possible boundary between adjacent words.

The normal playback UI continues to consume:

```text
GET /v1/subtitles/{track_id}/chunk-partitions
```

Developers can inspect the matching diagnostic output with:

```text
GET /v1/subtitles/{track_id}/chunk-diagnostics
```

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
  readability fit, fragment penalties, and length fallback.

Example:

```bash
curl -H "Authorization: Bearer $LLPLAYER_TOKEN" \
  "http://127.0.0.1:$LLPLAYER_PORT/v1/subtitles/$TRACK_ID/chunk-diagnostics" |
  jq '.[0].candidates[] | {left_token_index, right_token_index, raw_score, selected, evidence}'
```

Use the version-controlled calibration fixture at
`testdata/chunk/v2-golden.json` when changing V2 scores or thresholds. New
cases should capture an identifiable listening condition and state the expected
display chunks. C3 analyzers should add evidence to candidates rather than
changing the stable display partition contract.
