# listen-gen Machine Event Protocol v2

The v2 protocol is the capability-oriented exchange between Listen App and
Listen Gen, produced by `listen-gen package from-capability`. It is the supported App integration.

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
- `available_renditions`: the exact Media Renditions available
  to the run, each with its blob digest, size, and an absolute blob path.
  Source renditions declare their Source Asset binding (`source_asset_id`) or
  media source (`media_id`, `fingerprint`).
- `available_resources`: already-qualified resources of the revision. A
  Structured Reading resource is reusable only when it is a base resource
  whose declared language and Material Revision both match the request; a
  resource that is unknown, stale, or language-incompatible never suppresses
  generation. Reuse embeds the reading's payload in the new package (the
  package stays self-contained) and skips re-extraction.
- `attempt_id`: caller-owned attempt identity (required for retry semantics;
  a retry creates a new attempt and never rewrites the old attempt's facts).
- `created_at_ms`: caller-owned creation time; Gen never takes the clock, so
  identical requests produce byte-identical packages.

Provider selection and secrets stay outside the request: the caller selects
ASR and alignment adapters with CLI flags. Document renditions are rejected;
the presence of accompanying text does not make a document a supported Source.

## Events

Strict NDJSON on stdout; every line is one event. The sequence is
`protocol`, `accepted`, `planned`, zero or more `running`/`warning`, then
exactly one terminal event.

| Event | Payload | Meaning |
| --- | --- | --- |
| `protocol` | `capabilities` | Protocol capabilities and contract identities. |
| `accepted` | `attempt_id` | The run was accepted under this attempt identity. |
| `planned` | `plan` | The planned derivation graph: `kind`, `input_rendition_ids`, `input_resource_ids`, `provider`, `label`. |
| `running` | `stage` | A derivation or packaging stage started. |
| `warning` | `code`, `message` | Honest abstention (for example alignment unavailability); the run continues. |
| `completed` | `package_sha256`, renditions, `resources`, `warnings` | The artifact was committed. `package_sha256` is `null` when the capability was already satisfied and nothing was produced. |
| `cancelled` | — | The run stopped; owned child processes were terminated and no success artifact was left. |
| `failed` | `code`, `message` | Terminal failure; typed codes are stable and never leak raw provider output. |

Failure codes: `invalid_request`, `invalid_arguments`,
`unsupported_capability`, `abstained`, `asr_provider_failed`, `provider_not_configured`,
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
`listen` is already satisfied by the source media.
`synchronized_read_listen` requests media transcription and exact alignment.
Document-to-reading and document-to-listening derivations are unavailable.

## CLI

```
listen-gen package from-capability REQUEST --output OUT \
  [--provider none|fixture|command|qwen3|sensevoice|whisper-cpp] [--fixture P] ... \
  [--machine-events]
```

- The ASR flags drive media-to-read derivations with the same provider
  vocabulary (`--provider fixture` etc.) as the capability pipeline.
