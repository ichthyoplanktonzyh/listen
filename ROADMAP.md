# Listen Roadmap

> Current stage: audio/video listening scope reduction, 2026-10-21.

[STATE.md](STATE.md) defines the selected implementation scope.
[MODEL.md](MODEL.md) retains the broader conceptual model; that breadth is not
an implementation checklist. Previous plans and task queues are not inherited.

## 1. Remove deferred implementations

Preserve the complete source baseline, then remove coaching, AI conversation,
independent reading/writing/speaking, and document-material processing from the
active product. Remove their exclusive dependencies and configuration across
App, Core, Gen, contracts, and development tooling. Preserve the text and speech
foundations required for audio/video listening.

Keep dedicated frozen recovery branches for the deferred implementations.
Restore a feature only after reconsidering its value and adapting it to the
then-current interfaces; do not continuously merge all experimental breadth
back into the listening baseline.

Data compatibility with the earlier development implementation is waived by
the owner. Use fresh isolated stores for validation, without resetting actual
learner data. Published releases remain unchanged.

## 2. Verify the smaller product

Validate audio/video production, installation/adoption, Workbench playback,
subtitles and help, explicit collection, source re-entry, and listening review.
Exercise unavailable resources, failure/retry, cancellation, reopening, and
child-process cleanup with deterministic providers. Verify the extracted
application as well as source tests.

Update current documentation to match the final interfaces and supported
journey. Removed features must not remain reachable through menus, settings,
background requests, or development defaults.

Keep the existing narrow FSRS listening queue and learner ratings. Remove
coach and upgrade policies without removing the scheduling of saved listening
items.

## 3. Deepen the listening journey

After the smaller baseline is accepted, close the actual gaps in material
readiness, contextual perceptual help, intentional collection, Personal Corpus
re-entry, and audio-first review. Choose each change from a concrete learner
failure in [JOURNEYS.md](JOURNEYS.md). Add no new learning channel or source
modality merely because the model can describe it.
