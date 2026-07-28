# listen-app Agent Guide

This file is the mandatory entry point for every human or agent working in
`listen-app`. The repository owns the Flutter desktop product, UI/UX, client
state, backend compatibility layer, and final macOS application assembly.

## Ownership

- The product owner has final authority over product behavior, scope,
  compatibility, releases, and cross-repository decisions.
- Claude is the default implementation agent for this repository.
- Codex is the default implementation agent for `listen-core`.
- Agent ownership is a coordination rule, not an access-control mechanism.
  Do not edit `listen-core` from an app task unless the owner explicitly asks
  for a coordinated cross-repository change.
- The app drives feature discovery from user journeys and information needs;
  the core remains authoritative for canonical API files and backend behavior.

## First Read

Read these files before planning or changing code:

1. `.planning/STATE.md`
2. `.planning/PROJECT.md`
3. `.planning/MAINTENANCE.md`
4. `.planning/codebase/ARCHITECTURE.md`
5. `.planning/codebase/STRUCTURE.md`
6. `.planning/codebase/TESTING.md`
7. `.planning/CROSS_REPO.md` when backend data or behavior may change

Read only the active phase under `.planning/phases/`.

## Repository Responsibilities

`listen-app` owns:

- Flutter screens, widgets, navigation, interaction, accessibility, and visual
  language;
- client models, controllers, coordinators, state composition, and local
  playback behavior;
- client-side API transport and backward-compatible wire parsing;
- app settings, external-tool UX, native macOS integration, and embedded
  `third_party/fvp`;
- frontend fixtures, widget/controller/contract tests, app packaging, signing
  preparation, and packaged smoke verification;
- `backend.lock.json` and installation of immutable core artifacts;
- frontend roadmap, requirements, design decisions, and codebase documentation.

`listen-app` does not own:

- canonical OpenAPI or backend route definitions;
- Rust domain/application/persistence behavior;
- core release artifact contents or backend version declarations;
- production/research pipelines.

## Product and UI Rules

- Start from the user goal, journey, and information hierarchy before choosing
  an endpoint or implementation.
- UI must distinguish loading, empty, unavailable, degraded, failed, cancelled,
  and completed states honestly.
- Do not present heuristics, provider captions, projections, or model output as
  stronger evidence than the backend provenance supports.
- Playback position, current subtitle/word calculation, seeking, loops, and
  other high-frequency presentation state remain local.
- Widgets receive explicit data/callbacks where practical. Controllers own
  lifecycle and state transitions; services own I/O; widgets do not parse raw
  HTTP payloads.
- Keep UI language and learning language separate.
- Preserve keyboard, focus, screen-reader, reduced-motion, and responsive
  behavior when changing visible flows.
- Use the existing theme tokens in `lib/theme/`; do not introduce scattered
  color, spacing, typography, radius, breakpoint, or duration literals.
- Avoid milestone-coded names and oversized multi-domain files. Split a file
  before extending it when its responsibility is no longer clear.

## Frontend-Driven Cross-Repo Workflow

For a feature needing backend data or operations:

1. Define the user journey, UI states, required information, operations, and
   failure/cancellation semantics in the app phase.
2. Write a contract request using `.planning/CROSS_REPO.md`.
3. Hand the request to the core owner. Do not edit a local/sibling copy of
   `contracts/openapi/v1.yaml`.
4. Develop UI against typed fixtures or a mock while core designs and
   implements the canonical contract.
5. Consume an immutable core release by updating `backend.lock.json`.
6. Install and verify both artifacts.
7. Run contract tests, app tests, Release build, and packaged smoke as required.

The synchronization point is the released contract/runtime and lock update,
not a shared branch or moving core `main`.

## Backend Lock and Compatibility

- `backend.lock.json` pins one core repository, commit, contract version,
  runtime version, artifact URL, platform/architecture, and SHA-256.
- Never hand-edit generated/installed `.backend/` contents.
- Never commit `.backend/`, build output, downloaded archives, credentials, or
  local machine paths.
- Install and verify with:

  ```sh
  python3 tool/backend_artifacts.py install
  python3 tool/backend_artifacts.py verify
  ```

- For private releases provide `GITHUB_TOKEN`, or pass explicit local archives.
- The app validates startup API/contract/runtime compatibility before normal
  requests.
- Handwritten compatibility parsers remain authoritative. Generated clients
  may be introduced only after a documented spike passes typing, build, and
  migration gates. Generated files are never manually edited.

## Code Placement

- App composition: `lib/main.dart`
- Models and typed wire/domain views: `lib/models/`
- State machines and lifecycle: `lib/controllers/`
- API transport and endpoint adapters: `lib/services/api_service.dart`,
  `lib/services/api/`
- Global state composition: `lib/state/`
- Screens: `lib/screens/`
- Reusable UI: `lib/widgets/`
- Design tokens: `lib/theme/`
- Pure helpers: `lib/utils/`
- Native macOS integration: `macos/`
- Vendored player adapter: `third_party/fvp/`
- Artifact/release tooling: `tool/`
- Tests and pinned fixtures: `test/`

Models must not import widgets. Widgets must not launch processes or decode raw
wire maps. API part files must return typed client models at their public
boundary.

## Development and Validation

Run focused tests while iterating. Before review:

```sh
flutter pub get
flutter analyze --fatal-infos --fatal-warnings
flutter test
python3 -m unittest tool/test_backend_artifacts.py
```

Contract-facing changes require focused tests under `test/contract/`. Visible
UI changes require relevant widget/controller tests and manual evidence when
automated tests cannot prove layout or interaction. Backend lock or packaging
changes require:

```sh
python3 tool/backend_artifacts.py verify
tool/build-macos-release.sh
tool/verify-macos-release.sh
```

Do not require a sibling `listen-core` checkout for normal validation.
GitHub Actions may be unavailable because of account billing; record exact
local validation instead. Only the owner may authorize merge without CI.

## Planning and Documentation

The live `.planning` tree describes only frontend facts in this repository.

- `PROJECT.md`: durable app mission and product boundary
- `REQUIREMENTS.md`: testable frontend requirements
- `ROADMAP.md`: app-only phases and dependencies
- `STATE.md`: current app position, pinned core baseline, and next actions
- `codebase/`: current code-derived frontend architecture and maintenance facts
- `phases/`: active and completed frontend phases

Follow `.planning/MAINTENANCE.md`. Every commit-worthy change adds an exact
minute entry to `CHANGELOG.md`. Do not copy core planning into this repository.
Reference core facts by repository, release tag, commit, contract version, or
issue/PR URL.

## Git and Pull Requests

- Start with `git status --short --branch` and `git worktree list`.
- Preserve user-owned changes and unrelated work.
- Never implement directly on `main`.
- Start from current `origin/main` using the branch namespace required by the
  active development tool. Claude branches should use its configured namespace;
  Codex branches use `codex/`.
- Use one coherent branch and PR per task.
- Use Conventional Commit subjects and atomic commits.
- Inspect `git diff --check`, staged files, and `origin/main..HEAD` before push.
- PRs include user-visible outcome, UI states, scope/non-goals, validation,
  screenshots or interaction evidence when useful, compatibility, and the
  pinned core release when changed.
- Agents do not approve their own PRs or merge without explicit owner
  authorization.
- Never force-push `main`; do not use destructive recovery or cleanup commands
  without exact authorization.

## Definition of Done

Work is complete only when:

- the user journey and all meaningful UI states are implemented honestly;
- controller/widget/contract tests and strict analysis pass;
- accessibility and responsive behavior are considered;
- core dependency is either unchanged or immutably pinned and verified;
- planning/codebase docs match the new code fact;
- `CHANGELOG.md` is updated;
- the branch is pushed and the PR accurately reports evidence and residual
  risk.
