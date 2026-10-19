# listen-core

`listen-core` is Listen's semantic runtime and canonical contract authority. It
implements language-material, learning-resource, personal-state, corpus, and
provider-neutral application behavior behind a loopback HTTP runtime.

Project semantics, shared language, learner journeys, development policy, and
the cross-repository roadmap are canonical in the
[`listen`](https://github.com/ichthyoplanktonzyh/listen) documentation
repository. The root compatibility pages in this repository point there for
older links.

[ECOSYSTEM.md](ECOSYSTEM.md) is only a compatibility navigation page for older
links. Planning files and historical decisions do not override the semantic
baseline above.

## Repository Role

This repository owns:

- the Rust domain, application behavior, persistence adapters, and loopback
  runtime;
- canonical OpenAPI, event, timeline, and Content Package contracts under
  `contracts/`;
- Content Package validation and candidate installation semantics;
- Personal Library, Personal Corpus, Learning Record, and language-capability
  semantics;
- immutable Core contract and runtime release artifacts.

It does not own Flutter experience design, reusable offline content-production
implementations, project governance, or the future multi-tenant Community And
Sync infrastructure. See the project
[context map](https://github.com/ichthyoplanktonzyh/listen/blob/main/CONTEXT-MAP.md)
for the complete authority map.

## Consumer Contract

`listen-app` consumes versioned HTTP and resource contracts plus immutable
runtime artifacts. It pins an exact Core commit and release; it does not depend
on this repository's moving `main` branch or a sibling checkout in production.

`listen-gen` consumes the canonical Content Package schema and produces
data-only package artifacts. Core validates those artifacts without depending
on Gen's provider implementations.

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
- `.planning/` — current repository-specific status and implementation plans.

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
