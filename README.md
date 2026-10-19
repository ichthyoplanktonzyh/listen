# Listen

Listen turns authentic language into experiences a Learner can re-enter,
learn from, and make part of their own L2 world.

This repository contains the complete product source and its project model:

| Directory | Responsibility |
|---|---|
| `app/` | Flutter learning experience and desktop product assembly |
| `core/` | Rust semantic runtime, persistence, local services and canonical contracts |
| `gen/` | Python material production, replaceable providers and Content Package generation |
| `core/contracts/` | Canonical HTTP, event and material/package schemas |
| `tools/` | Shared development and release command implementation |

The former `listen-app`, `listen-core`, and `listen-gen` histories are imported
under their module directories. Their old releases and repository links remain
historical references. See [decision 0005](decisions/0005-single-repository-development.md).

## Development preview

Development previews are distributed through [GitHub Releases](https://github.com/ichthyoplanktonzyh/listen/releases).
The current package targets Apple Silicon with macOS 26 or newer, uses ad-hoc
signing, and is not notarized. Read the
[installation and runtime requirements](docs/development/dev-preview-distribution.md)
before downloading. Transcription models are downloaded only after confirmation.

## Development

Start with [DEVELOPMENT.md](DEVELOPMENT.md). From this repository root:

```sh
./dev setup
./dev run
./dev check
./dev test integration
```

Daily development builds the current App, Core and Gen together. Product
releases build one clean source commit and generate immutable artifact/lock
manifests; internal pin-update releases are not part of feature development.
Each module keeps its native toolchain. Heavy model dependencies are opt-in.

## Canonical documents

| Document | Authority |
|---|---|
| [MODEL.md](MODEL.md) | Project theoretical model and durable invariants |
| [PRODUCT.md](PRODUCT.md) | Product purpose, principles and non-goals |
| [DOMAIN.md](DOMAIN.md), [DOMAIN.zh-CN.md](DOMAIN.zh-CN.md) | One bilingual ubiquitous language |
| [CONTEXT-MAP.md](CONTEXT-MAP.md) | Module responsibilities and semantic interfaces |
| [JOURNEYS.md](JOURNEYS.md) | Learner journeys and experience invariants |
| [ROADMAP.md](ROADMAP.md) | Project outcome stages and exit conditions |
| [STATE.md](STATE.md) | Current project position and next transition |
| [DEVELOPMENT.md](DEVELOPMENT.md) | Shared development, verification and release workflow |
| [decisions/](decisions/) | Durable project decisions |

Each fact has one authority. The product model can lead implementation; code,
contracts and executable tests describe implemented behavior. Module glossaries
add local language without copying the project model. Historical plans do not
supersede the current model or claim its implementation is complete.

## Licensing

Public source visibility implies no project-wide open-source license grant.
Preserve original per-file and third-party license notices. This migration adds
no license grant and changes no learner-data ownership.
