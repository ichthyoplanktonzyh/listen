# Core implementation guide

Read [the root guide](../AGENT.md), [DEVELOPMENT.md](../DEVELOPMENT.md), and the
credential rules in `AGENTS.md`. `core/` is Listen's Rust semantic runtime and
canonical executable-contract authority within the same monorepo as App/Gen.

## Architecture

- Dependency direction is `domain <- application <- adapters`. HTTP handlers
  adapt requests and route use cases through `application`; they do not own
  domain/provider workflows or call analysis/provider crates directly.
- Persistence implements repository interfaces and does not define policy.
- Provider-specific protocols stay behind provider-neutral application traits.
- Long-running work has explicit progress, cancellation, failure and retry
  semantics. Learning records outlive replaceable media/resources.
- Heavy reusable material production belongs in `gen/`; Core remains a local,
  bounded and independently distributable runtime. Media word timing,
  pronunciation helpers, and application provider adapters remain Core concerns.
- Never log secrets, expose them through read APIs, or store them in ordinary
  settings/database fields when an OS secret store is required.
- Evidence, heuristics and model output retain provenance and do not claim
  stronger truth than their evidence supports.

## Contracts and integration

`contracts/` owns canonical OpenAPI, events and Content Package schemas. Change
contract, implementation, App adapters and Gen production in the same feature
branch when necessary. No prior component publication or cross-repository pin
handoff is required. Do not duplicate schema trees.

Preserve API/contract/runtime startup identities and published-format
compatibility. A monorepo does not erase existing user databases or package
versions: breaking durable-format changes require explicit migration.
For the current scope-reduction stage, the owner's fresh-store waiver in
[STATE.md](../STATE.md) overrides this migration requirement. Do not reset or
move a real learner's old database; use the branch-specific fresh store in STATE.md.
Published artifacts are immutable and never reuse a tag with different bytes.

Root tooling builds formal product artifacts from one clean commit and records
source identity and artifact hashes in generated output. Daily development can
build an identified current working-tree snapshot. Core scripts still run from
this directory; Git operations must account for the parent repository root.

## Verification

```sh
./scripts/test.sh --rust --strict
./scripts/validate-contracts.sh
python3 -m unittest scripts/test_release_artifacts.py
```

Additional native checks are `cargo test --workspace --locked`,
`cargo clippy --workspace --all-targets --locked -- -D warnings`, and
`cargo fmt --all -- --check`. Paid, ignored or live-model tests require explicit
owner authorization; normal tests use no real credentials.

Core tests cover migration/transaction atomicity, contract parity, provenance,
package validation, lifecycle and runtime cleanup. Interface changes also run
root `./dev test integration`; runtime assembly changes run package/verify/smoke
checks. Report actual local results; no checked-in Actions workflow runs them.

## Documentation

Shared product definitions, current scope, architecture, and workflow live at
the root. Keep executable contract notes, test-data instructions, and runtime
license notices beside their files. Do not restore old planning or ADR tasks.
