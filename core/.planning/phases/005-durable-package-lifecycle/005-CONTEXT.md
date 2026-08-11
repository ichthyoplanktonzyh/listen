# Durable Package Lifecycle Context

## Product Phase

This Core phase is the next repository slice of Product Alpha Phase 1,
Single-user Core Loop Alpha, defined in the canonical `listen` project. The
learner journey keeps Package Installation and Learning Edition Adoption as
distinct intents even when the App composes them behind one action.

## Starting Constraint

The durable lifecycle facts already exist behind `application::PackageLifecycleUseCases`
(from commit `db53cdf`) and the SQLite v60 adapter
(`crates/persistence-sqlite/src/package_lifecycle.rs`, from PR #131 merged as
`d435606`), but no HTTP surface consumes them: the routes, wire DTOs, error
contract, runtime composition and OpenAPI documentation are absent, so the
installed candidates and adopted Editions are unreachable for the App.

## Slice Boundary

- Expose exactly three fixed Bearer-protected operations through
  `crates/api-http/src/routes/package_lifecycle.rs`:
  - `POST /v1/materials/{material_id}/package-installations` (candidate-only
    Package Installation; fresh install and equal retry both return 200);
  - `GET /v1/materials/{material_id}/editions` (Edition Listing for the
    Material's actual current revision, application-deterministic order);
  - `PUT /v1/materials/{material_id}/edition-adoption` (explicit, idempotent
    Learning Edition Adoption preserving the original `adopted_at_ms`).
- Publish an additive OpenAPI `3.3.0` minor over `3.2.0` with the fixed
  operationIds `installMaterialPackage`, `listLearningEditions`,
  `adoptLearningEdition` and the five DTO schemas
  `InstallMaterialPackageRequest`, `AdoptLearningEditionRequest`,
  `LearningEditionDetails`, `LearningEditionResource`,
  `LearningEditionRendition`.
- Compose the real SQLite package lifecycle repository into every `AppServices`
  construction: `main.rs`, the in-crate test state, and the full-stack
  integration builder, so neither tests nor production fall into
  `DisabledPackageLifecycleRepository`.
- Define the typed error contract: 404 `not_found` envelope for unknown
  material/release installation; 422 `package_installation_invalid` for
  invalid carriers and mismatches; 409 `edition_adoption_conflict` for
  unadoptable states; 500 `package_lifecycle_failed` (retryable) for
  repository/internal failures. Responses and logs never leak paths, payloads,
  manifests, resource ids, digests, sizes, dependency edges, blob paths, or
  provider/model raw output.

## Compatibility

The HTTP surface is backward-compatible and additive, so contract `3.3.0`
keeps API generation `1` and runtime `0.7.0`. SQLite stays v60 with no new
migration; Content Package v1/v2 schema versions are unchanged; the existing
`/v1/media/{media_id}/content-packages/import` v1 route and its
candidate-only semantics are untouched; `listen-app/backend.lock.json` and the
root `CHANGELOG.md` are not modified.

## Non-goals

- no listen-app or listen-gen changes, App UI planning, or backend lock update;
- no raw text UI/session, RSS/Atom, hosted catalog/discovery, or package
  download/acquisition;
- no Gen process orchestration, automatic adoption, or automatic Material
  retention;
- no v1 resource activation refactor and no SQLite schema/migration change;
- no domain/application lifecycle interface refactor; if the fixed HTTP
  contract cannot be implemented on the existing application interface, the
  slice stops and reports the concrete blocker instead of extending C1;
- no release, tag, artifact, or GitHub release publication.

## Completion

`005-CONTEXT.md` + `005-PLAN.md` plus the code, contract and test facts this
slice lands. The phase stays active: consumer pinning, App client/UI, real
three-repository acceptance, and the contract `3.3.0` release/closeout remain
subsequent slices, so no `005-CLOSEOUT.md` is written here.
