# Compose multimodal capabilities from independent artifacts

> Status: superseded by
> [0003](0003-complete-learning-material-boundary.md), 2026-08-24. This record
> remains as history of the former partial-material/capability-completion model.

A Material Revision is valid with any supported set of modalities. Text-only,
audio-only, video-only, and mixed Materials are not different ownership objects
or quality ranks; when the Learner requests an unavailable experience, Listen
records a Capability Gap and may resolve or derive the exact Renditions and
Learning Resources needed to satisfy it. The coherent multimodal unit is a
composition: the Learning Material owns the active learner-facing selection,
while a Learning Edition offers one coherent reusable selection. Neither is one
monolithic Learning Resource.

Material Capability is a projection over the current Material Renditions and
the adopted composition, with a five-state resource availability vocabulary
(available, derivable, generating, unavailable, and failed attempt):

- **Read** is available when a usable Document Rendition or an adopted
  Structured Reading Resource exists, and derivable when media can produce
  Structured Reading through ASR.
- **Listen** is available when a usable audio Rendition exists, and derivable
  when a Document Rendition or Structured Reading can yield audio through TTS.
- **Watch** is available when a usable video Rendition exists; Phase 1 does not
  derive video from documents.
- **Synchronized Read-and-Listen** is available when an exact Structured
  Reading Resource, usable media, and a compatible Alignment Resource all
  exist, and derivable when the missing structure, audio, and alignment can be
  produced from exact inputs.

A directly viewable Document Rendition is never presented as unreadable because
Structured Reading is missing, and a failed attempt is attached to the exact
attempt that failed rather than invalidating an otherwise usable Material.

TTS output is a provenance-bearing Derived Media Rendition of the same Material
Revision only when it faithfully realizes the exact input reading content. A
separate Base Resource maps Reading Anchors to media-time Rendition Locators for
synchronized Read-and-Listen. Translation, abridgement, or other semantic
rewrites cannot silently inherit the source revision, and generated output
never replaces a Source Rendition merely because it is newer.

App requests production within Capability Completion using the exact currently
available Renditions and Resources. Gen owns the smallest derivation graph,
provider execution, qualification, provenance, and immutable Content Package
output; Core owns canonical identity, compatibility, validation, candidate
state, and Learning Edition Adoption. This seam supports text-to-TTS,
media-to-structured reading, OCR, and already-paired text/media without exposing
separate provider workflows to the Learner.

This rejects treating a single-modality Material as broken, forcing automatic
generation toward one universal notion of completeness, and bundling source,
derived modalities, alignment, assistance, and learner state into one artifact
with one lifecycle.
