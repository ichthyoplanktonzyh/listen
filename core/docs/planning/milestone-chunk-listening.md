# Chunk Listening Experience Milestones

## Summary

This plan advances the existing chunk research spike into a user-visible
listening feature. The first priority is not to perfect chunk detection. It is
to complete the product loop:

```text
load subtitle sentence
  -> produce one complete, non-overlapping chunk partition
  -> render the sentence grouped by chunk
  -> highlight or bounce the active chunk during playback
```

The product assumes that presenting speech in chunks is useful. Detection
quality will improve after the MVP, with acoustic evidence remaining the
highest-priority source for deciding boundaries.

The existing worktree already provides valuable foundations:

- word-level playback timing and active-word animation;
- gap-based acoustic boundary detection;
- text phrase span detection from PHRASE List, seed collocations, and phrase
  candidates;
- application-layer sentence and track detection methods;
- preliminary combined result types.

The current `combine_chunks()` implementation is a prototype, not the final
product partitioner. The milestones below replace it with a stable final
partition contract and then improve the evidence used by that partitioner.

## Product Contract

For every subtitle sentence containing word tokens, the product-facing chunk
result must:

1. Cover every word token exactly once.
2. Preserve token order.
3. Contain no overlapping chunks.
4. Provide token start/end and media start/end for every chunk.
5. Produce a usable fallback when precise acoustic timing is unavailable.
6. Allow the desktop client to determine the active chunk locally from the
   current playback position.
7. Preserve word click behavior and word-level learning styles inside chunks.

The user-facing output is a single partition:

```text
[I think] [that it's important] [to note]
```

Internally, acoustic boundaries, punctuation, phrase spans, and length rules
remain separate evidence. The final partitioner resolves them into the one
partition shown to the user.

## Execution Order

Implementation order is fixed:

1. **C0: Correctness baseline and final partition contract**
2. **C1: User-visible chunk MVP**
3. **C2: Acoustic-first partition quality**
4. **C3: Rich acoustic evidence**
5. **C4: Learned prosodic boundary provider**

C0 and C1 form the MVP. C2-C4 improve how the sentence is divided and must not
block the first user-visible experience.

### MVP Delivery Slices

| Slice | Output | Depends On | Can Start When |
|---|---|---|---|
| MVP-1 | Final partition types, V1 partitioner, invariant tests | Existing raw detectors | Immediately |
| MVP-2 | Application method and track-level HTTP endpoint | MVP-1 contract | Contract is stable |
| MVP-3 | Flutter models, loading, controller state, active-chunk helper | MVP-1 JSON shape | API shape is stable |
| MVP-4 | Chunk-aware `TokenLine`, active animation, fallback | MVP-3 state | Partitions load in desktop |
| MVP-5 | Settings, regression tests, collaborative acceptance | MVP-4 experience | End-to-end path works |

MVP-2 and MVP-3 may proceed in parallel after the JSON contract is locked.
MVP-4 must preserve existing word interaction before settings or visual polish
are added.

---

## Milestone C0: Final Partition Foundation

### Goal

Turn the current research outputs into one reliable, product-facing sentence
partition that can safely be consumed by API and Flutter code.

### Product Decisions

- The final partition is sentence-scoped.
- Acoustic evidence has the highest boundary priority when available.
- Phrase spans protect against undesirable internal splits but do not dictate
  the entire partition.
- Punctuation and length rules provide deterministic fallback behavior.
- Estimated word timings may drive animation, but must not be treated as real
  acoustic boundary evidence.
- The MVP does not persist chunk results. They are derived on demand from
  subtitle text, word timings, and the partitioner version.

### Core Contract

Add a product-facing result distinct from raw text and acoustic detections:

```text
SentenceChunkPartition
- sentence_id
- chunks: Vec<DisplayChunk>
- partitioner_id
- partitioner_version
- timing_quality

DisplayChunk
- index
- token_start
- token_end
- text
- start_ms
- end_ms
- boundary_after?

DisplayChunkBoundary
- left_token_index
- right_token_index
- score
- primary_source
- evidence[]
```

The product contract should use media-absolute integer milliseconds and token
indices. Raw candidate details may remain in the speech-analysis crate, but the
desktop API should expose only the stable display partition.

### Partition Algorithm V1

For every possible boundary between consecutive word tokens:

1. Start with a neutral boundary score.
2. Add a strong score for a real acoustic gap.
3. Add a score for punctuation strength.
4. Subtract a score when the boundary is inside a high-confidence phrase span.
5. Add a score when the current chunk would exceed the preferred maximum size.
6. Select boundaries while enforcing minimum/preferred/maximum chunk lengths.
7. Derive chunk times from the first and last word timing.

Initial configurable rules:

```text
preferred words per chunk: 3-5
minimum words per chunk: 1
soft maximum: 7
hard maximum: 10
strong punctuation: always prefer boundary
real gap >= configured threshold: strong boundary
estimated timing gap: ignored as acoustic evidence
high-confidence phrase interior: protected unless hard maximum requires split
```

These values are product defaults, not linguistic truth. Keep them in
`ChunkPartitionConfig`.

### Required Engineering Work

#### Rust Speech Analysis

- Add the final partition types and `partition_sentence()` entry point.
- Consume sentence tokens, word timings, text spans, and raw acoustic
  boundaries as evidence.
- Build the final partition from the union of candidate boundary positions.
- Derive timing for every display chunk, including estimated-timing fallback.
- Do not match text phrases across punctuation boundaries.
- Validate external phrase candidate token ranges before using them.
- Fix acoustic confidence interpolation and empty-input sentence identity.
- Retain raw `detect_text_chunks()` and `detect_chunk_boundaries()` for
  diagnostics and later algorithm work.

Primary files:

- `crates/speech-analysis/src/chunk_detection.rs`
- `crates/speech-analysis/src/text_chunk_detection.rs`
- `crates/speech-analysis/src/lib.rs`
- new `crates/speech-analysis/src/chunk_partition.rs` if separation keeps the
  final partitioner easier to reason about

#### Application Layer

- Add `chunk_partition(sentence_id)` and `chunk_partitions_for_track(track_id)`.
- Ensure the application passes the requested sentence identity even when
  there are no word timings.
- Keep raw text/acoustic detection methods internal or explicitly diagnostic.

Primary file:

- `crates/application/src/lib.rs`

### Tests

- Every word token is covered exactly once.
- Token order and sentence identity are preserved.
- No phrase is matched across punctuation.
- Acoustic boundary inside a text phrase is represented and resolved according
  to score/priority instead of disappearing.
- Estimated timings do not create fake acoustic boundaries.
- Every display chunk receives valid monotonic timing.
- Invalid external candidate ranges are ignored safely.
- Empty, punctuation-only, single-word, very long, and missing-timing sentences
  degrade safely.
- Golden partition tests cover at least 20 representative sentences.

### Completion Gate

- A stable `SentenceChunkPartition` is available from `AppServices`.
- Existing raw detectors remain usable for diagnostics.
- The correctness findings from the worktree review are fixed.
- Unit and integration tests for final partition invariants pass.

---

## Milestone C1: User-Visible Chunk MVP

### Goal

Deliver the first complete user experience: the primary subtitle sentence is
visibly grouped into chunks, and the current chunk highlights or bounces during
playback using the existing local timeline path.

### MVP Experience

During playback, the user sees:

```text
[I think]  [that it's important]  [to note]
             ^ active chunk
```

Requirements:

- chunks are visually separated without making the subtitle hard to read;
- the active chunk uses the existing configurable word animation style;
- word-level clicks, vocabulary colors, phrase interactions, and pronunciation
  display continue to work;
- seeking, pausing, speed changes, subtitle offsets, and cue changes immediately
  update the active chunk;
- chunk enhancement failure falls back to the existing word-level subtitle;
- only the primary learning subtitle is chunked in the MVP.

### API

Add one stable track-level endpoint:

```text
GET /v1/subtitles/{track_id}/chunk-partitions
```

The response is a list of `SentenceChunkPartition`, matching the existing
track-level word-timing load pattern. Do not add separate public text,
acoustic, and combined endpoints for the MVP.

Primary files:

- `crates/api-http/src/lib.rs`
- API contract/snapshot tests already maintained by `api-http`

### Flutter Models And Loading

- Add `DisplayChunk`, `DisplayChunkBoundary`, and `SentenceChunkPartition` to
  `apps/desktop/lib/models/timeline.dart`.
- Add `trackChunkPartitions()` to
  `apps/desktop/lib/services/api_service.dart`.
- Load chunk partitions alongside word timings in `_loadSpeechEnhancements()`.
- Store partitions by sentence in `SubtitleState`.
- Clear them when the primary track changes.

Primary files:

- `apps/desktop/lib/models/timeline.dart`
- `apps/desktop/lib/services/api_service.dart`
- `apps/desktop/lib/controllers/subtitle_controller.dart`
- `apps/desktop/lib/main.dart`

### Local Active-Chunk Timeline

Add a pure client-side helper:

```text
currentChunkIndex(partition, mediaPosition, subtitleOffset)
```

The helper must:

- use chunk `start_ms/end_ms`;
- remain local and avoid high-frequency HTTP calls;
- retain the previous active chunk through tiny timing gaps when appropriate;
- reset immediately when the current sentence changes.

Extend `SubtitleController.updateCurrentWord()` or introduce
`updatePlaybackHighlights()` so current word and current chunk update in one
notification where possible.

### Rendering

Refactor `TokenLine` so it can render chunk containers while preserving each
token's existing interaction and style.

Recommended structure:

```text
TokenLine
  -> ChunkSpan / ChunkTokenGroup
       -> existing token spans and phrase interactions
```

MVP visual behavior:

- subtle extra spacing or divider between chunks;
- optional low-opacity rounded background for the active chunk;
- active chunk animation reuses the configured word highlight style and
  intensity;
- no layout jump when the active chunk changes;
- current word highlight may remain visible inside the active chunk.

Primary file:

- `apps/desktop/lib/widgets/subtitle/token_line.dart`

### Settings

Add:

- `showChunkGrouping`, default `true` for the learning preset;
- `highlightCurrentChunk`, default `true`;
- optionally reuse `wordHighlightStyle` and `wordAnimationIntensity` for MVP
  instead of adding separate styling controls.

Settings and localization files:

- `apps/desktop/lib/settings.dart`
- `apps/desktop/lib/controllers/settings_controller.dart`
- `apps/desktop/lib/widgets/settings/settings_dialog.dart`
- `apps/desktop/lib/localization.dart`

### MVP Non-Goals

- chunk click-to-loop;
- user boundary editing;
- persistence/cache schema;
- pitch, energy, or learned-model analysis;
- secondary subtitle chunking;
- showing raw evidence or confidence in the normal playback UI;
- full COCA dataset expansion.

### Automated Verification

- API returns one valid partition per sentence.
- Dart JSON parsing and active-chunk timeline helpers are unit tested.
- `TokenLine` widget tests verify grouping, active style, word click behavior,
  and fallback without partitions.
- rapid seek, pause, speed, loop, and subtitle offset tests cover active chunk.
- existing word-level highlight and phrase interaction tests continue to pass.

### Collaborative Acceptance

1. Load a normal SRT/VTT track and see every primary subtitle sentence grouped.
2. Start playback and see the active chunk move with the audio.
3. Current word movement remains visible inside the active chunk.
4. Seek, pause, change speed, loop a sentence, and adjust subtitle offset;
   active chunk remains correct.
5. Click words and phrase candidates inside chunked subtitles; existing
   learning interactions still work.
6. Disable chunk grouping and recover the existing subtitle experience.
7. A chunk API failure does not interrupt playback or hide subtitles.

### Completion Gate

Milestone C1 is complete only when the user can watch media and experience a
fully chunked, actively highlighted primary subtitle without using developer
tools.

---

## Milestone C2: Acoustic-First Partition Quality

### Goal

Improve the partition mechanism while keeping the C1 user contract unchanged.
Acoustic evidence becomes the principal boundary signal; text and product rules
resolve ambiguity and keep the result readable.

### Completed

C2 completed on 2026-06-14:

- source-specific gap thresholds distinguish ASR-reported, forced-aligned,
  user-adjusted, and estimated timings;
- moderate acoustic gaps can combine with other evidence while strong acoustic
  gaps remain independently decisive;
- punctuation on known ASR-generated tracks is treated as inferred evidence and
  no longer forces a boundary by itself;
- phrase protection blocks ambiguous internal splits but does not erase strong
  acoustic boundaries;
- weak evidence is penalized when it would create a leading or trailing
  single-word fragment;
- structured diagnostics expose selected and rejected boundary candidates,
  scores, thresholds, forcing state, and evidence without changing the product
  API;
- an initial golden calibration baseline locks expected length and strong-gap
  behavior;
- a version-controlled golden corpus covers fast speech, hesitation, moderate
  pauses, ASR-inferred versus trusted punctuation, fixed expressions, and long
  subtitles while enforcing fragment and overlong-chunk bounds;
- preferred-range scoring selects supported natural boundaries before length
  fallback, minimum-length penalties suppress weak short fragments, and
  soft/hard limits prevent overlong chunks;
- `GET /v1/subtitles/{track_id}/chunk-diagnostics` exposes the structured
  diagnostics using the same source-aware configuration as product partitions.

Hesitation gaps remain deliberately visible as acoustic evidence in V2.
Determining whether a pause is a hesitation, breath, or meaningful boundary
requires the richer non-gap acoustic evidence scheduled for C3.

### Scope

- Treat `AsrReported`, `ForcedAligned`, `Estimated`, and `UserAdjusted`
  timings differently.
- Calibrate gap scoring by timing source.
- Add punctuation-aware boundary evidence using the original subtitle token
  stream.
- Add phrase-interior protection instead of treating phrase spans as mandatory
  display chunks.
- Improve long-chunk splitting and short-fragment merging.
- Add boundary provenance and diagnostics for developer inspection.
- Version the partitioner output so algorithm changes are observable.

### Suggested Boundary Priority

```text
user-adjusted boundary
  > strong real acoustic gap
  > sentence/strong punctuation boundary
  > moderate acoustic gap + punctuation/text support
  > product length fallback
```

Phrase evidence usually lowers the probability of an internal split. It should
not erase a strong acoustic boundary.

### Deliverables

- `ChunkPartitionConfig` with source-aware scoring.
- Developer/debug view or structured diagnostic output showing why each
  boundary was selected.
- Golden corpus expanded with fast speech, hesitation, long subtitles,
  punctuation, and fixed expressions.
- Optional chunk click-to-seek and chunk loop, using existing `DisplayChunk`
  timing.

### Completion Gate

- [x] C1 API and Flutter models remain compatible.
- [x] Partitioner V2 produces visibly fewer single-word fragments and no
  overlong chunks across the golden corpus quality bounds.
- [x] Acoustic boundaries can alter the final partition instead of merely
  annotating text chunks.

---

## Milestone C3: Rich Acoustic Evidence

### Goal

Detect meaningful boundaries that do not contain a large pause and reduce false
boundaries caused by hesitation or breathing.

### Evidence Roadmap

Implement as independent providers or analyzers that emit boundary evidence:

1. **Improved alignment**
   - consume forced-aligned word or phoneme timings when available;
   - retain the same `SentenceChunkPartition` output.
2. **Pre-boundary lengthening**
   - compare the final word/syllable duration with local speaking-rate context.
3. **Pitch reset**
   - measure voiced F0 before and after candidate boundaries.
4. **Energy/intensity change**
   - measure local energy dip/reset near boundaries.
5. **Hesitation evidence**
   - reduce confidence for filled pauses and isolated breath-like gaps.

Each analyzer should emit evidence, not directly construct the final partition.

### Architecture

```text
audio/timings/text
  -> independent boundary evidence analyzers
  -> per-word-boundary evidence scores
  -> versioned partitioner
  -> unchanged display partition API
```

### Completion Gate

- At least one non-gap acoustic cue influences final partitions.
- Analysis runs locally without blocking playback.
- Missing audio features degrade to C2 behavior.

---

## Milestone C4: Learned Prosodic Boundary Provider

### Goal

Evaluate and optionally integrate a learned model for prosodic or intonation
unit boundary evidence while preserving the same product-facing partition and
desktop experience.

### Candidate Uses

- run a PSST-like model as an offline teacher/provider;
- distill model output into a smaller local boundary classifier;
- consume Whisper encoder features with a lightweight boundary head;
- use a model only for ambiguous boundaries after rule-based evidence.

### Provider Contract

The learned model should emit per-boundary scores and provenance:

```text
ProsodicBoundaryEvidence
- sentence_id
- left_token_index
- right_token_index
- score
- provider_id
- model_revision
```

It must not bypass the final partitioner or expose model-specific output to the
normal playback UI.

### Completion Gate

- Model/runtime licensing and distribution are acceptable.
- Model is optional and failure-safe.
- C1-C3 behavior remains available without the model.

---

## Cross-Milestone Engineering Rules

1. The stable product contract is `SentenceChunkPartition`; raw detector
   outputs are implementation details or diagnostics.
2. Playback highlighting remains local in Flutter and never depends on
   high-frequency API requests.
3. Acoustic evidence has priority, but the final result must remain readable
   and fully cover the sentence.
4. Algorithm improvements must not require rewriting the desktop rendering
   path.
5. Chunk analysis failure must never block playback or ordinary subtitles.
6. Do not persist derived partitions until recomputation cost or startup
   latency demonstrates a real need.
7. Do not expand phrase datasets before the MVP user loop is complete.

## Immediate Work Queue

Execute these tasks next, in order:

1. Implement and test `SentenceChunkPartition` and `partition_sentence()`.
2. Fix reviewed correctness issues in the current raw detectors.
3. Add application and track-level HTTP partition APIs.
4. Add Flutter partition models, loading, and controller state.
5. Refactor `TokenLine` to render chunk groups while preserving word behavior.
6. Add local active-chunk tracking and animation.
7. Add settings, fallback behavior, automated tests, and collaborative MVP
   acceptance.
