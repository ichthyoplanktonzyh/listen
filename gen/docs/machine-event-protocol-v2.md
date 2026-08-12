# listen-gen Machine Event Protocol v2

The v2 protocol is the capability-oriented exchange between Listen App and
Listen Gen, produced by `listen-gen package from-capability`. Protocol v1
remains the media-package exchange until the Slice 3 cutover; v2 is the only
App integration after it.

- Protocol schema: `listen_gen.machine-event.v2`
- Protocol version: `2`
- Request schema: `listen_gen.capability-request.v2` (version `2`)
- Package output: Content Package v3 only (`listen.content-package.release.v3`)

## Request

One request document names the exact inputs of one Generation Run:

- `material`: exact Material and Material Revision identity.
- `edition`: caller-owned edition identity and language declaration.
- `requested_capability`: one of `read`, `listen`, `watch`,
  `synchronized_read_listen`.
- `available_renditions`: the exact Document and Media Renditions available
  to the run, each with its blob digest, size, and an absolute blob path.
  Source renditions declare their Source Asset binding (`source_asset_id`) or
  media source (`media_id`, `fingerprint`).
- `available_resources`: already-qualified resources of the revision; a
  compatible Structured Reading resource satisfies `read` without
  re-generation.
- `attempt_id`: caller-owned attempt identity (required for retry semantics;
  a retry creates a new attempt and never rewrites the old attempt's facts).
- `created_at_ms`: caller-owned creation time; Gen never takes the clock, so
  identical requests produce byte-identical packages.

Provider selection and secrets stay outside the request: the caller selects
the TTS, OCR, and ASR adapters with CLI flags.

## Events

Strict NDJSON on stdout; every line is one event. The sequence is
`protocol`, `accepted`, `planned`, zero or more `running`/`warning`, then
exactly one terminal event.

| Event | Payload | Meaning |
| --- | --- | --- |
| `protocol` | `capabilities` | Protocol capabilities and contract identities. |
| `accepted` | `attempt_id` | The run was accepted under this attempt identity. |
| `planned` | `plan` | The planned derivation graph: `kind`, `input_rendition_ids`, `provider`, `label`. |
| `running` | `stage` | A derivation or packaging stage started. |
| `warning` | `code`, `message` | Honest abstention (for example alignment or OCR unavailability); the run continues. |
| `completed` | `package_sha256`, renditions, `resources`, `warnings` | The artifact was committed. `package_sha256` is `null` when the capability was already satisfied and nothing was produced. |
| `cancelled` | — | The run stopped; owned child processes were terminated and no success artifact was left. |
| `failed` | `code`, `message` | Terminal failure; typed codes are stable and never leak raw provider output. |

Failure codes: `invalid_request`, `invalid_arguments`,
`unsupported_capability`, `abstained`, `document_text_unavailable`,
`tts_provider_failed`, `asr_provider_failed`, `provider_not_configured`,
`input_unavailable`, `input_changed`, `language_mismatch`,
`package_validation_failed`, `internal_error`.

## Honesty rules

- A document with no extractable text (for example a scanned PDF with no OCR
  provider) abstains; this is an honest capability result, never an import
  failure.
- Exact anchor-to-time alignment is produced only when the provider can
  produce it. The macOS `say` adapter cannot: audio succeeds and
  synchronized reading stays unavailable, reported as the
  `alignment_abstained` warning. Timing is never fabricated.
- Provider failures are terminal and distinguishable from abstention.
- Cancellation terminates owned child processes and leaves no success
  artifact; a retry is a new attempt and never rewrites the old attempt's
  facts.

## Derivation planning

`read` on a document plans `document_to_structured_reading`; on media it
plans `media_to_structured_reading` (ASR plus alignment). `listen` on a
document plans `document_to_listen` (TTS plus optional alignment); on media
the capability is already satisfied. `synchronized_read_listen` plans the
document or media derivation with exact alignment. `watch` from a
document-only Material is `unsupported_capability`.

## CLI

```
listen-gen package from-capability REQUEST --output OUT \
  [--tts-provider none|fixture|say|fake] [--tts-fixture P] \
  [--tts-alignment-fixture P] [--tts-voice V] \
  [--ocr-provider none|fixture] [--ocr-fixture P] \
  [--provider none|fixture|command|whisper-cpp] [--fixture P] ... \
  [--machine-events]
```

- `--tts-provider say` is the locally executable macOS adapter (no paid or
  live credential service); `fake` is the deterministic in-process adapter
  with exact alignment for tests; `fixture` replays committed audio.
- `--ocr-provider fixture` is the optional OCR seam for scanned PDFs.
- The ASR flags mirror the v1 media pipeline (`--provider fixture` etc.) for
  media-to-read derivations.
