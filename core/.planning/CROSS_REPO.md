# Cross-Repository Protocol

## Ownership

| Concern | Authority |
|---|---|
| User journey, UI states, information need | `listen-app` |
| Canonical OpenAPI/schema | `listen-core` |
| Backend implementation/runtime | `listen-core` |
| Client parsing and UX integration | `listen-app` |
| Core release artifact | `listen-core` |
| Pinned consumer baseline | `listen-app/backend.lock.json` |

## Contract Request

An app-originated request must provide:

- user journey and visible outcome;
- information fields and operations;
- loading/empty/error/cancel/retry semantics;
- latency/frequency expectations;
- privacy/authority/provenance constraints;
- mock examples;
- compatibility deadline, if any.

Core responds with:

- canonical method/path and schemas;
- compatibility classification and contract version;
- implementation and failure semantics;
- release tag, core commit, artifact URLs, and SHA-256;
- migration or deprecation notes.

App completes the handshake by committing:

- updated `backend.lock.json`;
- synced fixture manifest;
- client/contract tests;
- integration/build/smoke evidence.

## Rules

- No shared branch, source directory, or sibling-checkout dependency.
- No consumer fetch of moving core `main`.
- No unpublished contract is treated as stable.
- A target-repository issue or PR is the authoritative work item; the other
  repository records only a link and its local integration state.
- The owner resolves conflicts in scope, compatibility, and release timing.
