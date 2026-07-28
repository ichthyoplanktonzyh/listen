# Forced Alignment Research Mode

> Status: research-mode integration on `feature/forced-alignment-research`.
> It is not bundled with the app and is enabled only when the local sidecar
> environment exists.

## Overview

Whisper DTW word timestamps are derived from the model's cross-attention over
audio frames. They are useful and cheap, but they are still representational
timestamps: a token can be emitted while the model is attending to nearby
semantic context rather than the exact physical sound.

The forced-alignment research path adds an optional acoustic pass after DTW.
It uses torchaudio's MMS_FA CTC aligner to constrain the known transcript text
against the 16 kHz mono PCM WAV already created during transcription. Successful
words are stored as `timing_source = forced_aligned`; words that fail validation
keep their original DTW timing.

## Pipeline

```
transcription.rs execute_job()
  |
  +- ffmpeg extracts audio.wav (16 kHz mono PCM16)
  +- whisper-cli transcribes with -ojf and -dtw
  +- asr_timing::extract_word_timings_from_json() produces DTW word timings
  +- forced-align sidecar, if the research venv and script are present
  |    +- scripts/forced-align/align-cli.py
  |    +- torchaudio.pipelines.MMS_FA
  |    +- speech_analysis::forced_align::merge_alignments()
  +- pause_refinement, using the merged timing vector
  +- store_word_timings()
```

The sidecar is deliberately after DTW and before pause refinement. DTW provides
the baseline word mapping and a no-regression fallback; pause refinement can
then tune audible word-boundary pauses using whichever words were successfully
forced-aligned.

## Enabling

Prepare the isolated research environment:

```sh
scripts/forced-align/setup-venv.sh
```

By default the venv lives at:

```text
~/Library/Caches/LLPlayerNext/research/forced-align/venv/bin/python
```

`LLPLAYERNEXT_FA_DIR` can override the research directory. The Rust coordinator
also needs to find `scripts/forced-align/align-cli.py`; in normal development it
walks up from the current directory and executable path. `LLPLAYERNEXT_FA_SCRIPT`
can point directly at the script when running from somewhere else.

If the venv or script is missing, transcription behaves exactly as it did before:
DTW plus local pause refinement, with no user-visible error.

## Sidecar Protocol

The Rust side writes one JSON object to stdin:

```json
{
  "audio_path": "/tmp/.../audio.wav",
  "segments": [
    {
      "index": 0,
      "text": "hello world",
      "words": ["hello", "world"],
      "start_ms": 0,
      "end_ms": 2000
    }
  ]
}
```

The Python side writes one JSON object to stdout:

```json
{
  "timings": [
    {
      "segment_index": 0,
      "word_index": 0,
      "text": "hello",
      "start_ms": 120,
      "end_ms": 480,
      "score": 0.95
    }
  ]
}
```

`segment_index` maps to `SubtitleSentence.index`. `word_index` is the zero-based
position among lexical word tokens in that sentence.

## Validation And Fallback

`speech_analysis::forced_align::merge_alignments()` validates every aligned word
before replacing the DTW value:

- the aligned span must have positive duration;
- the span must remain inside the sentence window;
- the accepted spans must stay monotonic within the sentence;
- missing, unknown, or invalid aligned words keep their original timing.

This is a per-word fallback, not a per-sentence fallback. A sentence can safely
contain a mix of `asr_reported` and `forced_aligned` timings. Downstream chunk
partitioning already treats forced-aligned gaps with the stricter 180 ms
threshold.

## Known Limitations

- Requires local Python 3.11, `uv`, PyTorch, torchaudio, and model-cache access.
- The first real alignment may download MMS_FA model weights through torchaudio.
- It is currently word-level only; phone-level highlighting remains future work.
- It is not part of the app bundle and has no UI switch. Presence of the venv is
  the opt-in signal.
- The current sidecar is meant for manual research validation, not production
  distribution.

## Future Direction

If the research path consistently improves word highlighting and chunk boundary
quality, the production path should move to a distributable native runtime,
likely a Rust + ONNX Runtime style aligner or another license-cleared provider.
Python/torch should remain outside the shipped app unless a separate packaging
decision explicitly changes that constraint.
