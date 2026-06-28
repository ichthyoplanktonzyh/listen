# Sound-Line Real Media QA Pack

This directory contains QA metadata for validating the sound-line (PhoneTimeline,
`sound_analysis.learning_phones`, `sound_analysis.connected_speech`) pipeline on
real English media.

## What is stored in this repository

- `manifest.jsonl` — QA case registry (one JSON object per line, see schema below).
- `cases/<case-id>.md` — manual listening observations per case.
- This README.

## What is NOT stored in this repository

- Media bodies (audio/video files) without explicit redistribution permission.
- Restricted benchmark corpora (TIMIT, Buckeye, TED-LIUM bodies).
- `.lltimeline.json` files generated from restricted media.
- Full transcript timelines generated from local-only web videos.

All local-only resources are referenced via `local_path` in the manifest, with
SHA-256 checksums recorded when available. Local-only resources are managed
outside the repository at their original locations.

## Manifest schema

Each line in `manifest.jsonl` is a JSON object with these fields:

| Field | Required | Description |
|-------|----------|-------------|
| `case_id` | yes | Unique ID, lowercase ASCII + digits + hyphens |
| `title` | yes | Human-readable title |
| `dataset` | yes | Source dataset name |
| `layer` | yes | `phone_gold`, `natural_connected_speech`, `product_media`, or `supplemental` |
| `language` | yes | BCP-47 language tag |
| `license` | yes | `{redistributable, status, notes}` |
| `source` | yes | `{kind, locator, external_url}` |
| `media` | yes | `{local_path, sha256, duration_ms}` |
| `subtitle` | no | `{local_path, sha256, kind}` — when separate from timeline |
| `lltimeline` | yes | `{path, local_only, sha256}` |
| `targets` | yes | `{phenomena, expected_connected_speech_families, min_manual_observations}` |
| `qa_notes` | yes | Path to case notes markdown file |

## Generating checksums

```sh
shasum -a 256 /path/to/file
```

## Running the verifier

```sh
python scripts/verify-sound-line-real-media.py \
  --manifest testdata/sound-line-real-media/manifest.jsonl

# Strict mode: treat missing local-only resources as errors
python scripts/verify-sound-line-real-media.py \
  --manifest testdata/sound-line-real-media/manifest.jsonl --strict-local

# JSON summary output
python scripts/verify-sound-line-real-media.py \
  --manifest testdata/sound-line-real-media/manifest.jsonl --json

# Final readiness mode: require at least one timeline with sound_analysis and connected_speech
python scripts/verify-sound-line-real-media.py \
  --manifest testdata/sound-line-real-media/manifest.jsonl --require-ready
```

## Manual listening observations

Each case notes file under `cases/<case-id>.md` must contain at least 3 observations
per the template in the phase plan. See `.planning/phases/2.17-real-media-sound-line-qa/2.17-PLAN.md`
for the observation template and QA decision guide.
