# Project State

> Updated: 2026-10-21 (Asia/Shanghai).

## Current focus

Listen is reducing its active implementation to one audio/video listening
journey: acquire a Source, process and adopt a Learning Material, learn in the
MaterialWorkbench with contextual help, explicitly retain useful language,
and return through the Personal Corpus and listening review.

The owner has selected four implementations to move to separate branches:

- AI conversation, including standalone and material-anchored voice sessions;
- independent reading, writing, and speaking activities, output assessment,
  shadowing recording/comparison, personal-expression training, and the
  production corpus;
- document/text material import, extraction, OCR, display, and document-to-audio
  production;
- learner coaching, cross-channel dashboards, material-fit policies, automatic
  capability-upgrade suggestions, and learning recommendations.

Timed text, transcription, Structured Reading, translation, lookup, sound
analysis, and perceptual help remain foundations of listening. Removing a
reading activity does not remove the text representation of audio. Explicit
collection, source replay, learning facts, and listening review remain in scope.

Listening review retains the Core FSRS schedule, due queue, and explicit learner
ratings. Scheduling a saved listening item is distinct from coach dashboards,
cross-channel recommendations, or automatic capability-upgrade suggestions.

## Working baseline

The full implementation is preserved at `f01ba17e` on
`codex/preserve-before-listening-focus`. The scope reduction is developed on
`codex/listening-focus`; deferred implementations will have dedicated
`codex/park-*` branches. They are frozen recovery points, not separately
maintained products.

The owner has explicitly waived data compatibility for this stage. Development
and validation target fresh isolated stores; no in-place upgrade of the earlier
broad implementation is required. This does not authorize scripts or tests to
reset the owner's actual local data.

The listening baseline uses `listen-listening.sqlite` as its default database
filename and does not probe or move the earlier `listen.sqlite`. An explicit
database override is still supported, but incompatible stores are rejected
instead of reset.

App, Core, and Gen remain one repository and one macOS application. The
published [v0.7.0-dev.1 preview](https://github.com/ichthyoplanktonzyh/listen/releases/tag/v0.7.0-dev.1)
predates this reduction and remains immutable. Its source and artifact behavior
are separate from the current branch.

## Acceptance

Removing an entry point alone is insufficient: its exclusive runtime,
configuration, contracts, dependencies, and tests leave the active product too.
Shared listening foundations remain exercised by deterministic fixtures.

The smaller baseline must pass module checks and the Gen → Core → App integration
gate, and run from an extracted application outside the checkout. This scope
reduction does not claim that the Personal Corpus journey is already complete;
remaining depth gaps must be described against the listening journey.
