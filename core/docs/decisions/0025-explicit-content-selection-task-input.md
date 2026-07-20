# ADR 0025: Explicit Content Selection Is The Task Input

Status: Accepted — 2026-07-20

## Context

Owner QA showed that “play source”, Retelling, Personal Expression speaking, Review shadowing and the media-library
intensive CTA disagree about whether an activity applies to a whole document, the current sentence or an arbitrary
run of playback. Letting each surface infer its own unit makes audio run beyond the intended prompt, starts speaking
from the wrong sentence and makes “intensive” indistinguishable from opening ordinary playback.

## Decision

1. A `ContentDocument` is the browsable whole. A `ContentSelection` is the explicit bounded input to a learning
   task. `PlaybackContext` may seed a selection but never substitutes for it.
2. A selection is contiguous and carries immutable text plus time boundaries. Its granularity is a product choice:
   one sentence, several sentences or a passage are all valid; an unbounded “from here onward” range is not.
3. Listening and Reading may operate at document scope or selection scope. The active scope must be visible.
4. Speaking and Writing always receive an explicit selection or an explicit user-owned prompt. Defaults are
   scene-native: one sentence for Role Reply/pattern reuse, and a short multi-sentence passage for Retelling or
   reconstruction. Whole-document production requires an explicit user choice and must never be inferred.
5. Source playback inside a task is bounded to the selection. It stops or loops at the end according to an explicit
   control and never continues into unrelated content.
6. Opening “Intensive” must create or request a bounded selection and enter an intensive activity chooser. Opening
   “Extensive” may create a document-scoped listening session. Both may open the same document but cannot collapse
   into the same mode.
7. A TaskPrompt snapshots the selection and instruction at attempt start. Later player movement or source deletion
   does not rewrite the prompt or attempt history.

## Consequences

- Review, Speaking, Writing and Personal Expression must display their selection boundaries and return context.
- Existing source/range DTOs can be adapted incrementally; this ADR does not require one universal persisted target
  identity or merge Hunting, Review and UserSentencePattern assets.
- If no valid selection exists, a production task asks the user to choose one instead of guessing from the current
  cursor or silently using the rest of the document.

## Rejected

- Always use one sentence: too small for retelling, reconstruction and paragraph-level reading.
- Always use the whole document: unsuitable for most speaking/writing tasks and impossible to replay precisely.
- Let each surface infer from current playback: hidden, unstable and already contradicted by owner QA.
