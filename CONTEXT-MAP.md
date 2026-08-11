# Listen Context Map

This map assigns product authority across current repositories and the required
future hosted context. It describes durable seams, not source directories or
deployment technology. Product purpose is defined in [PRODUCT.md](PRODUCT.md)
and shared terms in [DOMAIN.md](DOMAIN.md).

## Contexts

### Learning Experience — `listen-app`

Owns learner-facing material intake, Personal Library interaction, Content
Subscriptions, discovery inbox, Material Acquisition, capability presentation,
safe direct document rendering, consumer-bundled decoding for supported
formats, playback and reading, corpus search, account and synchronization UX,
package adoption/update decisions, and orchestration of local runtimes.

It does not define canonical learning state, package validity, production
semantics, or community registry truth.

### Semantic Runtime — `listen-core`

Owns executable contracts and semantics for Learning Materials, Learning
Resources, Document and Media Renditions, Structured Reading Resources, Reading
Anchors, Content Package validation, Personal Library state, Personal Corpus
occurrences, Package Installation, Learning Edition Adoption, Learning Records,
language capabilities, persistence, and synchronization merge semantics.

It does not own learner-facing journeys, content-production implementations, or
multi-tenant community infrastructure.

### Content Production — `listen-gen`

Owns replaceable production of reusable Learning Resources and Content Packages:
media preprocessing, optional document extraction and OCR, provider execution,
generation recipes, qualification, provenance, deterministic packaging, and
honest degradation.

It does not own Learner state, package activation, learning journeys, community
ranking, or canonical package schemas.

### Project Governance — `listen`

Owns product purpose, shared language, cross-context boundaries, top-level
learner journeys, development policy, project state, and the outcome roadmap.
It owns no executable contract or implementation fact.

### Community And Sync — required future context

Will own accounts and devices, private-state replication, Package Listings and
immutable release distribution, Community Corpus indexing, publishers,
subscriptions, ratings, reports, moderation, and update discovery.

Its repository, protocols, service decomposition, and deployment remain
undecided. No existing repository may silently absorb it.

## External contexts

- **Material Sources** publish or identify language-bearing material. Discovery
  does not grant playback, download, or redistribution rights.
- **Model Providers** perform replaceable generation or learner-dependent
  inference. Output must cross a typed, provenance-bearing seam.
- **External Context Providers** return supplemental contexts such as YouGlish.
  Results remain attributed and ephemeral unless their material enters through
  normal intake.

## Relationships

```text
listen-app  -- learner intents / results / events --> listen-core
listen-app  -- generation request / progress ------> listen-gen
listen-gen  -- immutable Content Package ----------> listen-core

listen-app  -- discovery / publishing / sync ------> Community And Sync
listen-core -- domain changes / merge semantics ---> Community And Sync

Material Sources ----------> listen-app discovery and acquisition
Model Providers ------------> listen-gen or listen-core adapters
External Context Providers -> listen-app supplemental context

listen ---------------------> project meaning and governance links
```

Core publishes canonical runtime and package contracts. Gen consumes the
package contract and produces data-only artifacts. App pins compatible Core and
Gen releases and owns final assembly. No production integration depends on a
sibling checkout or moving branch.

## Authority matrix

| Concern | Authority |
|---|---|
| Product purpose and shared language | `listen` |
| Cross-repository roadmap and development policy | `listen` |
| Top-level learner journeys and experience invariants | `listen` |
| Detailed UI states, discovery, and acquisition UX | `listen-app` |
| Safe document rendering and basic supported-format decoding | `listen-app` |
| Canonical Learning Record and material state | `listen-core` |
| Rendition, Structured Reading Resource, and Reading Anchor semantics | `listen-core` |
| Runtime and Content Package contracts | `listen-core` |
| Package validation, installation, and adoption semantics | `listen-core` |
| Resource recipes and provider execution | `listen-gen` |
| Optional expensive or reusable extraction and OCR production | `listen-gen` |
| Generation-provider selection | Producer through `listen-gen` |
| Package discovery, distribution, and Community Corpus | Community And Sync |
| Private-state replication | Community And Sync using Core merge semantics |
| Local/downloaded asset availability | Learner device and source adapters |
| External context results | External provider with attribution and limits |

## Stable seams

### App to Core

Expresses learner intent and observable outcomes. Intake, retention, Package
Installation, and Learning Edition Adoption remain distinct even when one
learner action coordinates them. UI structure, transport parsing, database
layout, and provider configuration are not shared semantics.

### Gen to Core

The seam is the versioned, data-only Content Package. Gen does not write Core
storage or emit Core lifecycle state; Core does not expose generation-provider
details through validation.

### App to Gen

The seam is one bounded generation request with capabilities, progress,
cancellation, warnings, provenance, and an output artifact. App owns the
experience; Gen owns production semantics.

### Document processing

Document decoding is a replaceable adapter behind a typed Core-owned seam. A
consumer-bundled adapter or Gen may produce a candidate Structured Reading
Resource, and Core validates its identity, subject, anchors, provenance, and
applicability; Core also owns any persistence and selection semantics. Basic
viewing of a supported Document Rendition never requires Gen, and no parser or
renderer becomes the canonical owner of material or learner state.

Document inputs are untrusted data. Direct rendering or extraction does not
grant a document executable-code authority, hidden network access, or access to
credentials and unrelated local files.

### Client to Community And Sync

Public content distribution and private-state synchronization are separate data
planes even if one hosted product implements both. Public artifacts are
content-addressed and re-downloadable; private data is authenticated, mergeable,
and learner-owned.

## Architectural invariants

- Raw material is usable before enrichment.
- Document and Media Renditions are source representations; Structured Reading
  and Assistance Resources are separate, versioned capabilities.
- One material may expose Read, Listen, and Watch without being split into
  modality-specific library objects.
- A Reading Anchor is stable within an exact Base Resource. Cross-resource or
  cross-revision continuity requires explicit compatibility or mapping and
  never relies only on page or paragraph index.
- Subscription or automatic download does not itself retain a material.
- Enrichment is optional, incremental, replaceable, and honestly degraded.
- A Content Package contains no personal Learning Records or executable provider
  code.
- Package Releases are immutable; updates require learner intent.
- Installation exposes candidates; only adoption chooses a coherent selection.
- Learning Activities and learner-owned state are not children of a Package
  Release. Package or source changes cannot erase vocabulary capability,
  Personal Expressions, progress, or completed activity history.
- Package and resource complexity stays behind material-centered intents.
- Base and Assistance Resources have independent identity and lifecycle.
- Language behavior is selected by capabilities, not a universal English-shaped
  workflow.
- Missing advanced capability never disables basic reading or playback.
- Temporary Material enters the Personal Library only through learner intent.
- Corpus indexes and Learning Inferences are rebuildable projections.
- External-provider results remain supplemental, not hidden corpus authority.
