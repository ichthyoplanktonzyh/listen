# Rich Resource Stages v1

## Purpose

The optional rich stages (R4) produce three additional Analysis Resources on
top of the Subtitle Text Track and Word Timeline, in strict dependency order,
behind the same `media -> machine events -> deterministic .listenpkg`
interface as the ASR and alignment stages:

1. `sense_group_analysis` is derived from the exact Subtitle Text Track that
   was emitted into the package;
2. `word_acoustics` is derived from the exact Word Timeline resource plus the
   normalized audio window that produced it;
3. `prosody_analysis` is derived from the exact Word Timeline, the exact Word
   Acoustics resource, and optionally the exact Sense Group evidence, and
   declares explicit Prosodic Chunk token spans per the Core v1 schema.

Every stage is always optional. A failing stage degrades honestly: it
preserves every already-qualified upstream resource, reports a stable typed
warning, and never fails the whole generation. Cancellation and media-change
detection are never treated as degradation.

The optional fourth stage produces an audio-backed `phone_timeline` through a
fixture, normalized command, or first-class wav2vec2 CTC adapter. Every phone
must anchor to the exact Word Timeline; unusable evidence abstains, and no
phone-level observation is ever derived from text.

## Selecting the stages

`package from-media` accepts one adapter selector per stage:

| stage | selector | fixture flag | command flags | baseline |
| --- | --- | --- | --- | --- |
| sense groups | `--sense-groups` | `--sense-groups-fixture` | `--sense-groups-command` + `--sense-groups-command-arg` + `--sense-groups-command-timeout-seconds` | `--sense-groups baseline` |
| acoustics | `--acoustics` | `--acoustics-fixture` | `--acoustics-command` + `--acoustics-command-arg` + `--acoustics-command-timeout-seconds` | `--acoustics baseline` |
| prosody | `--prosody` | `--prosody-fixture` | `--prosody-command` + `--prosody-command-arg` + `--prosody-command-timeout-seconds` | `--prosody baseline` |

Each selector accepts `none` (default), `fixture`, `command`, or `baseline`.
The fixture adapters replay committed result documents without any model,
network, or media commands, so the offline fixture path stays fully
deterministic. The command adapters run an external tool as a direct argv
subprocess (never through a shell) with the shared process-safety rules:
bounded stdout (16 MiB), positive timeouts, and process-group reaping through
the same `run_argv` behavior used by the ASR and alignment stages. The
`baseline` adapters are the built-in deterministic, credential-free producers
that ship with `listen-gen`; they run in-process, never execute a child
process or contact a model, and are never selected implicitly. See
[The built-in baseline producers](#the-built-in-baseline-producers).

The `acoustics` command stage additionally requires media preprocessing: it
receives the same temporary 16 kHz mono signed-16-bit PCM WAV as the ASR
stage, prepared with the same `--ffprobe-command`, `--ffmpeg-command`, and
`--audio-stream-index` configuration. The acoustics preprocessing never emits
duplicate machine phases; the single `measuring_acoustics` phase covers the
whole stage.

```bash
listen-gen package from-media input.mp4 \
  --provider whisper-cpp \
  --whisper-cli /path/to/whisper-cli \
  --whisper-model /path/to/ggml-base.bin \
  --whisper-model-id whisper.cpp:base@main \
  --whisper-language auto \
  --aligner whisper-cpp \
  --sense-groups command --sense-groups-command /opt/listen/sense-groups \
  --sense-groups-command-arg analyze --sense-groups-command-arg '{input}' \
  --acoustics command --acoustics-command /opt/listen/acoustics \
  --acoustics-command-arg measure --acoustics-command-arg '{media}' \
  --acoustics-command-arg '{timeline}' \
  --prosody command --prosody-command /opt/listen/prosody \
  --prosody-command-arg analyze --prosody-command-arg '{input}' \
  --title "Lesson" --media-kind video --duration-ms 125000 \
  --created-at-ms 1786000000000 --output lesson.listenpkg
```

## The built-in baseline producers

`listen-gen` ships one deterministic, credential-free baseline producer per
stage behind the exact same request / result boundaries and package operation
as the fixture and command adapters. Selecting `baseline` explicitly enables
them; they never run by default. They carry stable provider identities
(`baseline-sense-groups`, `baseline-acoustics`, `baseline-prosody`, all
version `1`) and a canonical `config_sha256` that pins the exact algorithm
configuration.

### Sense groups: `PunctuationSenseGroupBaseline`

A text-backed producer that fully partitions every emitted Subtitle token
array using clause punctuation and a length limit:

- a clause-punctuation token (`,` `;` `:` `!` `?` `.` `…` `—` `(` `)` `[`
  `]` `{` `}` quotes, and related marks) closes the current group, keeping
  the punctuation token inside it, with `punctuation` evidence;
- a segment longer than 8 tokens is split by the length limit with
  `length_limit` evidence;
- a group that ends only at the sentence boundary carries `rule` evidence.

Every group records the exact rule evidence that produced its boundary,
splits no token, and assigns the head to the first word token in the span
(when present). Because the rules are deterministic, confidence is `1.0`.

### Acoustics: `WavWordAcousticsBaseline`

An audio-backed producer that operates only on the normalized 16 kHz mono
signed-16-bit PCM WAV (the exact format the pipeline preprocessor produces;
a caller that supplies a different container, format, channel count, or
sample rate gets the degraded `acoustics_failed` outcome, never a fabricated
measurement). For every Word Timeline window it measures:

- `rms_dbfs` with the 16-bit noise floor (silence is reported at −96 dBFS,
  never `-inf`), `local_baseline_dbfs` as the sentence median RMS, and
  `delta_db` / `prominence` relative to that sentence-local baseline;
- `duration_ms` as the exact Word Timeline span and `local_ratio` relative
  to the sentence median duration.

The baseline never measures pitch or voicing, so every pitch field and
`voiced_frame_ratio` stays `null` honestly. Audio coverage is validated
against the exact Word Timeline: when the audio does not cover a word window,
the stage abstains with `acoustics_failed` and preserves upstream resources.

### Prosody: `AcousticProsodyBaseline`

An acoustic-rule producer that consumes the exact Word Timeline plus the
exact Word Acoustics and the optional Sense Group only as weak corroborating
evidence. Prosodic Chunk spans are declared from actual timing/acoustic
cues:

- a pause of at least 150 ms between consecutive word windows is a strong
  boundary;
- a pause of at least 100 ms combined with a loud-to-quiet RMS drop of at
  least 6 dB is a weak boundary;
- sentence-final chunks are always strong.

Semantic boundaries stay independent: the Sense Group never drives a
boundary decision, `uses_sense_groups` is always `false`, and a chunk whose
span happens to coincide with a sense-group span receives only a small
confidence boost (weak evidence). Anchors are chosen conservatively — one
nucleus per chunk, the loudest measured word (falling back to the longest
word only when no energy was measured) — cite only the evidence actually
present (`energy` or `duration`), and preserve `unknown` lexical stress
because stress is never measured.

## Dependency order

The pipeline runs the stages in strict dependency order:

```text
Subtitle Text Track (required)
  -> Word Timeline (optional, from ASR word timing or alignment)
  -> Sense Group Analysis (depends on Subtitle Text Track)
  -> Word Acoustics (depends on Word Timeline + normalized audio)
  -> Prosody Analysis (depends on Word Timeline + Word Acoustics
                       + optional Sense Group Analysis)
```

- Sense groups need only the Subtitle Text Track, so they are still produced
  when no Word Timeline exists.
- Acoustics and prosody require a Word Timeline. When it is missing (for
  example a whisper.cpp transcript without word timing), those stages degrade
  with a stable `*_upstream_missing` warning and preserve the subtitle (and
  any sense-group) resources.
- When acoustics degrades, prosody degrades with `prosody_upstream_missing`
  and all earlier resources are preserved.
- Each rich resource cites the exact upstream resource ids from the same
  package; a regenerated upstream resource changes its identity and therefore
  the downstream resource ids too.

## The normalized command protocols

### Sense groups

`--sense-groups command` requires exactly one `{input}` placeholder. The
analyzer receives a temporary file with the exact emitted subtitle payload
(`listen_gen.subtitle-input.v1`, the same shape used by the aligner) and must
write one `listen_gen.sense-group-result.v1` document to stdout:

```json
{
  "schema": "listen_gen.sense-group-result.v1",
  "provider": {"id": "sense-groups", "version": "1"},
  "model": {"id": "groups-model", "version": "2026-08"},
  "config_sha256": "sha256:<64 lowercase hex>",
  "groups": [
    {
      "sentence_index": 0,
      "group_index": 0,
      "start_token_index": 0,
      "end_token_index_exclusive": 2,
      "confidence": 0.9,
      "label": "left",
      "head_token_index": 0,
      "sources": ["punctuation"]
    }
  ]
}
```

For every sentence the groups must form a complete, non-overlapping ordered
partition of the token array starting at zero; `group_index` must be
contiguous from zero; the head (when present) must lie inside the span; every
`source` must be one of `dependency_parse`, `phrase_structure`,
`language_model`, `punctuation`, `length_limit`, `rule`, or `user`; and the
confidence must be in `[0, 1]`.

### Acoustics

`--acoustics command` requires exactly one `{media}` placeholder and exactly
one `{timeline}` placeholder. `{media}` receives the normalized WAV;
`{timeline}` receives a temporary file with the exact Word Timeline payload
(`listen_gen.acoustics-input.v1`). The extractor must write one
`listen_gen.acoustics-result.v1` document to stdout:

```json
{
  "schema": "listen_gen.acoustics-result.v1",
  "provider": {"id": "acoustics", "version": "1"},
  "config_sha256": "sha256:<64 lowercase hex>",
  "sample_rate_hz": 16000,
  "measurements": [
    {
      "sentence_index": 0,
      "token_index": 0,
      "energy": {"rms_dbfs": -22.0, "local_baseline_dbfs": -27.5,
                "delta_db": 5.5, "prominence": 0.8},
      "pitch": {"median_f0_hz": 182.0, "local_baseline_f0_hz": 168.0,
                "delta_semitones": 1.4, "range_semitones": 2.0,
                "prominence": 0.75, "reset_after": 0.2},
      "duration": {"duration_ms": 380, "local_ratio": 1.25},
      "voiced_frame_ratio": 0.92
    }
  ]
}
```

The measurements must exactly cover the Word Timeline: every word appears
exactly once, in presentation order, with no extras, and the measured duration
cannot exceed the exact word timing span. The scalar rules mirror the Core v1
inspector: `sample_rate_hz` positive, `median_f0_hz`/`local_baseline_f0_hz`/
`local_ratio` positive when present, `range_semitones` non-negative,
prominences and `voiced_frame_ratio` in `[0, 1]`, and all numbers finite.
`voiced_frame_ratio: null` honestly means the extractor did not measure
voicing; it is never rewritten as zero.

### Prosody

`--prosody command` requires exactly one `{input}` placeholder. The analyzer
receives a temporary file with the exact Word Timeline, Word Acoustics, and
optional Sense Group payload (`listen_gen.prosody-input.v1`) and must write
one `listen_gen.prosody-result.v1` document to stdout:

```json
{
  "schema": "listen_gen.prosody-result.v1",
  "provider": {"id": "prosody", "version": "1"},
  "config_sha256": "sha256:<64 lowercase hex>",
  "uses_sense_groups": true,
  "anchors": [
    {
      "sentence_index": 0,
      "token_index": 0,
      "lexical_stress": "primary",
      "realized_prominence": 0.8,
      "utterance_role": "nucleus",
      "evidence": ["energy", "pitch", "duration"],
      "confidence": 0.75
    }
  ],
  "chunks": [
    {
      "sentence_index": 0,
      "chunk_index": 0,
      "start_token_index": 0,
      "end_token_index_exclusive": 2,
      "nucleus_token_index": 0,
      "confidence": 0.85
    }
  ]
}
```

Qualification rules mirror the Core v1 inspector:

- every anchor must reference a word that exists in the exact Word Timeline
  and has an exact Word Acoustics measurement; `evidence` must be non-empty
  and unique and use only `energy`, `pitch`, `duration`, `lexical_stress`, or
  `context`; `lexical_stress`, `utterance_role`, `realized_prominence`, and
  `confidence` must be typed and in range;
- the `chunks` array declares explicit Prosodic Chunk token spans; chunks must
  be non-empty, ordered, non-overlapping spans within their sentence with a
  contiguous `chunk_index` from zero and a nucleus inside the span;
- `uses_sense_groups: true` declares that the analysis used the exact Sense
  Group evidence: the stage then requires a produced Sense Group Analysis
  resource and the chunk spans must exactly equal the sense-group spans, and
  the prosody resource cites that Sense Group Analysis as a dependency.
  Without `uses_sense_groups` the prosody resource depends only on the Word
  Timeline and Word Acoustics resources.

## Provenance

Each rich resource carries its own provenance with a stable tool identity,
the provider/model identities, and a canonical `config_sha256`:

```json
{
  "created_at_ms": 1786000000000,
  "tool": {"id": "listen-gen.prosody", "version": "0.4.0"},
  "provider": {"id": "prosody", "version": "1"},
  "model": {"id": "prosody-model", "version": "2026-08"},
  "config_sha256": "sha256:<provider config identity>"
}
```

When the acoustics stage used preprocessed audio, the pipeline composes the
provider config identity with the audio stream and normalization format
(`listen_gen.acoustics-pipeline-config.v1`). Every command adapter also
composes the provider-declared config with path-free digests of the resolved
executable, file/directory arguments, opaque argument values, placeholders,
and timeout, and rejects runtime mutation. Executable paths, argv values, raw
provider output, secrets, temporary names, and user/host names are never
recorded.

## Degradation and warnings

Rich-stage failures produce a stable typed warning in both the ordinary JSON
result and the machine `completed` event, and preserve every already-qualified
upstream resource:

| code | message |
| --- | --- |
| `<stage>_start_failed` | The \<Stage\> provider could not be started; already-qualified resources were preserved. |
| `<stage>_timeout` | The \<Stage\> provider timed out; already-qualified resources were preserved. |
| `<stage>_failed` | The \<Stage\> provider failed; already-qualified resources were preserved. |
| `<stage>_output_invalid` | The \<Stage\> provider returned an invalid result; already-qualified resources were preserved. |
| `<stage>_output_too_large` | The \<Stage\> provider produced too much output; already-qualified resources were preserved. |
| `<stage>_qualification_failed` | The \<Stage\> result did not qualify; already-qualified resources were preserved. |
| `<stage>_upstream_missing` | The \<Stage\> required upstream resource was not produced; already-qualified resources were preserved. |

`<stage>` is `sense_groups`, `acoustics`, or `prosody`. The same codes are
advertised by the machine protocol capabilities under
`rich_resources.<stage>.warning_codes`. Cancellation (`CancellationRequested`),
signals, and media-change detection are never treated as degradation.

## Determinism

Identical input bytes, configuration, tool/model bytes, and `created_at_ms`
produce identical package bytes. First-class provider/model versions are byte
digests where applicable; normalized command providers bind their observed
runtime/config bytes through the canonical config identity. Different
installation paths with identical bytes therefore produce identical packages.
Tests for the fixture and command paths run offline without credentials or
network.
