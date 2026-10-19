# M1 Verification Report

- Date: 2026-06-09
- Platform: macOS Apple Silicon
- Result: Passed

## Exit Gates

| Gate | Evidence | Result |
|---|---|---|
| Core services run without UI | `scripts/verify-m1.sh` starts the service and calls its API | Passed |
| Database migration | New database and historical v1-to-v2 tests | Passed |
| Idempotent media registration | Persistence and repeated HTTP registration tests compare stable IDs | Passed |
| State persistence | Progress and word-profile repository tests plus API smoke test | Passed |
| HTTP handlers contain no domain rules | Handlers map requests to transport-independent `AppServices` | Passed |
| Local-only API | Runtime binds `127.0.0.1:0`; protected routes require a bearer token | Passed |
| Client-callable contract | OpenAPI v1 and generated TypeScript experiment cover health, media, progress, and word profile | Passed |

## Commands

```text
cargo fmt --check
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
./scripts/validate-contracts.sh
./scripts/verify-m1.sh
flutter analyze
flutter test
git diff --check
```

All commands passed. Flutter reported that `media_kit_video` and
`media_kit_libs_macos_video` do not yet support Swift Package Manager on macOS;
the accepted M0 path continues to use CocoaPods and this remains a packaging
risk to monitor.

## Delivered Baseline

- Rust domain and transport-independent application services.
- SQLite schema version 2, transactional migrations, pre-migration backup, and
  repository implementations.
- Loopback Axum sidecar with startup handshake, random bearer token, graceful
  shutdown, structured errors, and versioned routes.
- OpenAPI v1, versioned event envelope/schema, and client type experiment.
- Architecture boundary, data identity, lifecycle, security, and recovery
  documentation.

M2 may now begin with subtitle parsing, normalization, tokenization, and
timeline behavior built on this baseline.
