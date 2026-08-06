# listen-gen Machine Event Protocol v1

## Purpose

`listen-gen` normally prints one human-oriented JSON document and lets the
caller infer what happened. Supervisors such as the Listen app need a stable,
line-delimited contract instead: they have to start a generation, watch its
progress, cancel it, and verify the finished package without scraping logs.

`--machine-events` switches `listen-gen package from-media` to that contract.
Every line on stdout is one JSON object of the
`listen_gen.machine-event.v1` schema. A supervisor can parse the stream
incrementally, match each event by `sequence`, stop the pipeline with
SIGINT/SIGTERM, and trust that exactly one terminal event (`completed`,
`failed`, or `cancelled`) closes the run.

## CLI example

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

The flag is only available on `package from-media`. Without the flag,
`listen-gen` keeps its existing plain JSON stdout / stderr behavior, and no
machine event is produced.

## stdout / stderr rules

- stdout contains only NDJSON: one complete JSON object per line, followed
  immediately by `\n`, and flushed after every event.
- stdout never carries logs, progress bars, tracebacks, credentials, provider
  responses, or the final plain JSON result.
- stderr may carry internal logs, but never credentials, raw provider
  responses, or full command arguments.
- Exactly one terminal event is emitted per process run. No stdout is written
  after the terminal event.

Exit codes in machine mode: success `0`, failure `2`, cancellation `130`.

## Argument failures

When `--machine-events` is present, argument parsing itself is part of the
protocol. Missing required arguments, invalid `--provider` choices, argument
type errors, and unknown options are all reported as machine events:

```text
protocol
started
phase(validating)
failed(code=invalid_arguments)
```

The `failed` event carries the stable message
`Generation arguments are invalid.`; the raw argparse message is never written
to stdout, stderr, or the event. `argparse` usage text does not appear
anywhere in machine mode. Without `--machine-events`, the CLI keeps standard
`argparse` behavior: usage and error text on stderr, empty stdout, exit code
`2`.

## Common fields

Every event carries these fields:

```json
{
  "schema": "listen_gen.machine-event.v1",
  "protocol_version": 1,
  "sequence": 0,
  "tool": {
    "id": "listen-gen",
    "version": "0.1.0"
  },
  "event": "protocol"
}
```

`sequence` starts at 0 and increments by exactly one per event. `tool.version`
is the installed `listen-gen` package version. Events are serialized with
`ensure_ascii=False`, sorted keys, and compact separators; never pretty-print.

## Events

### protocol

The first line, always `sequence: 0`. It declares the capabilities of this
run:

```json
{
  "schema": "listen_gen.machine-event.v1",
  "protocol_version": 1,
  "sequence": 0,
  "tool": {"id": "listen-gen", "version": "0.1.0"},
  "event": "protocol",
  "capabilities": {
    "package_schema": "listen.resource-package.v1",
    "machine_protocol_version": 1,
    "events": [
      "protocol",
      "started",
      "phase",
      "completed",
      "failed",
      "cancelled"
    ],
    "phases": [
      "validating",
      "probing_media",
      "normalizing_audio",
      "transcribing",
      "building_package"
    ]
  }
}
```

### started

Emitted once, after `protocol`. It contains only the common fields plus
`"event": "started"`. It never includes input paths, output paths, provider
commands, credentials, or temporary directories.

### phase

```json
{
  "schema": "listen_gen.machine-event.v1",
  "protocol_version": 1,
  "sequence": 2,
  "tool": {"id": "listen-gen", "version": "0.1.0"},
  "event": "phase",
  "phase": "validating"
}
```

`phase` is one of the fixed names below. Machine events never carry
percentages; there is no stable progress-number protocol yet.

### completed

See [completed example](#completed-example). This is a terminal event.

### failed

```json
{
  "schema": "listen_gen.machine-event.v1",
  "protocol_version": 1,
  "sequence": 3,
  "tool": {"id": "listen-gen", "version": "0.1.0"},
  "event": "failed",
  "code": "input_not_found",
  "message": "Input media is unavailable."
}
```

`code` is a stable identifier from the error table below; `message` is a
short, stable, user-readable sentence. Messages never contain local absolute
paths, full argv, provider stdout/stderr, credentials, or tracebacks. This is
a terminal event.

### cancelled

```json
{
  "schema": "listen_gen.machine-event.v1",
  "protocol_version": 1,
  "sequence": 4,
  "tool": {"id": "listen-gen", "version": "0.1.0"},
  "event": "cancelled"
}
```

This is a terminal event emitted only after SIGINT/SIGTERM cancellation. If
`completed` or `failed` was already emitted, a later signal never produces
`cancelled`.

## Phases

Allowed `phase` values, in pipeline order:

```text
validating
probing_media
normalizing_audio
transcribing
building_package
```

`probing_media` and `normalizing_audio` appear only when the command provider
uses real media preprocessing. The offline fixture provider skips them.

## Error codes

| code | message |
| --- | --- |
| `invalid_arguments` | Generation arguments are invalid. |
| `input_not_found` | Input media is unavailable. |
| `input_changed` | Input media changed during generation. |
| `media_probe_failed` | The media audio streams could not be inspected. |
| `audio_stream_required` | An audio stream must be selected. |
| `audio_stream_not_found` | The selected audio stream is unavailable. |
| `audio_normalization_failed` | The media audio could not be prepared. |
| `provider_start_failed` | The transcription provider could not be started. |
| `provider_timeout` | The transcription provider timed out. |
| `provider_failed` | The transcription provider failed. |
| `provider_output_invalid` | The transcription provider returned an invalid result. |
| `package_validation_failed` | Generated resources did not pass package validation. |
| `package_write_failed` | The learning package could not be written. |
| `internal_error` | Generation failed because of an internal error. |

Raw exception strings are never used as `code`.

## Ordering constraints

1. `protocol` is always `sequence: 0` and the first event.
2. `started` follows `protocol`.
3. `phase` events follow `started`.
4. Terminal events (`completed`, `failed`, `cancelled`) follow `started`.
5. `protocol` and `started` each appear exactly once.
6. `sequence` increments by exactly one; no gaps, no duplicates.
7. Nothing follows the terminal event.

## Cancellation semantics

With `--machine-events`, SIGINT and SIGTERM:

1. set a cancellation flag in the run context;
2. prevent entry into any new pipeline phase;
3. terminate the provider or media-tool process started by `listen-gen`,
   killing its whole process group, not just the parent;
4. clean up temporary WAVs and temporary directories;
5. remove an unfinished output package;
6. emit exactly one `cancelled` terminal event; and
7. exit with code `130`.

If the pipeline already emitted `completed` or `failed`, a later signal does
not emit `cancelled`.

## Output commit semantics

In machine mode the pipeline never writes directly to the caller-specified
output path. It builds the package at a unique staging path in the same
directory (`. <output>.<random>.machine.tmp`), reads the package digest and
resource manifest from that staging package, and only then enters an
uninterruptible terminal commit:

1. the staging package is atomically moved to the final output with
   `os.replace()`;
2. the `completed` event is emitted immediately after.

Until that commit, the caller-specified output is never replaced: validation
failures, provider failures, SIGINT, and SIGTERM all leave a pre-existing
output byte-for-byte unchanged. A failed or cancelled run removes its staging
package. Inside the terminal commit, a late signal is recorded but does not
interrupt the move or suppress `completed`, so `completed` and `cancelled` can
never both appear for the same run.

## Completed example

```json
{
  "schema": "listen_gen.machine-event.v1",
  "protocol_version": 1,
  "sequence": 6,
  "tool": {"id": "listen-gen", "version": "0.1.0"},
  "event": "completed",
  "package_sha256": "sha256:<64 lowercase hex>",
  "media_fingerprint": "sha256:<64 lowercase hex>",
  "resources": [
    {
      "resource_id": "sha256:<64 lowercase hex>",
      "kind": "subtitle_text_track",
      "review_status": "machine_checked"
    },
    {
      "resource_id": "sha256:<64 lowercase hex>",
      "kind": "word_timeline",
      "review_status": "machine_checked"
    }
  ],
  "warnings": []
}
```

`package_sha256` is the SHA-256 of the complete, final `.listenpkg` file bytes,
lowercase hex with a `sha256:` prefix. `media_fingerprint` is the SHA-256 of
the original media file, never of the temporary normalized WAV. The
`resources` list is read from the final package manifest: same resource
`resource_id`, `kind`, and order, with `review_status` taken from each
resource document. The event never contains `output_path`, `input_path`,
`temporary_path`, `provider_command`, `provider_stdout`, `provider_stderr`,
`credential`, or `raw_response`.

## Ownership of the output path

`listen-gen` owns the output path only until `completed` is emitted. The app
must treat the `.listenpkg` named by its own invocation arguments (or recorded
out of band) as the generation result from that point on; the protocol
deliberately does not echo the output path. The app decides where the package
lives, moves or copies it as needed, and owns its lifecycle after the terminal
event.

## `package_sha256` vs Core `manifest_sha256`

These are two different digests and must not be conflated:

- `package_sha256` covers the complete archived `.listenpkg` file bytes
  (`manifest.json` plus all resource documents, ZIP framing included).
- Core's `manifest_sha256` covers only the canonical `manifest.json` document
  bytes inside the package.

Two packages can share a `manifest_sha256` while differing in resource bytes,
and two identical packages can be compared through `package_sha256`. The
machine `completed` event always reports `package_sha256`.
