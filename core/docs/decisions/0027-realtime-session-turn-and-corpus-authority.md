# ADR 0027: Realtime Session, Turn, And Corpus Authority Stay Separate

Status: Accepted — 2026-07-22

## Context

Phase 3.15.7 established provider-neutral session and turn facts, but its first Flutter surface recorded one continuous
microphone file and converted the entire conversation into `learner-1` at Finish. Real Qwen QA in Issue #7 showed
that this loses earlier rounds and also makes a local transcription failure look like failure of the whole provider
conversation.

## Decision

1. A `ConversationSession` describes the provider conversation lifecycle. `completed` means the user intentionally
   ended a working conversation after its provider drain; it does not claim every learner turn produced local text.
2. A `ConversationTurn` is one locally sequenced learner or assistant item. Local sequence is identity and ordering;
   provider item/response IDs are opaque correlation only.
3. Learner and assistant turns both belong to durable conversation history. Only a learner turn with its own local
   recording and completed local Whisper transcript becomes authoritative learner output.
4. Production Corpus is a rebuildable learner-output projection: it receives finalized learner turns only. Assistant,
   provider-caption-only, interrupted and failed turns never enter it. Existing Gap Review remains a read model over
   that projection.
5. One learner turn's local transcription failure is recorded on that turn and does not erase or downgrade other
   successful turns or convert an otherwise completed provider session into failed.
6. Free conversation and topic-anchored conversation reuse these facts. Topic context is explicit and bounded;
   surface mode is not inferred from playback position.

## Consequences

- The client needs a turn-assembly module rather than session-level transcript strings.
- Session finish drains provider output and closes capture; per-turn local transcription may report mixed outcomes.
- Provider adapters remain unchanged by product surface and corpus semantics.
- Tests must cover duplicate/out-of-order events, barge-in, partial local-ASR failure, learner-only projection and
  deterministic ordered history.

## Rejected

- One document per whole conversation: assistant text would contaminate learner production and a failed tail would
  invalidate earlier output.
- Provider item ID as domain identity: providers differ and may omit or reuse correlation events.
- Session failed when any local ASR fails: it conflates transport experience with downstream learner-output authority.

