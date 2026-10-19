# Listen

This repository is the project-level documentation authority for Listen. It
contains the project model, product semantics, shared language,
cross-repository boundaries, learner journeys, and the outcome roadmap. It
contains no application runtime, producer implementation, generated contract,
or learner data.

Listen is an authentic-material language-capability acquisition system. It
compiles arbitrary sources into complete, interactive language experiences and
helps a Learner turn meaningful Language Slices into a Personal Corpus that
supports independent reading, listening, speaking, and writing growth.

The concise learner promise is:

> Turn authentic language into experiences you can re-enter, learn from, and
> make part of your own L2 world.

## Canonical documents

| Document | Authority |
|---|---|
| [MODEL.md](MODEL.md) | Project-level theoretical model and durable invariants |
| [PRODUCT.md](PRODUCT.md) | Product purpose, principles, and non-goals |
| [DOMAIN.md](DOMAIN.md) | Shared ubiquitous language |
| [DOMAIN.zh-CN.md](DOMAIN.zh-CN.md) | Maintained Chinese rendering of the same ubiquitous language |
| [CONTEXT-MAP.md](CONTEXT-MAP.md) | Context and repository ownership |
| [JOURNEYS.md](JOURNEYS.md) | Simple learner journeys and experience invariants |
| [ROADMAP.md](ROADMAP.md) | Cross-repository outcome stages and exit conditions |
| [STATE.md](STATE.md) | Current project position and next decision |
| [decisions/](decisions/) | Durable cross-repository decisions |

Each fact has one authority. `MODEL.md` is primary for the theoretical model;
the other canonical documents specialize it without redefining it. Other
repositories link here rather than copying these documents.

`DOMAIN.md` and `DOMAIN.zh-CN.md` form one bilingual glossary and change
together. English domain names are the stable identifiers used in code and
executable contracts; the Chinese document supplies the canonical Chinese
terms for product discussion without creating a second model.

## Code repositories

- [`listen-app`](https://github.com/ichthyoplanktonzyh/listen-app) — learner
  experience and final product assembly.
- [`listen-core`](https://github.com/ichthyoplanktonzyh/listen-core) — semantic
  runtime, canonical executable contracts, persistence, and local services.
- [`listen-gen`](https://github.com/ichthyoplanktonzyh/listen-gen) — replaceable
  content production and deterministic Content Package generation.

Executable schemas, APIs, lock files, tests, and release manifests remain in
their owning code repository. This documentation never overrides code facts or
an executable contract.

## Licensing

The repositories are publicly visible, but no project-wide open-source license
grant is implied. Each repository's own license file, when present, is the only
license authority for that repository.
