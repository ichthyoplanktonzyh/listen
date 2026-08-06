# listen-gen

`listen-gen` is the heavy, replaceable production side of Listen. Its stable
output is a content package consumed by `listen-core`; model runtimes and raw
provider payloads are not part of that interface.

The production entry point transcribes media behind a provider-neutral ASR
adapter and writes native v1 `subtitle_text_track` and `word_timeline`
resources. The offline fixture provider exercises the full CLI without model
credentials or network access:

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
by `started`, fixed pipeline `phase` events, and exactly one terminal event
(`completed`, `failed`, or `cancelled`). SIGINT/SIGTERM terminate the provider
process group, clean up temporary audio, and emit `cancelled` with exit code
`130`. Ordinary mode output is unchanged when the flag is absent.

See [docs/machine-event-protocol-v1.md](docs/machine-event-protocol-v1.md) for
the full event, phase, and error-code contract.

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
