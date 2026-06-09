# ADR 0001: Independent Clean-room Repository

- Status: Accepted
- Date: 2026-06-09

## Decision

Develop LLPlayerNext in `/Users/shadow/LLPlayerNext` as an independent Git
repository. Copy planning documents, but do not copy or translate LLPlayer
source code. LLPlayer may be observed to produce behavior baselines and test
scenarios.

No license is granted for LLPlayerNext during M0. Third-party dependencies and
their licenses must be recorded before distribution.

## Consequences

- The new implementation can choose its later licensing independently.
- Any reused source requires an explicit license review.
- Behavior compatibility must be demonstrated through independent tests and
  verification records.
