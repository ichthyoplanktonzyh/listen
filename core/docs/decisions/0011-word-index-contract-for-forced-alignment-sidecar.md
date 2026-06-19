# ADR 0011: Word Index Contract for Forced Alignment Sidecar

## Status

Proposed for implementation in `2.1-alignment-pipeline-hardening`.

Not yet implemented. This ADR records the intended contract fix for the
`word_index` misalignment bug documented in
[`2.1-PLAN.md`](../../.planning/phases/2.1-alignment-pipeline-hardening/2.1-PLAN.md)
(P0). It supersedes the implicit, buggy indexing assumption inherited from
[ADR 0010](./0010-forced-alignment-research-sidecar.md).

## Context

ADR 0010 introduced the forced alignment research sidecar. The sidecar
(`scripts/forced-align/align-cli.py`) reads a JSON request listing per-segment
word strings, runs torchaudio MMS_FA, and writes aligned word timings as JSON.
Rust (`speech_analysis::forced_align::merge_alignments`) then merges the aligned
timings back onto the `WordTiming` rows produced by `asr_timing`.

The two sides disagree on what `word_index` means:

- **Python side** (`align-cli.py`): `_tokenize_words` normalizes each word and
  `continue`s past any word that normalizes to the empty string (e.g. CJK
  characters, pure digits outside the MMS dictionary, pure punctuation). The
  emitted `word_index` is therefore the position **within the filtered
  subsequence**, counted from 0.
- **Rust side** (`forced_align.rs`): `merge_alignments` builds `rows` from all
  `WordTiming` rows of the sentence sorted by `token_index` (**unfiltered**) and
  looks up the aligned word via `by_word.get(&(word_pos as u32))`, where
  `word_pos` is the enumerate index of the unfiltered row.
- `forced_align.rs:30` documents `word_index` as "the same indexing scheme used
  by `asr_timing::extract_word_timings`" — i.e. the unfiltered index. The Python
  filter makes that claim false.

When a word inside a sentence normalizes to empty, every later word's Python
`word_index` is shifted down by one (more for each skipped word). The aligned
timestamps are then written onto the **wrong** `WordTiming` rows, or dropped
silently if they fall outside the sentence. This does not trigger on pure
English TIMIT (the 171/171 matched benchmark), but is guaranteed to fire on
news video with proper nouns, numbers, or foreign borrowings.

The result is silent data corruption: highlighting diverges from the audible
word, and the objective evaluation (`evaluate-word-timelines.py`) cannot detect
it because it pairs words by `(sentence_id, token_index)` without comparing
`normalized_text`.

## Decision

Make the `word_index` contract explicit and **alignment-preserving** by having
the Python sidecar emit a placeholder for every skipped word.

### Sidecar output protocol

```json
{
  "segments": [
    {
      "segment_index": 0,
      "words": [
        {"word_index": 0, "word": "hello", "start_ms": 100, "end_ms": 300},
        {"word_index": 1, "skipped": true},
        {"word_index": 2, "word": "world", "start_ms": 400, "end_ms": 600}
      ]
    }
  ]
}
```

- `word_index` is the 0-based position among **all** lexical word tokens in the
  segment, **before** any normalization filtering. It is identical to the
  enumerate index of the `WordTiming` rows sorted by `token_index`.
- A skipped word (normalized to empty) is emitted as
  `{"word_index": k, "skipped": true}` and **does not** include `word`,
  `start_ms`, or `end_ms`.
- `align-cli.py` no longer uses a filtered counter; the original word-list index
  is carried through.

### Rust merge behavior

- `merge_alignments` recognizes `skipped: true` entries: the corresponding word
  keeps its original DTW timing (the existing per-word fallback path).
- The index lookup stays `word_pos`-based on the unfiltered `rows`, so the
  placeholder guarantees indices line up.
- `AlignedWord`'s doc comment (`forced_align.rs:30`) is corrected to state the
  unfiltered-index semantics explicitly.

### Backward compatibility

- Rust tolerates sidecar output that omits the `skipped` field entirely (treats
  all entries as non-skipped). This keeps an old sidecar functional while the
  new Python is rolled out, and keeps the contract valid for any future
  Rust-native / ONNX aligner that never skips words.

## Consequences

- **Positive**
  - `word_index` always aligns with Rust `token_index`; silent misalignment on
    CJK / proper-noun / numeric content is eliminated.
  - The contract is now documented and testable (Python unit tests for skipped
    words; Rust test for `merge_alignments` with placeholders).
  - Forward-compatible with a future production aligner (ADR 0010 Future Path):
    the index contract is independent of the MMS_FA backend.
- **Negative**
  - The sidecar output gains one new field (`skipped`). The Rust parser must
    treat it as optional, adding a small amount of defensive parsing.
  - A skipped word yields DTW timing rather than acoustic timing — but this is
    strictly better than today's behavior of writing another word's timing onto
    its row.

## Rejected Alternatives

- **Rust side adopts the filtered index.** Rejected because it touches
  `transcription.rs` (filter the words sent to Python), `forced_align.rs`
  (filter `rows` to match), and requires rewriting the `AlignedWord` contract
  plus its doc comment. The change surface is larger and the filtered index is
  harder to reason about than the natural token index.
- **Both sides changed (placeholder + Rust-side consistency assertion).**
  Rejected as redundant: the placeholder already guarantees alignment, and an
  assertion that "aligned word count == expected word count" is useful as a test
  but not as a protocol rule (skipped words are legitimately fewer).

## Future Path

If a later ADR replaces the Python sidecar with a Rust-native or ONNX Runtime
aligner (per ADR 0010 Future Path), the `word_index` contract from this ADR
still applies: the aligner emits one entry per lexical word token, using
`skipped: true` for any token it cannot align, and `merge_alignments` consumes
it unchanged.
