# listen-gen

`listen-gen` is the heavy, replaceable production side of Listen. Its stable
output is a content package consumed by `listen-core`; model runtimes and raw
provider payloads are not part of that interface.

The production entry point transcribes media behind a provider-neutral ASR
adapter. It always writes a native v1 `subtitle_text_track` resource; a
`word_timeline` resource is generated only when the provider supplies
complete word-level timing. An optional word-alignment stage can additionally
align the emitted subtitle tokenization against the media and produce a
`word_timeline` behind the same provider-neutral seam; alignment failures
degrade honestly to the subtitle package with a stable typed warning. The
offline fixture provider exercises the full CLI without model credentials or
network access:

```bash
python -m listen_gen package from-media input.wav \
  --provider fixture --fixture normalized-asr.json \
  --title "Lesson" --media-kind audio --duration-ms 2200 \
  --created-at-ms 1785542400000 --output lesson.listenpkg
```

`normalized-asr.json` is the provider-neutral boundary: it contains timed
segments and word character spans, plus versioned provider/model provenance.
Production provider adapters can be added behind the same interface without
changing the resource package contract. Explicit creation time and media
metadata make fixture and replay builds deterministic.

For actual media, `command` first uses `ffprobe` to identify audio streams and
`ffmpeg` to create a temporary 16 kHz mono signed-16-bit PCM WAV. It then runs
the local provider wrapper as a direct argv subprocess (never through a shell).
Put the exact `{media}` placeholder in one argument; that placeholder receives
the normalized temporary WAV, not the original container. The wrapper must
write a normalized `listen_gen.asr-result.v1` document to stdout:

```bash
python -m listen_gen package from-media input.mp4 \
  --provider command --command /opt/listen/bin/whisper-wrapper \
  --command-arg transcribe --command-arg '{media}' \
  --command-arg=--model --command-arg large-v3 \
  --audio-stream-index 1 \
  --command-timeout-seconds 3600 \
  --title "Lesson" --media-kind video --duration-ms 125000 \
  --created-at-ms 1785542400000 --output lesson.listenpkg
```

A media file with exactly one audio stream is selected automatically. If it
has multiple audio streams, `--audio-stream-index` is mandatory and refers to
the container stream index reported by `ffprobe`. `--ffprobe-command`,
`--ffmpeg-command`, and `--media-command-timeout-seconds` can select managed
tool installations and set the preprocessing deadline. Temporary audio is
removed after success, provider failure, or timeout. Timeouts terminate the
subprocess group; probe output is capped at 1 MiB and normalized ASR JSON at
16 MiB.

Whisper, hosted ASR, and other provider-specific decoding belongs inside that
wrapper. Non-zero exit, timeout, startup failure, and invalid JSON errors do
not echo provider stdout/stderr, raw responses, or command arguments.
The `command` provider's normalized contract is unchanged: the wrapper must
still emit one `listen_gen.asr-result.v1` document on stdout with word timing
for every segment.

## Optional word alignment

An optional word-alignment stage runs after transcription, aligns the exact
emitted Subtitle Text Track tokenization against the media, and emits a v1
`word_timeline` with its own alignment provenance. It is selected with
`--aligner` (`none`, `fixture`, `command`, `whisper-cpp`). Alignment failure
never fails generation: it preserves the ASR subtitle package and reports a
stable typed warning in the ordinary result and the machine `completed`
event. Cancellation never degrades.

```bash
python -m listen_gen package from-media input.mp4 \
  --provider whisper-cpp \
  --whisper-cli /path/to/whisper-cli \
  --whisper-model /path/to/ggml-base.bin \
  --whisper-model-id whisper.cpp:base@main \
  --whisper-language auto \
  --aligner whisper-cpp \
  --title "Lesson" --media-kind video --duration-ms 125000 \
  --created-at-ms 1786000000000 --output lesson.listenpkg
```

See [docs/alignment-provider-v1.md](docs/alignment-provider-v1.md) for the
adapter selection, the normalized command protocol, whisper.cpp alignment,
provenance, warnings, and determinism guarantees.

## First-class whisper.cpp provider

`whisper-cpp` is a first-class provider: `listen-gen` runs a local
`whisper-cli` directly (never through a shell) against the same temporary
16 kHz mono PCM WAV used by the `command` provider, parses whisper.cpp
standard JSON (`-oj`), and emits a subtitle package because that format does
not provide word-level timing:

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

The provider runs with the exact argv
`<whisper-cli> -m <model> -f <normalized-wav> -oj -of <temporary-prefix>
-l <language>` (plus `-tr` for `--whisper-translate-to-english`). Provenance
binds the provider version to the whisper-cli file bytes, the model version
to the model file bytes, and the config identity to a canonical provider
configuration; no local paths are recorded, so identical bytes and
configuration produce identical packages across different installation paths.

Word-level timing is available as an optional separate stage: add
`--aligner whisper-cpp` and the first-class whisper.cpp aligner reruns
`whisper-cli` with full JSON output against the same normalized WAV, aggregates
the ASR decoder's per-token offsets into each exact emitted subtitle word
(typed `asr_aligned`), and emits a native v1 `word_timeline` with alignment
provenance. Alignment failures degrade honestly to the subtitle package with a
stable typed warning. See
[docs/alignment-provider-v1.md](docs/alignment-provider-v1.md).

See [docs/whisper-cpp-provider-v1.md](docs/whisper-cpp-provider-v1.md) for
the full provider contract, machine phases, error mapping, and cancellation
semantics.

## Optional rich resources

Three optional rich stages (R4) run in strict dependency order behind the same
package seam and produce the v1 `sense_group_analysis`, `word_acoustics`, and
`prosody_analysis` Analysis Resources:

1. `sense_group_analysis` is derived from the exact emitted Subtitle Text
   Track;
2. `word_acoustics` is derived from the exact Word Timeline plus the
   normalized audio window;
3. `prosody_analysis` is derived from the exact Word Timeline, the exact Word
   Acoustics resource, and optionally the exact Sense Group evidence, and
   declares explicit Prosodic Chunk token spans per the Core v1 schema.

Each stage is selected with `--sense-groups`, `--acoustics`, and `--prosody`
(`none`, `fixture`, `command`, or `baseline`). The fixture adapters replay
committed result documents offline; the command adapters run external tools
as argv-only subprocesses with the same bounded-output, timeout, and
process-group reaping rules as every other provider. The `baseline` adapters
are the built-in deterministic, credential-free producers: they run
in-process, need no model or child process, and are never selected
implicitly. A failing rich stage degrades honestly: it preserves every
already-qualified upstream resource and reports a stable typed warning. The
`acoustics` command stage receives the same temporary 16 kHz mono PCM WAV as
the ASR stage; `--acoustics baseline` expects that normalized 16 kHz mono
PCM WAV produced by the shared ffmpeg preprocessor and abstains if that
normalized audio is unusable:

```bash
listen-gen package from-media input.wav \
  --provider fixture --fixture normalized-asr.json \
  --aligner fixture --alignment-fixture alignment-result.json \
  --sense-groups baseline \
  --acoustics baseline \
  --prosody baseline \
  --title "Lesson" --media-kind audio --duration-ms 2200 \
  --created-at-ms 1786000000000 --output lesson.listenpkg
```

Phone production is optional and audio-backed. Select `--phone fixture` for
deterministic tests, `--phone command` for a normalized provider, or
`--phone wav2vec2-ctc` for the first-class local CTC sidecar. Every emitted
phone is anchored to the exact Word Timeline by temporal overlap; unusable
output abstains and preserves upstream resources. With `--phone none` Gen
emits no `phone_timeline`, and it never derives observed phones from text. See
[docs/rich-resources-v1.md](docs/rich-resources-v1.md)
for the stage contracts, normalized command protocols, qualification rules,
degradation, and determinism guarantees.

The LLTimeline command is migration compatibility only:

```bash
python -m listen_gen package from-lltimeline input.lltimeline.json \
  --output lesson.listenpkg
```

That command selects the active word, phone, and sense-group resources, converts
the known `rhythm_word_acoustic_cues` artifact, and writes a deterministic ZIP.
Local paths, Core lifecycle state, and unknown artifact payloads are excluded.
Warnings are printed in the JSON command result.

The v1 package carries generated resources, not media bytes. Its content
document retains the SHA-256 of the original media bytes (not the temporary
normalized audio), so Core can attach the package to matching local media.
Local paths and subprocess output are never included. Entries use ZIP `STORE`;
each resource identity is the SHA-256 of its exact raw JSON bytes.
Resource provenance configuration combines the provider wrapper's declared
configuration identity with a stable description of the selected audio stream,
adapter protocol, and normalization format; executable and temporary paths are
excluded. Package files are completed and synced beside the destination before
an atomic replacement, so a failed build does not truncate an existing package.

## Machine-readable generation

Add `--machine-events` to `package from-media` to switch stdout to strict
NDJSON machine events that a supervisor can start, parse, cancel, and verify
without scraping logs:

```bash
listen-gen package from-media input.mp4 \
  --provider fixture \
  --fixture tests/fixtures/asr-result.json \
  --title "Test media" \
  --media-kind video \
  --duration-ms 10000 \
  --created-at-ms 1786000000000 \
  --output /tmp/generated.listenpkg \
  --machine-events
```

Every line is one JSON object of the `listen_gen.machine-event.v1` schema with
a continuous `sequence` starting at 0. The first event is `protocol`, followed
by `started`, fixed pipeline `phase` events (an `aligning` phase appears when
an optional aligner was selected), and exactly one terminal event
(`completed`, `failed`, or `cancelled`). SIGINT/SIGTERM terminate the provider
process group, clean up temporary audio, and emit `cancelled` with exit code
`130`. Ordinary mode output is unchanged when the flag is absent. The
`completed` event carries an additive `alignment` object describing produced,
degraded, or skipped alignment with stable typed warnings, and an additive
`rich_resources` object describing the produced, degraded, or skipped rich
stages with stable typed warnings.

See [docs/machine-event-protocol-v1.md](docs/machine-event-protocol-v1.md) for
the full event, phase, and error-code contract.

## Deterministic release bundle

A deterministic, verifiable release bundle can be built from a clean
checkout:

```bash
python tools/release_bundle.py build \
  --source-commit "$(git rev-parse HEAD)" \
  --output-parent dist
```

The bundle is written to `dist/listen-gen-<version>/` and consists of a
runnable `.pyz` zipapp plus a `.release.json` manifest; both files must be
published together. Verify it before distribution:

```bash
python tools/release_bundle.py verify \
  dist/listen-gen-0.3.0/listen-gen-0.3.0.release.json
```

The `.pyz` requires Python 3.11 or newer. See
[docs/release-bundle-v1.md](docs/release-bundle-v1.md) for the full bundle
contract and distribution rules.

## Contract authority

The canonical schema is owned by `listen-core` at
`contracts/content-package/v1`. `contracts.lock.json` records that dependency.
This repository does not carry a schema copy.

## Development

```bash
python -m unittest discover -s tests -v
```

No model credentials or live services are used by these tests. To also send
the generated fixture package through Core's Rust inspector, explicitly point
the suite at a checkout:

```bash
LISTEN_CORE_CHECKOUT=/path/to/listen-core \
  python -m unittest discover -s tests -v
```
