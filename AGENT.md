# Listen Agent Guide

Read [README.md](README.md), [STATE.md](STATE.md), and
[DEVELOPMENT.md](DEVELOPMENT.md), then the relevant module's AGENT.md.

## Authority

- The owner decides direction, priorities, compatibility, and releases.
- Root product definitions own shared semantics; code and
  `core/contracts/` own implemented behavior and executable formats.
- Root STATE.md and ROADMAP.md own current work. Product-model breadth is not
  the current implementation checklist.
- App owns experience, Core owns semantics and persistence, Gen owns material
  production. See [runtime architecture](docs/architecture/runtime.md).

## Working rules

- Inspect Git status and worktrees first; preserve unrelated work.
- Work on a `codex/` branch. Do not force-push main, merge a PR, archive a
  repository, or delete a worktree without owner authorization for that action.
- Use one coherent branch/PR across affected modules, contracts, and checks.
- Supervisor owns architecture, review, documentation, validation, and
  authorized Git delivery. Configured implementation workers own source,
  tests, scripts, schemas, migrations, and runtime configuration.
- Use deterministic fixtures for ordinary tests. Live or paid model calls
  require explicit authorization; do not download models as part of tests.
- Never print, log, commit, or persist credentials. Never commit learner data,
  virtualenvs, downloaded models, runtime binaries, or build output.
- Preserve learner facts and immutable published artifacts. Durable format
  changes need migration; published tags never acquire different bytes.
- Run checks appropriate to the change and report executed results. Interface
  changes also run `./dev test integration`; packaging changes verify the
  extracted application outside the checkout.
- Use focused Conventional Commits. Do not change release metadata as part of
  an ordinary documentation or implementation task.

## Documentation

- Maintain one current authority for each fact, with README.md as the index.
- Keep shared architecture, development guides, and protocols under root docs/.
  Module guides contain only local implementation details and links.
- Keep schema, fixture, and third-party usage/license notes beside their files.
- DOMAIN.md and DOMAIN.zh-CN.md are one glossary and change together.
- Do not create module planning trees, handoff logs, phase reports, or archive
  copies. Historical documents were deliberately removed by the owner; do not
  recover their requirements or treat their tasks as current work.
- Record present decisions in the relevant current document. Git preserves
  earlier versions; historical prose does not constrain future work.
- Public source visibility is not a license grant. Preserve license notices.
