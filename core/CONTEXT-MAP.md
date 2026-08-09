# Listen Context Map

This map assigns product authority across the current repositories and the
required future cloud context. It describes durable seams, not current source
directories or deployment technology.

The canonical product purpose is in [PRODUCT.md](PRODUCT.md), and shared terms
are defined in [CONTEXT.md](CONTEXT.md).

## Contexts

### Learning Experience — `listen-app`

Owns the learner-facing experience: temporary material intake, Personal Library
interaction, discovery, capability presentation, playback and reading, corpus
search, account interaction, synchronization UX, package update decisions, and
the orchestration of local runtimes.

It does not define canonical learning state, package validity, generation
semantics, or community registry truth.

### Semantic Runtime — `listen-core`

Owns canonical product semantics and contracts for Learning Materials, Learning
Resources, content-package validation, Personal Library state, Personal Corpus
occurrences, Learning Records, language capabilities, and synchronization merge
semantics.

It does not own learner-facing journeys, content-production implementations, or
multi-tenant community infrastructure.

### Content Production — `listen-gen`

Owns open, replaceable production of reusable Learning Resources and Content
Packages: media preprocessing, provider execution, generation recipes,
qualification, provenance, deterministic packaging, and honest degradation.

It does not own Learner state, package activation, learning journeys, community
ranking, or canonical package schemas.

### Community And Sync — required future context

Will own accounts and devices, private-state replication, Package Listings and
immutable release distribution, Community Corpus indexing, publishers,
subscriptions, ratings, reports, moderation, and update discovery.

This context is required by the product direction. Its repository, protocols,
service decomposition, and deployment remain undecided; no current repository
may silently absorb it.

## External Contexts

### Material Sources

Publish or provide references to language-bearing material. Discovery does not
itself grant playback, download, or redistribution rights.

### Model Providers

Perform replaceable generation or learner-dependent inference. Provider output
must cross a typed, provenance-bearing seam before it becomes a Listen resource
or inference.

### External Context Providers

Return supplemental real-world contexts, such as YouGlish results. Their output
remains attributed and ephemeral unless the underlying material enters through
the ordinary material intake path.

## Relationships

```text
listen-app  -- learner intents / results / events --> listen-core
listen-app  -- generation request / progress ------> listen-gen
listen-gen  -- immutable Content Package ----------> listen-core

listen-app  -- discovery / publishing / sync ------> Community And Sync
listen-core -- domain changes / merge semantics ---> Community And Sync

Material Sources ----------> listen-app material intake
Model Providers ------------> listen-gen or listen-core adapters
External Context Providers -> listen-app supplemental context
```

`listen-core` publishes the canonical package and runtime contracts.
`listen-gen` consumes the package contract and produces data-only artifacts.
`listen-app` pins compatible Core and Gen releases and owns the end-to-end user
journey. No runtime integration depends on a sibling checkout or moving branch.

## Authority Matrix

| Concern | Authority |
|---|---|
| Product purpose and shared domain language | `listen-core` root semantic documents |
| Learner journeys and presentation | `listen-app` |
| Canonical Learning Record and material state | `listen-core` |
| Canonical runtime and Content Package contracts | `listen-core` |
| Package validation and installation semantics | `listen-core` |
| Resource generation recipes and provider execution | `listen-gen` |
| Generation-provider selection | Producer through `listen-gen` |
| Credential custody and account interaction | Calling client or producer environment |
| Package discovery, distribution, and Community Corpus | Community And Sync |
| Private state replication | Community And Sync using Core-owned merge semantics |
| Local and downloaded asset availability | Learner device and source-specific adapters |
| External context results | External provider; Listen retains attribution and limits |

## Stable Seams

### App To Core

The interface expresses learner intent and observable outcomes. UI structure,
transport parsing, database layout, and provider-specific configuration do not
belong in the shared interface.

### Gen To Core

The interface is the versioned, data-only Content Package. Gen does not write
Core storage or emit Core lifecycle state; Core does not expose generation
provider details through its package validation interface.

### App To Gen

The interface covers one bounded generation request with capabilities,
progress, cancellation, warnings, provenance, and an output artifact. App owns
the experience; Gen owns production semantics.

### Client To Community And Sync

Public content distribution and private state synchronization remain separate
data planes even if one hosted product implements both. Public artifacts are
content-addressed and re-downloadable; private learning data is authenticated,
mergeable, and learner-owned.

## Architectural Invariants

- A raw Language Material is usable before enrichment.
- Content Enrichment is optional, incremental, and replaceable.
- A Content Package never contains personal Learning Records or executable
  provider code.
- Package Releases are immutable; updates require an explicit learner decision.
- Base Resources and Support-Language Assistance Resources have independent
  identity and lifecycle.
- Language-specific behavior is selected by capabilities, not a universal
  English-shaped workflow.
- A missing advanced capability degrades honestly without disabling basic
  reading, playback, or material access.
- Temporary Material does not enter the Personal Library without learner intent.
- Corpus indexes and Learning Inferences are rebuildable projections, not
  primary learner truth.
- External-provider results remain supplemental and cannot become a hidden
  dependency of the Personal or Community Corpus.
