# Learner Journeys

Listen may coordinate acquisition, compilation, provider execution,
qualification, packaging, installation, and adoption internally. The Learner
experiences one coherent path from Raw Source to authentic Learning Experience
and Personal Corpus.

This document owns project-wide journey intent. The theoretical boundary is
defined in [MODEL.md](MODEL.md); executable code and tests remain the authority
for what a current build already supports.

## Bring or discover a Source

1. Choose a local document, pasted text, audio, or video; discover an article,
   podcast, feed item, channel item, or community material; or provide another
   learner-authorized Source.
2. Listen records Source identity, rights, binding, and availability honestly.
   Discovery, preview, acquisition, retention, and redistribution permission
   remain separate facts.
3. The Learner may inspect or preview the Raw Source while it remains in the
   language-world production stage. Preview is not presented as a formal
   Learning Activity and does not create acquisition evidence.
4. The Learner chooses to compile the Source or adopt a compatible already
   compiled Learning Edition.

## Compile a Complete Learning Material

1. App submits the exact authorized Source, declared Target/Support Languages,
   and compatible reusable inputs to Gen.
2. Gen produces or qualifies the material contract defined in
   [MODEL.md](MODEL.md#complete-learning-material-contract):

   - Canonical Text and audio-independent Structured Reading;
   - Sentence Translation for the declared Support Language;
   - text-side Sense Groups usable in both text-only and audio-backed learning;
   - when audio is present, Canonical Audio, Structured Timed Text, and the full
     sound-processing scope, including phone evidence and pronunciation/
     prediction/actual-delivery comparison;
   - Source Video when present.

   Text-only materials need no TTS to enter formal learning. Existing audio
   is processed without a separate speech-enhancement request.

3. Progress, cancellation, provider limitations, missing language support,
   retry, and failure are presented as material-production state. An incomplete
   production result is never relabeled as a complete learning experience.
4. Gen returns a versioned, provenance-bearing Content Package. Core validates
   identity, dependencies, compatibility, evidence classes, and the modality-aware
   contract.
5. Installation exposes a qualified candidate. Explicit Learning Edition
   Adoption selects the coherent Complete Learning Material composition.
6. Once validated and adopted, the material crosses the Learning Boundary.
   Core supplies it to the unified Workbench for formal interaction; learning
   does not depend on the provider recipe that produced it.

## Add sound to a text material on demand

1. The Learner can already read, use Sense Groups, retain text Slices, and build
   Personal Corpus history without requesting sound.
2. When wanted, the Learner requests faithful TTS for the text material.
3. Generated audio enters the same full processing as source audio, including
   exact alignment and material-side Speech Learning Representation. TTS alone
   is not completion of that sound-processing scope.
4. Failure or unavailable evidence is reported honestly; the existing qualified
   text-learning experience and its history remain valid.
5. Compatible audio references support new listening Activities and episodes.
   They extend the same material in the Workbench, not a separate TTS-result
   workspace. Previous reading episodes never acquire retroactive listening evidence.

## Enter a Learning Activity

1. Choose a meaningful cognitive operation such as listening for meaning,
   intensive listening, reading, dictation, shadowing, reconstruction,
   speaking, or writing.
2. App's unified Workbench presents the Core-provided Complete Learning Material
   according to that Activity, using the appropriate views and components.
   Text-only Activities do not require audio; Sense Group reading/focus is
   available independently. Present audio, text, translation, and speech
   resources remain compatible representations of one Material Revision.
3. The Learner establishes a bounded Learning Focus. Subtitle visibility,
   replay, lookup, or an explanation panel may support the Activity but are not
   Activities by themselves.
4. Core/App record factual conditions and explicit outcomes. Raw playback and
   clicks remain observations unless they participate in a Meaningful Learning
   Episode.

## Create or retain a Language Slice

1. The Learner intentionally focuses, saves, reports difficulty with, practices,
   produces from, or reactivates a bounded part of the material.
2. Listen records one Language Slice pointing to the exact Material Revision,
   Canonical Text span, exact Canonical Audio rendition/range when available,
   and compatible resources. Text-only Slices need no artificial audio locator.
3. Listen does not normally create a detached MP3 or a new Material. The Slice
   remains re-enterable:

   ```text
   open Slice (replay when audio is available) -> context -> whole material
   ```

4. A Slice may cover a word, expression, phrase, Sense Group, Prosodic Chunk,
   sentence, utterance, or another bounded audio/text span.

## Form a Meaningful Learning Episode

1. Record the Activity intent, Slice/target, source context, assistance
   conditions, attempt or explicit judgment, and outcome.
2. Preserve distinctions among Exposure, Attention, Learning, and Acquisition.
   Passing playback, pausing, opening timed text, or clicking a token does not
   silently change capability.
3. Episodes worth retaining include explicit difficulty, bounded recognition,
   speech-cue-assisted re-perception, production, correction, or transfer under
   changed conditions.
4. Append facts and evidence provenance. Learner State remains a separate,
   replaceable interpretation.

## Continue through the Personal Corpus

1. A Personal Corpus Entry combines the Language Slice, Learner Relation, and
   Meaningful Learning History.
2. The Learner freely browses/searches entries, opens their source context and
   meaningful history, and selects entries to add to learning or review.
3. An explicit selection enters the corresponding Activity in the same
   Workbench, carrying the Slice, Activity intent, and relevant history.
   Browsing alone does not record an attempt or mastery. This early loop needs
   no automatic scheduler or next-experience recommendation engine.
4. Multiple occurrences of one Language Object become an Experience Reservoir
   for personalized review and transfer.
5. Search indexes and suggestions may be rebuilt. Language Slices, Episodes,
   explicit decisions, and qualified learner facts remain durable.

## Review listening through re-perception

1. The Learner selects an audio-backed Slice for review, initially through the
   Personal Corpus. A later Review Schedule may suggest when to return, but is
   neither a prerequisite nor the definition of the experience itself.
2. Re-enter the original Language Slice audio-first, without immediately
   revealing timed text or translation.
3. If perception fails, reveal the Minimum Sufficient Scaffold progressively:

   ```text
   original audio
       -> replay or narrower focus
       -> rhythm / perceptual cue
       -> speech explanation
       -> timed text
       -> translation
   ```

4. After every useful cue, return to the audio. The purpose of Speech Learning
   Representation is successful re-perception, not terminology consumption.
5. Record the support actually used and the resulting perception honestly.
6. Test transfer with a different sentence, speaker, rate, prosody, acoustic
   realization, or context. Same-recording success alone does not prove
   Perceptual Robustness.

## Develop other capability dimensions

Reading, listening, speaking, and writing may reuse the same Language Object,
Slice, and Corpus history, but each uses its own evidence and Acquisition
Experiences:

```text
Reading:   written form -> structure -> meaning
Listening: sound -> perception -> segmentation -> form -> meaning
Speaking:  intention -> retrieval -> phonological planning -> speech
Writing:   intention -> retrieval -> lexical/construction choice -> text
```

The Learner may choose among these paths. Evidence in one dimension does not
silently update another.

## Experience invariants

- Learners see Sources, compilation progress, Complete Learning Materials,
  Activities, Slices, supports, and their Corpus—not provider DAGs or manifests.
- Formal material interaction uses one Core-backed Workbench across modalities
  and entry paths; different views and modes are not separate learning systems.
- Raw Source preview stays outside formal learning and does not create false
  acquisition evidence.
- A material crosses the Learning Boundary only after its modality-aware contract is
  validated.
- Text-only learning and Sense Groups need no TTS; present or requested audio
  receives full processing, not optional speech upgrades.
- Canonical Text, Structured Reading, translation, and any audio/timed/speech
  resources remain one compatible composition.
- Material-side Signal Facts and Speech Structure are reusable; Perceptual
  Guidance is learner-relative.
- Predicted or text-derived speech structure is never presented as observed
  acoustic evidence.
- Sense Groups and Prosodic Chunks remain distinct.
- A Language Slice always retains a route to original context.
- Personal Corpus stores meaningful history, not clickstream.
- Learner facts survive package, provider, model, and projection replacement.
- Minimum Sufficient Scaffold leads back to the target cognitive operation.
- Scheduling answers when; Acquisition Experience answers what.
- Reading, listening, speaking, and writing remain independent.
- Optional Sensa integration does not alter current Listen journeys.
