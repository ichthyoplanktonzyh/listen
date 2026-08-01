# Cross-Repository Protocol

## Ownership

| Concern | Authority |
|---|---|
| User journey, UI states, discovery and acquisition UX | `listen-app` |
| Canonical OpenAPI and `.listenpkg` schemas | `listen-core` |
| Package validation, candidate installation and learning semantics | `listen-core` |
| Offline media preprocessing, provider adapters and package production | `listen-gen` |
| Gen process orchestration, cancellation and user-visible provenance | `listen-app` |
| Client parsing, package choice UX and final product assembly | `listen-app` |
| Core release artifact | `listen-core` |
| Pinned consumer baseline | `listen-app/backend.lock.json` |
| Hosted Catalog/Registry server | Undecided future role; do not infer an owner |

`ECOSYSTEM.md` records the shared context. Each repository's planning tree
contains only facts and work owned by that repository.

## App To Core Contract Request

An app-originated request must provide:

- user journey and visible outcome;
- information fields and operations;
- loading/empty/error/cancel/retry semantics;
- latency/frequency expectations;
- privacy/authority/provenance constraints;
- mock examples;
- compatibility deadline, if any.

If the owner authorizes Core to infer a request from current App behavior, the
work item and PR must label it `owner-approved synthetic request`. It is a
design input, not evidence that the App implementation has accepted or tested
the contract.

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

## App To Gen Orchestration Request

The App owns the process journey and asks Gen for the smallest stable CLI or
SDK interface needed to implement it. A request states media input authority,
provider/model choice, progress, cancellation, retry, output ownership,
temporary-file cleanup, and redacted failure semantics.

Gen responds with a versioned producer interface, deterministic fake/fixture
evidence, supported resource inventory, provenance rules, and exact Core
contract compatibility. Gen does not ask Core to expose provider/model flags or
ask the App to parse provider-native output.

Until `listen-gen` has an owner-selected remote and release process, local
checkout validation is development evidence only and is not a cross-repository
release handoff.

## Catalog And Registry Request

Discovery clients request Catalog Entries, Media Offers, Listings, and Releases
from the future Hosted Catalog/Registry role. The request must keep discovery,
playback, and lawful media acquisition distinct and must expose Publisher,
Review, and License Status independently.

No current repository owns that server. Do not put registry persistence,
moderation, federation, or hosted generation billing into Core, App, or Gen
without a separate owner decision.

## Rules

- No shared branch, source directory, or sibling-checkout dependency.
- No consumer fetch of moving Core or Gen `main`.
- No unpublished contract or local Gen prototype is treated as stable.
- A target-repository issue or PR is the authoritative work item; other
  repositories record only a link and their local integration state.
- Package Releases and release artifacts are immutable and identified by exact
  digests; Listings and human-readable tags may change.
- The owner resolves conflicts in scope, compatibility, release timing, and
  ownership of new hosted roles.
