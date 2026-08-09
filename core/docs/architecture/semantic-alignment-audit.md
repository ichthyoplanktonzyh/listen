# Semantic Alignment Audit

> Snapshot: 2026-08-09. Code baselines: `listen-core` `f10376f`, `listen-app`
> `5dcf6ae`, `listen-gen` `a660946`.

This report compares current code with the owner-approved semantic baseline in
[`../../PRODUCT.md`](../../PRODUCT.md), [`../../CONTEXT.md`](../../CONTEXT.md),
and [`../../CONTEXT-MAP.md`](../../CONTEXT-MAP.md). It is a dated implementation
audit, not another source of product truth.

## Executive Summary

The existing architecture already contains several strong foundations: a
rebuildable local corpus, provider-neutral generation, provenance-bearing
resources, immutable package bytes, candidate-only installation, explicit
resource activation, and degraded language profiles.

The main mismatch is that the current model is still **media-and-subtitle
centered**, while the approved product model is **language-material centered**.
That mismatch appears in the package contract, material lifecycle, corpus
anchors, and several English-shaped defaults. The next architectural effort
should deepen the material/resource seam rather than add more learning
activities.

## Already Aligned

### Rebuildable Personal Corpus Foundation

Core already projects subtitle-derived `CorpusOccurrence` rows and supports
lexical and semantic search. App exposes local-corpus playback and collection,
while semantic embeddings remain optional and rebuildable.

Evidence:

- `listen-core/crates/application/src/corpus.rs`
- `listen-core/crates/domain/src/learning_loop.rs` (`CorpusOccurrence`)
- `listen-app/lib/data/repositories/lexical_repository.dart`
- `listen-app/lib/widgets/vocabulary/semantic_search_dialog.dart`

### Package Safety And Candidate Installation

Content Packages are data-only, bounded, hashed, validated, and installed as
candidates. Import does not silently replace active resources. This matches the
approved update and authority model.

Evidence:

- `listen-core/crates/content-package/`
- `listen-core/contracts/content-package/v1/`
- `listen-core/crates/application/src/content_package.rs`

### Replaceable Content Production

Gen has real fixture, command, and local-model production paths, deterministic
package construction, typed machine events, cancellation, qualification,
provenance, and honest partial degradation.

Evidence:

- `listen-gen/src/listen_gen/`
- `listen-gen/tools/release_bundle.py`
- `listen-gen/tests/`

### Partial Multilingual Capability Model

Core distinguishes language profiles and uses open namespaced capability kinds
with an unsupported-language fallback. Lexical identity already carries
language and granularity.

Evidence:

- `listen-core/crates/domain/src/language_profile.rs`
- `listen-core/crates/domain/src/lexical_unit.rs`

## Near-Term Semantic Conflicts

### 1. Content Package v1 Models Media, Not General Language Material

**Conflict:** Every v1 package requires `media_fingerprint`, `media_kind` limited
to audio/video, positive `duration_ms`, and a required timed subtitle resource.
It cannot represent a text-only article, optional source assets, an embedded
media delivery, or a mixed embedded/reference package.

It also lacks first-class Source Identity, Material Revision, Learning Edition,
Base Resource versus Assistance Resource, Support Language, and package lineage.

**Evidence:**

- `listen-core/contracts/content-package/v1/manifest.schema.json`
- `listen-core/crates/content-package/src/model.rs`
- `listen-gen/src/listen_gen/package.py`

**Direction:** Design a new major contract generation around Language Material
and resource descriptors. Preserve v1 as a legacy adapter rather than stretching
its media-specific fields into ambiguous meanings.

The new contract should support:

- text, audio, video, and mixed materials;
- embedded, referenced, and hybrid Delivery Profiles in one schema;
- stable material/revision/edition/release identity;
- resource role (`base` or `assistance`) and language metadata;
- segment-level Content Language where needed;
- optional text spans and optional media-time anchors;
- immutable resource dependencies and complete provenance.

### 2. Opening Material Currently Implies Permanent Registration

**Conflict:** The approved model separates Temporary Material from an explicit
Retention Decision. App currently registers a successfully opened media path in
Core immediately, and Core's media-library view lists every registered item.

**Evidence:**

- `listen-app/lib/controllers/media_session_coordinator.dart`
  (`openMediaPath` calls `registerMedia`)
- `listen-core/crates/application/src/media.rs` (`register_media` and
  `list_media_library`)

**Direction:** Separate transient material sessions from Personal Library
membership. Playback can use an ephemeral material handle; retaining a material
creates durable membership, progress, corpus indexing, and later synchronization.

### 3. Text-Only Material Is Not A First-Class Intake Path

**Conflict:** App's file intake accepts audio/video media, subtitles, packages,
and legacy timeline JSON. Reading experiences operate on subtitle text attached
to media rather than a standalone article.

**Evidence:**

- `listen-app/lib/services/media_import_file_service.dart`
- `listen-app/lib/widgets/channels/reading_channel.dart`
- `listen-core/crates/domain/src/reading.rs`

**Direction:** Add a Language Material intake seam that accepts text without
inventing fake media, duration, or timestamps. Existing subtitle-backed reading
becomes one adapter into that deeper module.

### 4. Language Scope Still Has Hidden English Defaults

**Conflict:** Corpus indexing substitutes English when a track has no language,
and the HTTP corpus search defaults to English when callers omit the language.
Unknown language is therefore sometimes silently interpreted as English rather
than remaining unknown or requiring explicit learner context.

**Evidence:**

- `listen-core/crates/application/src/corpus.rs`
- `listen-core/crates/api-http/src/routes/corpus.rs`

**Direction:** Require or derive language from explicit material/segment and
learner context. Unknown language must degrade as unknown, never as English.

### 5. Language Extension Is Declared Open But Registered Centrally

**Conflict:** Capability kinds are open strings, but `available_languages()` and
`profile_for()` hard-code English, Chinese, and Japanese. Several resources also
encode word and English prosody assumptions (`WordTimeline`, `LexicalStress`,
word-anchored `ProsodyAnalysis`).

**Evidence:**

- `listen-core/crates/domain/src/language_profile.rs`
- `listen-core/crates/domain/src/word_timing.rs`
- `listen-core/crates/domain/src/prosody_analysis.rs`

**Direction:** Keep common anchors generic and make language-shaped analyses
explicit capability resources. Replace central language matching with a profile
registry/provider seam when the next real language addition exercises it. Do
not build a speculative plugin framework before that second adapter exists.

### 6. Gen Is Intended To Be Open Source But Has No License Grant

**Conflict:** `listen-gen` is intended to seed an open production ecosystem, but
the repository contains no LICENSE or COPYING file and declares no package
license. Public source without a license is not an open-source grant.

**Evidence:**

- `listen-gen/` repository root
- `listen-gen/pyproject.toml`

**Direction:** The owner must choose and explicitly grant an OSI-compatible
license before presenting Gen as open source. This is a product/legal decision,
not an implementation-agent default.

### 7. Cross-Repository Package Compatibility Does Not Hash Schema Contents

**Conflict:** Gen's contract lock and release manifest hash contract metadata,
not the actual canonical schema bytes. Schema files can change without changing
the digest App verifies.

**Evidence:**

- `listen-gen/contracts.lock.json`
- `listen-gen/tools/release_bundle.py` (`canonical_sha256`)
- `listen-app/listen_gen.lock.json`

**Direction:** Core must publish a deterministic schema bundle manifest with
per-file hashes and a Core commit. Gen pins and embeds that bundle digest; App
verifies it against the Core contract it pins.

### 8. App's Production Gen Setup Has Two Disconnected Paths

**Conflict:** `ContentGeneratorLocator` resolves a local/bundled toolchain but is
not used by production composition. The active `LocalListenGenProcessService`
depends on environment-only provider arguments and manifest configuration, so
ordinary generation is not a closed product journey.

**Evidence:**

- `listen-app/lib/services/content_generator_setup.dart`
- `listen-app/lib/data/repositories/core_repositories.dart`
- `listen-app/lib/services/listen_gen_process_service.dart`
- `listen-app/lib/services/listen_gen_release_service.dart`

**Direction:** Keep one verified setup module that resolves the pinned Gen
artifact, required tools/models, and typed producer capabilities, then injects
that resolved setup into the process adapter. Environment variables remain
development overrides, not the production configuration model.

## Required Future Capabilities, Not Current Defects

The following are accepted product direction but should not be reported as
current regressions:

- account and device identity;
- private-state synchronization and conflict handling;
- Package Listings, subscriptions, moderation, and release distribution;
- Community Corpus indexing and the Current/Personal/Community search selector;
- optional external-context adapters such as YouGlish;
- editable package forks or a community correction workflow;
- Learning Inferences and Training Candidates.

These belong to the future Community And Sync context or later product modules.
Their absence must remain visible in product status, but current Core, App, and
Gen should not pre-implement the hosted context speculatively.

## Recommended Sequence

1. Select and add the `listen-gen` open-source license.
2. Write the next Content Package contract design around Language Material,
   resource roles, delivery profiles, multilingual segments, and real schema
   digests.
3. Introduce Temporary Material versus Personal Library membership and add a
   text-only material path.
4. Generalize Corpus Occurrence anchors and remove hidden English defaults.
5. Close the verified App-to-Gen production setup.
6. Exercise the language-capability seam with the next real non-English
   end-to-end slice, then replace only the hard-coded registration it exposes.
7. Design Community And Sync protocols only after the local identities and
   merge semantics above are stable.

This order makes the material/resource module deeper before adding cloud or
community surface area. It avoids building hosted interfaces on top of today's
media-specific identities.
