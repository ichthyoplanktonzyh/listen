# Make Complete Learning Material the formal learning boundary

> Status: accepted 2026-08-24; partially superseded by
> [0004](0004-text-learning-and-full-sound-processing.md), 2026-09-08.
> The universal audio/TTS requirement is historical; the formal learning
> boundary, evidence separation, and durable learner-history principles remain.

## Context

The previous project model treated text-only, audio-only, video-only, and mixed
materials as equally valid formal learning objects. Missing modalities or
resources appeared as Material Capability gaps that App could fill later. That
model usefully separated exact Renditions, resources, and learner state, but it
left the learning system responsible for many partial foundations and did not
express Listen's actual listening-acquisition product boundary.

The converged project model distinguishes two worlds:

```text
Raw Source -> material production -> Complete Learning Material

Complete Learning Material -> Learner-relative Learning Experience
```

The distinction also clarifies the responsibility split: material production
describes the language; the learning system decides how this Learner should
experience it.

## Decision

Formal Learning Activities consume a validated **Complete Learning Material**,
not a Raw Source or partial material composition.

The minimum contract contains:

1. Canonical Audio;
2. Canonical Text;
3. Structured Timed Text with stable text identities and exact audio/text
   alignment;
4. Sentence Translation for a declared Support Language;
5. Speech Learning Representation, with material-side Signal Facts and Speech
   Structure capable of supporting learner-relative Perceptual Guidance;
6. Source Video when the Source contains video.

Text Sources gain Canonical Audio through faithful TTS. Audio/video Sources
gain qualified Canonical Text through transcription or another verified path.
Optional grammar, semantic, pragmatic, discourse, cultural, and contextual
explanations may be added without becoming minimum validity requirements.

Source acquisition, inspection, and preview may occur before compilation, but
they remain language-world production journeys. They do not become formal
Learning Activities or acquisition evidence.

`listen-gen` compiles reusable Language Experience and records provider/model
provenance, evidence class, qualification, and compatibility. `listen-core`
validates canonical material semantics and owns Language Slices, episodes,
Personal Corpus, evidence, and learner-state projections. `listen-app` owns the
learner-facing Activity, assistance, re-entry, and Perceptual Guidance
experience.

Speech Learning Representation is a conceptual boundary over multiple
versioned resources, not a promise of one schema. Signal Facts must distinguish
observed, aligned, predicted, canonical, and estimated evidence. Semantic Sense
Groups remain distinct from Prosodic Chunks. Current Prosodic Chunks use
Prosody Analysis anchored to exact words and compatible Word Timeline playback
projection; the retired legacy Chunk Timeline is not restored.

## Consequences

- App/Core/Gen contracts and journeys must be audited against the new minimum
  material contract.
- Incomplete production becomes explicit Source/material-production state, not
  an ordinary formal-learning fallback.
- The previous Material Capability model may remain temporarily in code as
  implementation history, but it no longer defines project semantics.
- Existing Source Asset, Rendition, provenance, exact-anchor, and compatibility
  work remains useful inside material production and contract validation.
- Existing durable learner facts must survive realignment even when old material
  compositions no longer satisfy the new contract.
- Earlier Phase 1 plans based on incremental capability completion are
  historical inputs and require replacement.

## Supersession

This decision supersedes
[0002](0002-material-capabilities-and-derived-renditions.md).

It partially supersedes
[0001](0001-document-renditions-and-structured-reading.md): exact Source Asset,
Rendition, Structured Reading, anchor, provenance, and compatibility semantics
remain accepted, while direct source viewing is now a preview/production concern
rather than evidence that formal learning may begin from an incomplete material.
