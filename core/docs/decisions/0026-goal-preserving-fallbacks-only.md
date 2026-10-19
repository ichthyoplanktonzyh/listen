# ADR 0026: Fallbacks Must Preserve The User Goal

Status: Accepted — 2026-07-20

## Context

Phase 3.x accumulated many “honest degradation” paths. Owner QA found that some protect data correctly but also
hide broken primary paths or substitute a different activity: a locally available Review source is labelled
unavailable, text snapshot is offered where audio review was requested, and optional provider absence is surfaced
even when its product value is unclear.

## Decision

1. Keep a fallback only when it preserves the same user goal, authority semantics and durable facts.
2. If the alternate path changes medium or learning goal, show an `UnavailableState` with cause and recovery action;
   the alternate may be offered as a separate explicit action, never as if the original task succeeded.
3. A SourceSnapshot preserves history and explanation. It does not make audio playback, speaking or source navigation
   available and must not be presented as a replacement for those actions.
4. Missing optional enhancement providers stay quiet unless the user invokes that enhancement. Core surfaces must
   not advertise configuration whose user value has not been established.
5. Every retained degradation path needs a real triggering condition, a user recovery action and a test. Paths that
   merely catch broad exceptions, mask broken local resolution or preserve unused product options are removed.

## Consequences

- Review source resolution must try the durable local media identity before declaring audio unavailable.
- Offline/provider states remain where they protect a real workflow, but “offline works” is not an independent product
  goal for every feature.
- Phase 3.19 will audit degradation paths by consumer and may delete paths that have no goal-preserving behavior.
