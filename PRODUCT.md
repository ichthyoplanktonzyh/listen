# Listen Product Semantics

> Status: owner-approved semantic baseline, revision 4, 2026-08-11.

This document defines what Listen is, why it exists, and the durable principles
that shape the product. It does not describe current implementation status,
repository structure, release versions, or roadmap commitments.

## Purpose

Listen helps people improve language ability through language-bearing material
they genuinely want to understand and reuse.

Its primary interaction is listening, but it also supports reading and leaves
speaking, writing, and future learning experiences open. Audio is not required:
a Learner can open a document immediately and later enrich it with speech or
other resources.

## Product statement

Listen is a multilingual, material-centered, self-directed language-learning
ecosystem. Learners can study their own documents, audio, and video immediately,
or use reusable Content Packages produced by other people. As retained
materials accumulate, Listen turns them into a searchable Personal Corpus in
which real language contexts can be rediscovered and learned repeatedly.

> Turn language content you care about into a personal corpus you can search,
> revisit, and keep learning from.

The Personal Corpus is the compounding mechanism; improved language ability is
the learner outcome.

## Product principles

### Material-centered

Learning begins with Language Materials rather than a mandatory curriculum.
Listen may offer structure and suggestions, but it does not require one course
or one sequence of activities.

### Listening-first, not listening-only

Listening is the primary emphasis. Reading is a complete entry path, and
speaking, writing, pronunciation, and other activities may build on the same
materials and resources.

### Immediate use, optional enrichment

A supported Document or Media Rendition is usable before generation.
Structured extraction, transcription, alignment, translation, explanation,
pronunciation analysis, text-to-speech, and future resources are independent
capabilities rather than admission gates.

### Documents are first-class renditions

Text is a content modality; plain text, Markdown, HTML, EPUB, and PDF are
document formats. Each supported input is preserved or bound as a Document
Rendition instead of being silently flattened into one string. Typing or
pasting text is a convenience intake adapter that creates a plain-text
Document Rendition, not a separate product category or the boundary of Listen's
document model.

Direct document viewing and structured reading are distinct capabilities. A
renderer may show an original rendition before Listen has chapter, paragraph,
language, or text-span structure. A Structured Reading Resource provides that
logical structure and stable Reading Anchors for resume, annotation, corpus,
and dependent Learning Resources. Missing or failed extraction, including OCR
for a scanned document, is reported honestly without invalidating a viewable
rendition.

### Multimodal by composition

A Material is valid with any supported set of modalities. A text-only Material
is not a broken multimodal object: it offers Read while Listen may be derivable,
generating, or unavailable. A failed enrichment attempt is reported separately
and may remain retryable. Capability presentation answers what the Learner can
do now or request next; it does not redefine Material identity or rank one
modality as universally complete.

The active learner-facing composition belongs to the Learning Material. A
producer publishes a coherent reusable composition as a Learning Edition.
Individual artifacts remain independently identified and replaceable. A richer
composition may combine a Document Rendition, audio or video Renditions,
Structured Reading and timed-text Base Resources, alignment, and Assistance
Resources without collapsing them into one monolithic resource.

Text-to-speech adds a provenance-bearing Derived Media Rendition; it does not
replace or mutate the source document. Synchronized Read-and-Listen additionally
requires an exact mapping between Reading Anchors and media-time Rendition
Locators. A translation, abridgement, or other semantic rewrite cannot silently
claim to be a faithful rendition of the same Material Revision.

### Self-directed learning

The Learner chooses how to use a material. Listen exposes capabilities and
preserves meaningful state without pretending the current set of Learning
Activities is complete.

### Multilingual core, language-aware capabilities

Materials, resources, corpus occurrences, and learning records use shared
semantics across languages. Tokenization, lexical identity, writing systems,
pronunciation, tone, stress, mora, rhythm, and morphology are language-aware
capabilities that may vary or be unavailable without breaking basic use.

### Accumulation with intent

Opening a material temporarily does not add it to the Personal Library. The
Learner explicitly retains a material before it is durably indexed and synced.
Personal Library membership is independent of file location. By default,
Listen may keep a verified device-local copy in its Managed Asset Store while
leaving the original untouched; learners may instead reference an asset in
place. Either storage choice preserves the same learner-owned material and
learning records.

### Replaceable production, reusable results

Listen Gen lets producers choose models and tools suited to their hardware,
budget, language, and privacy needs. Consumers reuse the resulting package
without needing the producer's models. The project intends an open production
ecosystem; repository licensing remains an explicit, separate decision.

Capability Completion begins with a Material Capability, not a provider
workflow. Given the exact current Renditions and Resources, Listen first reuses
a compatible installed or community result; when production is needed, Gen
derives only the missing artifacts, records provenance and compatibility, and
returns a reusable Content Package.

### Public content, private learning

Content Packages, editions, and community metadata can be public. Personal
progress, notes, saved items, and Learning Facts belong to the Learner and are
never part of a community package.

### Account-enhanced, offline-capable

An account is not required to open local material or use basic learning
capabilities. Accounts enable future synchronization, subscriptions, and
publishing. Downloaded or local material remains usable offline.

### Replaceable external providers

Model vendors, media sources, and external context providers may enrich the
experience but are never the sole authority for a core Listen concept. Their
results remain attributed and follow provider usage constraints.

### Simple journeys, deep internals

Listen may use sophisticated material identity, package, resource, acquisition,
and synchronization architecture internally, but ordinary learner journeys
remain about materials, assistance, the Personal Library, and corpus search.
Technical package concepts are progressive detail, never chores required before
learning.

## Durable learner journey

```text
import or discover material
  -> read, listen, or watch it immediately
  -> add a capability or assistance when useful
  -> retain it intentionally
  -> rediscover its contexts through the corpus
```

Acquisition, package matching, local generation, validation, installation, and
edition adoption may run behind one learner intent. Direct document viewing or
media playback starts as soon as a supported source asset is available;
structured reading starts when a compatible Structured Reading Resource is
available.

## Material entry paths

1. Open a supported document, audio, or video; use its available capabilities
   immediately; optionally enrich or retain it. Typing or pasting creates one
   plain-text Document Rendition through the same path.
2. Discover a community Learning Edition; resolve its source assets; install a
   compatible Package Release.
3. Subscribe to a Content Source such as a blog, podcast, or channel; choose a
   Discovery Item; acquire it; reuse community resources or generate missing
   enrichment in the background.

All three paths produce a Learning Material. A Content Package is a distribution
mechanism, not the product's central learning object or a prerequisite.

## Content discovery and acquisition

- A Content Subscription produces Discovery Items, not Personal Library
  membership.
- Discovery does not imply that source assets are downloadable, playable, or
  licensed for redistribution.
- Acquisition may use an authorized feed enclosure, source page, local asset
  binding, or another source-specific option.
- **Start learning** may combine acquisition, retention, Package Installation,
  and Learning Edition Adoption without exposing the technical steps.
- Listen prefers compatible community resources; local production is a fallback
  or explicit alternative, not mandatory duplicate work.
- A modality is presented as available, derivable, generating, or unavailable
  according to evidence; a failed attempt is explicit and may remain retryable.
  None is collapsed into a generic missing flag or automatic generation
  command.
- Missing enrichment degrades honestly while usable source assets remain usable.

## Corpus search

Listen uses one Corpus Occurrence model across Current Material, Personal
Corpus, and Community Corpus. Text occurrences anchor to Reading Anchors and
text spans in an exact Base Resource; they may also map to Rendition Locators.
Timed occurrences may additionally anchor to media ranges. External context
providers such as YouGlish may supplement these scopes with attributed,
ephemeral references but do not silently enter a Listen corpus.

## Content Package ecosystem

- One Language Material can have multiple Material Revisions.
- One Material Revision can have multiple Source and Derived Document or Media
  Renditions. Read, Listen, Watch, and synchronized Read-and-Listen are
  capabilities of one material rather than separate ownership objects.
- One Material Revision can have multiple Learning Editions.
- A Learning Edition is a coherent reusable composition for one or multiple
  modalities; the Learning Material owns the active learner-facing composition,
  and no single Rendition or Learning Resource represents universal
  completeness.
- One Learning Edition can have multiple immutable Package Releases.
- Base Resources can be reused across Support Languages; Assistance Resources
  may target a support language or audience.
- A package may embed resources, reference them externally, or mix both.
- Package Installation verifies and exposes candidates. Learning Edition
  Adoption is the separate Learner decision to use a coherent selection.
- Package changes never own or erase progress, Lexical Capability Profiles,
  Personal Expressions, or completed activity records.
- New releases are offered as updates and never silently replace an adopted
  release.
- Publisher Status, Review Status, and License Status remain independent.

## Personal data

Listen synchronizes durable data that the Learner cannot safely recreate:
subscriptions, library membership, progress, notes, saved items, explicit
outcomes, and meaningful Learning Facts. Public package bytes are
re-downloadable; indexes, caches, and Learning Inferences are rebuildable. Raw
media and large sensitive assets are not assumed to synchronize automatically.

## Non-goals

Listen does not currently aim to:

- prescribe a universal curriculum or mandatory learning sequence;
- require generation or a Content Package before basic learning;
- force every Material to become multimodal or treat an absent modality as a
  defect;
- enumerate every future Learning Activity;
- model every language with English-specific concepts;
- bind production to one provider or model generation;
- make a full community correction editor part of the learner application;
- copy external-provider content into the corpus without ordinary material
  intake.

## Deliberately deferred decisions

- how Learning Inferences and Training Candidates are produced;
- how mastery or overall language ability is calculated;
- the complete set of Learning Activities;
- community moderation, reputation, and business models;
- cloud implementation technology and deployment topology;
- optional synchronization of large private media and recordings.
