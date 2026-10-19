# ADR 0029: HTTP–Persistence Execution Seam

Date: 2026-07-26

Status: Accepted

## Context

Application and SQLite repository interfaces are synchronous so transactions,
in-memory tests and aggregate invariants remain local. Calling them directly from
async Axum handlers can occupy Tokio workers. Rewriting all repository ports as
async would spread transport/runtime concerns through the application layer.

## Decision

`api-http::ApplicationExecutor` owns the single async-to-blocking seam:

- synchronous application work runs through `tokio::task::spawn_blocking`;
- mixed provider workflows are driven on a blocking worker with the captured
  runtime handle, keeping their synchronous repository sections off async workers;
- handlers receive only this executor, never raw `AppServices`;
- slow operations emit structured diagnostics;
- SQLite remains a single synchronous connection protected by a non-poisoning
  mutex, with transaction boundaries unchanged.

SSE remains a recoverable notification channel. Lag skips unavailable events and
continues with retained notifications; clients recover authoritative state through
existing reads.

## Alternatives

- A SQLite actor gives explicit queueing but turns every repository trait into a
  command protocol and complicates multi-step transactions.
- A connection pool improves read concurrency but changes transaction and
  in-memory-test semantics without evidence that local single-user write throughput
  needs it.
- Repository-internal `block_in_place` couples persistence to Tokio and fails on
  current-thread runtimes.

## Consequences

Transport responsiveness is testable without changing domain/application
interfaces. Blocking work is cancellable only at the awaiting request boundary;
once dispatched, the synchronous operation finishes normally. The blocking pool
is shared, so future saturation evidence may justify a bounded dedicated executor,
but handlers must continue using the same deep interface.
