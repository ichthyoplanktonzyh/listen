# listen-gen Machine Event Protocol v2

The v2 protocol is the capability-oriented exchange between Listen App and
Listen Gen, produced by `listen-gen package from-capability`. It is the supported App integration.

- Protocol schema: `listen_gen.machine-event.v2`
- Protocol version: `2`
- Request schema: `listen_gen.capability-request.v2` (version `2`)
- Package output: Content Package v3 only (`listen.content-package.release.v3`)

## Request

One request document names the media inputs and caller-owned identities of one
Generation Run. An optional `--subtitle` file supplies a separate explicit
SRT/VTT input, identified by its byte digest in the plan:

- `material`: exact Material and Material Revision identity.
- `edition`: caller-owned edition identity and language declaration.
- `requested_capability`: one of `read`, `listen`, `watch`,
  `synchronized_read_listen`.
- `available_renditions`: the exact Media Renditions available
  to the run, each with its blob digest, size, and an absolute blob path.
  Source renditions declare their Source Asset binding (`source_asset_id`) or
  media source (`media_id`, `fingerprint`).
- `available_resources` does not enable resource reuse in the current media
  producer. The run constructs its own Structured Reading from ASR or the
  declared subtitle input; it does not embed a caller's existing reading payload.
- `attempt_id`: caller-owned attempt identity (required for retry semantics;
  a retry creates a new attempt and never rewrites the old attempt's facts).
- `created_at_ms`: caller-owned creation time; Gen never takes the clock, so
  identical requests produce byte-identical packages.

Provider selection and secrets stay outside the request: the caller selects
ASR and alignment adapters with CLI flags. Document renditions are rejected;
the presence of accompanying subtitles does not make standalone text a supported
Source. When `--subtitle` is supplied, no ASR runs for the transcript: Gen hashes
the file before planning and parses the matching byte snapshot. A change between
planning and execution fails the run. The subtitle digest and assembly settings
enter the resource's `config_sha256`; neither the plan nor package records the
local subtitle path.

## Events

Strict NDJSON on stdout; every line is one event. The sequence is
`protocol`, `accepted`, `planned`, zero or more `running`/`warning`, then
exactly one terminal event.

| Event | Payload | Meaning |
| --- | --- | --- |
| `protocol` | `capabilities` | Protocol capabilities and contract identities. |
| `accepted` | `attempt_id` | The run was accepted under this attempt identity. |
| `planned` | `plan` | The planned derivation graph: `kind`, `input_rendition_ids`, `provider`, `label`, plus `subtitle_sha256` for subtitle input. |
| `running` | `stage` | A derivation or packaging stage started. |
| `warning` | `code`, `message` | Honest abstention (for example alignment unavailability); the run continues. |
| `completed` | `package_sha256`, renditions, `resources`, `warnings` | The artifact was committed. `package_sha256` is `null` when the capability was already satisfied and nothing was produced. |
| `cancelled` | — | The run stopped; owned child processes were terminated and no success artifact was left. |
| `failed` | `code`, `message` | Terminal failure; typed codes are stable and never leak raw provider output. |

Failure codes: `invalid_request`, `invalid_arguments`,
`unsupported_capability`, `abstained`, `subtitle_unavailable`,
`asr_provider_failed`, `provider_not_configured`,
`input_unavailable`, `input_changed`, `resource_invalid`,
`package_validation_failed`, `internal_error`.

## Honesty rules

- Unsupported document input is explicitly rejected before production.
- Exact anchor-to-time alignment is produced only from qualified timing
  evidence. Timing is never fabricated from text length or an assumed rate.
- Provider failures are terminal and distinguishable from abstention.
- Cancellation terminates owned child processes and leaves no success
  artifact; a retry is a new attempt and never rewrites the old attempt's
  facts.

## Derivation planning

`read` on media plans `media_to_structured_reading` (ASR plus alignment).
This text is a listening foundation, not an independent reading activity.
With `--subtitle`, the same derivation uses provider `subtitle` and its declared
digest instead of provider `asr`; subtitle timing and configured forced alignment
supply the corresponding audio mappings.
`listen` is already satisfied by an audio rendition; a video-only request is
unsupported. `watch` requires a video rendition; an audio-only request is
unsupported. Video sound plays with `watch`; extracting a separate audio
rendition is outside the current production scope.
`synchronized_read_listen` requests media transcription and exact alignment,
or subtitle-based text and alignment when `--subtitle` is supplied.
Document-to-reading and document-to-listening derivations are unavailable.

## CLI

```
listen-gen package from-capability REQUEST --output OUT \
  [--subtitle /path/to/track.srt] \
  [--provider none|fixture|command|qwen3|sensevoice|whisper-cpp] [--fixture P] ... \
  [--machine-events]
```

- The ASR flags drive media-to-read derivations with the same provider
  vocabulary (`--provider fixture` etc.) as the capability pipeline.
