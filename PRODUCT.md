# Listen Product Semantics

> Status: owner-approved semantic baseline, revision 2, 2026-08-09.

This document defines what Listen is, why it exists, and the durable principles
that shape the product. It does not describe current implementation status,
repository structure, release versions, or roadmap commitments.

## Purpose

Listen helps people improve language ability through language-bearing material
they genuinely want to understand and reuse.

Its primary interaction is listening, but it also supports reading and leaves
speaking, writing, and future learning experiences open. Audio is not required:
a Learner can open an article immediately and later enrich it with speech or
other resources.

## Product statement

Listen is a multilingual, material-centered, self-directed language-learning
ecosystem. Learners can study their own articles, audio, and video immediately,
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

A raw article, audio file, or video is usable before generation. Transcription,
alignment, translation, explanation, pronunciation analysis, text-to-speech,
and future resources are independent enrichments rather than admission gates.

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

### Replaceable production, reusable results

Listen Gen lets producers choose models and tools suited to their hardware,
budget, language, and privacy needs. Consumers reuse the resulting package
without needing the producer's models. The project intends an open production
ecosystem; repository licensing remains an explicit, separate decision.

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
  -> use it immediately
  -> enrich it when useful
  -> retain it intentionally
  -> rediscover its contexts through the corpus
```

Acquisition, package matching, local generation, validation, installation, and
edition adoption may run behind one learner intent. Basic reading or playback
starts as soon as the required source asset is available.

## Material entry paths

1. Open raw text, audio, or video; use it immediately; optionally enrich or
   retain it.
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
- Missing enrichment degrades honestly while usable source assets remain usable.

## Corpus search

Listen uses one Corpus Occurrence model across Current Material, Personal
Corpus, and Community Corpus. Text occurrences anchor to text spans; timed
occurrences may also anchor to media ranges. External context providers such as
YouGlish may supplement these scopes with attributed, ephemeral references but
do not silently enter a Listen corpus.

## Content Package ecosystem

- One Language Material can have multiple Material Revisions.
- One Material Revision can have multiple Learning Editions.
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
