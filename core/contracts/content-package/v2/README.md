# Listen Content Package v2

Content Package v2 is the material-centered release contract that succeeds
the v1 resource package. One canonical `release.json` fixes exactly one
Learning Edition of exactly one Material Revision and names an exact set of
resources, renditions, and entrypoints. Release, resource, blob, Media
Rendition, and delivery identity are distinct and independent: no archive path
or URL participates in any of them.

V1 remains a separate, unchanged legacy contract (`../v1`). V2 never
reinterprets v1 semantics, and no v1 field is reused with a different meaning
here.

## Contract files

- `release.schema.json` — validates the canonical `release.json`.
- `resource.schema.json` — validates every resource and rendition descriptor
  embedded in `release.json`.
- `delivery.schema.json` — validates the optional canonical `delivery.json`.
- `payload/*.schema.json` — validate the typed payload blobs of the supported
  schema inventory.
- `examples/` — the three committed golden carriers, valid trees before ZIP
  assembly with honest missing-blob inventories.

Schema `$id` values are stable contract identifiers, not network locations
that an importer must fetch.

## Carrier and canonical JSON

A carrier is a safe directory tree or a deterministic ZIP (`.listenpkg`)
containing exactly:

```text
release.json              required, canonical
delivery.json             optional, canonical
blobs/sha256/<hex>        embedded payload and media blobs
```

- Any other file is rejected as undeclared.
- Media and payload bytes are never inline documents: they are always
  content-addressed blobs at `blobs/sha256/<64 lowercase hex>`.
- `release.json`, `delivery.json`, and every resource/rendition descriptor are
  identity documents and must be canonical JSON: UTF-8, no byte-order mark;
  object keys recursively sorted in ascending byte order with no duplicates;
  compact separators; integer-only numbers; no trailing newline.
- Payload blobs are not canonical JSON: they are raw-byte hashed and may use
  their resource-specific numeric types.

Deterministic ZIP profile: write `release.json` first, then `delivery.json`
when present, then blob paths in ascending UTF-8 byte order; use `STORE`
(compression method 0); set every entry timestamp to `1980-01-01T00:00:00Z`
and regular-file mode to `0644`; emit no directory entries, archive or entry
comments, extra fields, encryption, data descriptors, absolute paths,
backslashes, `.` segments, or `..` segments; preserve every input file
byte-for-byte (packaging never rewrites JSON).

## Identities

- **Release identity**: `sha256:<hex>` of the raw canonical `release.json`
  bytes. `release.json` never contains its own id; `delivery.json` binds the
  computed release id.
- **Resource identity**: `sha256:<hex>` of the canonical serialization of the
  resource descriptor only. The descriptor embeds its payload blob descriptor,
  so any payload change changes the resource identity.
- **Rendition identity**: `sha256:<hex>` of the canonical serialization of the
  rendition descriptor only.
- **Blob identity**: `sha256:<hex>` of the raw blob bytes; embedded paths are
  fixed as `blobs/sha256/<hex>`.
- **Delivery identity**: `delivery.json` is its own canonical document; it
  binds the release id and never participates in release identity.

`ReleaseResource.required` is release policy recorded on the release entry,
outside the identity-bearing descriptor: it never affects the resource
identity. It is part of `release.json`, so it is part of the release identity.

## Renditions

- A rendition fixes exactly the release's `material_revision_id`: the
  rendition descriptor `material_revision_id` must equal the release
  `material_revision_id`.
- `kind` is `audio` or `video` with a matching schema
  (`listen.rendition.audio.v1` / `listen.rendition.video.v1`) and a matching
  `media_type` prefix (`audio/` / `video/`).
- Raw media bytes are a blob and may be absent from the carrier.

## Entrypoints and empty resources

- `entrypoints` is non-empty; each entrypoint references exactly one declared
  `resource_id` or `rendition_id`.
- At least one entrypoint must reference a declared Base Resource or a Media
  Rendition.
- `resources` may be empty for a rendition-only release whose entrypoint
  references a Media Rendition.

## Resources: subject, provenance, quality, dependencies

- Every resource descriptor carries a mandatory `subject` that always binds
  the exact release `material_revision_id`; it may also bind declared
  rendition ids and anchor resource ids, and every reference is validated.
- `provenance` is mandatory and strict: it requires `created_at_ms`, a
  versioned `tool`, `input_resource_ids` naming declared in-release resource
  ids, and `extensions`; `provider`, `model`, and `config_sha256` remain
  optional.
- `quality` is mandatory with an explicit `review_status`
  (`unreviewed`, `machine_checked`, or `human_reviewed`), plus required
  `warnings` and `extensions`.
- `dependencies` are the runtime dependency DAG: they reference exact
  in-release resource ids, are unique and closed, and are acyclic. A Base
  Resource must not reach an Assistance Resource transitively.
- Provenance `input_resource_ids` are a recorded production-input ledger and
  are not runtime edges; they are independent of the runtime dependency DAG.

## Roles and languages

- Role is explicit: `base` or `assistance`.
- A Base Resource requires an explicit `content_language` and no support
  languages.
- An Assistance Resource requires at least one explicit `support_language` and
  no content language.
- The edition declares its own `target_language` and `support_languages`.
- There is no default English: every language tag is explicit and BCP47-shaped
  (`en`, `zh-Hans`, ...).

## delivery.json

`delivery.json` is optional, canonical, and binds the computed release id. It
may carry untrusted HTTPS acquisition hints keyed by blob digest; inspection
never fetches the hints, and non-HTTPS hints, credentials, local paths, and
file URLs are rejected.

The derived carrier profile is reported by inspection and must match
`delivery.json.profile` when present:

- **embedded** — every referenced blob is present in the carrier;
- **referenced** — no referenced blob is present in the carrier;
- **hybrid** — some referenced blobs are present and some are absent.

Carrier delivery never changes the release identity.

## Typed compatibility and the payload inventory

- Known payload schemas are decoded and structurally validated when embedded;
  absent known payloads are reported missing, never pretended validated.
- Unknown **required** resources make inspection typed-incompatible
  (`Incompatible`); unknown **optional** resources remain verified opaque.
- A required resource must not depend on an unknown optional resource.

The supported payload schema inventory uses v2 payload identifiers
(`listen.payload.*`). The six generated families reuse their v1 payload
shapes verbatim under v2 identifiers; the v1 `listen.resource.*` full-envelope
identifiers are never reinterpreted.

| Kind | Payload schema |
|---|---|
| `document_text` | `listen.payload.document-text.v1` |
| `timed_text_track` | `listen.payload.timed-text-track.v2` |
| `translation` | `listen.payload.translation.v1` |
| `subtitle_text_track` | `listen.payload.subtitle-text-track.v1` |
| `word_timeline` | `listen.payload.word-timeline.v1` |
| `phone_timeline` | `listen.payload.phone-timeline.v1` |
| `sense_group_analysis` | `listen.payload.sense-group-analysis.v1` |
| `word_acoustics` | `listen.payload.word-acoustics.v1` |
| `prosody_analysis` | `listen.payload.prosody-analysis.v1` |

`timed_text_track` carries per-segment BCP47 language and half-open positive
time spans. There is no package-wide media duration, fingerprint, or subtitle
requirement, and English-only prosody is not a universal package requirement.

## Committed golden examples

Release ids are `sha256:<hex>` of the raw `release.json` bytes (the committed
`delivery.json` files bind the same values).

| Example | Delivery profile | Release ID |
|---|---|---|
| `examples/text-full/` | embedded | `sha256:fc30d8eb76ff9b549294becb8e0f95e0daeafd6f114673fd4ec57925389e6122` |
| `examples/detached-media/` | hybrid | `sha256:e188fd643b969b2c1405428018af962faec18c25252ceddaa468c2d3c049b0b5` |
| `examples/hybrid-multilingual/` | hybrid | `sha256:8a8e6d71c667273ff537a95aea838a25b00621af0f7dab360a98a341ea8a835c` |

- `text-full/` embeds its single `document_text` base resource blob.
- `detached-media/` embeds its `timed_text_track` base resource blob; its audio
  rendition blob is referenced with an HTTPS hint.
- `hybrid-multilingual/` embeds its `document_text` base and `translation`
  assistance blobs; its `word_timeline` blob is referenced with an HTTPS hint.

## Deliberately excluded

The package must not contain learner state, active/candidate lifecycle
vocabulary, local paths, credentials, executable code, raw provider responses,
or job/cache/runtime state.

## Consumer interface

```text
inspect_v2_path(source) -> V2Inspection
inspect_v2_path_with_limits(source, limits) -> V2Inspection
installation_plan(&V2Inspection) -> InstallationPlan
```

Inspection performs archive safety, canonical identity verification, blob
size/hash checks, dependency/subject/entrypoint invariants, known payload
decoding and validation, opaque optional preservation, missing-blob inventory,
delivery hint validation, and delivery classification — with no network and no
persistence. The pure `InstallationPlan` reports release/edition/revision
identity, delivery profile, per-resource candidate/opaque/missing disposition,
rendition availability, and missing blobs; it never activates, selects,
persists, or adopts anything.
