# Project State

> Updated: 2026-10-22 (Asia/Shanghai).

## Current focus

Listen limits its active implementation to one audio/video listening
journey. The approved target opens a Source in MaterialWorkbench for native
playback before preparation, then adds qualified foundational learning
resources and on-demand help in the same workspace. The Learner can retain
whole Sources, save meaningful text-backed language, and return through the
Personal Corpus and listening review.

Desktop and mobile are now joint construction targets. The owner-approved
[devices and production design](docs/architecture/devices-and-production.md)
retains local prepared learning on both ends while allowing personal-computer
or remote production, with independently replaceable model providers.

Four implementations have moved to separate frozen recovery branches:

- AI conversation, including standalone and material-anchored voice sessions;
- independent reading, writing, and speaking activities, output assessment,
  shadowing recording/comparison, personal-expression training, the
  production corpus, and imported Anki text-flashcard activities;
- document/text material import, extraction, OCR, display, and document-to-audio
  production;
- learner coaching, cross-channel dashboards, material-fit policies, automatic
  capability-upgrade suggestions, review-derived hunting candidates, and
  learning recommendations.

Timed text, transcription, Structured Reading, translation, lookup, sound
analysis, and perceptual help remain foundations of listening. Removing a
reading activity does not remove the text representation of audio. Explicit
collection, source replay, learning facts, and listening review remain in scope.

Listening review retains the Core FSRS schedule, due queue, and explicit learner
ratings. Scheduling a saved listening item is distinct from coach dashboards,
cross-channel recommendations, or automatic capability-upgrade suggestions.

## Working baseline

The full implementation is preserved at `f01ba17e` on
`codex/preserve-before-listening-focus`. The listening scope reduction was
merged into `main` in [PR #8](https://github.com/ichthyoplanktonzyh/listen/pull/8),
merge commit `43bffca8`; `codex/listening-focus` retains its implementation
branch. Dedicated recovery branches use the reduced baseline:

| Deferred implementation | Branch |
|---|---|
| AI conversation | `codex/park-ai-conversation` |
| Other learning channels and output training | `codex/park-other-learning-channels` |
| Document materials | `codex/park-document-materials` |
| Learning coach and recommendations | `codex/park-learning-coach` |

These are frozen recovery points, not separately maintained products. Each
keeps its own feature and necessary dependencies; the complete earlier product
remains on the preservation branch.

The owner has explicitly waived data compatibility for this stage. Development
and validation target fresh isolated stores; no in-place upgrade of the earlier
broad implementation is required. This does not authorize scripts or tests to
reset the owner's actual local data.

The listening baseline uses `listen-listening.sqlite` as its default database
filename and does not probe or move the earlier `listen.sqlite`. An explicit
database override is still supported, but incompatible stores are rejected
instead of reset.

App, Core, and Gen remain one repository, currently assembled as one macOS
application. The published
[v0.7.0-dev.1 preview](https://github.com/ichthyoplanktonzyh/listen/releases/tag/v0.7.0-dev.1)
predates this reduction and remains immutable. Its source and artifact behavior
are separate from the current branch.

## Approved target and implementation gaps

The owner-approved resource policy now requires interactive qualified text,
exact sentence/word timing and media binding, and declared Sentence Translation
for foundational listening readiness. Deeper sound analysis, Sense Groups,
lookup/pronunciation, and explanations are on demand. [MODEL.md](MODEL.md#4-resource-policy-and-readiness)
owns the mapping to current resource types. [JOURNEYS.md](JOURNEYS.md) now owns
the full path from native viewing to preparation, partial readiness, learning,
whole-Source retention, text-backed saving, Corpus re-entry, and review.

These are approved semantics, not completed runtime changes. Existing package
acceptance and media/read/listen/watch projections do not prove the full new
foundational contract. Readiness enforcement, missing production/consumption
paths, the unified pre-production entry, and text-backed save gating still
need implementation verification against this journey. This documentation
change modifies no executable schema, provider, database, or UI behavior.

The accepted target journey is phone submission, computer production, automatic
material delivery, phone offline learning/collection/review, and private learning
records returning to the computer. Mixed production using vendor APIs follows;
remote production later allows preparing new materials with the personal
computer off. [ROADMAP.md](ROADMAP.md) owns execution order.

The supported runtime is still the macOS App/Core/Gen assembly in
[runtime architecture](docs/architecture/runtime.md). Mobile product assembly
and local Core embedding, paired-device persistent tasks, automatic delivery,
private-state replication, and remote production are not implemented. Existing
provider API calls do not imply those capabilities. The new documentation
records approved direction, not successful two-device acceptance.

The Personal Corpus journey still has depth gaps. Close them against the same
listening journey while building the shared desktop/mobile learning path.

Vocabulary capability state and interfaces still retain reading, listening,
speaking, and writing, but the scope reduction narrowed the vocabulary UI to
listening only. Restoring four-dimensional display, filtering, and manual
marking is a separately queued fix; it does not restore independent activities
or coach policies and is not implemented by this documentation change.

## Acceptance rules

Exercise the whole selected journey with deterministic production providers,
including unavailable input/executor, cancellation, retry, reconnect, local
readiness, offline learning, and duplicate-safe private-data exchange. Desktop
checks do not substitute for mobile execution or two-device acceptance.
Interface changes retain the Gen → Core → App integration gate; packaging
changes verify the extracted application outside the checkout. No live/paid
model calls or model downloads are implied by documenting these targets.
