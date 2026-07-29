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
  migration-backup publication, and sidecar cancellation;
- local realtime contract fixtures for snapshot transcripts, chunk merging,
  loopback/keyless policy, plus sidecar pool-readiness and process reaping;
- OpenAPI method+path parity and structural validation;
- committed schema/example/fixture validation;
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
