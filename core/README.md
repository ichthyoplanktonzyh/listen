# Listen Core

Rust semantic runtime and canonical executable-contract authority in the
Listen monorepo. It implements learning semantics, persistence, package
validation and provider-neutral application behavior behind local HTTP.

The complete product workflow is [DEVELOPMENT.md](../DEVELOPMENT.md). Project
model, shared language, journeys, active status and roadmap live at the root.
App and Gen integrate the current Core source in the same feature branch.
Formal releases build all modules from one clean commit with generated artifact
manifests. Published formats and user-data migrations remain explicit.

## Repository Layout

- `crates/domain/` — product records, values, and invariants;
- `crates/application/` — application behavior and repository/provider seams;
- `crates/persistence-sqlite/` — SQLite adapters and migrations;
- `crates/api-http/` — loopback HTTP composition and routes;
- `crates/api-events/` — event envelopes;
- `crates/local-runtime/` — local runtime mechanisms;
- `crates/*-provider/` — external provider adapters;
- `contracts/` — canonical wire and resource contracts;
- `scripts/` — validation, packaging, release, and retained production tooling;
- `docs/decisions/` — historical architectural decisions;
- `.planning/` — local implementation context and historical plans.

## Development

Fast Rust feedback:

```sh
./scripts/test.sh --rust
```

Strict validation:

```sh
./scripts/test.sh --rust --strict
./scripts/validate-contracts.sh
python3 -m unittest scripts/test_release_artifacts.py
```

Equivalent direct workspace checks:

```sh
cargo test --workspace --locked
cargo clippy --workspace --all-targets --locked -- -D warnings
cargo fmt --all -- --check
```

Paid, ignored, credential-dependent, and live-model tests run only when
explicitly authorized.

## Complete App Testing

For pinned-release startup, unreleased local-Core integration, logs, and manual
smoke coverage, follow
[docs/development/full-app-local-testing.md](docs/development/full-app-local-testing.md).

The local API binds only to loopback and reports its address and bearer token in
a structured startup handshake. Consumer-visible changes require contract
validation and a coordinated immutable release handoff.

## License

No license is granted for this repository unless a license file explicitly says
otherwise.
