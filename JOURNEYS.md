# Learner Journeys

This document defines the current audio/video listening journey.
[STATE.md](STATE.md) owns implementation scope and [ROADMAP.md](ROADMAP.md)
owns execution priority. [MODEL.md](MODEL.md) describes the broader domain;
code, contracts, and executable tests establish what the build supports.

The Learner experiences one path through content acquisition, material
production, the MaterialWorkbench, and the Personal Corpus. Internal provider
execution and package construction do not become extra learner tasks.

Desktop and mobile are joint targets. The cross-device journey below is
approved direction, not a claim of implemented mobile or remote support; see
the [devices and production design](docs/architecture/devices-and-production.md).

## Bring or discover audio/video

1. Choose a local audio/video file or acquire an audio/video Source through an
   available discovery path. Standalone document/text material is outside the
   current implementation scope; accompanying subtitles are listening inputs.
2. Record Source identity, authorization, binding, and availability honestly.
   Acquisition, preview, retention, and redistribution are separate facts.
3. The Learner can preview a Raw Source and choose to prepare it for learning.
   Preview does not silently establish learning or acquisition evidence.

## Prepare a Learning Material

1. App submits the authorized Source, language declaration, target material
   contract, and reusable resources as a durable Material Production Task to
   the chosen executor. Source acquisition establishes exact input identity
   and revision binding before derivation.
2. Gen transcribes and aligns media and prepares compatible text, translation,
   and sound resources. Structured Reading and stable Text Anchors remain
   necessary for timed text, lookup, help, and precise saved references.
3. Show progress, missing prerequisites, unavailable evidence, cancellation,
   failure, and retry as production states. Do not fabricate timing, speech
   evidence, or readiness when required inputs are absent.
4. Gen returns a versioned, provenance-bearing Content Package. Core validates
   and installs it; explicit adoption selects the coherent material composition.
5. The MaterialWorkbench consumes the adopted composition through Core. It does
   not interpret provider output as canonical material.

## Ask another device to prepare a material

1. On a phone or computer, share a supported audio/video link or choose a local
   file, then request preparation using the configured Production Executor and
   Model Provider choices. A vendor API alone is not a remote executor.
2. Submit links as source references; transfer device-local files when the
   executor cannot otherwise obtain the authorized bytes. Show input-access
   failures honestly. If a personal computer is offline, retain the request
   and show that it is waiting for that computer.
3. Leave the submission page without losing the task. The selected computer
   or remote executor processes it, reports progress, and supports retry or
   cancellation. Reconnecting or submitting again does not duplicate effects.
4. Deliver the produced material automatically through the configured device
   exchange path. Distinguish production success from transfer, validation,
   and local readiness. Core validation and explicit adoption still apply;
   new results never silently replace an adopted composition.
5. When all required resources are locally verified, offer learning in the
   same Workbench. A completion notification is a convenience: reopening the
   App also discovers and receives completed results. Background delivery is
   subject to platform scheduling, not a promise of immediate availability.
6. Disconnect the phone and turn off the production computer. Learn, collect,
   browse the Personal Corpus, and review using prepared local resources.
   Additional inference requests may wait without blocking that experience.
7. Reconnect and exchange private learning records. The computer can reopen
   the retained Slice and relevant history in the same Material Revision.
   Duplicate exchange does not duplicate facts; removal of an offline media
   copy does not remove learner history.

The first acceptance path uses macOS production and Android learning, followed
by vendor-API production on the computer and then remote production with the
personal computer off. [ROADMAP.md](ROADMAP.md) owns that execution sequence.

## Listen and resolve a difficulty

1. Open or resume the material and listen for meaning. Playback position and
   material context survive closing and reopening.
2. Narrow attention to a sentence or smaller audio range when needed. Replay,
   loop, and rate adjustment support listening without changing the material.
3. Request the help needed for the current difficulty: timed text, word meaning,
   sentence translation, structure, or a perceptual cue grounded in the sound.
   Text display is support for this journey, not an independent reading course.
4. Return to the same audio after receiving help and check perception again.
   Direct hearing checks such as dictation or cloze can serve this step.
   Production training, retelling assessment, shadowing recording, and free AI
   conversation are outside this stage.
5. Record explicit outcomes and assistance actually used. Playback, clicks,
   and opening an explanation do not automatically prove mastery.

## Intentionally retain useful language

1. The Learner explicitly saves a useful or difficult word, expression,
   sentence, or bounded clip from the current material.
2. Retain the exact Material Revision, text span, audio rendition and range,
   source context, and relevant learner relation/history.
3. A saved Language Slice remains a reference into the material rather than
   an unnecessarily detached audio file. It supports this route:

   ```text
   saved entry -> original audio slice -> surrounding context -> whole material
   ```

4. Collection is intentional; browsing and pausing alone do not add entries.
   The Personal Corpus is distinct from a corpus of the Learner's own spoken
   or written output, which is outside the active scope.

## Return through the Personal Corpus

1. Browse or search saved language and select an entry to reopen, listen to,
   or review.
2. Re-enter its original source and bounded audio context in the same
   MaterialWorkbench. Preserve an honest unavailable state when the source
   cannot be accessed; do not silently discard the entry.
3. Inspect relevant learning history and choose the next action explicitly.
   This loop does not require a coach dashboard, capability-upgrade suggestion,
   or next-material recommendation engine.
4. Multiple occurrences of a Language Object can provide further listening
   contexts. Search indexes are replaceable; intentional relations and history
   are not inferred from search activity.

## Review through re-perception

1. Select an audio-backed entry directly or through the review queue. Scheduling
   answers when to return; the review activity still begins with perception.
2. Play the original slice audio-first, initially withholding text/translation.
3. Reveal help progressively when needed:

   ```text
   audio -> replay/narrower focus -> perceptual cue -> text -> translation
   ```

4. Return to the audio after a useful cue. The purpose is a successful second
   act of listening, not consumption of phonetic terminology.
5. Record the support used and the resulting perception honestly. Success on
   one recording alone does not establish transfer to a new speaker or context.

## Experience invariants

- Prepared learning and learner-owned records remain locally usable on both
  desktop and mobile without the original production executor being online.
- Material delivery, task state, and private learner-data exchange are distinct.
- One Core-backed MaterialWorkbench serves material and Personal Corpus entry.
- Canonical Text, timed text, translation, and sound resources refer to one
  compatible Material Revision.
- Material-side evidence is reusable; requested perceptual help is relative
  to the Learner's current difficulty.
- Predictions and text-derived estimates are not observed acoustic evidence.
- Sense Groups and Prosodic Chunks remain distinct.
- Every retained Slice has a route back to its source context.
- Learner intent and factual outcomes remain distinct from policy suggestions.
- Reading, speaking, and writing remain distinct conceptual capabilities;
  listening success does not establish evidence in those dimensions.
