# LLPlayerNext Project Handoff: Text-Level Chunk Detection (2026-06-13)

## Repository State

- Workspace: `/Users/shadow/LLPlayerNext/.claude/worktrees/feature+chunk-listening-comprehension`
- Branch: `worktree-feature+chunk-listening-comprehension`
- Based on: `feature/asr-word-timestamps` (main branch at 888f310)
- Commits pending (unstaged changes):

Preserve these paths exactly as they are:

- `.claude/`
- `docs/architecture/`
- All existing `milestone-2.0` and M1.9 planning documents

## What Was Built

Text-level (lexical) chunk detection — a companion module to the acoustic
(gap-based) chunk detection spike completed earlier in the same worktree.

### New Files

| File | Description |
|------|-------------|
| `crates/speech-analysis/src/text_chunk_detection.rs` | Core module: data types, data loading (compile-time embedded TSV), span collection from 3 sources, overlap resolution, partition building, 18 unit tests |
| `crates/speech-analysis/data/phrase_list.tsv` | 505 PHRASE List entries (Martinez & Schmitt 2012) with category labels, compiled into binary via `include_str!` |
| `crates/speech-analysis/data/coca_ngrams.tsv` | ~1K seed COCA n-gram collocations (MI ≥ 3.0, 2-5 grams), compiled into binary via `include_str!` |

### Modified Files

| File | Changes |
|------|---------|
| `crates/speech-analysis/src/chunk_detection.rs` | Added `BoundaryMarker::LexicalPhrase` variant, `CombinedChunkResult`/`CombinedChunkGroup` types, `combine_chunks()`, `annotate_acoustic_with_text()`, `evidence_source_name()` |
| `crates/speech-analysis/src/lib.rs` | Added `pub mod text_chunk_detection;` |
| `crates/application/src/lib.rs` | Added `detect_text_chunks()`, `detect_text_chunks_for_track()`, `detect_combined_sentence_chunks()` methods on `AppServices` |
| `CHANGELOG.md` | Incremental additions to 0.7.1 section |

### Key Design Decisions

1. **Text partition covers every word**: Unlike `phrase_candidates()` which finds
   isolated multi-word expressions, `detect_text_chunks()` partitions the entire
   sentence — every word token belongs to exactly one chunk. Tokens not covered
   by any phrase span become single-word chunks with `TextChunkEvidence::SingleWord`.

2. **Three data sources, embedded at compile time**: COCA n-grams and PHRASE List
   are embedded in the binary via `include_str!` + `std::sync::OnceLock` (same
   pattern as CMUdict in `speech-analysis/src/lib.rs`). External phrase candidates
   (ECDICT, built-in rules) are passed at call time.

3. **Longest-match-first overlap resolution**: When spans overlap (e.g. "a lot of"
   vs "a lot"), the longer span wins. Same-length ties are broken by confidence.
   This is the standard approach (WhisperX, stable-ts).

4. **Parallel type hierarchy**: `TextChunkGroup`/`TextChunkBoundary`/
   `TextChunkDetectionResult` parallel the acoustic `ChunkGroup`/`ChunkBoundary`/
   `ChunkDetectionResult`. The `Combined*` types sit at the intersection.

5. **Four-quadrant confidence logic**: When merging acoustic and text evidence:
   - Both detect → `(ac + tc)/2 + 0.1` (mutual reinforcement)
   - Acoustic only → `ac * 0.8` (possible breath, not grammar)
   - Text only → `tc * 0.6` (grammatical chunk, no pause)
   - Neither → `0.0`

6. **Zero new dependencies**: No changes to any `Cargo.toml`. Uses existing
   `serde` for serialization and `std::sync::OnceLock` for lazy data init.

### Data Sources

| Source | Entries | Confidence | How Embedded |
|--------|---------|------------|--------------|
| PHRASE List | 505 | 0.85 fixed | `include_str!("../data/phrase_list.tsv")` |
| COCA n-gram | ~1K seed | MI→[0.50,1.00] | `include_str!("../data/coca_ngrams.tsv")` |
| ECDICT/builtin | Runtime | 0.70 fixed | Passed via `PhraseCandidate` from application layer |

### Architecture

```
crates/speech-analysis/
  data/
    phrase_list.tsv          ← 505 entries, compile-time embedded
    coca_ngrams.tsv          ← ~1K seed, compile-time embedded
  src/
    text_chunk_detection.rs  ← Core module (types, loading, algorithm, tests)
    chunk_detection.rs       ← Extended with LexicalPhrase + combine_chunks
    lib.rs                   ← pub mod text_chunk_detection
crates/application/
  src/
    lib.rs                   ← 3 new AppServices methods
```

### Data Flow

```
SubtitleSentence.tokens
  │  extract word tokens (filter Punctuation/Whitespace/Other)
  │
  ├─→ COCA lookup (sliding window 2..=5)
  ├─→ PHRASE List lookup (sliding window 2..=7)
  └─→ External PhraseCandidate conversion
  │
  └─→ resolve_overlaps (longest-match-first greedy)
        │
        └─→ build_partition
              ├─→ Vec<TextChunkGroup>  (every word covered)
              └─→ Vec<TextChunkBoundary>
```

### Combinator Flow (acoustic + text)

```
WordTiming[]  ──→ detect_chunk_boundaries()  ──→ ChunkDetectionResult
                                                        │
SubtitleSentence + PhraseCandidate[]                    │
  ──→ detect_text_chunks()  ──→ TextChunkDetectionResult │
                                    │                    │
                                    └─ combine_chunks() ─┘
                                          │
                                          └─→ CombinedChunkResult
```

## Verification

```bash
# All tests pass (49 speech-analysis + 42 application + all other crates)
cargo test --workspace

# Zero warnings
cargo clippy --workspace -- -D warnings

# No new dependencies
git diff --stat Cargo.toml crates/*/Cargo.toml  # should show no changes
```

### Test Coverage

- **18 unit tests** in `text_chunk_detection.rs`: empty, single word, COCA
  collocation, PHRASE List, external candidate forwarding, single-word skip,
  longest-match resolution, non-overlapping phrases, case insensitivity,
  partition coverage, boundary count, token order, punctuation filtering,
  MI→confidence (boundaries + monotonic), source counts, multi-source detection
  ("in front of", "take care of")

## Known Limitations

1. **COCA data is seed only**: ~1K entries vs the full ~50K. Replace with actual
   COCA frequency data (word.info) when available. The code structure and MI→confidence
   mapping are production-ready; only the data file needs upgrading.
2. **No HTTP API**: Following the acoustic chunk pattern, text chunk detection
   is library-only for now. API endpoints should be added once the combined
   detection interface stabilizes.
3. **No persistence**: Text chunk results are ephemeral (computed on demand).
   If caching is desired, follow the pronunciation/timing caching pattern in
   `application/src/lib.rs`.
4. **English-only**: The embedded data (COCA + PHRASE List) is English-specific.
   The algorithm itself is language-agnostic (token-based sliding window).

## Next Steps for the Chunk Feature

1. **Replace COCA seed data** with full MI ≥ 3.0 n-gram dataset (~50K entries)
   from word.info or equivalent.
2. **Expose HTTP API** (`GET /v1/sentences/{id}/text-chunks`,
   `GET /v1/sentences/{id}/combined-chunks`).
3. **Cross-reference with M2.0 forced-alignment timings** when available —
   ms-level timing precision will significantly improve acoustic boundary
   detection and therefore the `combine_chunks()` output.
4. **Flutter UI integration** — display text-level chunk boundaries in the
   learning subtitle overlay alongside pronunciation/word-timing data.
5. **Additional data sources** — Multiword Expressions (MWE) databases,
   Academic Formulas List (AFL), discipline-specific phrase lists.

## Relationship to Milestone 2.0

This feature is independent of M2.0 (real-speech phoneme analysis). It operates
on subtitle text and existing word timings, not on audio signals. However:

- Better word timings from M2.0 (forced alignment) will improve acoustic chunk
  boundary precision, which in turn improves `combine_chunks()` output.
- The chunk detection infrastructure is provider-agnostic — switching from DTW
  to forced-alignment timings requires zero code changes.
- The `BoundaryMarker` enum already has slots for `PreBoundaryLengthening` and
  `PitchReset` — these can be populated when M2.0 provides access to audio features.

Do not claim M2.0 completion based on text-level chunk detection. This feature
is complementary but orthogonal.
