# Cross-Repository Protocol

## Request Authority

Cross-repository work starts from an app-owned user journey. A request written
before a separate App implementation validates that journey must be labeled
**owner-approved synthetic request** when the product owner has authorized the
simulation. The label grants planning authority; it is not evidence that the
App or an end-to-end flow already works.

## Common Request Content

Before asking another component for data or operations, record:

- user journey and user-visible outcome;
- screen/component and all UI states;
- required fields, operations, filters and ordering;
- loading, empty, error, cancellation, retry and partial-result semantics;
- expected frequency, volume and latency;
- privacy, user authority and provenance requirements;
- ownership and cleanup of media, package, credentials, processes, and
  temporary files;
- compatibility, versioning, idempotency, and migration expectations;
- representative mock request/response examples.

App planning records only the stable request link and local integration state,
not another repository's implementation plan.

## Core Contract Request

Submit canonical local API, validation, persistence, package-import,
active-selection, and learning-record requests to `listen-core`. Do not edit a
local or sibling copy of `contracts/openapi/v1.yaml`.

## Core Handoff Expected

Core returns:

- canonical method/path and schemas;
- compatibility classification and contract version;
- failure/lifecycle semantics;
- release tag and exact core commit;
- contract/runtime artifact URLs and SHA-256;
- migration/deprecation notes.

Core package import must state fingerprint and Timeline Compatibility rules,
atomicity and idempotency, candidate-versus-active behavior, size and path
authority limits, and stable redacted failures.

## Generator Request

Submit media preprocessing, provider, offline-generation, deterministic package
output, progress, cancellation, and CLI/protocol requests to `listen-gen`.
Record:

- executable and protocol compatibility;
- provider configuration and credential authority;
- progress and cancellation semantics, including child-process cleanup;
- input-media and output-package ownership;
- deterministic, redacted, dependency-closed output requirements;
- fake or fixture validation that does not spend paid model credit.

Gen returns a versioned CLI or protocol, supported package contract version,
failure and exit semantics, deterministic fixtures, and release/install
instructions. App code must not depend on Gen internals or import its Python
modules directly.

## Catalog or Registry Request

Submit discovery, Catalog Channel and Entry, Media Offer, Package Listing and
Release, publisher, signature, rating, report, and update requests to the future
Hosted Catalog/Registry owner. That service and its repository ownership are
not yet decided; do not assign them implicitly to App, Core, or Gen.

The request must keep discovery, playback, and lawful media acquisition
separate, especially for YouTube. It must define pagination, caching, offline
and unavailable states, mutable metadata versus immutable digests, trust and
license provenance, and direct local-import behavior when the service is absent.

## App Integration

1. Implement against typed app-owned fixtures or a mock.
2. Receive immutable releases or versioned protocols from the owning component.
3. For Core changes, update `backend.lock.json` and verify the artifact.
4. Sync fixture manifests and compatibility expectations.
5. Implement typed parsing, process/service boundaries, controllers, and honest
   UI behavior.
6. Run focused contract tests, full app tests, Release build, and packaged smoke
   as needed.

No shared branch, source directory, sibling checkout, moving-main dependency,
or direct import of Gen internals is an accepted synchronization mechanism.
