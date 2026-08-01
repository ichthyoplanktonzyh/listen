# Listen Resource Package v1

This directory defines the first portable exchange contract between a heavy,
offline resource producer such as `listen-gen` and a bounded consumer runtime
such as `listen-core`.

The contract describes reusable knowledge about a Content Document. It does
not serialize a core database, choose an active analysis, or contain learner
history.

## Contract files

- `manifest.schema.json` validates the package manifest.
- `resource.schema.json` validates every resource kind known to v1.
- `examples/minimal/` is a complete package tree before ZIP assembly. It
  includes the required Subtitle Text Track and all five optional Analysis
  Resource kinds.

Schema identifiers are stable contract identifiers, not network locations that
an importer must fetch.

## Package layout

A package is a ZIP archive with the `.listenpkg` suffix. Its root contains
exactly one `manifest.json`. Every other regular file must be listed once in
`manifest.resources`.

```text
example.listenpkg
├── manifest.json
└── resources
    ├── phone-timeline.json
    ├── prosody-analysis.json
    ├── sense-group-analysis.json
    ├── subtitle-text-track.json
    ├── word-acoustics.json
    └── word-timeline.json
```

Media bytes are not part of v1. `content_document.media_fingerprint` binds the
package to the media bytes known to the producer. A consumer may attach the
package to matching local media or retain the Content Document as unavailable.

## Deterministic ZIP profile

For an identical `manifest.json` and identical resource bytes, a conforming
packer must produce identical archive bytes:

1. Write `manifest.json` first, followed by resource paths in ascending UTF-8
   byte order.
2. Use ZIP `STORE` (compression method 0).
3. Set every entry timestamp to `1980-01-01T00:00:00Z` and regular-file mode to
   `0644`.
4. Emit no directory entries, archive comment, entry comment, extra field,
   encryption, data descriptor, absolute path, backslash, `.` segment, or `..`
   segment.
5. Preserve each input file byte-for-byte; packaging must not rewrite JSON.

JSON files are UTF-8 without a byte-order mark. Producers should use a stable
serializer and LF line endings because insignificant JSON formatting still
changes the resource identity.

## Resource identity and dependencies

A resource identity is exactly:

```text
sha256:<lowercase SHA-256 of the complete raw resource file bytes>
```

The resource file does not contain its own identity, avoiding a circular hash.
The manifest supplies `resource_id`; dependencies inside an envelope refer to
the same strong identity. Resource filenames have no identity semantics.

All dependencies must resolve to resources in the same v1 package. The graph
must be acyclic. A dependency's `kind` must equal the referenced manifest
entry's `kind`. An importer must verify `size_bytes` before hashing, then verify
raw-byte hashes, graph closure, kind agreement, and acyclicity before importing
anything.

The common resource envelope is:

```json
{
  "schema": "listen.resource.word-timeline.v1",
  "kind": "word_timeline",
  "subject": {
    "media_fingerprint": "sha256:..."
  },
  "dependencies": [
    { "resource_id": "sha256:...", "kind": "subtitle_text_track" }
  ],
  "provenance": {},
  "quality": {},
  "payload": {}
}
```

Every resource subject must equal the manifest's media fingerprint. Provenance
belongs to the individual generated resource because pipeline stages may use
different tools, providers, models, and configurations.

## v1 resource kinds

| Kind | Schema | Required | Direct dependency |
|---|---|---:|---|
| `subtitle_text_track` | `listen.resource.subtitle-text-track.v1` | yes | none |
| `word_timeline` | `listen.resource.word-timeline.v1` | no | one Subtitle Text Track |
| `phone_timeline` | `listen.resource.phone-timeline.v1` | no | one Word Timeline |
| `sense_group_analysis` | `listen.resource.sense-group-analysis.v1` | no | one Subtitle Text Track |
| `word_acoustics` | `listen.resource.word-acoustics.v1` | no | one Word Timeline |
| `prosody_analysis` | `listen.resource.prosody-analysis.v1` | no | one Word Timeline and one Word Acoustics resource; a Sense Group dependency is optional |

The manifest may contain more than one resource of a known kind, but it must
contain at least one required Subtitle Text Track. Every Analysis Resource is
optional so unsupported languages and partial generation failures can still
produce a useful package. Core chooses candidates after import; the package
never declares an active version.

`subtitle_text_track` is the timed, language-bearing document component. An
ASR transcript is represented by this kind with `payload.source_kind = "asr"`.
The other five kinds are replaceable Analysis Resources.

`word_acoustics` exchanges measurable observations with units and explicit
local baselines. `prosody_analysis` exchanges the higher-level interpretation
derived from those observations. This keeps energy, pitch, and duration
measurements distinct from claims such as realized prominence or nucleus.
`voiced_frame_ratio: null` means the extractor did not measure voicing; it must
not be rewritten as zero, and it does not invalidate the measurement's other
available energy, pitch, or duration observations.

## Anchors and ranges

- All media times are non-negative integer milliseconds.
- Every time interval is half-open: `[start_ms, end_ms)` with
  `start_ms < end_ms`.
- Character and token spans are also half-open.
- Sentence indexes and token indexes start at zero and are contiguous within
  their owning arrays.
- A `token_index` addresses the complete Subtitle Text Track token array,
  including whitespace and punctuation tokens.
- Word references must identify `word` tokens in the depended-on Subtitle Text
  Track.
- A Sense Group must be non-empty and contained in one sentence.
- Timeline entries must remain within their sentence and media duration and
  must be monotonic in presentation order.
- Every confidence and prominence score is in the inclusive range `[0, 1]`.

JSON Schema validates structural and scalar constraints. Importers must also
enforce the cross-resource, ordering, equality, graph, and range invariants
above.

## Required and optional compatibility

The manifest deliberately permits future `kind` and `schema` strings:

- an unknown entry with `required: true` makes the package incompatible and
  must reject the whole import;
- an unknown entry with `required: false` must retain its bytes and manifest
  metadata when the package is preserved, but the consumer need not interpret
  or import its payload;
- a known kind with an unsupported schema version follows the same rule.

Even for an unknown optional resource, the importer still verifies the entry
path, raw-byte identity, common envelope fields, subject, and closed dependency
references. It treats the payload as opaque. Known v1 resources must validate
against `resource.schema.json` without unknown properties.

## Consumer interface

The package is intended to sit behind a small import module interface:

```text
inspect_package(source) -> PackageInspection
import_package(source, policy) -> ImportReceipt
```

Inspection performs archive safety, schema, hash, graph, anchor, subject, and
compatibility checks without persistence. Import repeats verification and then
commits the Content Document component and Analysis Resources atomically and
idempotently. Package-local hashes are mapped to core-local identities inside
the module. Existing domain-specific read interfaces remain the consumption
surface.

The module hides ZIP parsing, limits, hashing, dependency ordering, compatibility
negotiation, local identity mapping, candidate selection, transactions,
rollback, and reindexing. These concerns are not part of the exchange format.

## Producer flow

A producer typically performs:

```text
media
  -> ASR Subtitle Text Track
  -> Word Timeline
  -> Phone Timeline
  -> Sense Group Analysis
  -> optional Word Acoustics
  -> optional Prosody Analysis
  -> validate
  -> deterministic .listenpkg
```

Each stage writes a new immutable resource and cites exact upstream hashes.
Regenerating a transcript therefore gives it a new identity and prevents stale
downstream analyses from silently attaching to it.

## Deliberately excluded

The package must not contain:

- local filesystem paths, core database IDs, repository row IDs, or runtime
  installation state;
- `active`, `candidate`, `archived`, lifecycle, job, progress, retry, or cache
  state;
- learner attempts, playback progress, recordings, reviews, schedules,
  capability, corrections, decisions, conversations, or other learner facts;
- credentials, provider profiles, model binaries, raw provider responses,
  hidden states, logits, embeddings, debug logs, or temporary intermediates;
- arbitrary untyped artifact payloads masquerading as known resources.

The Core may derive cheap display projections from imported resources and may
run learner-dependent or realtime intelligence. Those results do not alter the
immutable package.

## LLTimeline migration

LLTimeline remains a legacy interchange input during migration. A compatibility
adapter may map:

- `segments` to `subtitle_text_track`;
- versioned word, phone, and Sense Group records to their v1 resource kinds;
- existing inclusive Sense Group end indexes to
  `end_token_index_exclusive = end_token_index + 1`.

Local media/track IDs, paths, lifecycle state, active selection, timestamps used
only by persistence, and arbitrary `artifact.payload` values are not copied.
Lossy or unsupported fields must produce explicit conversion warnings. New
producers should emit this package contract directly.
