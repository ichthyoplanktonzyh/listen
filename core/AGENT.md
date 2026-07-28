# listen-core Agent Guide

This file is the mandatory entry point for every human or agent working in
`listen-core`. The repository is the backend, canonical contract, production
pipeline, and runtime-artifact authority for the listen product.

## Ownership

- The product owner has final authority over scope, compatibility, releases,
  repository settings, and cross-repository decisions.
- Codex is the default implementation agent for this repository.
- Claude is the default implementation agent for `listen-app`.
- Agent ownership is a coordination rule, not an access-control mechanism.
  Do not edit `listen-app` from a core task unless the owner explicitly asks
  for a coordinated cross-repository change.
- Consumer UI code, Flutter state, UI/UX decisions, and app packaging belong in
  `ichthyoplanktonzyh/listen-app`.

## First Read

Read these files before planning or changing code:

1. `.planning/STATE.md`
2. `.planning/PROJECT.md`
3. `.planning/MAINTENANCE.md`
4. `.planning/codebase/ARCHITECTURE.md`
5. `.planning/codebase/STRUCTURE.md`
6. `.planning/codebase/TESTING.md`
7. `.planning/CROSS_REPO.md` when work can affect `listen-app`

Read only the active phase under `.planning/phases/`. Everything under
`.planning/archive/monorepo-baseline/` is frozen historical context and is not
current repository truth.

## Repository Responsibilities

`listen-core` owns:

- Rust domain, application, persistence, provider, and HTTP implementation;
- `api-http`, its loopback lifecycle, authentication, and version handshake;
- canonical OpenAPI at `contracts/openapi/v1.yaml`;
- shared event, timeline, and resource schemas under `contracts/`;
- Python production, evaluation, and research tooling under `scripts/`;
- runtime assembly inputs and immutable contract/runtime release artifacts;
- backend ADRs, backend roadmap, backend requirements, and backend codebase
  documentation.

`listen-core` does not own:

- Flutter widgets, controllers, navigation, themes, or client settings;
- the app's handwritten wire adapters and compatibility parsers;
- app distribution assembly;
- `listen-app/backend.lock.json`.

## Architecture Rules

- Dependency direction is `domain <- application <- adapters`. HTTP handlers
  adapt requests; they do not own domain or provider workflows.
- `api-http` routes cross-crate work through `application`; they must not call
  analysis/provider implementation crates directly.
- Persistence implements repository interfaces and must not define product
  policy.
- Provider-specific protocols stay behind provider-neutral application traits.
- Long-running work uses durable jobs/events with explicit progress,
  cancellation, failure, and retry semantics.
- Learning records outlive replaceable media and generated resources. Avoid
  accidental cascade deletion of durable user history.
- LLTimeline, events, OpenAPI, and release manifests are versioned contracts.
- Production/research runtimes may be heavy; the consumer runtime must remain
  local, bounded, and independently distributable.
- Secrets are never logged, returned by read APIs, committed, or stored in
  ordinary settings/database fields when an OS secret store is required.
- Evidence, heuristics, and model output must retain provenance and must not be
  presented as stronger truth than their evidence class supports.

## Contract-First Workflow

For a change visible to `listen-app`:

1. Start from the user journey and the data/operation request supplied by the
   app side.
2. Design the smallest compatible change in
   `contracts/openapi/v1.yaml` and related schemas.
3. Decide compatibility and version impact before implementation.
4. Implement routes and application behavior.
5. Run method+path parity and contract validation.
6. Publish immutable contract/runtime artifacts from a clean commit.
7. Hand the release tag, core commit, versions, URLs, and SHA-256 values to the
   app owner.

Never ask the app to fetch moving `main`, import backend source, or depend on a
sibling checkout. See `.planning/CROSS_REPO.md`.

## Compatibility and Versioning

- `API_VERSION` identifies the protocol generation.
- `CONTRACT_VERSION` follows semantic compatibility:
  - patch: clarification or schema correction without consumer change;
  - minor: backward-compatible additive change;
  - major: consumer-breaking change requiring an explicit migration.
- Workspace/runtime version identifies the shipped sidecar/runtime bundle.
- Startup and health responses must report API, contract, and runtime versions.
- Do not silently mutate a published artifact or reuse a release tag.
- A breaking change requires an ADR or phase decision and coordinated
  `listen-app` migration.

## Code Placement

- Domain records and invariants: `crates/domain/`
- Use cases and repository/provider traits: `crates/application/`
- SQLite implementations and migrations: `crates/persistence-sqlite/`
- HTTP composition and routes: `crates/api-http/`
- Event envelopes: `crates/api-events/`
- Subtitle parsing/tokenization: `crates/subtitle-core/`
- Diagnosis: `crates/diagnosis-core/`
- Speech/timing/phonetic analysis: `crates/speech-analysis/`
- Provider adapters: `crates/*-provider/`
- Local runtime lifecycle: `crates/local-runtime/`
- Production/evaluation tooling: `scripts/`
- Canonical wire/resource contracts: `contracts/`
- Durable decisions: `docs/decisions/`

Do not create cross-cutting utility dumping grounds. Prefer deep modules with
small public interfaces and keep public types owned by the layer whose concept
they represent.

## Development and Validation

Use focused checks while iterating. Before review, run the checks relevant to
the changed boundary:

```sh
./scripts/test.sh --rust --strict
./scripts/validate-contracts.sh
python3 -m unittest scripts/test_release_artifacts.py
```

Additional commands:

```sh
cargo test --workspace --locked
cargo clippy --workspace --all-targets --locked -- -D warnings
cargo fmt --all -- --check
```

Contract changes require `./scripts/validate-contracts.sh`. Artifact changes
require artifact unit tests plus package/verify/smoke checks. Paid, ignored,
credential-dependent, and live-model tests run only when the owner explicitly
authorizes them.

For complete app startup, pinned-release testing, unreleased local-core
integration, manual smoke coverage, logs, and troubleshooting, follow
`docs/development/full-app-local-testing.md`.

GitHub Actions may be unavailable because of account billing. A job that never
started is infrastructure failure, not validation. In that case record exact
local commands and results; only the owner may authorize merge without CI.

## Planning and Documentation

The live `.planning` tree describes only facts owned by this repository.

- `PROJECT.md`: durable backend mission and boundaries
- `REQUIREMENTS.md`: testable backend requirements
- `ROADMAP.md`: backend-only phases and dependencies
- `STATE.md`: current backend position and next actions
- `codebase/`: current code-derived architecture, structure, stack, data model,
  testing, conventions, and concerns
- `phases/`: active and completed backend phases
- `archive/`: frozen imported monorepo history

Follow `.planning/MAINTENANCE.md`. Root `CHANGELOG.md` is release-only: ordinary
feature, fix, refactor, planning, and documentation branches do not edit it.
The release owner curates it once from merged PRs when publishing a version. Do
not copy `listen-app` planning into this repository. Cross-repo status is
recorded as a release/commit/issue/PR link, not duplicated plans.

## Git and Pull Requests

- Start with `git status --short --branch` and `git worktree list`.
- Preserve user-owned changes and unrelated work.
- Never implement directly on `main`.
- Start from current `origin/main`:

  ```sh
  git fetch origin --prune
  git switch -c codex/<issue-or-phase>-<slug> origin/main
  ```

- Use one coherent branch and PR per task.
- Use Conventional Commit subjects and atomic commits.
- Inspect `git diff --check`, staged files, and `origin/main..HEAD` before push.
- PRs include outcome, scope/non-goals, validation, compatibility, migrations,
  release impact, and cross-repo handoff when applicable.
- Agents do not approve their own PRs or merge without explicit owner
  authorization.
- Never force-push `main`; use `--force-with-lease` only for an explicitly
  coordinated agent-owned branch.
- Do not use destructive recovery commands or delete branches/worktrees without
  exact authorization.

## Definition of Done

Work is complete only when:

- behavior and failure semantics are implemented;
- relevant tests and local quality gates pass;
- contract/version impact is explicit;
- planning/codebase docs match the new code fact;
- release notes are updated only when this task publishes a version;
- cross-repo handoff data is complete when applicable;
- the branch is pushed and the PR accurately reports validation and residual
  risk.
