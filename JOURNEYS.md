# Learner Journeys

Listen may coordinate acquisition, package matching, generation, validation,
installation, and adoption internally. The Learner experiences one
material-centered journey:

```text
find or bring a material
  -> start reading, listening, or watching
  -> add a modality or help when useful
  -> keep it intentionally
  -> find its language again through the corpus
```

This document owns cross-repository journey intent. Executable code and tests
remain the authority for what a current build already supports.

## Start from local material

1. Choose or drop a supported document, audio, or video into Listen. Document
   inputs may include formats such as plain text, Markdown, HTML, EPUB, or PDF;
   typing or pasting is an optional adapter that creates a plain-text Document
   Rendition through the same intake path.
2. Open the available rendition immediately. A document may initially offer
   source-layout viewing only; when a compatible Structured Reading Resource is
   available it also offers structured reading, stable resume, and span-based
   learning capabilities. A scanned PDF remains viewable while OCR is absent,
   running, failed, or declined.
3. Resolve compatible installed or community capabilities in the background.
4. Derive missing structure or generate other learning data when useful.
5. Explicitly keep the material when it should enter the Personal Library;
   temporary preview remains possible. By default, Listen verifies a copy in
   its Managed Asset Store and leaves the original untouched; the learner may
   instead choose to reference the source asset in place.

Personal Library membership does not depend on a file's storage location.
Keeping a material, copying or moving its asset, and deleting a managed copy are
separate actions. If the Managed Asset Store is unavailable, the material stays
in the Personal Library while its local asset is reported as unavailable.
Document, audio, and video filters or Read, Listen, and Watch switches are views
over the same retained materials; they do not create separate library objects.

## Add a material capability

1. The Learner requests an experience such as Listen, Read, or synchronized
   Read-and-Listen. An absent capability is not treated as a broken Material.
2. Listen evaluates the exact current Renditions and Learning Resources and
   first resolves a compatible installed or community Learning Edition.
3. When production is needed, App sends Gen the requested capability and exact
   available inputs rather than prescribing provider steps. Gen plans the
   smallest derivation graph and reports progress, cancellation, warnings, and
   failure honestly.
4. A text-only Material may gain a TTS-derived audio Rendition plus text-to-time
   alignment. An audio- or video-only Material may gain structured reading
   content through transcription and alignment. Existing compatible text and
   media are aligned without unnecessary regeneration.
5. Qualified output arrives as a Content Package. Installation exposes
   candidate Renditions and Resources; only Learning Edition Adoption selects
   the coherent composition the Learner will use.
6. New voices, models, transcriptions, or alignments remain alternatives or
   updates. They never replace Source Renditions or erase learner-owned state
   merely because they were generated later.

## Start from community content

1. Discover a Learning Edition and see whether source assets are available,
   playable, or must be supplied separately.
2. **Start learning** resolves the source asset, validates and installs a
   compatible Package Release, adopts the edition, and retains the material as
   one explicit intent.
3. Missing optional resources degrade honestly. New releases are offered as
   updates and never silently replace the adopted edition.

## Start from a content subscription

1. Subscribe to a blog, podcast, channel, or another RSS/Atom Content Source.
2. New entries appear in the Discovery Inbox. Subscription and automatic
   download do not add every entry to the Personal Library.
3. Preview or select an interesting Discovery Item.
4. **Start learning** acquires an authorized source asset when necessary and
   retains the material.
5. Reuse a compatible community or installed Package Release first. When none
   is available, local generation can run while basic use remains available.
6. Qualified output becomes candidate Renditions and Learning Resources, and
   the chosen Learning Edition is adopted without exposing installation
   mechanics as chores.

An explicit source-level retention policy may automate selected steps later,
but remains distinct from merely subscribing.

## Continue through the personal corpus

Retained materials contribute language occurrences to the Personal Corpus. The
Learner can search a word, phrase, construction, or sound and return to the
exact material context. External services such as YouGlish may supplement
results but do not replace the Learner's corpus or become its authority.

## Experience invariants

- Learners see materials and capabilities, not manifests, blobs, dependency
  graphs, or installation plans.
- Direct document viewing or media playback begins as soon as a supported
  source asset is usable. Structured reading and Assistance Resources degrade
  independently.
- Source Renditions remain source representations; Structured Reading Resources
  and Derived Renditions never silently replace them.
- A text-only or media-only Material is valid. Capability absence becomes a
  Capability Gap only when the Learner requests that experience.
- TTS adds a Derived Media Rendition, and synchronized reading adds a separate
  alignment Base Resource; neither mutates the source document.
- Gen completes requested capabilities from exact available inputs. It does not
  force a universal multimodal end state or expose provider workflows as the
  learner journey.
- Reading positions and dependent resources use Reading Anchors in an exact
  Base Resource. Page numbers, paragraph indexes, file paths, and screen
  coordinates are locators or projections, not durable learner-state identity.
- Preview, subscription, acquisition, retention, installation, and adoption are
  distinct facts even when one action coordinates them.
- Generation is optional enrichment; failure does not make usable material
  unusable.
- Package lifecycle never owns or erases vocabulary capability, Personal
  Expressions, progress, or completed activity history.
- Downloadability, permission, redistribution rights, publisher status, review
  status, and package compatibility are separate facts.
- Language-specific experiences are capability-driven and do not assume English
  or one universal rhythm model.
