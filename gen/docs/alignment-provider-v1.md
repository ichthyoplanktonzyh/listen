# Word Alignment Provider v1

## Purpose

The optional word-alignment stage aligns the exact Subtitle Text Track
tokenization that was emitted into a content package against the media, and
produces the v1 `word_timeline` resource with exactly one dependency on that
subtitle resource. It sits behind the same
`media -> machine events -> deterministic .listenpkg` interface as the ASR
stage and is always optional: when alignment is selected but fails, the ASR
Subtitle Text Track package is preserved and a stable typed warning is
reported. Cancellation never degrades.

## Selecting an aligner

`package from-media` accepts `--aligner` with one of:

| value | adapter | requires |
| --- | --- | --- |
| `none` | no alignment (default) | — |
| `fixture` | offline fixture adapter | `--alignment-fixture` |
| `command` | external aligner command | `--alignment-command` and `--alignment-command-arg` |
| `whisper-cpp` | first-class whisper.cpp aligner | the `--whisper-*` provider arguments |

The `fixture` aligner needs no media commands and no model, so the offline
fixture path stays fully deterministic. The `command` and `whisper-cpp`
aligners receive the same temporary 16 kHz mono signed-16-bit PCM WAV that the
ASR stage used, prepared with the same `--ffprobe-command`,
`--ffmpeg-command`, and `--audio-stream-index` configuration. The alignment
preprocessing never emits duplicate machine phases; the single `aligning`
phase covers the whole stage.

```bash
listen-gen package from-media input.mp4 \
  --provider whisper-cpp \
  --whisper-cli /path/to/whisper-cli \
  --whisper-model /path/to/ggml-base.bin \
  --whisper-model-id whisper.cpp:base@main \
  --whisper-language auto \
  --aligner whisper-cpp \
  --title "Lesson" \
  --media-kind video \
  --duration-ms 125000 \
  --created-at-ms 1786000000000 \
  --output lesson.listenpkg \
  --machine-events
```

When `--aligner` is selected, the alignment stage is authoritative for the
`word_timeline` resource: an ASR transcript that also carries word timing does
not produce a second timeline, and an alignment failure degrades to a
subtitle-only package rather than silently falling back to ASR timing.

## Input: the exact emitted Subtitle Text Track

The aligner input is the exact tokenization emitted into the package. Every
subtitle `word` token must be matched by exactly one group of aligner words
in presentation order; non-lexical tokens (whitespace and punctuation) are
never fabricated into word timings. Aligner word text is normalized with NFKC
casefolding after stripping whitespace and leading/trailing punctuation, so a
whisper token such as `" Hello,"` matches the subtitle word token `"Hello"`.
An unmatched subtitle word token, an extra lexical aligner word, or a
non-matching word degrades the whole alignment.

## The normalized command protocol

`--aligner command` runs an external aligner as a direct argv subprocess
(never through a shell) and requires exactly one `{media}` placeholder and
exactly one `{transcript}` placeholder. `{media}` receives the normalized WAV;
`{transcript}` receives a temporary file with the exact emitted subtitle
payload:

```json
{
  "schema": "listen_gen.subtitle-input.v1",
  "language": "en-US",
  "sentences": [
    {
      "id": "sentence.<sha256>",
      "index": 0,
      "start_ms": 100,
      "end_ms": 1200,
      "original_text": "Listen, carefully!",
      "display_text": "Listen, carefully!",
      "tokens": [
        {"index": 0, "kind": "word", "text": "Listen",
         "normalized": "listen", "start_char": 0, "end_char": 6}
      ]
    }
  ]
}
```

The aligner must write exactly one `listen_gen.align-result.v1` JSON document
to stdout:

```json
{
  "schema": "listen_gen.align-result.v1",
  "provider": {"id": "command-aligner", "version": "1"},
  "model": {"id": "align-model", "version": "2026-08"},
  "config_sha256": "sha256:<64 lowercase hex>",
  "words": [
    {
      "sentence_index": 0,
      "text": "Listen",
      "start_ms": 110,
      "end_ms": 490,
      "confidence": 0.99,
      "timing_source": "forced_aligned"
    }
  ]
}
```

`words` are ordered in presentation order. `sentence_index` addresses the
subtitle sentence array; `text` is the lexical word text. `confidence` and
`timing_source` are optional (`timing_source` defaults to `forced_aligned`
and must be one of the v1 typed sources). A command aligner that genuinely
performs text-constrained forced alignment may honestly declare
`forced_aligned`; it must not label ASR-decoder token timestamps that way.
Words that do not cover every subtitle word token, that reference the wrong
sentence, or that produce non-monotonic or out-of-bounds timings fail
qualification and the package degrades.

Non-zero exit, timeout, oversized output (capped at 16 MiB), invalid JSON,
and startup failures are degradable and never fail the whole generation.

## First-class whisper.cpp alignment

`--aligner whisper-cpp` is a genuine production adapter: it reruns the local
`whisper-cli` directly (never through a shell) against the same normalized WAV
with full JSON output and derives timing from whisper.cpp's per-token offsets.

Exact argv (a translation run appends `-tr`):

```text
<resolved-whisper-cli>
-m <whisper-model-path>
-f <normalized-wav-path>
-ojf
-of <temporary-directory>/result
-l <whisper-language>
[-tr]
```

The expected artifact is `<temporary-directory>/result.json` in whisper.cpp
full JSON, read with a hard 16 MiB bound. Each transcription segment's `tokens`
array is parsed for token `text`, `offsets` (milliseconds), and probability `p`.

**Tokens are model/BPE tokens, not words.** whisper.cpp token text is not
guaranteed to be one token per subtitle word: words may be split across tokens
(`" care"` + `"fully"` for `carefully`), multi-byte non-ASCII words may arrive
in pieces, and apostrophe words may be split around the apostrophe. The adapter
therefore aggregates one-or-more consecutive lexical tokens into each exact
emitted subtitle word token:

- the grouped timing uses the first component start and the last component end;
- the grouped confidence is the deterministic minimum over the component
  confidences and is emitted only when every lexical component in the matched
  group carries one; if any component confidence is missing, the aggregated
  confidence is omitted rather than presenting a partial value as complete;
- the normalized concatenation must equal the exact subtitle word token;
- punctuation and special tokens are never fabricated into words and do not
  affect the timing range.

Any split that cannot be resolved to the exact subtitle tokenization degrades
honestly instead of guessing. Aggregation is linear and unbounded in component
count, so a single no-whitespace non-ASCII (e.g. CJK) word token produced by
the tokenizer from many whisper components is still aggregated exactly. The
timing source for these ASR-decoder token timestamps is `asr_aligned`: they
are the ASR model's own token boundaries qualified against the emitted
subtitle, **not** text-constrained forced alignment. An external command
aligner that performs genuine text-constrained forced alignment may honestly
declare `forced_aligned` in its normalized result; the whisper.cpp adapter
never claims that.

Runtime and model file bytes are hashed before the run and recomputed after
it; a mutation during alignment is a degradable `alignment_failed` failure.

## Provenance

The `word_timeline` provenance is alignment provenance, not the reused ASR
provenance:

```json
{
  "created_at_ms": 1786000000000,
  "tool": {"id": "listen-gen.alignment", "version": "0.3.0"},
  "provider": {"id": "whisper.cpp", "version": "sha256:<whisper-cli bytes>"},
  "model": {"id": "whisper.cpp:base@main", "version": "sha256:<model bytes>"},
  "config_sha256": "sha256:<alignment config identity>"
}
```

The config identity binds the provider/model byte digests, the language, the
task, the output format, the `asr_aligned` timing source, and the
normalization, token-aggregation, and confidence-aggregation choices
(`listen_gen.whisper-cpp-align-config.v1`). When the aligner used preprocessed
audio, the pipeline composes that provider config identity with the audio
stream and normalization format (`listen_gen.align-pipeline-config.v1`).
Executable paths, argv, raw provider output, secrets, temporary names, and
user/host names are never recorded.

## Degradation and warnings

Alignment failures produce a subtitle-only package and a stable typed warning
in both the ordinary JSON result and the machine `completed` event:

| code | message |
| --- | --- |
| `alignment_start_failed` | The word aligner could not be started; the subtitle package was preserved. |
| `alignment_timeout` | Word alignment timed out; the subtitle package was preserved. |
| `alignment_failed` | The word aligner failed; the subtitle package was preserved. |
| `alignment_output_invalid` | The word aligner returned an invalid result; the subtitle package was preserved. |
| `alignment_output_too_large` | The word aligner produced too much output; the subtitle package was preserved. |
| `alignment_qualification_failed` | Word alignment did not qualify; the subtitle package was preserved. |

The same codes are advertised by the machine protocol capabilities under
`alignment.warning_codes`. Cancellation (`CancellationRequested`), signals,
and media-change detection are never treated as degradation.

## Determinism

Identical input bytes, configuration, tool/model bytes, and `created_at_ms`
produce identical package bytes. Provider/model versions are byte digests and
the config identity is a canonical JSON hash, so different installation paths
with identical bytes produce identical packages. Tests for both the fixture
and the production whisper-cpp path run offline without credentials or
network.
