# Listen

This repository is the project-level documentation authority for Listen. It
contains product semantics, shared language, cross-repository boundaries,
learner journeys, development policy, and the outcome roadmap. It contains no
application runtime, producer implementation, generated contract, or learner
data.

Listen is a multilingual, material-centered language-learning ecosystem. Its
primary interaction is listening, while reading is a complete entry path and
speaking, writing, pronunciation, and future learning activities can reuse the
same materials and resources.

The concise learner promise is:

> Turn language content you care about into a personal corpus you can search,
> revisit, and keep learning from.

## Canonical documents

| Document | Authority |
|---|---|
| [PRODUCT.md](PRODUCT.md) | Product purpose, principles, and non-goals |
| [DOMAIN.md](DOMAIN.md) | Shared ubiquitous language |
| [DOMAIN.zh-CN.md](DOMAIN.zh-CN.md) | Maintained Chinese rendering of the same ubiquitous language |
| [CONTEXT-MAP.md](CONTEXT-MAP.md) | Context and repository ownership |
| [JOURNEYS.md](JOURNEYS.md) | Simple learner journeys and experience invariants |
| [DEVELOPMENT.md](DEVELOPMENT.md) | Owner, Supervisor, Worker, validation, and delivery policy |
| [ROADMAP.md](ROADMAP.md) | Cross-repository outcome stages and exit conditions |
| [STATE.md](STATE.md) | Current project position and next decision |
| [decisions/](decisions/) | Durable cross-repository decisions |
| [plans/phase-1-completion.md](plans/phase-1-completion.md) | Active Supervisor execution plan for the remaining Phase 1 work |

Each fact has one authority. Other repositories link here rather than copying
these documents.

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
