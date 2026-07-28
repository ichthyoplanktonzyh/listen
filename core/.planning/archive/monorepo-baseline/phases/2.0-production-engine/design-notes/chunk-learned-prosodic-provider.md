# Learned Prosodic Chunk Provider

Milestone C4 adds an optional learned boundary-evidence provider without
changing the product-facing `SentenceChunkPartition` contract.

## Bundled Baseline

The bundled provider is `llplayer-prosodic-linear@v1`, a project-authored
linear classifier distributed under MIT. It runs locally on the CPU from the
embedded model artifact:

```text
crates/speech-analysis/data/prosodic-boundary-linear-v1.json
```

This is a deployable integration and calibration baseline, not a claim of
state-of-the-art prosodic recognition or an external PSST model. Its current
features use real word timings:

- left-word duration relative to a local median;
- current and previous inter-word gap ratios;
- sentence-relative boundary position.

## Partitioning Policy

The provider emits scored, provider-attributed evidence. The V4 partitioner
may consume it only when the existing rule score is ambiguous. Learned
evidence:

- cannot bypass the final partitioner;
- does not replace decisive acoustic-gap or punctuation decisions;
- does not undo filled-pause hesitation suppression;
- is ignored for estimated or incomplete word timings.

The normal playback UI continues to receive only the stable display partition.
Diagnostics include model probability, score delta, provider ID, model
revision, and license.

## Optional Runtime And Fallback

Model parsing and feature failures emit no learned evidence. Disabling
`ChunkPartitionConfig.learned_prosodic` reproduces C1-C3 behavior, and no
learned-provider failure can block playback.

Inspect bundled provider availability and distribution metadata with:

```text
GET /v1/chunk/providers
```

Inspect per-boundary evidence with:

```text
GET /v1/subtitles/{track_id}/chunk-diagnostics
```

The C4 calibration corpus is:

```text
testdata/chunk/v4-learned-prosodic.json
```

Future external or audio-feature models should implement the same evidence
contract and remain optional.
