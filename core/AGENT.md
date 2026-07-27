# LLPlayerNext Agent Notes

This file is the fast memory card for coding agents working in this repository.
The canonical project memory lives under `.planning/`; use this file as the
entry point, not as a replacement for the planning system.

## First Read

Start every fresh session from these files:

1. `.planning/STATE.md` — current phase, open work, recent decisions.
2. `.planning/MAINTENANCE.md` — documentation ownership and update rules.
3. `.planning/codebase/ARCHITECTURE.md` — crate boundaries and data flow.
4. `.planning/codebase/STACK.md` — Rust/Flutter/Python stack and commands.
5. `.planning/codebase/DATA-MODEL.md` — persistence identity and learning data
   invariants.
6. `.planning/codebase/TESTING.md` — validation strategy and command scope.

Then read the active phase files under `.planning/phases/<phase>/` only as
needed. Completed phase folders are historical records and should stay frozen.

## Project Shape

LLPlayerNext has two coordinated tracks:

- Local production engine: Python-heavy, local-first tooling that creates
  accurate `.lltimeline.json` resources, including WordTimeline, ChunkTimeline,
  PhoneTimeline, artifacts, evaluation reports, and manual-review inputs.
- Lightweight consumer app: Flutter desktop UI plus Rust sidecar that reads
  timeline resources, plays media, highlights words/chunks, and supports
  learning workflows without bundling heavy research runtimes.

Core directories:

- `crates/` — Rust workspace libraries and the `api-http` binary.
- `apps/desktop/` — Flutter macOS desktop client.
- `scripts/` — test runner, contract validation, Python production/evaluation
  tooling.
- `contracts/` — shared API/resource contracts.
- `testdata/` — fixtures for subtitles, timelines, ASR, chunks, pronunciation,
  phonetic analysis, and generated test media.
- `.planning/` — project management source of truth.
- `docs/decisions/` — append-only ADRs.

Local QA media:

- `/Users/shadow/Desktop/视频` — user-provided real English media samples for
  manual or pipeline QA, especially speech/sound-line phases that need real
  listening material beyond repository fixtures.

## Architecture Rules

- Product form stays open. Optimize for better user experience and useful
  capability; do not turn a current phase scope, an existing UI container, or
  an architecture pattern into a permanent product prohibition. Hard limits
  come from real engineering conditions such as platform/audio behavior,
  latency, compute, storage, network/provider protocols, cost, privacy,
  security, data integrity, and compatibility.
- A shared deep module may unify facts, lifecycle, and difficult implementation
  without forcing every consumer to share one UI. In particular, content-
  anchored realtime conversation, a GPT-like open-chat surface, role play, and
  future conversation forms may present differently while reusing session/turn/
  audio/transcript facts, production-corpus ingestion, and review. A feature
  being out of scope for one phase means "not delivered now", not "forbidden".
- Keep dependency direction one-way: `domain` is the leaf foundation;
  `application` is the use-case orchestration layer; `api-http` adapts HTTP.
- `api-http` handlers must not directly call `speech-analysis`; route cross-crate
  workflows through `application`.
- Consumer app code must not depend on Python, PyTorch, WhisperX, MFA, or other
  heavy production runtimes.
- High-frequency playback position and current subtitle/word calculations stay
  local to the Flutter client, not round-tripped through HTTP.
- Learning tasks must receive an explicit bounded content selection or an
  explicit user-owned prompt. Current playback position may seed a selection,
  but must not silently turn into an unbounded task input.
- A fallback is valid only when it preserves the user's goal and authority
  semantics. Source snapshots preserve history; they do not substitute text for
  requested audio or mask a broken local-source resolver.
- LLTimeline JSON is versioned. Backward-compatible fields need defaults;
  incompatible changes require a schema/version decision.
- Vocabulary and learning assets outlive replaceable media/subtitle records.
  Do not casually cascade-delete durable learning history.
- Phase 2.18 established `LexicalEntry + LexicalUnit + LearningStatus`; Phase
  3.4.1 now explicitly migrates the status axis to a four-channel capability
  profile with evidence/projection/override separation (ADR 0015). Until its
  authority-switch slice lands, `LearningStatus` remains the runtime active
  path. Do not reintroduce `WordProfile` / `WordObservation`, and do not bypass
  the additive compatibility plan in the 3.4.x shared context.
- Phase 2.18 intentionally does not preserve historical compatibility for old
  SQLite data, old LLTimeline resources, old learning assets, or old API/UI
  adapters.
- Learning language and UI language are separate concepts. Language-specific
  behavior should enter through profiles/providers/capability checks and degrade
  cleanly.
- Single `.rs` or `.dart` implementation files over roughly 1500 lines, or files
  carrying more than one clear subdomain, should be split into modules before
  adding more feature work there. Mechanical splits do not need their own phase.

## Code Placement

- Domain types, IDs, timeline/resource contracts: `crates/domain/`.
- Use-case orchestration and repository/provider traits: `crates/application/`.
- SQLite migrations and repository implementations: `crates/persistence-sqlite/`.
- HTTP routes: `crates/api-http/src/routes/`, registered from `api-http`.
- SSE event schema: `crates/api-events/`.
- Subtitle parsing/tokenization: `crates/subtitle-core/`.
- Diagnosis rules: `crates/diagnosis-core/`.
- Speech/timing/chunk/phonetic analysis: `crates/speech-analysis/`.
- Flutter models/controllers/widgets: `apps/desktop/lib/`.
- Production pipeline work: `scripts/timeline-production/` or related scripts.
- New durable architecture decisions: new numbered files in `docs/decisions/`.

Follow existing module style before adding new abstractions. Keep changes scoped
to the requested behavior and surrounding ownership boundary.

## Algorithms And Metrics

- Existing project data, metrics, small smoke runs, and automatic labels are
  diagnostic signals, not truth by default.
- Algorithm, metric, and threshold changes should be grounded in published
  research, public corpus annotation conventions, reported tool baselines, or
  explicit manual product QA.
- Good evidence should unlock bold iteration. Do not stall merely because an
  input is not human gold, but always record the evidence class and intended use:
  `gold`, `silver_label`, `heuristic_proxy`, `manual_product_qa`, or `coverage`.
- Small samples are for validating the pipeline and exposing failure modes. Do
  not blindly tune product semantics to improve a tiny smoke score.
- When research or product evidence is missing for a user-facing algorithm
  change, add the research note, annotation plan, or experiment design before
  treating the change as a product claim.

## Toolchain Environment

Some shells used by agents do not load the user's interactive profile. Before
running Rust or Flutter commands directly, resolve the tool paths or export them.

Preferred project defaults:

```sh
export CARGO="${CARGO:-/opt/homebrew/opt/rustup/bin/cargo}"
export FLUTTER="${FLUTTER:-$HOME/.local/share/flutter/bin/flutter}"
export PATH="$(dirname "$CARGO"):$(dirname "$FLUTTER"):$PATH"
```

If those paths do not exist, fall back to `command -v cargo`, `$HOME/.cargo/bin/cargo`,
or `command -v flutter`.

Project scripts already know this rule:

- `scripts/test.sh` resolves `CARGO`, then `PATH`, then common cargo locations,
  and prepends cargo's directory to `PATH`.
- `scripts/lib-testing.sh` provides the same `resolve_cargo` and `resolve_flutter`
  helpers for milestone verification scripts.
- `scripts/build-macos-mvp.sh` defaults to `/opt/homebrew/opt/rustup/bin/cargo`
  and `$HOME/.local/share/flutter/bin/flutter`, then prepends both directories
  to `PATH`.

Use the project scripts when possible. For ad hoc commands such as `cargo test`,
`cargo clippy`, `flutter analyze`, or `flutter test`, set the environment first
or invoke the resolved binaries explicitly.

## Development Commands

Use focused commands while iterating, then broaden validation based on risk.

```sh
./scripts/test.sh --quick
./scripts/test.sh --full --strict
./scripts/validate-contracts.sh
cargo test --workspace
cargo clippy --workspace --all-targets
cd apps/desktop && flutter analyze
cd apps/desktop && flutter test
```

For low-memory local runs:

```sh
./scripts/test.sh --full --strict --low-memory
```

## Documentation Maintenance

Follow `.planning/MAINTENANCE.md` exactly:

- Every commit-worthy change should append `CHANGELOG.md` with an exact
  timestamp to the minute.
- `STATE.md` records current position and next steps, not a full changelog.
- Product direction changes update `PROJECT.md`, `REQUIREMENTS.md`, `ROADMAP.md`,
  and a timestamped summary in `STATE.md`.
- Architecture changes update relevant files in `.planning/codebase/` and may
  require a new ADR under `docs/decisions/`.
- Phase completion requires a closeout/summary, `STATE.md` update, and
  `MILESTONES.md` update when a milestone closes.
- Do not edit frozen completed phase documents; reference them from new phase
  context instead.
- Keep handoff notes sparse. Prefer `.planning/handoff/continue-here.md` and
  `STATE.md` for live memory.

## Phase Branch Workflow

- Every phase must use a dedicated phase branch and PR; do not implement,
  commit, or push phase work directly on `main`.
- Phase 3.19 is a subtraction-first product correction gate. Do not start or
  plan new product features until retained Phase 3.x journeys are usable,
  discoverable, owner-accepted, and the fake-requirement/fallback audit is
  complete. Existing code is not evidence that a feature should be kept.
- After the phase functionality is complete and validated, merge its dedicated
  branch through an approved PR so `main` remains the integrated record of
  completed phases.

## Git and Pull Request Workflow

These rules apply to every agent and every worktree.

### Safety and ownership

- Treat the user's existing changes, branches, commits, and worktrees as
  user-owned. Do not discard, overwrite, amend, rebase, delete, or clean them
  unless the user explicitly authorizes the exact action.
- Start every task with `git status --short --branch`, inspect relevant diffs,
  and check `git worktree list` before selecting or creating a branch.
- Fetching and pruning remote-tracking refs is allowed:
  `git fetch origin --prune`. Pruning remote-tracking refs is not permission to
  delete local branches or worktrees.
- Never use destructive broad commands such as `git reset --hard` or
  `git clean -fd` to recover a worktree.
- Never force-push `main`. Use `--force-with-lease`, never `--force`, only on an
  agent-owned feature branch after a necessary rebase, and disclose it first
  if anyone else may be using the branch.

### Branch and worktree discipline

- `main` is integration-only. Never implement, commit, or push task work
  directly on `main`.
- Start new work from the latest `origin/main`, not from a stale local branch:

  ```bash
  git fetch origin --prune
  git switch -c codex/<issue-or-phase>-<short-slug> origin/main
  ```

- Codex branches use `codex/`; another tool may use its required agent
  namespace. Keep the remainder short, descriptive, and tied to an issue or
  phase when one exists. Use one branch for one coherent PR.
- Use a dedicated worktree for concurrent tasks. Never reuse a branch already
  checked out in another worktree, and never let two agents edit the same files
  without explicit coordination.
- Do not merge `main` into a feature branch merely to update it. Rebase an
  agent-owned branch onto `origin/main` before review when safe. If the branch
  is shared or already under review, coordinate before rewriting it.
- After a PR is merged or closed, cleanup is a separate explicit operation.
  Verify the branch is integrated, the worktree is clean, and no agent is using
  it. Prefer `git worktree remove` and `git branch -d`; do not manually delete
  worktree metadata.

### Commit discipline

- Make small, atomic commits with one purpose. Do not mix unrelated formatting,
  refactors, generated files, or opportunistic fixes.
- Use Conventional Commit subjects:
  `feat(scope): ...`, `fix(scope): ...`, `refactor(scope): ...`,
  `test(scope): ...`, `docs(scope): ...`, or `chore(scope): ...`.
- Explain intent and non-obvious tradeoffs in the commit body. Reference the
  issue with `refs #N`; use `fixes #N`/`closes #N` only when the change actually
  completes it.
- Review `git diff --check`, `git diff --staged`, and the staged file list
  before committing. Never commit secrets, local credentials, build outputs,
  editor state, temporary files, or unrelated user changes.
- Do not amend commits already pushed to a shared branch unless coordination
  and history rewriting are explicit.

### Validation before push

- Run the smallest relevant formatter, linter, and tests during development,
  then run the required checks for the affected area before asking for review.
  Report exact commands and results; never claim a check passed if it was not
  run.
- Routine validation must not invoke ignored, paid, live-model, or
  credential-dependent tests.
- Before push, confirm the branch is based on current `origin/main`, inspect
  `git log --oneline origin/main..HEAD`, and verify the diff contains only the
  intended PR scope.

### Pull request discipline

- Push with an upstream and open a draft PR while work is in progress. Never
  open a PR from `main`, and never combine independent tasks into one PR.
- A PR must state the problem and user-visible outcome, implementation scope
  and non-goals, linked issue/phase, exact validation commands and results,
  relevant risks/migrations/rollback considerations, and UI evidence for
  visible changes.
- Keep PRs reviewable. Split changes when they span unrelated domains or cannot
  be understood as one coherent unit.
- Mark a PR ready only when the diff is self-reviewed, required local checks
  pass, the description is complete, and CI has finished successfully.
- Agents must not approve their own PRs and must not merge without explicit
  user authorization. Do not merge with unresolved review threads, failing or
  pending required checks, conflicts, or an out-of-date base.
- Use squash merge by default so `main` receives one coherent Conventional
  Commit per PR. Use another strategy only when the user explicitly chooses it
  for a documented reason.
- After merge, perform safe source-branch cleanup when authorized and update
  local `main` with `git pull --ff-only origin main`.

### CI infrastructure exception

- GitHub Actions is currently blocked by account billing/spending state; see
  issue `#75`. A job that never started is an infrastructure failure, not a
  passing check and not evidence that the code failed.
- An agent may document the outage, link `#75`, and provide exact local
  validation as temporary evidence. It must not silently ignore the red check,
  mark it successful, or decide to merge anyway.
- Only the user may explicitly authorize an exceptional merge while CI is
  unavailable. Record that exception and the local evidence in the PR.
- Once Actions can run again, the normal green-CI requirement applies
  immediately. Re-run the checks before merge.

### Target repository settings

- When the GitHub plan permits it, protect `main` with PR-only changes,
  required CI checks, required resolved conversations, no force pushes, and no
  branch deletion. Until then, agents must enforce the same policy manually.
- Enable automatic deletion of merged PR branches.
- Keep squash merge as the default merge method.
- Maintain a PR template matching the required PR content above.
- Avoid duplicate feature-branch CI runs from both `push` and `pull_request`.
  Use per-branch concurrency with `cancel-in-progress: true`.

## Before Finishing Work

- Check `git status --short` and avoid overwriting unrelated user changes.
- Run the smallest meaningful validation, and state what did or did not run.
- If behavior touches contracts, run `./scripts/validate-contracts.sh`.
- If behavior touches both Rust and Flutter, run the relevant Rust tests plus
  `flutter analyze`/`flutter test` or explain why not.
- Update planning docs only when the maintenance rules call for it; do not churn
  historical phase files.
