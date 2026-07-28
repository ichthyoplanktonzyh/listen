# listen User Journeys: Current And Planned

状态：DRAFT

日期：2026-07-03

## Purpose

This document describes how a real user should move through the app now and in
the planned Phase 3.x product direction. It is written from the user's point of
view, not from internal module names.

It covers two groups:

- **Current / backend-ready journeys**: features that already exist in the app
  or have backend foundations but are not fully exposed as polished user
  surfaces.
- **Planned journeys**: Phase 3.x learning-loop experiences that should build on
  the current media, subtitle, timeline, vocabulary, diagnosis, practice/review,
  and corpus foundations.

This is a discussion/product artifact. Later phases can split it into formal
`CONTEXT.md`, `PRODUCT-FLOW.md`, `PLAN.md`, and acceptance documents.

## Status Legend

| Status | Meaning |
|---|---|
| Current | User can reach this path today, though wording or degraded states may need polish. |
| Backend-ready | Backend/domain foundations exist, but the user-facing surface is incomplete or absent. |
| Planned | Product direction is documented, but implementation is future work. |
| Research | Needs product validation, external policy checks, algorithm work, or manual QA before implementation. |

## Product Frame

listen is not a generic media player with vocabulary features attached. The core
user promise is:

```text
Use real audio/video input
  -> locate why you did not understand
  -> replay the exact sound context
  -> practice active recognition
  -> save the result for review
  -> return to real input with better listening ability
```

The product should keep ordinary playback calm, then become precise only when
the user asks: "why did I miss that?"

## Primary User Types

### U1: Intensive Listener

This user watches real English material and pauses when something becomes
unclear. They need sentence loop, chunk replay, word lookup, listening
structure, diagnosis, and practice.

### U2: Extensive Listener

This user wants to keep listening without constant interruption. They need
reliable media playback, subtitles, progress recovery, and light markers of what
was hard.

### U3: Vocabulary Repair User

This user has many words they "know" on paper but miss in real speech. They need
word status, source examples, hearing observations, listening dictionary, and
review.

### U4: Resource Builder

This user imports or produces richer timeline resources. They need `.lltimeline`
import/export, Word sync, Chunk replay, Listening structure, Phone evidence,
manual review, and resource readiness.

### U5: Future Self-Coach

This user expects listen to recommend the next action: easier input, harder
input, targeted practice, review, shadowing, or L1-aware drills.

## Top-Level Journey Map

```text
Start app
  -> Open media
  -> Get subtitles
  -> Check learning capabilities
  -> Listen normally
  -> Hit a comprehension failure
  -> Use word/chunk/listening tools
  -> Diagnose the failure
  -> Practice or save for review
  -> Continue listening
  -> Later revisit through review/dashboard/corpus recall
```

## 1. First Open: From Empty App To Playable Input

Status: Current

### User Intent

"I want to start with a real video or audio file."

### Entry

- Center no-media call to action.
- AppBar `Open Media`.
- Drag/drop a media file.
- Open a URL or a completed download.

### Happy Path

1. User opens a local video or audio file.
2. App registers the media and restores saved playback progress.
3. Player surface displays the video or audio state.
4. Bottom controls become meaningful: play/pause, seek, speed, volume, previous
   or next sentence once subtitles exist.
5. App loads known subtitle resources and timeline resources for this media.
6. If learning resources exist, the Resources panel summarizes available
   capabilities.

### User Sees

```text
Media loaded
Subtitles: not loaded / ready
Word sync: unavailable / ready
Chunk replay: unavailable / ready
Listening structure: unavailable / ready
Phone evidence: unavailable / ready
```

### Degraded Paths

- Unsupported media: explain that playback failed and keep the user at the media
  entry path.
- Missing file path for known media: preserve learning data and ask user to
  locate the file again.
- Backend startup error: show retry separately from media playback errors.
- No media: hide or soften controls that cannot act yet.

### Next Best Action

- Import subtitles.
- Generate subtitles with local Whisper.
- Attach a `.lltimeline.json`.
- Continue ordinary playback if subtitles are not needed.

## 2. URL And Download Journey

Status: Current

### User Intent

"I have an online media URL. I want to play it or download it for local study."

### Entry

- AppBar `Open URL`.
- Download bar after URL resolution.

### Happy Path

1. User pastes a URL.
2. App resolves direct playable media or invokes `yt-dlp` when configured.
3. User chooses direct playback or local download.
4. Direct playback starts as an online media session.
5. Download shows progress, supports cancel, and exposes the completed local
   file.
6. User opens the downloaded file, returning to the canonical local media path.

### User Sees

```text
Resolving URL
Downloading
Downloaded
Open downloaded media
```

### Degraded Paths

- `yt-dlp` missing: explain where to configure it.
- Unsupported URL: tell the user this source cannot be resolved by the current
  tools.
- Download failure: preserve the error and allow retry.
- Online playback without local media: make clear that local subtitle/resource
  features may be limited until a local media item is registered.

### Next Best Action

- Open downloaded media.
- Import subtitles.
- Generate subtitles after download.

## 3. Subtitle Acquisition Journey

Status: Current

### User Intent

"I need text aligned to this media so I can learn from it."

### Entries

- Import SRT/VTT as primary subtitle.
- Import SRT/VTT as secondary subtitle.
- Generate subtitles with local Whisper.
- Extract embedded text subtitles.
- Search/download OpenSubtitles.
- Drag/drop subtitle files.

### Happy Path A: Import SRT/VTT

1. User imports an SRT or WebVTT file.
2. App parses and normalizes cues into subtitle sentences and tokens.
3. Primary subtitle appears in the overlay and transcript.
4. User can click sentences, loop sentences, click tokens, and use vocabulary
   and diagnosis.
5. Capability summary marks subtitles ready and richer timing features as
   unavailable or degraded unless resources exist.

### Happy Path B: Generate With Local Whisper

1. User opens the subtitle generation dialog.
2. User selects language/model/quality destination.
3. App starts a local transcription job.
4. Progress appears through task feedback and the Transcription Center.
5. On completion, generated track loads.
6. App summarizes which learning capabilities were produced:

```text
Generated subtitles: ready
Word sync: ready if word timings exist
Chunk replay: ready if generated or available
Listening structure: ready/degraded if Word sync can support it
Phone evidence: not yet generated unless audio analysis ran
```

### Happy Path C: Embedded Subtitle Extraction

1. User opens embedded subtitle extraction.
2. App lists text subtitle tracks when available.
3. User selects a track.
4. Extracted text subtitle becomes a normal primary or secondary subtitle
   resource.

### Happy Path D: OpenSubtitles

1. User searches online subtitles for the current media.
2. User selects a result.
3. Downloaded subtitle imports into the current media.
4. App treats it like any other plain subtitle resource.

### Degraded Paths

- Plain subtitles have no exact word timing: Word sync and Listening structure
  should explain what is missing.
- Secondary subtitle without primary: allow reading, but explain which track is
  used for learning interactions.
- Embedded bitmap subtitles: explain unsupported text-learning path.
- OpenSubtitles API key missing or search fails: keep the user in an actionable
  setup/retry path.

### Next Best Action

- Play with subtitles.
- Generate or import timeline resources for Word sync and Chunk replay.
- Start vocabulary/diagnosis from the current sentence.

## 4. Subtitle And Timeline Resource Journey

Status: Current

### User Intent

"I want to know what this subtitle resource can do, and I want to choose the
best resource."

### Entries

- Subtitle Resources screen.
- Resources side-panel tab.
- Import/attach `.lltimeline.json`.
- Export SRT or `.lltimeline.json`.

### Happy Path

1. User opens Resources.
2. App shows subtitle resources for the current media.
3. User activates, archives, restores, deletes, or exports subtitle resources.
4. For the active subtitle, app summarizes learning capabilities before raw
   internal details:

```text
Subtitles
Word sync
Chunk replay
Listening structure
Phone evidence
Production artifacts
```

5. Advanced users can inspect WordTimeline, ChunkTimeline, PhoneTimeline,
   provider ids, artifacts, and lifecycle states.
6. User imports a `.lltimeline.json`; app checks fingerprint and asks for
   confirmation on mismatch.
7. Imported resource unlocks richer playback and learning surfaces where data is
   present.

### Degraded Paths

- Fingerprint mismatch: ask whether to attach anyway and explain the risk.
- Candidate timeline exists but is not active: show that the capability requires
  activation.
- Missing Listening structure: do not imply Phone evidence is required if
  document-level rhythm frames could exist separately.
- Estimated Word sync: mark as degraded, not equivalent to audio-backed timing.

### Next Best Action

- Activate the best resource.
- Run generation/analysis if missing.
- Use Word sync, Chunk replay, Listening structure, or Phone evidence in
  playback.

## 5. Normal Listening Journey

Status: Current

### User Intent

"I want to watch/listen normally, with learning help available but not noisy."

### Entry

- Play button after media and subtitles are loaded.

### Happy Path

1. User starts playback.
2. Subtitle overlay follows the media.
3. Transcript side panel can auto-scroll to the current sentence.
4. Current word or chunk highlights when resources support it.
5. User can stay in flow without opening learning panels.
6. App records playback progress and keeps the current learning context ready.

### User Sees

- Current subtitle.
- Optional secondary subtitle.
- Light word/chunk styling.
- Playback controls.
- Optional capability/status chips when relevant.

### Degraded Paths

- No subtitles: media still plays; learning actions prompt subtitle acquisition.
- No Word sync: sentence-level playback still works.
- No Chunk replay: sentence loop remains available.
- No Listening structure: hide or mark unavailable; do not show empty teaching
  chrome.

### Next Best Action

- Keep listening.
- Replay current sentence.
- Click a word/chunk when comprehension fails.

## 6. Sentence Replay Journey

Status: Current

### User Intent

"I missed that sentence. Let me hear it again."

### Entries

- Previous/next sentence.
- Loop current sentence.
- Transcript sentence click.
- Subtitle overlay click/seek.

### Happy Path

1. User presses loop current sentence.
2. App plays from sentence start to sentence end repeatedly.
3. User can change speed, pause, or exit loop.
4. Current subtitle, transcript, word highlight, and diagnosis stay aligned.
5. User either understands and continues, or opens deeper tools.

### Degraded Paths

- Subtitle timing is rough: sentence loop may include extra silence or clipped
  audio; explain if known.
- No subtitle: sentence loop is unavailable.
- Online playback seek is imprecise: preserve basic playback and explain
  platform/tool limitation if user sees drift.

### Next Best Action

- Click unclear word.
- Switch to chunk replay.
- Open diagnosis.

## 7. Word Sync Journey

Status: Current

### User Intent

"I want to know which word I am hearing right now."

### Entry

- Active WordTimeline or generated word timings during playback.

### Happy Path

1. App loads word timings for the active subtitle.
2. As media plays, the current word is highlighted.
3. User can connect text position to audio position.
4. Word click opens word learning details.
5. Word timing supports cloze, dictation, listening dictionary, and future
   practice anchors.

### Degraded Paths

- Estimated timing: show Word sync as degraded.
- No word timings: word highlight is unavailable, but sentence playback remains.
- Active subtitle changed: mark stale resources and offer refresh or reattach.

### Next Best Action

- Use Chunk replay.
- Open word learning.
- Generate or import better timing resources.

## 8. Chunk Replay Journey

Status: Current

### User Intent

"The full sentence is too much. I want to replay a meaningful phrase."

### Entries

- Chunk controls in bottom bar.
- TokenLine chunk grouping.
- Resources capability summary.

### Happy Path

1. Active ChunkTimeline or generated chunk partitions load.
2. TokenLine groups words into chunks.
3. User moves to previous/next chunk.
4. User loops a chunk.
5. User expands from one chunk to adjacent chunks, then back to the full
   sentence.
6. Chunk becomes the natural unit for future dictation, cloze, and shadowing.

### Degraded Paths

- No ChunkTimeline: show chunk controls as unavailable and explain that sentence
  loop still works.
- Approximate chunks: mark degraded if based on weak timing.
- Chunk id stale after subtitle/resource switch: reload or clear chunk state.

### Next Best Action

- Use chunk dictation.
- Save chunk as review item.
- Shadow the chunk in a future practice flow.

## 9. Listening Structure Journey

Status: Current / improving

### User Intent

"I know the words, but I do not know what to listen for in the actual sound."

### Entries

- Subtitle overlay Listening structure layer.
- Diagnosis card.
- Resources capability summary.
- Local Whisper or `.lltimeline` result summary.

### Happy Path

1. User opens or enables Listening structure.
2. App shows stress anchors, weak groups, compression spans, phrase boundaries,
   nuclei, and listening hotspots where available.
3. User clicks a cue to replay that sound region.
4. User compares:

```text
A: citation form
B: default connected form
C: actual delivery in this clip
```

5. User understands the likely reason the sentence sounded different from the
   written text.

### Degraded Paths

- Predicted-only cue: label as text prior, not actual measured audio.
- No Word sync: explain that actual listening structure needs timing evidence.
- No energy/phone evidence: still allow timing/text-prior explanations where
  honest, but mark confidence.
- No Listening structure at all: recommend generating/importing resources or
  continue with sentence/chunk replay.

### Next Best Action

- Replay hotspot.
- Open diagnosis.
- Turn cue into practice/review item in planned flows.

## 10. Phone Evidence Journey

Status: Current / specialist layer

### User Intent

"I want detailed evidence about phones, reductions, linking, or mismatches."

### Entries

- Phone evidence mode in overlay.
- Diagnosis card.
- Audio/Phonetic Analysis Center.
- Analyze current sentence or whole track actions.

### Happy Path

1. User runs or opens phone/audio analysis.
2. App shows job status.
3. Phone evidence appears for current sentence where available.
4. User sees phone-level findings as evidence, not as the default learning
   frame.
5. User can replay relevant phone or sound-pattern regions.

### Degraded Paths

- Provider/model missing: route user to setup.
- Analysis running: show generating state.
- No detected phones: say no phone evidence is available, while preserving
  Listening structure if present.
- Low confidence/raw mismatch: do not present as teaching truth.

### Next Best Action

- Use evidence to understand a hotspot.
- Improve or regenerate resources.
- Leave this layer closed if the default Listening structure is enough.

## 11. Word Learning Journey

Status: Current

### User Intent

"I need to know this word, mark whether I recognize it, and keep source
evidence."

### Entries

- Click token in overlay or transcript.
- Vocabulary screen.
- Diagnosis card lexical barrier.
- Future listening dictionary result.

### Happy Path

1. User clicks a word.
2. Word learning side panel opens immediately.
3. App loads lexical entry, dictionary, pronunciation, language profile, and
   source context.
4. User sets `LearningStatus`:

```text
unknown_meaning
known_not_recognized
known_recognized
```

5. User adds custom definition or notes.
6. App updates word styling and refreshes diagnosis.
7. Source sentence remains durable even if the media later moves or is deleted.

### Degraded Paths

- Dictionary offline/missing: preserve local status editing and notes.
- Lemma is wrong: user uses correction flow.
- Source media missing: show source snapshot and recovery action instead of
  deleting the learning record.
- Phrase candidate not confirmed: keep word and phrase identities separate.

### Next Best Action

- Replay source sentence.
- Add phrase candidate.
- Open listening dictionary for more examples.
- Generate practice/review from the word.

## 12. Vocabulary Book Journey

Status: Current

### User Intent

"Show me the words I am learning, especially the ones I know but miss in real
speech."

### Entry

- Vocabulary screen.
- Learning assets/resources screens.
- Import/export vocabulary.

### Happy Path

1. User opens Vocabulary.
2. User filters by status or searches.
3. User opens a lexical entry.
4. User sees definitions, notes, pronunciation, status, history, and source
   context where available.
5. User exports or imports lexical assets for backup or transfer.

### Degraded Paths

- Import conflicts: preserve newer local state and do not overwrite blindly.
- Missing media: keep source sentence snapshots.
- Phrase and word identity mismatch: route to phrase or lemma correction tools.

### Next Best Action

- Review `known_not_recognized` words.
- Open source clips.
- Use planned listening dictionary to find more real examples.

## 13. Diagnosis Journey

Status: Current / expanding

### User Intent

"Why did I not understand this sentence?"

### Entry

- Diagnosis side panel for current sentence.
- After word status change.
- After practice failure in planned flows.

### Happy Path

1. User opens diagnosis for current sentence.
2. App reads lexical entries and latest observations.
3. Diagnosis identifies barriers:

```text
unknown meaning
known but not recognized
insufficient evidence
listening structure / sound evidence
other unresolved difficulty
```

4. User sees short reasons and next actions.
5. User can open a word, replay a cue, run analysis, or start practice.

### Degraded Paths

- Missing dictionary: lexical status still works, dictionary explanation is
  degraded.
- Missing Word sync: diagnosis can handle word status but not precise sound
  windows.
- Missing Listening structure/Phone evidence: say which evidence is missing.
- No known status: ask user to mark key words before over-explaining.

### Next Best Action

- Mark word statuses.
- Replay chunk.
- Generate Listening structure or Phone evidence.
- Create practice/review item in planned flows.

## 14. Settings And Tool Setup Journey

Status: Current

### User Intent

"Configure the app so my normal workflow works."

### Entry

- Settings dialog.
- Tool path setup.
- Provider/model setup in task centers.

### Happy Path

1. User opens Settings.
2. User configures UI language and learning language separately.
3. User adjusts subtitle display, transcript width, word/chunk styles, colors,
   and overlay preferences.
4. User configures `ffmpeg`, `ffprobe`, `yt-dlp`, transcription defaults,
   OpenSubtitles key, pronunciation/audio-analysis provider, model, and cache.
5. Settings change future defaults, while main workflows remain discoverable in
   context.

### Degraded Paths

- Missing tool path: feature entry explains missing dependency and links to
  Settings.
- Invalid API key/model: preserve error and allow retry.
- Internal labels: keep technical names in advanced sections only.

### Next Best Action

- Return to the workflow that required setup.
- Run subtitle generation, download, extraction, or audio analysis again.

## 15. Task Center And Recovery Journey

Status: Current / improving

### User Intent

"Something is running or failed. I need to know what happened and recover."

### Entries

- Transcription Center.
- Audio/Phonetic Analysis Center.
- Download bar.
- Global status/snackbar.
- Logs export.

### Happy Path

1. User starts a long-running job.
2. Inline feedback shows progress.
3. Task center stores job history and actions.
4. On completion, app summarizes user-facing output:

```text
Generated subtitle loaded
Word sync ready
Listening structure degraded/ready
Phone evidence not generated yet
```

5. User can open result, retry failed job, or inspect logs.

### Degraded Paths

- Job event missed: task center can recover current status.
- Job failed: preserve error and retry action.
- Download cancelled: do not resurrect dismissed progress after late process
  output.
- Free-form status text: use it as a summary, not as the state contract.

### Next Best Action

- Load completed resource.
- Retry or change settings.
- Continue playback if job is optional.

## 16. Practice Journey

Status: Backend-ready / planned UI

### User Intent

"I want to prove whether I actually heard the word/chunk, not just read it."

### Planned Entries

- Current sentence/chunk.
- Diagnosis card.
- Word learning panel.
- Listening dictionary result.
- Review queue.

### Planned Happy Path

1. User clicks `Practice` from a sentence, chunk, word, or diagnosis.
2. App creates a `PracticeItem` with stable prompt, expected answer, and anchors.
3. User chooses or receives a mode:

```text
cloze
dictation
subtitle fade
shadowing
```

4. App plays the real audio segment.
5. User submits text, rating, or recording depending on mode.
6. App creates a `PracticeAttempt`.
7. Failed lexical anchors generate `LexicalObservation`.
8. App optionally creates `ReviewItem`.
9. App appends `LearningEvent`.
10. UI shows a result that explains what was missed and what to do next.

### Planned Degraded Paths

- No Word sync: allow sentence-level dictation but disable precise word cloze.
- No chunk: fall back to sentence.
- No media: keep prompt snapshot and mark audio unavailable.
- Failure result: do not silently change global `LearningStatus`.

### Next Best Action

- Retry immediately.
- Save to review.
- Open listening dictionary for the failed word/phrase.

## 17. Review Journey

Status: Backend-ready / planned UI

### User Intent

"Bring back the exact things I missed and test whether I can hear them now."

### Planned Entries

- Review queue.
- Vocabulary book.
- Practice result.
- Listening dictionary saved examples.

### Planned Happy Path

1. User opens Review.
2. App schedules review items from lexical entries, practice failures, chunks,
   sentences, or connected-speech cases.
3. User receives an audio-first prompt:

```text
hear target word
fill cloze
dictate chunk
recognize phrase across clips
rate shadowing attempt
```

4. User submits answer or rating.
5. App records `ReviewAttempt`.
6. Review result may create a new practice attempt or observation.
7. Dashboard/event ledger sees the result.

### Planned Degraded Paths

- Source media missing: show prompt snapshot and skip audio card or ask user to
  relocate media.
- Review item stale: preserve item but refresh anchors when possible.
- Low evidence: do not over-schedule uncertain audio cases.

### Next Best Action

- Continue review.
- Open source clip.
- Adjust global status only through explicit user confirmation.

## 18. Listening Dictionary / Corpus Recall Journey

Status: Planned

### User Intent

"Show me this word or phrase in real speech, across many contexts, so I can
learn to recognize it."

### Planned Entries

- Subtitle token click.
- Word learning panel.
- Diagnosis result.
- Vocabulary book.
- Search box.
- Practice/review failure.

### Planned Happy Path

1. User searches a word, phrase, chunk, or connected-speech family.
2. App searches current media, local corpus, saved examples, and optional
   external provider links.
3. Results show playable segments:

```text
source title
subtitle context
target highlight
word/chunk/sentence play controls
accent/source hints if available
availability state
Listening structure cues if available
```

4. User listens to several real examples.
5. User saves good examples.
6. User creates cloze/dictation/review items from examples.
7. App tracks recognition across speakers, speed, position, and contexts.

### Planned Degraded Paths

- No local result: offer external YouGlish link/embed or dictionary audio as a
  temporary reference.
- External result not playable: allow opening the original page, but do not
  pretend the audio is locally practice-ready.
- Caption mismatch: mark low confidence and avoid dictation generation.
- Copyright/API limits: cache metadata/source snapshots only when allowed; do
  not default to systematic external media download.

### Next Best Action

- Practice the target.
- Add examples to review.
- Import more personal media to grow the corpus.

## 19. Comprehensible Input And Difficulty Journey

Status: Planned

### User Intent

"Tell me whether this material is good for me now: too easy, comprehensible,
challenging, or too hard."

### Planned Entries

- Media library.
- Current media summary.
- Segment/chunk recommendation.
- Dashboard.

### Planned Happy Path

1. App computes a difficulty profile for media, sentence, segment, or chunk.
2. Signals include:

```text
unknown word density
known_not_recognized density
speech rate
chunk complexity
connected-speech density
resource quality
past user performance
```

3. User sees fit:

```text
too_easy
comprehensible
challenging
too_hard
```

4. User chooses extensive listening or intensive listening.
5. App recommends the next segment or practice type.

### Planned Degraded Paths

- Not enough lexical status: ask user to mark key words.
- No Word sync: omit speech-rate/chunk precision or mark degraded.
- No history: make a conservative first estimate.

### Next Best Action

- Start extensive listening.
- Start intensive practice.
- Save material for later.

## 20. L1-Aware Diagnosis Journey

Status: Planned

### User Intent

"Explain why my Mandarin listening habits make this English sound hard."

### Planned Entries

- Diagnosis card.
- Practice failure.
- Listening dictionary connected-speech family.
- Specialty practice.

### Planned Happy Path

1. User sets UI language, L1, and L2 separately.
2. App recognizes Mandarin -> English as the active profile.
3. When a failure matches a known difficulty, diagnosis adds a short L1-aware
   hint:

```text
weak function words
schwa/reduced vowels
final consonants
consonant clusters
t/d deletion
flapping
linking
stress-timed rhythm
compressed forms
```

4. Hint links back to real audio replay.
5. User starts a focused practice set from their own media examples.

### Planned Degraded Paths

- L1 not configured: show base diagnosis only.
- Unsupported L1/L2 profile: avoid generic stereotypes; show language-neutral
  listening explanation.
- No real examples: offer current clip or ask user to build corpus first.

### Next Best Action

- Practice similar clips.
- Add to review.
- Track progress in dashboard.

## 21. Shadowing And Recording Journey

Status: Planned

### User Intent

"I can hear it now; I want to imitate the real chunk and compare myself."

### Planned Entries

- Chunk replay.
- Practice mode.
- Listening structure cue.
- Review item.

### Planned Happy Path

1. User chooses a chunk.
2. App plays reference audio at 0.75x, 0.9x, or 1.0x.
3. User records their attempt.
4. App saves `RecordingAsset`.
5. App compares duration, pause placement, and coarse rhythm.
6. User plays A/B: original, self, original again.
7. App stores a `PracticeAttempt` and optional `ShadowingComparison`.

### Planned Degraded Paths

- Microphone permission missing: explain and route to system settings.
- No chunk: allow sentence-level shadowing.
- No advanced scoring: still provide playback and duration/pause comparison.
- No media later: keep recording and prompt snapshot.

### Next Best Action

- Retry.
- Save best attempt.
- Review difficult chunks later.

## 22. Dashboard Journey

Status: Planned

### User Intent

"Tell me what changed in my listening and what I should do next."

### Planned Entries

- Dashboard screen.
- End-of-session summary.
- Review completion summary.

### Planned Happy Path

1. App aggregates `LearningEvent`, `PracticeAttempt`, `ReviewAttempt`,
   `LexicalObservation`, and status history.
2. Dashboard shows listening-relevant progress:

```text
extensive listening time
intensive sentences practiced
cloze/dictation accuracy
known_not_recognized -> known_recognized movement
repeatedly missed words
connected-speech families
L1-aware difficulty groups
materials worth revisiting
```

3. Dashboard recommends a next action:

```text
review due items
practice weak function words
return to a previously hard clip
choose easier input
try shadowing a mastered chunk
```

### Planned Degraded Paths

- Not enough history: show a starter checklist.
- Missing events due to older app version: aggregate what exists and explain
  limited insight.
- Media unavailable: keep source snapshots and recommend recoverable items.

### Next Best Action

- Start review.
- Open recommended corpus examples.
- Continue current material.

## 23. Production Resource Builder Journey

Status: Current developer workflow / planned user-facing polish

### User Intent

"I want to create or refine high-quality timeline resources for serious study or
distribution."

### Entries

- Production pipeline scripts.
- `.lltimeline.json` import/export.
- Manual WordTimeline review.
- Resource evaluation reports.

### Happy Path

1. User prepares source media and transcript/subtitles.
2. Production pipeline generates candidate WordTimeline, ChunkTimeline, Phone
   Timeline, RhythmFrame, artifacts, and reports.
3. User imports `.lltimeline.json` into the app.
4. App displays capability readiness.
5. User manually reviews word timing where needed.
6. User saves user-adjusted timeline candidate and activates it.
7. User exports updated `.lltimeline.json`.

### Degraded Paths

- Heavy tools unavailable in consumer app: explain that production generation is
  separate from lightweight playback.
- Poor alignment quality: mark resource degraded and route to manual review.
- Artifact mismatch after import/remap: avoid silent capability claims.

### Next Best Action

- Use resource in study.
- Publish/distribute resource with media where legally appropriate.
- Add examples to corpus/review.

## 24. End-To-End Current Journey: Plain Subtitle Learning

Status: Current

```text
Open local media
  -> Import SRT/VTT
  -> Play with subtitles
  -> Loop current sentence
  -> Click unknown word
  -> Read definition/pronunciation
  -> Set LearningStatus
  -> Diagnosis updates
  -> Continue listening
```

Expected product feel:

- Fast and reliable.
- Honest about missing Word sync or sound evidence.
- Still useful without advanced resources.

## 25. End-To-End Current Journey: Generated Subtitle Learning

Status: Current

```text
Open local media
  -> Generate subtitles with local Whisper
  -> Generated track loads
  -> Word sync readiness appears if timings exist
  -> Listening structure readiness appears if available
  -> User replays sentence/chunk
  -> User clicks missed word
  -> Diagnosis and vocabulary update
```

Expected product feel:

- The user should not need to visit advanced resource details to understand what
  the generation produced.
- Completion feedback should name learning capabilities, not only job status.

## 26. End-To-End Current Journey: Rich Timeline Resource

Status: Current

```text
Open media
  -> Import/attach .lltimeline.json
  -> Confirm mismatch only if needed
  -> Activate best subtitle/timeline resources
  -> Play with Word sync and Chunk replay
  -> Inspect Listening structure
  -> Expand Phone evidence when useful
  -> Manual review timing if needed
  -> Export updated resource
```

Expected product feel:

- Capability-first.
- Advanced details available but not required.
- Degraded states visible and actionable.

## 27. End-To-End Planned Journey: Listening Dictionary Loop

Status: Planned

```text
User misses "would have"
  -> Diagnosis says known phrase not recognized
  -> Open listening dictionary
  -> Hear current clip plus multiple real examples
  -> Practice cloze across examples
  -> Save two examples to review
  -> Review later with audio-first prompts
  -> Recognition improves across speakers/contexts
```

Expected product feel:

- This is not a pronunciation dictionary.
- It is a real-speech recognition and generalization tool.

## 28. End-To-End Planned Journey: Full Learning Loop

Status: Planned

```text
Real input
  -> Comprehension failure
  -> Diagnosis
  -> Practice
  -> Observation / ReviewItem / LearningEvent
  -> Review
  -> Dashboard recommendation
  -> Return to real input
```

Expected product feel:

- The loop starts and ends in real audio.
- Practice failure becomes evidence, not shame and not silent status mutation.
- Review resurrects the original sound context.

## Open Product Questions

1. What is the first polished Phase 3.x user-facing slice: Practice UI,
   listening dictionary, review queue, or difficulty/input fit?
2. Should listening dictionary first search only local personal corpus, or ship
   with a YouGlish external-link/widget experiment?
3. Which current controls should be hidden in no-media/missing-resource states,
   and which should remain visible with explanations?
4. What is the minimum honest Listening structure state for plain SRT/VTT:
   unavailable, predicted-only, or generated after word timing?
5. How much of the production resource builder should become a normal user
   workflow versus remain developer/advanced tooling?

## Source Planning Inputs

- `.planning/phases/2.22-user-facing-workflow-semantics/2.22-CURRENT-FEATURE-INVENTORY.md`
- `.planning/phases/2.22-user-facing-workflow-semantics/2.22-STEP0-UI-AUDIT.md`
- `.planning/phases/2.22-user-facing-workflow-semantics/2.22-FEATURE-SEMANTICS-MODEL.md`
- `.planning/phases/3.0-english-listening-learning-loop/3.0-CONTEXT.md`
- `.planning/phases/3.0-english-listening-learning-loop/3.0-PLAN.md`
- `.planning/phases/3.0.1-learning-loop-architecture-foundation/3.0.1-ARCHITECTURE.md`
- `.planning/codebase/ARCHITECTURE.md`
- `.planning/codebase/DATA-MODEL.md`
