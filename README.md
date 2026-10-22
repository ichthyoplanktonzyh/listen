# Listen

Listen turns authentic language into experiences a Learner can re-enter,
learn from, and make part of their own L2 world.

One repository contains Flutter `app/`, Rust `core/`, Python `gen/`, and the
shared development tooling in `tools/`. The desktop product packages these
modules together as `listen.app`.

The approved direction targets desktop and mobile local learning, with material
production on a personal computer or remote executor and replaceable model
providers. The current supported build remains macOS; see the
[desktop/mobile and production design](docs/architecture/devices-and-production.md)
for the target and [current state](STATE.md) for implementation gaps.

## Start here

- [Current state](STATE.md) and [roadmap](ROADMAP.md): audio/video listening,
  contextual help, and returning through the Personal Corpus.
- [Development](DEVELOPMENT.md): setup, run, checks, and packaging.
- [Runtime architecture](docs/architecture/runtime.md): module, process,
  contract, and persistence boundaries in the implementation.
- [Desktop/mobile and production design](docs/architecture/devices-and-production.md):
  approved local-first target, production executors, providers, and delivery.
- [Development preview](docs/development/dev-preview-distribution.md): download,
  installation, signing, and external runtime requirements.

```sh
./dev setup
./dev run
./dev check
./dev test integration
```

## Product definitions

| Document | Responsibility |
|---|---|
| [MODEL.md](MODEL.md) | Product/domain model and foundational versus on-demand resource policy |
| [PRODUCT.md](PRODUCT.md) | Purpose, principles, and non-goals |
| [DOMAIN.md](DOMAIN.md), [DOMAIN.zh-CN.md](DOMAIN.zh-CN.md) | One bilingual glossary |
| [CONTEXT-MAP.md](CONTEXT-MAP.md) | Semantic responsibilities across modules |
| [JOURNEYS.md](JOURNEYS.md) | Full media-first journey: native playback, resource preparation, learning, retention, re-entry and review |

These documents describe the product direction. They do not assert that every
capability is implemented or require every capability in the current stage.
Code, contracts, and executable tests describe implemented behavior;
[STATE.md](STATE.md) and [ROADMAP.md](ROADMAP.md) define current work.

## Engineering references

- [App UI checks](docs/development/app-ui.md)
- [Gen CLI and providers](docs/development/gen.md)
- [Gen machine-event protocol](docs/protocols/gen-machine-events.md)
- [Gen release bundle](docs/protocols/gen-release-bundle.md)
- [Canonical contracts](core/contracts/)

Module README and AGENT files provide local entry points and toolchain details.
There are no separate module roadmaps, planning trees, or historical handoff
instructions. Removed documents remain available through Git history.

## Licensing

Public source visibility grants no project-wide open-source license.
Preserve per-file and third-party license notices. See the bundled runtime's
[third-party notices](core/third_party/runtime/THIRD_PARTY_NOTICES.md).
