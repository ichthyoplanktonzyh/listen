# Listen Ecosystem Context

> Context revision: 1 — accepted by the product owner on 2026-08-01.

This is the shared product and architecture context for `listen-core`,
`listen-app`, and `listen-gen`. Each repository keeps its own roadmap and code
facts; changes to the shared decisions below require an explicit owner decision
and a coordinated context update across all three repositories.

## Product Thesis

Listen follows an Anki-like open ecosystem for media-based language learning.
An open Resource Package format carries reusable learning resources, an open
producer lets users choose their own providers, and the App plus Core provide
the trusted installation and learning experience. Commercial value comes from
the App, synchronization, hosted generation, curated discovery, and related
services rather than a closed package format or mandatory provider.

The intended learner journey is:

```text
discover content
  -> obtain playable media lawfully
  -> find a compatible Package Release
     or generate one with listen-gen
  -> validate and install candidates in Core
  -> explicitly choose resources
  -> learn while durable learner history accumulates independently
```

## Ecosystem Roles

| Role | Responsibility |
|---|---|
| `listen-app` | Discovery and library UX, lawful acquisition UX, local process orchestration, package trust/provenance presentation, resource choice, and learning interaction |
| `listen-core` | Canonical contracts, bounded package validation, idempotent candidate installation, active selection, local learning semantics, and durable learner history |
| `listen-gen` | Open offline production, replaceable provider adapters, media preprocessing, provenance, and deterministic native `.listenpkg` output |
| Hosted Catalog/Registry | Future optional discovery and distribution role for channels, listings, immutable releases, publishers, moderation, and update metadata |

The Hosted Catalog/Registry is a future fourth role. Its repository, service
ownership, protocol, and deployment have not been selected. Agents must not
silently place it inside one of the current three repositories.

## Accepted Invariants

- `.listenpkg` is a pure-data, immutable exchange artifact. It contains no
  executable code, provider plugin, media by default, learner fact, Core
  lifecycle state, credential, local path, or raw provider response.
- Media, Resource Packages, and learner records are independent assets with
  independent identity, availability, licensing, and lifecycle.
- The package format and producer path are open. Official and community
  publishers use the same contract and the same technical validation; official
  packages have no hidden format privileges.
- Users may import a technically valid package from any source. Publisher
  status, review status, and license status are separate facts and never replace
  package validation.
- A Package Release is immutable and addressed by digest. A Package Listing,
  human-readable tag, rating, moderation state, or withdrawal notice may
  change without changing the release bytes.
- Installing or updating a package only adds idempotent resource candidates.
  It never creates, replaces, or downgrades an active selection. Activation is
  an explicit Core lifecycle decision initiated through the user experience.
- The official Starter Catalog is permanently free. Where licensing permits,
  it should be browsable and downloadable without an account. It uses
  self-produced, public-domain, openly licensed, or explicitly authorized
  media, and keeps publisher identity, review status, and license status
  distinct.
- The official registry is intended as a default source, not an exclusive one.
  Direct local import and future third-party registries remain valid paths.
- Discovery, playback, and media acquisition are different capabilities.
  Source adapters must not imply download rights; acquisition is offered only
  for user-controlled or otherwise authorized media.
- Reusable expensive whole-media generation belongs in `listen-gen`.
  Learner-recording transcription, realtime conversation, and genuinely
  realtime or learner-dependent model behavior remain in Core.

## Identity And Compatibility

Community distribution requires identity to be layered rather than collapsed
into one file hash:

```text
Source Identity
  -> Content Edition
     -> Media Rendition
        -> Timeline Compatibility
           -> Package Release
```

A Source Identity identifies the external work but does not prove that two
files share the same cut or timeline. A Content Edition identifies one stable
semantic and timeline version. A Media Rendition is one concrete encoding or
audio-track realization. Timeline Compatibility must be verified before timed
resources can attach across different renditions.

Content Package v1 intentionally remains stricter: it binds to an exact media
SHA-256, with only the legacy bare-versus-prefixed SHA representation treated
as equivalent. Cross-rendition compatibility, Content Edition wire fields,
publisher signatures, and Registry protocols require later contract design and
must not be invented ad hoc by one repository.

## Trust And Updates

Every Listing or Release must keep three independent dimensions visible:

- **Publisher Status**: who published or signed it, such as official, verified
  community, ordinary community, or unsigned local.
- **Review Status**: how its learning content was checked, such as generated,
  machine checked, sample reviewed, or fully human reviewed.
- **License Status**: whether redistribution and use rights are verified,
  publisher-declared, unknown, restricted, or withdrawn.

An official publisher is not automatically human reviewed. A signature proves
publisher identity and byte integrity, not learning quality or legal rights.
When a newer release is available, the App may notify or download it, but Core
installs it as candidates and preserves the learner's current active choices.

## Current Reality And Migration

- Core owns content-package v1 validation, typed projection, atomic
  candidate-only import and explicit activation. Contract `2.1.0` retains the
  R1 removal of `/v1/transcription/jobs*` and additively projects package-native
  Prosody Analysis; immutable release `v0.7.0-split.4` is the App baseline.
- `listen-gen` commit `42649d9f` / tool `0.3.0` natively produces deterministic
  Subtitle Text Track, aligned Word Timeline, Sense Group, Word Acoustics,
  Prosody Analysis with explicit chunk spans, and optional qualified
  audio-backed Phone Timeline resources behind one verified package operation.
- App merge `1711eff5` verifies and launches that pinned Gen bundle, imports its
  `.listenpkg` through Core, and has no Core whole-media transcription job UI,
  DTO/event or call. Missing-transcript preparation has one Gen package journey.
- The real pinned three-repository gate passes through Core HTTP import and
  proves imported resources remain candidates rather than silently becoming
  active.
- At R1 `whisper-cli`, `ffmpeg` and `ffprobe` are shared verified runtime tools:
  Core still needs them for learner recording, SoundLine and other media paths,
  while App also uses the ffmpeg tools. App supplies their paths to Gen only
  after the pinned Core runtime and Gen release verify; none is Gen-only today.
- `scripts/timeline-production` and remaining legacy production overlap are R5
  retirement targets. They are neither a foundation fallback nor a second
  supported whole-media generation journey.

R4 is complete. R5 legacy retirement and the future Package Listing/Release
interface remain separate owner-directed work; neither is started by this
closeout.

## Decisions Still Open

- exact open-source and contributor licenses, including the legal grant for
  `listen-gen` and the package schemas;
- Hosted Catalog/Registry ownership, protocol, moderation, and federation;
- publisher signature and revocation formats;
- cross-rendition timeline compatibility evidence;
- hosted generation pricing, quotas, and provider settlement;
- media-specific licensing and platform compliance rules.

Agents must surface these as open decisions instead of silently choosing them.
