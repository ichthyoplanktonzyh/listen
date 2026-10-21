# Core test data

These files are inputs to existing tests and verification tools. They do not
set the current project scope or establish that a feature has passed product
acceptance. Shared checks are in [DEVELOPMENT.md](../../DEVELOPMENT.md).

## Inputs

- `asr/`, `subtitles/`, and `pronunciation/`: deterministic parser/analysis inputs.
- `chunk/` and `word-timelines/`: existing timeline/scoring regression fixtures.
- `phonetic-analysis/`: scorer and adapter inputs, including synthetic data and
  a source/license registry. Synthetic examples are not quality evidence.
- [Syntactic analysis](syntactic-analysis/README.md): alignment/mapping and locked
  validation inputs.
- [Content packages](content-package/README.md): package import/idempotency data.
- [Sound-line media metadata](sound-line-real-media/README.md): manifests and
  Markdown QA inputs checked by the media verifier.
- [Rhythm QA](rhythm-frame-qa/README.md) and
  [prosody fixtures](rhythm-prosody-benchmarks/README.md): scoring examples.

Keep copyrighted media, restricted corpora, credentials, and generated full
transcripts out of Git. Source/license records in fixture manifests remain
part of the input provenance.

## Generated media

From `core/`, with FFmpeg available:

```sh
bash testdata/generate.sh
```

This produces ignored synthetic media and checksums under `testdata/generated/`.
Tests use crate-relative paths or `include_str!`/`include_bytes!`; do not move
an input without updating its actual consumers.

Some manifests explicitly name Markdown files through `qa_notes`; keep those
files with the manifest. In contrast, provenance fields may name historical
source paths removed from the working tree. Those values record original
inputs and are not current navigation or project instructions. Documentation
cleanup does not rewrite fixture data.
