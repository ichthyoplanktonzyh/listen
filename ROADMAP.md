# Listen Roadmap

> Status: accepted by the owner on 2026-08-09.

This is the only cross-repository roadmap. It describes product outcomes,
dependencies, and exit conditions. Repository tasks and temporary sequencing
belong in issues or Supervisor plans.

The roadmap is deliberately outcome-based. A phase is complete when its exit
conditions hold across the relevant repositories, not when a predetermined
feature list or date is exhausted.

## Completed stage: Foundation Convergence

The project is no longer an exploratory prototype: its product semantics,
bounded contexts, repository ownership, learner journeys, development model,
and principal contracts are established. It is not yet a product Beta because
the material-centered single-user loop has not been integrated end to end.

Content Package v2 completed the final foundation slice through Core #125,
Gen #8, and App #107. It proved the material-centered contract, bounded Core
inspection and pure Installation Plan, deterministic Gen production, embedded
and referenced-media delivery, unchanged v1 behavior, and the agreed
documentation authority.

Exit conditions:

- Content Package v2 passes the Core and Gen contract and interoperability
  gates for embedded and referenced delivery;
- the three code repositories point to this repository for project-level
  meaning, journeys, development policy, state, and roadmap;
- existing learning activities and learner-owned state remain independent of
  package lifecycle;
- the Supervisor / replaceable Worker delivery process is operational.

These exit conditions are met. The project has entered **Product Alpha**.

## Phase 1: Single-user Core Loop Alpha — active

Deliver one reliable, simple, single-device journey across every material entry
path: import or discover a material, use it immediately, enrich it when useful,
adopt a Learning Edition explicitly, learn through existing activities, retain
it, and reopen it later.

Internal Package Installation and Learning Edition Adoption remain separate
intents even when App composes them behind a simple learner action. Package
files, Resource DAGs, candidates, and generation internals do not leak into the
ordinary learner journey.

Exit conditions:

- direct import and RSS/Atom discovery converge on the same material lifecycle;
- raw text or media remains immediately readable or playable without a package;
- an existing package can be resolved, or Gen production can run in the
  background with explicit progress, cancellation, retry, and failure states;
- installed resources remain candidates until an explicit adoption intent;
- adopted editions, learner records, and current activity state survive restart;
- v1 compatibility remains explicit and no existing learning activity is
  silently redefined.

## Phase 2: Personal Corpus Alpha/Beta

Make the learner's retained materials a coherent personal corpus rather than a
collection of import sessions. The corpus must preserve durable learning facts
while media, packages, generated resources, and projections remain replaceable.

Exit conditions:

- learners can organize, retain, remove, and rediscover materials and editions;
- material, segment, expression, and contextual occurrence search is available
  across the local corpus;
- content identity and revision handling avoid accidental duplicate ownership;
- detached media can be reported and reattached without losing learning facts;
- export, backup, and recovery have explicit integrity and failure semantics.

## Phase 3: Learning Experience Review & Optimization

Review and improve the learning activities that already exist, including My
Expressions, the four-state vocabulary model, and their composition with
reading, listening, speaking, and writing. This phase improves clarity,
continuity, feedback, and extensibility; it does not force every learner into a
fixed sequence or discard previously accepted activity semantics.

Exit conditions:

- every existing activity has an explicit learner intent, entry condition,
  observable outcome, durable state, and resume behavior;
- overlapping concepts, actions, and state transitions are identified and
  either unified or deliberately kept distinct;
- navigation between material context and activities preserves learner context
  and avoids duplicate work;
- My Expressions and the four-state vocabulary model retain their accepted
  semantics while unclear transitions and feedback are made testable;
- loading, empty, error, cancellation, retry, and offline behavior are defined
  for each activity journey;
- language-general activity behavior is separated from language-specific
  capabilities such as stress timing or syllable timing;
- new activities can be added through stable seams without expanding a central
  workflow or changing unrelated activity state;
- representative end-to-end usability and regression evidence confirms that
  optimization did not narrow the learner's available learning paths.

## Phase 4: Multi-device Sync Beta

Protect the learner's private corpus and learning history across devices. Public
content distribution and private synchronization remain separate data planes,
even if a future Community And Sync context shares infrastructure.

Exit conditions:

- the future hosted context and repository/service boundary are chosen
  explicitly before implementation;
- identity, privacy, authentication, ownership, conflict, deletion, and offline
  semantics are documented and tested;
- durable learner records and corpus metadata synchronize without treating
  replaceable package or media blobs as the same kind of state;
- interrupted synchronization is resumable and cannot silently lose accepted
  learner changes;
- a learner can recover their supported private state on another device.

## Phase 5: Community Content Ecosystem

Enable a package produced once to be discovered and reused by other learners.
Gen may be released and packages may circulate as files before this hosted
phase; the community phase adds authoritative Listings and distribution rather
than making the package format depend on a server.

Exit conditions:

- immutable Package Releases and mutable Listings have separate identities and
  lifecycle rules;
- publishers can submit releases and learners can discover, verify, acquire,
  and use embedded or detached packages;
- fingerprint matching prevents avoidable duplicate production while allowing
  multiple editions and releases for the same material revision;
- publisher, review, license, provenance, moderation, and security facts remain
  distinct and are represented honestly;
- Gen has a documented contributor and release path that does not depend on
  one fixed model or provider.

## Phase 6: Intelligence & Expansion

Add optional capabilities only after the core product and ecosystem semantics
are stable. Candidates include learning suggestions, external contextual search
such as YouGlish integration, TTS-derived renditions, additional activities, and
deeper language-specific capabilities.

These are opportunity directions rather than committed features. Suggestions
remain candidates rather than commands, and every addition must preserve the
learner's freedom to choose how to use their corpus.

## Sequencing rules

- Exit conditions, not dates, advance a phase.
- A phase may contain repository-local slices, contract evolution, and
  cross-repository vertical slices; use the smallest independently deliverable
  mode for each outcome.
- Code repositories may develop independently behind stable contracts, but a
  cross-repository outcome is not complete until consumer and producer evidence
  agrees on exact versions.
- New learning activities, hosted community infrastructure, recommendations,
  TTS, and external context providers do not block the earlier product phases
  unless the owner changes this roadmap explicitly.
