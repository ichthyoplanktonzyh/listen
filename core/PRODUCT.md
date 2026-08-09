# Listen Product Semantics

> Status: owner-approved semantic baseline, revision 1, 2026-08-09.

This document defines what Listen is, why it exists, and the durable principles
that shape the product. It deliberately does not describe current implementation
status, repository structure, release versions, or roadmap commitments.

## Purpose

Listen helps people improve language ability through language-bearing material
they genuinely want to understand and reuse.

Its primary interaction is listening, but it also supports reading and leaves
speaking, writing, and future learning experiences open. Audio is not required:
a Learner can open an article immediately, and later enrich it with speech or
other resources.

## Product Statement

Listen is a multilingual, material-centered, self-directed language-learning
ecosystem. Learners can study their own articles, audio, and video immediately,
or use reusable Content Packages produced by the community. As retained
materials accumulate, Listen turns them into a searchable Personal Corpus in
which real language contexts can be rediscovered and learned repeatedly.

A concise learner-facing promise is:

> Turn language content you care about into a personal corpus you can search,
> revisit, and keep learning from.

The Personal Corpus is the compounding mechanism; improved language ability is
the learner outcome.

## Product Principles

### Material-Centered

Learning begins with Language Materials rather than a mandatory curriculum.
Listen may offer structure and suggestions, but it does not require one course
or one sequence of activities.

### Listening-First, Not Listening-Only

Listening is the primary product emphasis. Reading is a complete entry path,
and speaking, writing, pronunciation, and other activities may build on the
same materials and resources.

### Immediate Use, Optional Enrichment

A raw article, audio file, or video is usable before generation. Transcription,
alignment, translation, explanation, pronunciation analysis, text-to-speech,
and future resources are independent enrichments rather than admission gates.

### Self-Directed Learning

The Learner chooses how to use a material. Listen exposes capabilities and
preserves meaningful state without pretending the current set of Learning
Activities is complete.

### Multilingual Core, Language-Aware Capabilities

Materials, resources, corpus occurrences, and learning records use shared
semantics across languages. Tokenization, lexical identity, writing systems,
pronunciation, tone, stress, mora, rhythm, and morphology are language-aware
capabilities that may vary or be unavailable without breaking basic use.

### Accumulation With Intent

Opening a material temporarily does not add it to the Personal Library. The
Learner explicitly retains a material before it is durably indexed and synced.

### Open Production And Reusable Results

Listen Gen is an open production path that lets producers choose models and
tools suited to their hardware, budget, language, and privacy needs. Consumers
reuse the resulting package without needing the producer's original models.

### Public Content, Private Learning

Content Packages, editions, and community metadata can be public. Personal
progress, notes, saved items, and Learning Facts belong to the Learner and are
never part of a community package.

### Account-Enhanced, Offline-Capable

An account is not required to open local material or use basic learning
capabilities. Accounts enable required future capabilities such as personal
state synchronization, subscriptions, and publishing. Downloaded or local
material remains usable when the network is unavailable.

### Replaceable External Providers

Model vendors, media sources, and external context providers may enrich the
experience but are never the sole authority for a core Listen concept. External
results remain attributed and follow their providers' usage constraints.

## Material Entry Paths

Listen has two equal material entry paths:

1. A Learner opens raw text, audio, or video, uses it immediately, and optionally
   enriches or retains it.
2. A Learner discovers a community Learning Edition, resolves its required
   source assets, and installs a compatible Package Release.

Both paths produce a Learning Material. A Content Package is a distribution
mechanism, not the product's central learning object and not a prerequisite for
learning.

## Corpus Search

Listen uses one Corpus Occurrence model across three Search Scopes:

- Current Material;
- Personal Corpus;
- Community Corpus.

Text-only occurrences anchor to text spans. Timed occurrences additionally
anchor to audio or video ranges. External context providers may supplement
these scopes with ephemeral External Context References, but their results do
not silently enter a Listen corpus.

## Content Package Ecosystem

- One Language Material can have multiple Material Revisions.
- One Material Revision can have multiple Learning Editions from different
  producers or for different audiences.
- One Learning Edition can have multiple immutable Package Releases.
- Base Resources are reusable across Support Languages.
- Assistance Resources may target a particular Support Language or audience.
- A package may embed resources, reference external resources, or mix both.
- A newer release is announced; it does not silently replace an installed or
  active release.
- Publisher Status, Review Status, and License Status remain independent.

## Personal Data

Listen synchronizes durable data the Learner cannot safely recreate: library
membership, progress, notes, saved items, explicit outcomes, and meaningful
Learning Facts. Public package bytes are re-downloadable; indexes, caches, and
Learning Inferences are rebuildable. Raw media and large sensitive assets are
not assumed to synchronize automatically.

## Non-Goals

Listen does not currently aim to:

- prescribe a universal curriculum or mandatory learning sequence;
- require generation or a Content Package before basic learning;
- enumerate every future Learning Activity;
- model every language with English-specific concepts;
- bind content production to one provider or model generation;
- make a full community correction editor part of the learner application;
- copy external-provider content into the Listen corpus without an authorized
  material intake path.

## Deliberately Deferred Decisions

The semantic baseline does not yet decide:

- how Learning Inferences and Training Candidates are produced;
- how mastery or overall language ability is calculated;
- the complete set of Learning Activities;
- community moderation, reputation, and business models;
- cloud implementation technology and deployment topology;
- optional synchronization of large private media and recordings.
