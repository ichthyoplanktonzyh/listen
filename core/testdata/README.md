# Test Data

> **Last updated:** 2026-06-13
> **Status:** active

## Directory Structure

```
testdata/
├── README.md                  # This file — fixture catalog
├── generate.sh                # Regenerates all generated/ media files
│
├── asr/                       # ASR/transcription fixtures
│   └── sample-output.json     # Hand-crafted whisper.cpp -ojf output (3 segments)
│
├── subtitles/                 # Subtitle parsing fixtures
│   ├── timeline.srt           # SRT with gaps, overlap, punctuation, apostrophe, hyphen
│   └── timeline.vtt           # Same timeline in WebVTT format
│
├── pronunciation/             # Pronunciation analysis fixtures
│   └── en-us-baseline.tsv     # 100-sentence fixed en-US baseline for rule validation
├── phonetic-analysis/          # M2.0 Phase 0 research catalog and scorer smoke data
│   ├── evaluation-catalog-v1.tsv
│   ├── candidates-v1.json
│   ├── reference-smoke-v1.jsonl
│   ├── prediction-smoke-v1.jsonl
│   └── prediction-smoke-errors-v1.jsonl
│
└── generated/                 # Synthetic media (gitignored, rebuild with generate.sh)
    ├── SHA256SUMS             # Checksums of generated files
    ├── sample-video.mp4       # 10s color bars + sine-wave audio
    ├── sample-audio.m4a       # 10s sine-wave audio-only
    ├── multi-audio.mkv        # Video with two distinguishable audio tracks
    ├── long-timeline.srt      # 2,100 subtitle cues
    └── embedded-text-subtitle.mkv  # MKV with embedded text subtitle track
```

## Fixture Catalog

### ASR Fixtures

| File | Size | Used By | Description |
|------|------|---------|-------------|
| `asr/sample-output.json` | ~2 KB | `speech-analysis/tests/asr_timing_integration_test.rs` | Compact real-structure whisper `-ojf` output exercising special-token filtering, non-empty word intervals, subword merge, and unavailable lexical-token fallback |

### Subtitle Fixtures

| File | Size | Used By | Description |
|------|------|---------|-------------|
| `subtitles/timeline.srt` | ~400 B | `subtitle-core/src/lib.rs` (6 tests), `persistence-sqlite/src/lib.rs` (17 tests), `persistence-sqlite/tests/persistence_integration_test.rs` (6 tests), `api-http/src/lib.rs` (6 tests) | 4-cue SRT with gaps, overlap, punctuation, apostrophe, hyphen, and line-break scenarios |
| `subtitles/timeline.vtt` | ~500 B | `subtitle-core/src/lib.rs` (6 tests) | WebVTT equivalent of timeline.srt |

### Pronunciation Fixtures

| File | Size | Used By | Description |
|------|------|---------|-------------|
| `pronunciation/en-us-baseline.tsv` | ~10 KB | `speech-analysis/src/lib.rs` (1 test) | 100-sentence baseline mapping words to expected ARPAbet/IPA/stress. Validates the CMUdict lookup + deterministic fallback pipeline |

### Phonetic Analysis Research Fixtures

| File | Used By | Description |
|------|---------|-------------|
| `phonetic-analysis/evaluation-catalog-v1.tsv` | `scripts/verify-m20-phase0.sh` | Fixed 60-slot M2.0 evaluation design. Slots remain planned until licensed audio and human-verified actual-phone references exist. |
| `phonetic-analysis/candidates-v1.json` | Phase 0 research | Candidate status, licensing constraints, and source registry. |
| `phonetic-analysis/reference-smoke-v1.jsonl` | `scripts/phonetic-eval.py` | Synthetic scorer reference; not quality evidence. |
| `phonetic-analysis/prediction-smoke-v1.jsonl` | `scripts/phonetic-eval.py` | Synthetic perfect prediction used to verify metric calculations. |
| `phonetic-analysis/prediction-smoke-errors-v1.jsonl` | `scripts/phonetic-eval.py` | Synthetic errors used to verify PER and failed release-gate calculations. |

### Generated Media

Generated files are **not checked into Git** (size: ~2 MB). Run `generate.sh` to recreate them locally. They are used by acceptance (`verify-m*.sh`) and manual QA scripts.

| File | Use Case |
|------|----------|
| `sample-video.mp4` | Media registration, subtitle import workflow |
| `sample-audio.m4a` | Audio-only media tests |
| `multi-audio.mkv` | Multi-audio-track selection tests |
| `long-timeline.srt` | Large subtitle import performance/stress tests |
| `embedded-text-subtitle.mkv` | MKV embedded subtitle extraction tests |

## Fixture Design Principles

1. **Version-controlled fixtures** (`asr/`, `subtitles/`, `pronunciation/`) are checked into Git. They are hand-crafted and intended to be stable over time.
2. **Generated media** (`generated/`) is created by `generate.sh` using FFmpeg. It is gitignored — run the script locally to recreate.
3. **Test references** use `include_str!` or `include_bytes!` for compile-time embedding, or relative paths from the crate root for runtime access.
4. **Isolation**: Each fixture targets a specific test concern. Don't overload fixtures with unrelated test scenarios.

## Adding a New Fixture

1. Place the file in the appropriate subdirectory.
2. Update this README — add an entry to the catalog table.
3. Reference it from tests using one of these patterns:
   - `include_str!("../../../testdata/<category>/<file>")` — for text fixtures
   - `include_bytes!("../../../testdata/<category>/<file>")` — for binary fixtures
   - `concat!(env!("CARGO_MANIFEST_DIR"), "/../../testdata/<category>/<file>")` — for runtime paths (integration tests)

## Regenerating Media

```bash
cd testdata && bash generate.sh
```

Requires: `ffmpeg` in PATH. Produces `generated/SHA256SUMS` for integrity verification.

## Related

- [Testing Milestone](../docs/features/testing-milestone.md)
- [Unified Testing Workflow](../docs/features/testing-workflow.md)
- [CI Configuration](../.github/workflows/ci.yml)
