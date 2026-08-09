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

Worker is a role, not a model name. The configured Worker may currently be
DeepSeek V4 Flash through OpenCode and later be GPT-5.6 Luna or another suitable
implementation agent. The Supervisor selects it by task complexity, reliability,
latency, and cost; the owner may explicitly override the choice.

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

An authority repository publishes a versioned, preferably backward-compatible
boundary. Consumers adopt it asynchronously through exact versions and
immutable artifacts. Repositories do not need synchronized merges.

### Cross-repository vertical slice

A user outcome crosses existing boundaries and therefore requires coordinated
changes. The Supervisor builds a dependency DAG, serializes shared seams, runs
independent repository work in parallel when ownership does not overlap, and
closes with a real cross-repository round trip.

A vertical slice does not mean all three repositories must change. It means the
smallest complete outcome determines the coordination scope.

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

Parallel Workers must have non-overlapping ownership. Shared contracts and
shared files are changed serially. Workers preserve other edits and adapt to
concurrent work rather than reverting it.

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
incomplete handoffs are narrowed and returned to a Worker; they are not silently
finished under a different execution model.

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
