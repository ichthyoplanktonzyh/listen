# ADR 0031: Versioned Repository Separation

Date: 2026-07-28

Status: Accepted

Supersedes in part: ADR 0014

## Context

The Flutter desktop client, Rust local backend, production pipeline, contracts,
runtime assets, tests and final macOS packaging currently share one repository.
That shape made early vertical slices inexpensive, but independent frontend and
backend work now contends on shared planning files, contracts, release scripts
and repository-wide validation. It also hides dependencies that must become
explicit before either side can advance independently.

The deployed product is not a conventional independently hosted frontend and
backend. Flutter starts an `api-http` loopback sidecar, reads a bearer-token
handshake from stdout, consumes REST and SSE, and ships the sidecar plus local
runtime executables inside one signed macOS application. Repository separation
therefore cannot make release compatibility implicit.

The existing OpenAPI parity test proves that implemented and documented `/v1`
paths have the same names. It does not by itself prove HTTP methods, request
schemas, response schemas, status codes or compatibility with a released
frontend. Frontend contract fixtures currently rely on repository-relative
paths. The desktop package also depends on the local `third_party/flutter/fvp`
fork and the root packaging scripts.

ADR 0014 chose handwritten Dart parsing plus shared fixtures because the
timeline compatibility parsers deliberately accept legacy and optional shapes.
That evidence remains valid. Repository separation changes the cost of
handwritten transport DTO drift, but it does not make legacy compatibility
semantics safe to generate automatically.

## Decision

### Repository ownership

Two source repositories will be created while preserving relevant Git history:

- `listen-core` owns Rust crates, backend and production tooling, persistence
  migrations, canonical OpenAPI/SSE/resource contracts, backend fixtures,
  runtime assets and backend artifact publication.
- `listen-app` owns the Flutter project at repository root, Flutter tests and
  design assets, the local `fvp` fork, frontend scenario fixtures, final macOS
  assembly, signing and product release.

The current `LLPlayerNext` repository remains the migration authority until the
exit gates pass. It is archived read-only only after the split repositories can
reproduce the validated product release.

### External seams

Repository separation exposes exactly three external seams:

1. **Contract release interface.** `listen-core` publishes an immutable,
   checksummed artifact containing OpenAPI, SSE/resource schemas, canonical
   examples and a contract manifest.
2. **Runtime bundle interface.** `listen-core` publishes a platform-specific,
   checksummed bundle containing `api-http`, required local runtime executables,
   manifests and third-party notices.
3. **Product assembly interface.** `listen-app` pins exact contract and runtime
   versions, verifies their hashes, assembles them with Flutter, and produces
   the signed application.

Source-tree layout, backend Cargo targets and CI job names are implementation
details, not parts of these interfaces.

The production HTTP adapter and the in-memory frontend transport adapter remain
the two justified adapters at the frontend transport seam. Stateless schema
mocking and stateful scenario fakes remain internal testing mechanisms rather
than new external interfaces.

### Contract authority and versioning

- Canonical contracts live in `listen-core`.
- Frontend-driven feature design proposes the contract change through a
  contract-first pull request to `listen-core`.
- `listen-app` never fetches a moving branch during a reproducible build. A
  committed lock file records the core repository commit, contract version,
  runtime version and SHA-256 digests.
- Contract updates reach `listen-app` as explicit dependency-update pull
  requests.
- The sidecar handshake and health response expose additive runtime and contract
  version fields. The frontend checks compatibility before normal requests.
- A contract release classifies compatibility. Additive optional behavior may
  increment the minor version; removal, required-field changes or semantic
  reinterpretation require a breaking release and an explicit migration.
- Backend CI validates the document, route/method parity, representative real
  responses and compatibility against the previous released contract.
- Frontend CI validates locked artifact hashes, typed consumer fixtures,
  compilation and integration against the locked runtime bundle.

### Dart client generation

ADR 0014 continues to govern handwritten parsers whose interface includes
intentional legacy tolerance, especially timeline and SSE compatibility
behavior. It no longer prohibits generated code at the cross-repository
transport seam.

The target shape is:

```text
generated or mechanically derived wire client
  -> explicit mapper
  -> handwritten UI/domain model
```

A pinned-generator spike must prove deterministic output, OpenAPI 3.1 nullable
and union handling, bearer configuration, useful static types, fixture
compatibility and maintainable diffs. Generated files are never edited by hand.
If the spike cannot meet those gates without widespread `dynamic` values or
custom-template ownership, the split proceeds with handwritten transport DTOs
plus generated schema/fixture guards. Full legacy model migration is not part of
repository separation.

### Release ownership

`listen-core` is responsible for producing a valid runtime bundle, not a final
GUI application. `listen-app` owns the final product release because it combines
Flutter, the player fork, entitlements, runtime bundle, signing and smoke tests.
A release manifest records both repository commits, the contract/runtime
versions and artifact hashes.

## Alternatives

### Keep the monorepo and use only worktrees

This avoids cross-repository coordination but retains contention on shared
contracts, planning, changelog and release infrastructure. It does not create
independent frontend/backend dependency updates, so it was rejected as the
long-term shape.

### Put contracts in a third repository

This creates another release and review hop without an independent owner or
validation implementation. The backend already implements and can enforce the
contract, so a third repository would be a shallow pass-through module.

### Let frontend CI consume the latest backend contract

This makes builds time-dependent: an unchanged frontend commit can fail after a
backend merge. It was rejected in favor of immutable artifacts and a committed
lock.

### Generate every Dart model during the split

This couples repository migration to a large compatibility rewrite and ignores
ADR 0014's evidence. It was rejected in favor of a bounded wire-layer spike.

### Let the backend repository publish the final application

This would require the backend to know Flutter layout, the player fork,
entitlements and signing. It puts product assembly behind the wrong interface
and was rejected.

## Consequences

- Most feature work will use two coordinated pull requests when it changes the
  contract, but implementation after a released contract can proceed in
  parallel.
- Contract and runtime versions become explicit product dependencies.
- Backend releases must publish artifacts before frontend integration can
  advance.
- Frontend development can use a locked real runtime, stateless schema mock or
  stateful in-memory adapter without a backend source checkout.
- Final release remains one coordinated product operation even though source
  development is split.
- Historical compatibility parsing remains local and testable instead of being
  silently tightened by generation.
- CI availability issue #75 remains infrastructure failure; local evidence
  cannot be relabeled as a successful required check.
