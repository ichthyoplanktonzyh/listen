# Single-user Material Retention Context

## Product Phase

This Core phase is the first repository slice of Product Alpha Phase 1,
Single-user Core Loop Alpha, defined in
[`ichthyoplanktonzyh/listen`](https://github.com/ichthyoplanktonzyh/listen).
It starts from the local-material journey: a learner can open raw media and use
it immediately, then decide separately whether it belongs in the Personal
Library.

## Verified Starting Fact

The current App can play an ordinary local MP4 before subtitles or a Content
Package exist. The Core boundary nevertheless conflates two facts:

- `registerMedia` is required to attach progress and learning resources;
- `listMediaLibrary` returns every registered media item.

Consequently, opening a file also retains it. That contradicts the canonical
distinction between Temporary Material and explicit Personal Library
membership.

## First Slice

Core will make Personal Library membership explicit for the current
media-backed material path without pretending that `MediaItem` is the future
generic Language Material model.

- Media registration remains the identity/resource attachment operation.
- Registration accepts an explicit retain choice.
- Omitted retain choice preserves the published behavior for older clients.
- New clients can register a Temporary Material without retaining it.
- A separate idempotent learner intent retains or unretains an existing item.
- The media-library projection contains retained items only.
- Existing database rows migrate as retained so an upgrade never empties the
  learner's current library.
- Personal Library membership is logical Core state, not a managed filesystem
  folder. Retaining or unretaining never moves, copies, renames or deletes the
  bound source file.
- Unretaining changes membership only. Media identity, playback progress,
  subtitles, resources, vocabulary facts, Personal Expressions, attempts and
  other Learning Records remain intact.

The App follow-up uses temporary registration for ordinary open, scanning and
acquisition. Explicit **keep** copies and verifies the source in an App-owned
Managed Asset Store before re-registering the same fingerprint as retained;
the learner can instead explicitly retain a reference in place. Folder
contents never imply Personal Library membership, and retaining or unretaining
in Core still performs no file operation. That consumer work is a separate
repository handoff from this Core contract slice.

Later Phase 1 enrichment/adoption UI may compose Package Installation and
Learning Edition Adoption behind one explicit **generate and use** intent. A
second Edition chooser is required only when there are genuine alternatives or
an update decision; installation alone still never adopts or activates a
candidate.

## Compatibility

The intended HTTP change is backward-compatible and additive:

- the registration request gains an optional retain choice whose absence means
  retained;
- `MediaItem` gains nullable membership evidence;
- explicit retain/unretain operations are new;
- upgraded rows are retained, so the existing library projection remains
  stable for an old database and an old client.

This requires a contract minor version, a forward SQLite migration and an
immutable Core artifact before App adoption.

## Non-Goals

- no generic text/article persistence yet;
- no RSS/Atom subscription or hosted Catalog/Registry implementation;
- no Source Identity or Media Rendition redesign in this slice;
- no package persistence, Package Installation or Learning Edition Adoption;
- no deletion, archival or cascade policy change;
- no App UI or Flutter code in the Core PR;
- no live model, provider credential or paid inference.
