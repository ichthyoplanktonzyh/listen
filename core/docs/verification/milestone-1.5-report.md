# Milestone 1.5 Verification Report

Date: 2026-06-10
Release: 0.3.0
Platform: macOS Apple Silicon

## Delivered

- Schema v4 with durable word occurrences, status history, media availability,
  latest-effective context observations, and migration from v1-v3.
- User-selected status updates atomically persist profile, history, and source.
- Three status-driven vocabulary books with search, details, durable source
  sentences, status history, and return-to-playback behavior.
- Missing or archived media detaches live links while retaining snapshots.
- Re-registering matching media and subtitles restores live source links.
- Versioned JSON export/import supports empty-database restore and idempotent
  timestamp-based merge.

## Automated Evidence

- `cargo test --workspace`: domain, migration, persistence, diagnosis, and API
  tests, including v1-v3 migration, empty restore, repeated import, and a
  10,000-profile / 50,000-source query. The final persistence suite contains
  10 passing tests.
- `flutter analyze` and `flutter test`: desktop static analysis and widget
  coverage for dynamic books, status movement, detail/history, playable and
  unavailable sources, and transfer actions. The final Flutter suite contains
  16 passing tests.
- `scripts/validate-contracts.sh`: OpenAPI and client contract coverage.
- `scripts/verify-m15.sh`: full headless status/source/book/archive/export/
  empty-restore/repeated-import acceptance flow.
- `scripts/verify-m1.sh` and `scripts/verify-mvp.sh`: previous core and packaged
  macOS workflows remain functional.

## Acceptance Result

The vocabulary asset bundle remains fully searchable and restorable when the
original media and subtitle files are absent. Media archiving removes live
playback links without deleting vocabulary state, history, or source snapshots.

Final macOS artifact:

```text
dist/LLPlayerNext-macos-arm64.zip
SHA-256 28ef1bf923eb3e0764320f5f59c42a288c3b64b32a95369665d69bc7bed92052
```
