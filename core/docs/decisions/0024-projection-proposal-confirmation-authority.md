# ADR 0024: Projection Proposal and Confirmation Authority

Status: Accepted — 2026-07-18

## Context

ADR 0015 separated evidence, projection, override and effective assessment. ADR 0019 introduced the
first listening evidence projection before a product confirmation surface existed, so observation append
still wrote listening projection synchronously and non-listening upgrade confirmation retained a
transitional direct writer. Reading and speaking now have real channelized evidence; Writing and Personal
Expression have immutable learner attempts but no lexical-target writing confirmation.

Phase 3.17 must add correctable proposals without rewriting source facts or allowing a second writer to
compete for one capability slot.

## Decision

1. A channel algorithm consumes only that channel's qualified `LearningObservation` rows and returns a
   versioned `ProjectionProposal`. It never writes capability state.
2. Proposal and decision rows are append-only. Rebuild replays evidence into new/versioned proposals;
   observations, attempts, rubrics, judgments, adjudications, capability history and overrides are never
   rewritten.
3. One 3.17 repository operation atomically appends a confirmation decision and writes the proposal's
   conclusion into the projection slot plus capability history. Rejection writes only the decision.
4. User override is not mutated by confirmation and remains the effective read-time authority.
5. Reading v1 requires explicit unassisted word markings; listening v2 uses unassisted listening facts;
   speaking v1 requires two user-confirmed, unassisted constructed-production observations. No channel
   borrows another channel's evidence.
6. Writing is explicitly `insufficient_evidence` until a real lexical-target writing confirmation exists.
   Studio attempts, LLM judgments and `UserSentencePattern` attempts remain traceable supporting/source
   facts and do not manufacture lexical acquired.
7. LLM judgment is never a sole acquired event. Phase 3.17 v1 does not consume it as decisive evidence.
8. Cross-modal gaps are read models over effective assessed states. `unassessed` is not failure. Each
   candidate cites an observation/source reference and stores an immutable text snapshot for honest source
   loss degradation.

## Consequences

- Existing listening evidence projections remain historical state until a new proposal is confirmed;
  migration does not silently revoke or reinterpret them.
- Observation append now refreshes proposals, not projections. The old upgrade-suggestion confirmation is
  evidence only and cannot bypass the 3.17 confirmation gate.
- Schema v44 stores proposal/decision history. Algorithm upgrades append and supersede proposals instead of
  mutating old rows.
- `UserSentencePattern`, Hunting List, production corpus and embedding identities remain unchanged; no
  generic `FocusTarget` is introduced.

## Rejected

- Direct projection on observation append: removes the correction gate and creates hidden authority.
- Treating Studio self-assessment or LLM feedback as lexical acquired: target identity and qualification are
  insufficient.
- Filling every channel for completeness: turns missing evidence into fabricated capability.
- Generalizing Hunting List/pattern/review targets into one identity: the three-consumer razor still fails.
