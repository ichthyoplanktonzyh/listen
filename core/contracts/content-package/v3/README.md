# Listen Content Package v3

Content Package v3 is the Phase 1 canonical release contract. One canonical
`release.json` fixes exactly one Learning Edition of exactly one Material
Revision and names an exact set of Document and Media Renditions and
Learning Resources. Release, resource, rendition, and blob identity are
distinct and independent: no archive path or URL participates in any of them.

V1 and v2 remain separate, unchanged historical contracts (`../v1`,
`../v2`). V3 never reinterprets their semantics, and no older field is reused
with a different meaning here.

## Contract files

- `release.schema.json` — validates the canonical `release.json`.
- `resource.schema.json` — validates every resource and rendition descriptor
  embedded in `release.json`.
- `definitions.schema.json` — shareable definitions (blob, producer,
  provenance, quality, compatibility, edition, material) referenced by the
  release and resource schemas.
- `payload/structured-reading.v1.schema.json` — the v3 Structured Reading
  payload schema.
- `payload/anchor-time-alignment.v1.schema.json` — the v3 anchor-to-time
  alignment payload schema.
- `tests/negative-schemas.json` — documents that must fail schema validation
  or the typed semantic checks.
- `examples/` — the three committed golden carriers: `document-source`,
  `media-only`, and `composed`.

The shared v2 payload families used by v3 (timed text track, translation,
and the six generated resource families) keep their v2 schemas under
`../v2/payload/`. **There is no `document_text` resource in the v3 active
path**: raw document bytes live on the Document Rendition's `text_blob`, and
exact logical reading content lives in a Structured Reading payload. The
dual `document_text` + `structured_reading` model is rejected.

Schema `$id` values are stable contract identifiers, not network locations
that an importer must fetch.

## Carrier and canonical JSON

A carrier is a safe directory tree or a deterministic ZIP (`.listenpkg`)
containing exactly:

```text
release.json              required, canonical
blobs/sha256/<hex>        embedded payload, rendition, and media blobs
```

- Any other file is rejected as undeclared.
- There is no `delivery.json` in v3: every blob is explicitly declared either
  `embedded` (must be present in the carrier) or `referenced` (may be absent
  and acquired later). A missing embedded blob makes the carrier invalid;
  missing referenced blobs are honest availability facts.
- Media, rendition, and payload bytes are never inline documents: they are
  always content-addressed blobs at `blobs/sha256/<64 lowercase hex>`.
- `release.json` and every resource/rendition descriptor are identity
  documents and must be canonical JSON: UTF-8, no byte-order mark; object
  keys recursively sorted in ascending byte order with no duplicates; compact
  separators; integer-only numbers; no trailing newline.
- Payload blobs are not canonical JSON: they are raw-byte hashed and may use
  their resource-specific numeric types.

Deterministic ZIP profile: write `release.json` first, then blob paths in
ascending UTF-8 byte order; use `STORE` (compression method 0); set every
entry timestamp to `1980-01-01T00:00:00Z` and regular-file mode to `0644`;
emit no directory entries, archive or entry comments, extra fields,
encryption, data descriptors, absolute paths, backslashes, `.` segments, or
`..` segments; preserve every input file byte-for-byte (packaging never
rewrites JSON).

## Identities

- **Release identity**: `sha256:<hex>` of the raw canonical `release.json`
  bytes. `release.json` never contains its own id.
- **Resource identity**: `sha256:<hex>` of the canonical serialization of the
  resource descriptor only. The descriptor embeds its payload blob
  descriptor, so any payload change changes the resource identity.
- **Rendition identity**: `sha256:<hex>` of the canonical serialization of
  the rendition descriptor's identity fields only (`{media_type, language,
  text_blob}` for a Document Rendition; `{kind, media_type, media_blob,
  media_id, fingerprint}` for a Media Rendition). Origin, producer, and
  compatibility facts do not participate in identity.
- **Blob identity**: `sha256:<hex>` of the raw blob bytes; embedded paths are
  fixed as `blobs/sha256/<hex>`.

`ReleaseResource.required` is release policy recorded on the release entry,
outside the identity-bearing descriptor: it never affects the resource
identity. It is part of `release.json`, so it is part of the release identity.

## Renditions

- A Source Rendition realizes the Learner-authorized original bytes and must
  bind an exact Source Asset: a Source Document Rendition binds
  `source_asset_id`; a Source Media Rendition binds `media_id`. A rendition
  must never fabricate or fake a Source Asset identity.
- A Derived Rendition records strict producer facts (`created_at_ms`, versioned
  `tool`, optional `provider`/`model` with versions, optional `config_sha256`)
  and compatibility evidence (`verified_inputs` naming exact declared
  renditions/resources and the satisfied checks). Derived renditions never
  replace a Source Rendition merely because they are newer.
- `kind` is `audio` or `video` with a matching `media_type` prefix
  (`audio/` / `video/`).
- Document Rendition bytes are the exact source representation (plain text,
  Markdown, HTML, EPUB, or PDF); they are not an extraction result.

## Resources: subject, provenance, quality, dependencies

- Every resource descriptor carries a mandatory `subject` that always binds
  the exact release `material_revision_id`; it may also bind declared
  rendition ids and anchor resource ids, and every reference is validated.
- `provenance` is mandatory and strict (v3 shape): `created_at_ms`, a
  versioned `tool`, optional `provider` and `model` with versions, optional
  `config_sha256`, and the exact production inputs — `input_rendition_ids`
  naming declared in-release rendition ids and `input_resource_ids` naming
  declared in-release resource ids. Every input is unique and validated;
  inputs are a production-lineage ledger, independent of the runtime
  dependency DAG.
- `quality` is mandatory with an explicit `review_status`
  (`unreviewed`, `machine_checked`, or `human_reviewed`), plus required
  `warnings` and `extensions`.
- `dependencies` are the runtime dependency DAG: they reference exact
  in-release resource ids, are unique and closed, and are acyclic. A Base
  Resource must not reach an Assistance Resource transitively.

## Structured Reading

`structured_reading` v1 is a self-contained, format-neutral Base Resource:

- `text` is the exact UTF-8 logical reading text. It is the single source of
  truth for every anchor range in the payload.
- `anchors` are stable identities for logical blocks or spans. Each anchor is
  a half-open byte range `[start_offset, end_offset)` into the exact `text`
  bytes: ranges must stay within the text byte length, land on UTF-8
  character boundaries, and appear in monotonic byte order.
- `blocks` form one deterministic hierarchy: exactly one `root` block with no
  parent, a typed `kind` (`root`, `book`, `chapter`, `section`, `heading`,
  `paragraph`), valid parent references, and contiguous 0-based `order` within
  each parent. `span_anchor_ids` reference exact anchors.
- `spans` reference exact anchors and may nest under a parent anchor; spans
  never duplicate the text they anchor.
- `document_mappings` point at exact declared Document Renditions
  (`rendition_id`) with a format-related `locator`
  (`epub_itemref`, `pdf_page`, `character_range`, or `fragment`).
- A Reading Anchor is stable only inside the exact Resource identity; the
  schema never promises cross-resource anchor stability.

Document and media paths converge here: document bytes go through
parser/OCR to Structured Reading, media bytes go through ASR to Structured
Reading. Semantic production (TTS, translation, explanation) consumes
Structured Reading — never raw PDF/EPUB bytes — and Markdown is not a
uniform intermediate format. A producer that prefers Markdown derives a
temporary `Production Input Projection` from Structured Reading; such a
projection is not a Rendition, Resource, or authoritative storage.

## Anchor-to-time alignment

`anchor_time_alignment` v1 is a Base Resource mapping exact Reading Anchors
of one declared `structured_reading` resource to exact media-time positions
of one declared Media Rendition. Entries are unique, anchors are verified
against the embedded anchor resource when present, and media times are
non-decreasing. A derived alignment never fabricates time: entries are exact
or absent.

## Roles, languages, and translation

- Role is explicit: `base` or `assistance`.
- A Base Resource requires an explicit `content_language` and no support
  languages. An Assistance Resource requires at least one explicit
  `support_language` and no content language.
- The edition declares its own `target_language` and `support_languages`.
- There is no default English: every language tag is explicit and BCP47-shaped
  (`en`, `zh-Hans`, ...).
- `translation` is an Assistance Resource anchored to an exact Base Resource.
  In the v3 active path its base must be a `structured_reading` resource and
  each `source_segment_id` must reference one of its sentence anchors.
  Phase 1 does not add a translation provider.

## Committed golden examples

Release ids are `sha256:<hex>` of the raw `release.json` bytes.

| Example | Shape | Release ID |
|---|---|---|
| `examples/document-source/` | one source Document Rendition + embedded structured reading | `sha256:beea001336240bb939795e4906f5df591ddc03efda5f3589972b9e0b58b2c153` |
| `examples/media-only/` | source + derived Media Renditions (referenced/embedded mix) + derived structured reading + alignment | `sha256:6d13f14dba8bf7226fdc9d600d1293c22bbd7450e07f518813a85d84124dbf3d` |
| `examples/composed/` | source + derived Document Renditions, source + derived Media Renditions, structured reading, alignment, translation | `sha256:c7982855e6394edeb5cfcd0d3364661012df6df3c6d116f47ace0d59a3cd1a51` |

- `document-source/` proves direct-viewable raw bytes plus exact logical
  reading content.
- `media-only/` proves the media path converging on Structured Reading with
  an anchor-to-time alignment; its source media blob is referenced and
  honestly reported missing from the carrier.
- `composed/` proves the composed material: a document mapping with a
  `character_range` locator, a translation anchored to Structured Reading
  sentence anchors, and mixed embedded/referenced blobs.

## Deliberately excluded

The package must not contain learner state, active/candidate lifecycle
vocabulary, local paths, credentials, executable code, raw provider
responses, or job/cache/runtime state. `Production Input Projection`
documents never appear in a release.

## Consumer interface

```text
inspect_v3_path(source) -> V3Inspection
inspect_v3_path_with_limits(source, limits) -> V3Inspection
installation_plan_v3(&V3Inspection) -> V3InstallationPlan
```

Inspection performs archive safety, canonical identity verification, blob
size/hash checks, dependency/subject/provenance/anchors/locator invariants,
known payload decoding and validation, opaque optional preservation,
missing-blob inventory, and release-schema dispatch — with no network and no
persistence. The pure `V3InstallationPlan` reports release/edition/revision
identity, per-resource candidate/opaque/missing disposition, rendition
availability, and missing blobs; it never activates, selects, persists, or
adopts anything.
