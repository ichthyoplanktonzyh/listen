# Project State

> Updated: 2026-08-11 CST.

## Current position

The project has an agreed semantic and architectural foundation across three
independently versioned repositories. Content Package v2 is complete through
[Core #125](https://github.com/ichthyoplanktonzyh/listen-core/pull/125),
[Gen #8](https://github.com/ichthyoplanktonzyh/listen-gen/pull/8), and
[App #107](https://github.com/ichthyoplanktonzyh/listen-app/pull/107). Durable
Material, Package Installation, and Learning Edition Adoption semantics are
complete in Core, and [App #108](https://github.com/ichthyoplanktonzyh/listen-app/pull/108)
establishes the Managed Asset Store and first Personal Library Material
projection.

The official product-development stage is now **Product Alpha — Phase 1:
Single-user Core Loop Alpha**. Foundation Convergence is complete.

## Confirmed project decisions

- multilingual, material-centered, listening-first product semantics;
- simple learner journeys over deep internal architecture;
- explicit three-repository responsibilities and stable seams;
- learner-owned learning activities and state outlive package lifecycle;
- Owner / Supervisor / replaceable Worker operating model;
- repository-local, contract-evolution, and cross-repository work modes;
- no internal backward-compatibility requirement before the accepted Phase 1
  stack release: coordinated replacement is preferred, published artifacts stay
  immutable, and that release becomes the first maintained baseline;
- this repository as the single project-level documentation authority;
- the ordered outcome roadmap in `ROADMAP.md`;
- Document Renditions as first-class Material representations, with source
  inputs preserved instead of flattened and typed or pasted text only one
  plain-text intake adapter;
- Structured Reading Resources as separate, versioned Base Resources whose
  Reading Anchors support durable reading and learning-resource alignment;
- a valid Material may offer any supported subset of modalities; an absent
  modality is a Capability Gap only when the Learner requests it;
- TTS audio as a provenance-bearing Derived Media Rendition, with synchronized
  reading supplied by a separate text-to-time alignment Base Resource;
- Learning Materials as the active learner-facing composition, Learning
  Editions as coherent reusable multimodal compositions, and Gen as a
  Capability Completion producer rather than a mandatory normalization gate;
- a dedicated Learning Experience Review & Optimization phase after Personal
  Corpus and before Multi-device Sync, without redefining accepted learning
  activity semantics or forcing a fixed learning sequence.

## Next transition

Complete the remaining Phase 1 slices in the dependency order recorded in the
active [Phase 1 completion plan](plans/phase-1-completion.md): finish the current
App document work, establish the breaking canonical Rendition and Resource
contract, complete document reading and multimodal Capability Completion,
converge RSS/Atom acquisition on Source Identity, remove displaced compatibility
paths, then perform one stack release and final desktop acceptance. The plan is
an execution document; `ROADMAP.md` remains the authority for Phase 1 exit
conditions.
