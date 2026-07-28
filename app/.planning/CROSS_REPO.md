# Cross-Repository Protocol

## App-Originated Contract Request

Before asking core for an endpoint or field, record:

- user journey and user-visible outcome;
- screen/component and all UI states;
- required fields, operations, filters and ordering;
- loading, empty, error, cancellation, retry and partial-result semantics;
- expected frequency, volume and latency;
- privacy, user authority and provenance requirements;
- representative mock request/response examples.

Submit the request to the target `listen-core` issue/PR. App planning records
only the link and local integration state.

## Core Handoff Expected

Core returns:

- canonical method/path and schemas;
- compatibility classification and contract version;
- failure/lifecycle semantics;
- release tag and exact core commit;
- contract/runtime artifact URLs and SHA-256;
- migration/deprecation notes.

## App Integration

1. Update `backend.lock.json`.
2. Install and verify artifacts.
3. Sync fixture manifest.
4. Implement typed parsing and UI behavior.
5. Run contract tests, full app tests, Release build and packaged smoke as needed.

No shared branch, source directory, sibling checkout, or moving-main dependency
is an accepted synchronization mechanism.
