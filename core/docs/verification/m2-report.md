# M2 Verification Report

- Date: 2026-06-09
- Result: Passed

## Exit Gates

| Gate | Evidence | Result |
|---|---|---|
| SRT and VTT import | Fixed fixture parser tests and HTTP smoke test | Passed |
| Common encodings and parse diagnostics | UTF-8/BOM/UTF-16 import tests and line-number error test | Passed |
| Complete persistence round trip | Application import, SQLite transaction, and HTTP read tests | Passed |
| Token display round trip | Punctuation, apostrophe, hyphen, number, Unicode, and newline test | Passed |
| Timeline gaps, overlap, boundary, offset, previous/next | `subtitle-core` timeline contract tests | Passed |
| Duplicate import idempotence | Application and HTTP smoke tests compare stable track IDs | Passed |
| Large timeline lookup | 2,100-cue timeline test | Passed |
| Existing database upgrade | Historical v1 and v2 upgrade to schema v3 | Passed |

## Commands

```text
cargo fmt --check
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
./scripts/validate-contracts.sh
./scripts/verify-m1.sh
tsc --noEmit contracts/generated/local-api-v1.ts
git diff --check
```

The complete normalized timeline is available through OpenAPI and the client
experiment, so M3 can keep current-cue calculation, seeking, and loop behavior
inside the desktop client.
