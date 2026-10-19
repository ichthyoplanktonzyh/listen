# Listen Agent Guide

Listen is one repository containing `app/` (Flutter), `core/` (Rust), `gen/`
(Python), and project documentation. Read [DEVELOPMENT.md](DEVELOPMENT.md) for
the shared development and release workflow.

## Authority

- The owner decides product direction, priorities, compatibility and releases.
- `MODEL.md` owns the project theoretical model; `PRODUCT.md`, `DOMAIN.md`,
  `CONTEXT-MAP.md`, `JOURNEYS.md`, `ROADMAP.md`, and `STATE.md` specialize it.
- Code and executable tests describe implemented behavior. The agreed product
  model can be ahead of implementation; report that drift honestly.
- `core/contracts/` is the executable contract authority. Keep one schema copy.
- App owns experience, Core owns learning semantics and persistence, Gen owns
  material production. A task can change multiple modules in one branch/review.

## Working rules

- Start with Git status and worktree inventory. Preserve unrelated work.
- Implement on a `codex/` branch, never directly on `main`. Do not force-push
  `main`, merge a PR, archive old repositories, or delete worktrees without
  the owner's authorization for that action.
- Use one coherent branch and PR for a feature, including affected modules,
  contracts, migrations, and verification. Internal integration needs no prior
  component release or separate handoff PR.
- Supervisor owns architecture, decomposition, review, independent validation,
  documentation, and authorized Git delivery. Configured implementation workers
  own source, tests, scripts, schemas, migrations and runtime configuration.
- Read the relevant module's `AGENT.md` and local executable discipline tests.
- Ordinary tests use deterministic providers and no paid/live model calls.
  Never print, persist or commit credentials; never commit learner data,
  virtualenvs, downloaded models, runtime binaries or build output.
- Run relevant native checks and the fixture integration gate when changing a
  module interface. Report exact executed commands and outcomes. No checked-in
  GitHub Actions workflow currently runs these checks automatically.
- Use focused Conventional Commits. Root/module changelogs are release-only.

## Documentation

- Each fact has one authority; link instead of duplicating runbooks or plans.
- `DOMAIN.md` and `DOMAIN.zh-CN.md` are one glossary and change together when
  domain language changes. English domain names remain stable identifiers.
- Root `STATE.md` and `ROADMAP.md` own active project status and outcomes.
  Module planning trees are historical/local implementation evidence; do not
  restart superseded phases or override the root product model.
- Preserve historical decisions; append a superseding decision when needed.
- Public visibility is not an open-source license. Preserve license notices.
