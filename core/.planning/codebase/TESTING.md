# Testing

## Required Local Gates

```sh
./scripts/test.sh --rust --strict
./scripts/validate-contracts.sh
cargo deny check
python3 -m unittest scripts/test_release_artifacts.py
```

## Test Layers

- crate unit tests for domain/application/provider logic;
- integration tests for SQLite, HTTP routes, lifecycle, and jobs;
- failure-injection tests for background-job writes, credential cleanup retry,
  LLTimeline resource/projection transaction rollback, migration-backup
  publication, semantic-embedding candidate download/validation/activation,
  syntax candidate activation/cleanup, and sidecar cancellation;
- semantic-embedding lifecycle tests cover restart cleanup, last-good
  retention, persisted candidate-failure provenance, final-path reload, and
  concurrent-upgrade rejection without downloading a live model;
- scripted foundation-preparation execution tests cover the exact three-resource
  plan, WordTimeline-to-Chunk dependency, independent SenseGroup execution, and
  completion without any SoundLine or phoneme-analysis job;
- preparation state tests cover cancellation CAS conflicts, input replacement,
  restart/retry preservation, derived A/B readiness, invalid-artifact rebuild,
  and stable plan identity after artifacts appear;
- timeline persistence tests cover atomic activate-if-absent for WordTimeline,
  PhoneTimeline, SenseGroup, and Prosody, including preservation of an existing
  active user selection and the WordTimeline legacy-timing invariant;
- local realtime contract fixtures for snapshot transcripts, chunk merging,
  loopback/keyless policy, plus sidecar pool-readiness and process reaping;
- OpenAPI method+path parity and structural validation;
- focused OpenAPI/router regression assertions that learner-recording
  transcription (`/v1/recording-transcriptions*`) and the transcription
  provider/model routes remain present while the removed whole-media
  `/v1/transcription/jobs*` surface stays absent;
- committed schema/example/fixture validation;
- Content Package v2 golden-carrier tests cover canonical release/resource/
  rendition identity, embedded/referenced/hybrid delivery, exact missing-blob
  plans, typed and opaque compatibility, explicit multilingual role rules, and
  deterministic release IDs;
- Content Package v2 adversarial tests cover path traversal and symlinks,
  undeclared files, non-canonical JSON, digest/size mismatch, bounded combined
  resource/rendition inventory, dependency cycles and invalid transitive role
  edges, missing strict provenance/quality fields, and payload extension shape;
- release-artifact tests assert the packaged v2 contract inventory exactly, so
  adding or removing any v2 schema/example requires an intentional inventory
  update;
- Learning Material domain/application tests cover text, media and mixed
  shapes, exact deterministic convergence, temporary/default-retained create,
  revision ownership, idempotent membership and path-free serialization;
- SQLite material tests cover v59 backfill, atomic initial/revision binding,
  rollback, restart reload, retained-list filtering, media-resolution and
  transactional synchronization with the legacy media membership projection;
- material HTTP/OpenAPI tests cover all eight operations, flat typed assets,
  omitted/null/false retain semantics, historical revision ownership, stable
  failures, route parity and generated-client identity;
- package-import HTTP tests cover the typed receipt, repeated-import
  idempotency, candidate-only active-selection invariant, exact-media mismatch,
  resource provenance/review status, and path/hash redaction; application tests
  cover honest unknown trust fields for opaque preserved resources;
- deterministic Python unit/contract tests;
- architecture debt regression tests and dependency policy checks;
- release archive safety, reproducibility, manifest, and SHA checks;
- runtime smoke outside the source tree.

## Rules

- Run focused tests while iterating, then boundary-appropriate gates.
- Normal tests never require real credentials or paid model calls.
- Contract changes always run contract validation.
- Persistence changes include migration and repository integration tests.
- Runtime/release changes include package, verify, and smoke.
- Report exact commands and failures. Zero-step GitHub Actions failure caused by
  billing is infrastructure, not a passing or failing code test.
