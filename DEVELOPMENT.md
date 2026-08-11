# Development And Maintenance

> Status: owner-approved operating model, 2026-08-09.

Listen is a single-owner, multi-repository project developed with a Supervisor
and replaceable implementation Workers.

## Roles

### Product Owner

The owner decides product meaning, priorities, compatibility policy, and genuine
product tradeoffs. The owner may explicitly override the selected Worker or any
technical decision.

### Supervisor

The Supervisor is the technical and delivery lead. It owns requirements,
architecture, code-derived diagnosis, task decomposition, dependency planning,
Worker selection, review of actual diffs, independent validation, documentation,
commits, pull requests, merges, and releases within an approved work scope.

The Supervisor stops for owner input only when a product choice is genuinely
missing, the requested scope must materially expand, or an external action is
irreversible and was not authorized.

### Implementation Worker

Worker is a role, not a model name or provider. A Worker may be a native Codex
subagent, an agent reached through OpenCode, or another configured implementation
runtime. The Supervisor may create and select Workers by task complexity,
reliability, latency, cost, and tool compatibility; the owner may explicitly
override the choice.

The current default Worker is the native `luna_max_coder`, using GPT-5.6 Luna
with `max` reasoning effort. DeepSeek V4 Flash through OpenCode remains an
approved alternative. These are execution defaults rather than product or
repository architecture and may be replaced as models and runtimes evolve.

The Supervisor may use different Worker types in one deliverable when ownership
does not overlap. The selected runtime is stated in each assignment and handoff;
changing it does not require owner approval unless it also changes product scope,
compatibility policy, cost authorization, or an irreversible external action.

Source code, tests, schemas, migrations, scripts, and runtime configuration are
implemented by Workers. The Supervisor directly owns prose documentation and
delivery coordination. A Worker does not commit, push, publish, or silently
expand product scope.

Auto mode is allowed only for a bounded task whose repository, file ownership,
acceptance criteria, forbidden actions, and validation commands are explicit.
Ambiguous work returns to the Supervisor for refinement first.

## Work modes

Use the smallest independently verifiable and deliverable scope.

### Repository-local slice

One repository changes while its published boundaries remain compatible. It is
developed, tested, merged, and released independently. Examples include Core
internals, a Gen provider behind an existing producer contract, or App UX that
requires no new backend data.

### Contract-evolution slice

An authority repository publishes a versioned boundary. Before the first
maintained product baseline, it may make a coordinated breaking cutover under
the policy below. After that baseline, compatibility and migration are explicit
release decisions. Consumers always adopt exact versions and immutable
artifacts; repositories do not consume moving branches in production.

### Cross-repository vertical slice

A user outcome crosses existing boundaries and therefore requires coordinated
changes. The Supervisor builds a dependency DAG, serializes shared seams, runs
independent repository work in parallel when ownership does not overlap, and
closes with a real cross-repository round trip.

A vertical slice does not mean all three repositories must change. It means the
smallest complete outcome determines the coordination scope.

## Pre-Phase-1 evolution and compatibility

Listen currently has no external users and no maintained public compatibility
baseline. Until the Phase 1 stack release is accepted, internal App interfaces,
Core APIs and persistence for unfinished Phase 1 concepts, Gen protocols, test
fixtures, and development data may be replaced directly when the replacement
better expresses the accepted product model.

Do not add compatibility adapters, dual reads or writes, deprecated paths,
feature flags, or migrations solely to preserve pre-Phase-1 behavior. Prefer
one coordinated cutover and remove the displaced path. Local test and
development data may be reset unless the owner explicitly identifies a data set
that must survive; such a data set receives one bounded migration rather than a
permanent compatibility layer.

This freedom does not relax contract or release discipline:

- all affected repositories must agree on the exact new contract and prove a
  real round trip before the cutover is accepted;
- already published tags, schemas, packages, and binary artifacts remain
  immutable, even when the active stack no longer supports them;
- a changed wire or package meaning receives a new version or schema identity
  rather than silently reinterpreting a published identity;
- external format and protocol standards, source fidelity, provenance, learner
  data ownership, and security invariants still apply;
- unrelated learner behavior is not changed merely because compatibility is
  inexpensive.

The accepted Phase 1 stack release becomes Listen's first maintained
compatibility baseline. Any later breaking change must state its supported
upgrade path, data migration, and consumer impact explicitly.

## Worker assignment contract

Every implementation assignment states:

- objective and user-visible or contract outcome;
- absolute repository path;
- exclusive file or module ownership;
- relevant facts and interfaces;
- acceptance and failure semantics;
- non-goals and forbidden actions;
- exact local validation;
- required handoff evidence.

Parallel Workers, including Workers using different models or runtimes, must
have non-overlapping ownership. Shared contracts and shared files are changed
serially. Workers preserve other edits and adapt to concurrent work rather than
reverting it.

## Review and validation

Completion requires three evidence layers when applicable:

1. the Worker runs focused tests and static checks for its owned change;
2. the Supervisor reviews the actual diff and independently reruns repository
   quality gates;
3. a boundary change runs a real cross-repository contract probe, round trip,
   or end-to-end journey.

Generated output, a Worker summary, or a green focused test alone is not review.
No paid model or live credential test runs unless explicitly authorized.

The Supervisor waits for Worker events rather than repeatedly polling. Failed or
incomplete handoffs are narrowed and returned or reassigned. A reassignment keeps
the original scope and ownership explicit, records the execution-model change,
and receives the same independent review and validation.

## Git and releases

- Each repository has independent branches, commits, pull requests, versions,
  quality gates, and releases.
- Use one coherent branch and pull request per repository per deliverable.
- Use Conventional Commit subjects and review the exact staged scope.
- Merge cross-repository work in dependency order.
- Consumers pin immutable contracts and artifacts; production never depends on
  a sibling checkout or moving `main`.
- Sibling checkouts are allowed only for explicit development integration tests.
- Release only when a consumable boundary or product artifact exists; do not
  mechanically publish every internal refactor.
- Never overwrite a published tag or artifact.

## Documentation and tracking

Stable product truth belongs in this repository. Code facts, executable
contracts, and repository-local decisions stay in their owning code repository.
Tasks and transient plans belong in issues, a project board, or the Supervisor's
working plan. `ROADMAP.md` contains outcomes and exit criteria; `STATE.md`
contains only the current project position and next decision.

## Definition of done

A slice is done only when behavior and failure semantics are implemented,
relevant gates pass independently, compatibility and migration impact are
explicit, canonical documentation matches the result, cross-repository evidence
exists when needed, and the intended branches/PRs/releases have been delivered.
