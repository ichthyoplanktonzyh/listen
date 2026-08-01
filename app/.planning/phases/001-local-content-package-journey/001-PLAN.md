# Plan

## Slice 1 — App-owned boundary

- Pin representative Core import and Gen machine-event fixtures.
- Define immutable package, receipt, resource, provenance, and event models.
- Record the Core and Gen contract requests.

## Slice 2 — Data and lifecycle

- Add the typed Core endpoint adapter and package repository.
- Add a service that launches `listen-gen` without a shell, parses NDJSON,
  owns temporary output, and supports cancellation.
- Add an immutable ViewModel state machine with stale-run guards and retry.

## Slice 3 — Learner surface

- Add a lean package journey screen reachable from Subtitle resources.
- Present lifecycle, provenance, warnings, receipt resources, and explicit
  candidate activation.
- Keep all existing subtitle and transcription actions intact.

## Validation

- Model and focused Core/Gen contract tests.
- Repository and process-service tests using local fakes only.
- Controller and widget tests for success, mismatch, cancellation, retry, and
  explicit activation.
- Strict analyzer, complete Flutter test suite, and backend artifact tool tests.
