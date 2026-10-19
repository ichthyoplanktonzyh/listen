# Durable Package Lifecycle Plan (C2b)

## Objective

Wire the already-merged `application::PackageLifecycleUseCases` (commit
`db53cdf`) and the SQLite v60 adapter (PR #131, merge `d435606`) into the real
`api-http` runtime and publish a precise, additive, App-consumable OpenAPI
`3.3.0` contract. The three intents stay separate: candidate-only Package
Installation, Edition Listing, and explicit idempotent Learning Edition
Adoption.

## Steps

1. **Fixed HTTP routes** (`crates/api-http/src/routes/package_lifecycle.rs`)
   - `POST /v1/materials/{material_id}/package-installations` with
     `InstallMaterialPackageRequest { package_path }`; blank path rejected;
     delegates to `services.package_lifecycle().install_for_material(...)`;
     200 + `LearningEditionDetails` for fresh install and equal retry;
     candidate-only.
   - `GET /v1/materials/{material_id}/editions` → `list_editions(...)` →
     200 + `LearningEditionDetails[]` for the actual current revision.
   - `PUT /v1/materials/{material_id}/edition-adoption` with
     `AdoptLearningEditionRequest { release_id }` → `adopt_for_material(...)`
     → 200 + adopted `LearningEditionDetails`; idempotent, original
     `adopted_at_ms` preserved. The handler never builds adoption plans,
     selects resources, or touches repositories directly.
2. **Wire DTOs**: `LearningEditionDetails` / `LearningEditionResource` /
   `LearningEditionRendition` with explicit `From<application::PackageEditionView>`
   conversions and explicit enum string mappings (`base|assistance`,
   `available|missing|opaque`, `unreviewed|machine_checked|human_reviewed`).
3. **Error contract**:
   - unknown material / release installation → 404 existing `not_found` envelope;
   - installation invalid/incompatible → 422 `package_installation_invalid`,
     public message `package release is invalid or incompatible`, retryable
     false;
   - adoption conflict (stale revision, missing required resource, broken
     closure, exclusive ambiguity) → 409 `edition_adoption_conflict`, public
     message `learning edition cannot be adopted`, retryable false;
   - repository/internal failure → 500 `package_lifecycle_failed`, public
     message `local package lifecycle operation failed`, retryable true;
   - no path/payload/manifest/resource-id leakage in bodies or logs;
   - empty/malformed `material_id`/`release_id` keep the existing 400 typed
     input error path.
4. **Runtime composition**: add `.with_package_lifecycle_repository(...)` in
   `main.rs`, `crates/api-http/src/tests/mod.rs`, and
   `crates/api-http/tests/api_integration_test.rs`; audit every `AppServices`
   construction so tests and production never use
   `DisabledPackageLifecycleRepository`.
5. **Router**: register the three routes in the material/package lifecycle
   route group through `ApplicationExecutor`; HTTP layer never calls the
   content-package inspector, reads/writes SQLite, interprets manifests,
   selects active resources, changes Material membership, or auto-retains.
6. **OpenAPI 3.3.0** (`contracts/openapi/v1.yaml`,
   `crates/api-http/src/lib.rs` `CONTRACT_VERSION`, `tests/openapi.rs`
   snapshot, `contracts/generated/local-api-v1.ts`,
   `scripts/validate-contracts.sh`): fixed operationIds, five new schemas,
   generated-client method signatures, privacy gates; API generation stays 1,
   runtime 0.7.0, SQLite v60, Content Package schema versions unchanged; v1
   import route and backend lock untouched; no CHANGELOG edit.
7. **Focused tests** (`crates/api-http/src/tests/package_lifecycle.rs`):
   exact install DTO/enums/no-leak; delete carrier then list/adopt still work
   (durable SQLite facts/payloads); equal retry idempotent and candidate-only;
   two editions list/switch adoption semantics; repeat adoption preserves
   `adopted_at_ms`; file DB restart keeps editions and adoption evidence;
   typed 404s; 422/409 codes with body+log redaction; method+path parity;
   DTO/enum pinning. Fixtures use deterministic local v2 carriers bound to the
   HTTP-created material/revision; identities come from canonical v2
   computation, never fake fixed release ids; temp files are cleaned; no
   network, credential, paid model, or real inference.
8. **Planning convergence**: record in 005 CONTEXT/PLAN, phases README,
   STATE, ROADMAP, REQUIREMENTS that application/domain lifecycle landed via
   `db53cdf`, SQLite v60 via PR #131/`d435606`, and that this slice is the
   HTTP/OpenAPI/runtime composition with contract `3.3.0` still unpublished.

## Verification

Run and report:
`cargo fmt --all -- --check`,
`cargo test -p domain --locked package_lifecycle`,
`cargo test -p application --locked package_lifecycle`,
`cargo test -p persistence-sqlite --locked package_lifecycle`,
`cargo test -p persistence-sqlite --locked migrations`,
`cargo test -p api-http --locked package_lifecycle`,
`cargo test -p api-http --locked openapi`,
`cargo test -p api-http --locked`,
`./scripts/validate-contracts.sh`,
`cargo clippy -p domain -p application -p persistence-sqlite -p api-http --all-targets --locked -- -D warnings`,
`cargo check --workspace --locked`,
`./scripts/test.sh --rust --strict`,
`git diff --check`,
`git status --short`.

## Definition of Done

- The three fixed routes, DTOs, error codes, runtime wiring, OpenAPI 3.3.0
  artifacts, focused tests and planning docs above are implemented and pass.
- No commit, no push, no PR, no tag/release is created by this slice.
