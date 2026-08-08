# Listen Ecosystem Context

> Owner-approved direction as of 2026-08-01. This document records durable
> cross-repository product boundaries and accepted invariants. It does not claim
> that every described capability is implemented.

## Product Thesis

Listen follows an Anki-like open ecosystem for listening study. `.listenpkg`
is a portable learning-resource format that users, the official project, and
community publishers can produce and exchange. `listen-gen` is open source and
lets users choose or replace providers. `listen-app` and `listen-core` provide
the trusted local consumption and learning experience.

The official project may bootstrap the ecosystem with an Official Starter
Catalog of free resources. Its contents use self-produced, public-domain,
Creative Commons, or explicitly licensed media and pass through the same public
format and validation rules as community packages.

Commercial value comes from the quality of the app, durable learning and sync
experiences, convenient hosted generation, discovery and curation, and future
institutional or licensed-content services. It does not depend on a closed
package format or a mandatory provider.

## System Roles

### listen-app

The Flutter product owns discovery and catalog presentation, local media and
package acquisition journeys, process orchestration for `listen-gen`, package
provenance and trust presentation, explicit resource selection, playback, and
the complete learner-facing experience. It presents loading, empty,
unavailable, degraded, failed, cancelled, retrying, and completed states
honestly.

The app may launch `listen-gen` as an external process through a service and
controller boundary. It owns progress, cancellation, retry, temporary-output
cleanup, and recovery UX; widgets do not launch processes directly.

The app does not own the canonical `.listenpkg` schema, generator provider or
media-processing implementation, canonical Core API behavior, or the Hosted
Catalog/Registry server.

### listen-core

Core is the trusted local consumer and learning runtime. It owns media
fingerprints and registrations, package validation, atomic and idempotent
candidate import, active-resource selection, durable learning records, and
canonical local APIs. Importing or updating a package adds candidates and does
not silently replace an existing active resource.

Realtime conversation, genuinely realtime processing, and learner-dependent
LLM capabilities remain Core responsibilities.

### listen-gen

Gen is the open offline production tool. It owns media inspection, audio
preprocessing, provider adapters, expensive batch generation, deterministic
and redacted `.listenpkg` output, and migration compatibility for older
production inputs. Its native production boundary is the versioned package,
not Core's internal timeline representation.

### Hosted Catalog/Registry

A future hosted service can own Catalog Channels and Entries, Package Listings
and immutable Releases, publisher identity, signatures, ratings, reports,
update discovery, and distribution. It is a convenience and discovery plane,
not a dependency for local import or offline learning. The server's repository,
deployment, ownership, and public API are not yet decided.

## Accepted Invariants

- `.listenpkg` is a data-only artifact. Consumers never execute code from it.
- A community package contains neither learner records nor scheduling history.
- A package excludes third-party media by default. Media and package assets are
  acquired and licensed independently.
- Users may import packages from outside the official Registry. The app
  distinguishes official, verified, community, and unsigned-local trust rather
  than treating source restriction as the safety model.
- Publisher Status, Review Status, and License Status are separate facts. None
  implies either of the others.
- Package Releases and their digests are immutable. Listings, human-readable
  tags, ratings, and curation may change.
- Installing the same release or the same resources is idempotent.
- Installing an update adds candidates and never silently changes existing
  active selections.
- Learning records outlive package replacement, package removal, and Media
  Offer availability.
- Source Identity, Content Edition, Media Rendition, and Timeline Compatibility
  are distinct. A matching source identifier alone never proves that a time
  axis is safe to use.
- Official packages use the same public generation, validation, and import
  contracts as community packages. Official publisher identity does not imply
  human review.
- Local package import and already-installed learning remain usable without a
  Hosted Catalog/Registry account or network connection.

## Discovery, Playback, and Acquisition

A source adapter is not automatically a downloader. Discovery, playback, and
media acquisition are separate capabilities with separate policy and failure
states:

- discovery finds and describes a source item;
- playback uses an allowed embedded, external, streamed, or local experience;
- acquisition obtains a local rendition only when the user and application are
  authorized to do so;
- package matching finds releases independently of whether a local rendition
  is currently available.

This separation applies especially to YouTube. A YouTube Source Identity or
catalog entry does not grant download rights, and the product architecture must
not depend on unauthorized acquisition. The discovery direction is related to
`listen-core` issue #49; its eventual app journey still requires an app-owned
phase and contract request.

## Current App Reality

The current checked-in baseline is a local-media-first Flutter app pinned to the
immutable Core release in `backend.lock.json`. Whole-media transcription is
fully cut over to the pinned `listen-gen` package journey: the app prepares a
learning transcript by generating a `.listenpkg` with the pinned `listen-gen`
release bundle and importing it through Core's content-package import — it no
longer consumes Core's whole-media transcription model/job surface
(`/v1/transcription/jobs`), and the transcription center is gone. Core's
`/v1/transcription/models` surface remains for learner recording and realtime
conversation model selection.

At R1 the media tools are shared, not repository-exclusive: `backend.lock.json`
verifies the Core runtime artifact, which bundles `whisper-cli`, `ffmpeg`, and
`ffprobe`; Core still needs `whisper-cli` for learner recording and
`ffmpeg`/`ffprobe` for the sound-line and other Core paths; the app uses
`ffmpeg`/`ffprobe` helpers of its own; and Gen declares the tool roles its
providers require while the app supplies paths only after the pinned Gen and
Core artifacts verify byte-for-byte. So none of the three tools is Gen-only at
R1, and verification claims go no further than those full-artifact SHA-256
checks.

Discovery covers two source families behind one catalog. Podcast RSS is read
and parsed in the app, and its acquisition is a direct fetch of the
publisher-provided enclosure — no external tool is involved, and the feed's own
durations and media types drive the journey. YouTube discovery reads the
per-channel Atom feed, and its acquisition still goes through an app-managed
external-tool flow on the user's own responsibility. An entry carries which
acquisition applies to it, including that none does.

Recognising media acquired in an earlier session relies on the external tool's
`[id]` filename convention, so it works only on the YouTube path. A podcast
episode downloaded in a previous session is not matched back to its feed entry;
there is no persisted acquisition record yet.

The app does not yet implement `.listenpkg` discovery or a Catalog/Registry UI,
package trust presentation, or the complete media/package compatibility
journey. Documentation and UI must not present those capabilities as available
before their contracts and code exist.

## Migration Order

1. Define the app-owned discovery, acquisition, package-match, generation,
   import, cancellation, retry, provenance, and selection journey with typed
   fixtures.
2. Send explicit requests to Core, Gen, or the future Catalog/Registry owner and
   receive canonical versioned boundaries.
3. Add and validate the new path without removing the existing whole-media
   transcription path.
4. Cut the App flow to `listen-gen` package production followed by Core package
   import, and verify fixed-fixture semantic equivalence.
5. Separate Core's whole-media production responsibilities from recording and
   realtime responsibilities, reconnect dependent workflows, and observe the
   cutover.
6. Deprecate and remove the old whole-media path only after no supported App
   release depends on it. Migrate later resource slices incrementally rather
   than deleting the legacy production tree at once.

## Synthetic Requests

When implementation must begin before a separate App agent has written the
request, the owner may authorize a simulated App request. Such a document must
be labeled **owner-approved synthetic request**, must describe every meaningful
UI and lifecycle state, and must not be represented as evidence that the App
implementation or end-to-end journey has already been validated.
