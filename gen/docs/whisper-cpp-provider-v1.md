# whisper.cpp ASR Provider v1

## Provider CLI

`package from-media` gains a first-class `whisper-cpp` provider next to the
offline `fixture` provider and the argv-only `command` provider:

```bash
listen-gen package from-media input.mp4 \
  --provider whisper-cpp \
  --whisper-cli /path/to/whisper-cli \
  --whisper-model /path/to/ggml-base.bin \
  --whisper-model-id whisper.cpp:base@main \
  --whisper-language auto \
  --title "Lesson" \
  --media-kind video \
  --duration-ms 125000 \
  --created-at-ms 1786000000000 \
  --output lesson.listenpkg \
  --machine-events
```

Provider-specific arguments, consumed only by `whisper-cpp`:

| argument | type | default | rules |
| --- | --- | --- | --- |
| `--whisper-cli` | str | `whisper-cli` | executable path, or resolved from PATH |
| `--whisper-model` | Path | (required) | must be a regular file |
| `--whisper-model-id` | str | (required) | non-empty after trimming |
| `--whisper-language` | str | `auto` | must match the language tag pattern |
| `--whisper-translate-to-english` | store_true | false | appends `-tr` |
| `--whisper-timeout-seconds` | float | `3600.0` | must be positive |

The `fixture` and `command` providers keep their existing argument semantics
unchanged; the whisper arguments do not alter them.

## Actual whisper-cli argv

The executable is resolved as an executable path first, then through
`shutil.which()`. Each transcription runs in its own temporary directory with
output prefix `<temporary-directory>/result` and this exact argv (a
translation run appends `-tr`):

```text
<resolved-whisper-cli>
-m <whisper-model-path>
-f <normalized-wav-path>
-oj
-of <temporary-directory>/result
-l <whisper-language>
[-tr]
```

The process is launched directly as argv with `run_argv(...)` — never through
a shell — with `stdout_limit_bytes=None`, so neither stdout nor stderr enters
the protocol or the package. `-ojf`, `-dtw`, SRT output, and token dumps are
never requested. The expected artifact is `<temporary-directory>/result.json`
in whisper.cpp standard JSON.

## Input is a normalized temporary WAV

`WhisperCppAsrAdapter` sits below `PreprocessingAsrAdapter`, so it receives
the temporary 16 kHz, mono, signed-16-bit PCM WAV produced by
`FfmpegAudioPreprocessor`, never the original media container. The temporary
WAV is deleted after success, provider failure, timeout, or cancellation.

## Output: subtitle-only package

The transcript segments carry no word timing, so this PR emits exactly one
resource:

```text
subtitle_text_track
```

No empty `word_timeline` is created and the package manifest has a single
`required: true` resource entry. `package_media` rejects a transcript whose
segments mix word-bearing and word-free entries with
`ASR transcript must provide word timings for every segment or none`.

## Why no word_timeline in this PR

whisper.cpp's standard JSON output exposes segment-level text and offsets
only. Building a `word_timeline` would require estimating word boundaries
from segment text or mechanically mapping whisper tokens to package words,
which this PR deliberately does not do. Word-level alignment is a separate,
provider-specific problem and lands in a later slice.

## Provider / model / config provenance

`provider` binds to the actual resolved whisper-cli file bytes:

```json
{
  "id": "whisper.cpp",
  "version": "sha256:<whisper-cli-file-bytes-sha256>"
}
```

`model` binds to the logical `--whisper-model-id` and the model file bytes:

```json
{
  "id": "<--whisper-model-id>",
  "version": "sha256:<model-file-bytes-sha256>"
}
```

The provider configuration is a canonical-JSON document hashed into
`config_sha256`:

```json
{
  "schema": "listen_gen.whisper-cpp-config.v1",
  "provider_id": "whisper.cpp",
  "provider_version": "sha256:<runtime sha256>",
  "model_id": "<logical model id>",
  "model_version": "sha256:<model sha256>",
  "requested_language": "<language>",
  "task": "transcribe",
  "output_format": "whisper.cpp-standard-json",
  "word_timestamps": false
}
```

Translation runs use `"task": "translate_to_english"` and pin the subtitle
language to `en`. `PreprocessingAsrAdapter` then composes this provider config
identity with the selected audio stream and normalization format into the
final package provenance config identity.

Runtime and model SHA-256 digests are recorded before the provider starts and
recomputed after it finishes; a mismatch fails the run without writing a
package.

## No local paths recorded

The package, machine events, and provider configuration never contain the
executable path, model path, normalized WAV path, temporary directory, argv,
stdout, stderr, or raw whisper JSON. Provenance identities are byte digests,
which also makes output deterministic across different installation paths.

## Machine phases

`whisper-cpp` runs through the full media pipeline, so machine phase order is
fixed:

```text
validating
probing_media
normalizing_audio
transcribing
building_package
```

`WhisperCppAsrAdapter` itself never emits `transcribing`; the
`PreprocessingAsrAdapter` layer owns that phase, so it appears exactly once.

## Error-code mapping

All existing machine error codes are reused:

| condition | internal error text | machine code |
| --- | --- | --- |
| invalid model file / model id / language / timeout / empty executable | `whisper.cpp model must be a regular file`, `whisper.cpp model id must be non-empty`, `whisper.cpp language must be a valid language tag`, `whisper.cpp timeout must be positive`, `whisper.cpp executable must be non-empty` | `invalid_arguments` |
| executable unresolved, not executable, or `Popen` failure | `whisper.cpp provider could not be started` | `provider_start_failed` |
| timeout | `whisper.cpp provider timed out` | `provider_timeout` |
| non-zero exit or runtime/model changed mid-run | `whisper.cpp provider failed with exit status <code>`, `whisper.cpp provider runtime or model changed during transcription` | `provider_failed` |
| no JSON / invalid JSON / invalid shape / mixed word presence | `whisper.cpp provider produced no JSON output`, `whisper.cpp provider returned invalid JSON`, `whisper.cpp provider returned an invalid result`, `ASR transcript must provide word timings for every segment or none` | `provider_output_invalid` |

Machine events only carry the stable user-facing messages from the protocol;
the internal texts, raw JSON, stdout, stderr, argv, and paths never appear.

## Cancellation and temporary-file cleanup

Cancellation reuses the existing `run_argv()` process-group semantics. A
SIGINT/SIGTERM during a whisper run terminates whisper-cli and its children
as a group, deletes the whisper temporary directory, deletes the normalized
audio temporary directory, removes the machine staging package, and leaves a
pre-existing final output untouched. The run then emits exactly one
`cancelled` terminal event and exits `130`.

## Future work

Word-level alignment remains deferred until the immutable Gen handoff and
the three-repository exact-media round trip have been completed and observed.
A later provider slice may add DTW, WhisperX, MFA, or another aligner without
changing the subtitle-only contract of this provider version.
