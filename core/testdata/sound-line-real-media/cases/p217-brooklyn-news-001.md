# p217-brooklyn-news-001

**Title:** Brooklyn middle school cell phone ban - CNN News June 9 2026
**Layer:** product_media
**Dataset:** local_media (YouTube)
**Language:** en-US

## Source / License

- Source: YouTube, CNN news clip
- License: Local-only QA. Do not redistribute.
- Media: `~/Desktop/视频/How a cell phone ban has transformed this Brooklyn middle school ... [9FFSOYLiFxc].mp4`

## Resource Status

- [x] Media available locally
- [x] Subtitle generated via WhisperX (word-level timestamps)
- [x] Base LLTimeline generated (word_timelines only)
- [x] PhoneTimeline with sound_analysis.learning_phones (236 learning phones, 5 sentences)
- [x] sound_analysis.connected_speech markers present (27 markers)

## Generation Steps

### Step 1: Generate base LLTimeline (completed)

```sh
# Extract audio
ffmpeg -hide_banner -loglevel error -y \
  -i "~/Desktop/视频/How a cell phone ban...mp4" \
  -vn -ac 1 -ar 16000 -sample_fmt s16 \
  ~/Desktop/视频/audio-16k-mono.wav
```

Already done in prior run. This WAV file was used as media for the CTC API workflow.

### Step 2: Generate PhoneTimeline with sound_analysis (refreshed 2026-06-29)

```sh
python3 scripts/run-sound-line-real-media-case.py \
  --case-id p217-brooklyn-news-001 \
  --sentence-limit 5
```

Result: 5 sentence-level CTC phonetic analyses. 236 learning_phones, 27 connected_speech markers (13 deletion, 7 weak_form, 6 assimilation, 1 flapping). The previous 15 generic `linking` markers disappeared after raw CTC insertion stopped being promoted to learner-facing linking without cross-token boundary evidence.

The exported timeline (`p217-brooklyn-news-001.lltimeline.json`) tracks to a local-only WAV media + QA SQLite DB and is not meant to be portable to other machines. Keep it under ignored `.tmp/sound-line-real-media/cases/`; do not commit the generated full transcript timeline.

## Observation 1: Helpful - flapping on "with" (T→DX)

- timestamp_ms: 18831-18851
- sentence / words: "...with a trivia question that has quite the ring to it." / "with"
- phone_range: token 19, phone 34
- connected_speech_family: flapping
- ui_label: "possible flap"
- marker_status: detected_in_audio
- playback_window_ms: ~20ms
- playback_result: (requires audio playback - not evaluated in headless run)
- qa_decision: keep
- mismatch_source: real_connected_speech
- notes: Classic American English flap. /t/ between vowels -> DX. This is exactly the kind of marker learners benefit from. The detected phone DX (flap) is correct for natural speech. High-confidence useful marker.

## Observation 2: Helpful - weak_form on "dealing" (AH→AX)

- timestamp_ms: 26799-26819
- sentence / words: "...which is dealing with the aftermath..." / "dealing"
- phone_range: token 9, phone 13
- connected_speech_family: weak_form
- ui_label: "possible reduction"
- marker_status: detected_in_audio
- playback_window_ms: ~20ms
- playback_result: (requires audio playback - not evaluated in headless run)
- qa_decision: keep
- mismatch_source: real_connected_speech
- notes: The first vowel in "dealing" reduces from AH to AX (schwa). This is a common reduction pattern in fast speech. Good teaching example for weak forms in unstressed syllables.

## Observation 3: Suspicious - "And" deletion cascade (possible_by_rule)

- timestamp_ms: 26449-26534
- sentence / words: "And we begin in the Philippines..." / "And"
- phone_range: token 0, phones 0-2
- connected_speech_family: deletion
- ui_label: "possible deletion"
- marker_status: possible_by_rule (NOT detected_in_audio)
- playback_window_ms: ~20ms
- playback_result: (requires audio playback - not evaluated in headless run)
- qa_decision: filter
- mismatch_source: unclear
- notes: Multiple "possible deletion" markers on sentence-initial "And" (ND cluster). Status is only "possible_by_rule", not detected in audio. This is exactly the kind of marker that should be default-hidden: it's a rule-based guess without audio evidence. If the speaker actually drops the /d/ here (common in fast speech), it's useful; if not, it's noise. The "possible_by_rule" status should trigger a lower-confidence display or be filtered from learner view by default.

## Observation 4: Resolved - old linking markers with empty expected symbols

- timestamp_ms: 30842-30883
- sentence / words: "And we begin in the Philippines..." / "And"
- phone_range: token 0, phone 52 (repeated 13 times for same phone)
- connected_speech_family: linking
- ui_label: "possible linking"
- marker_status: supported_by_audio
- playback_window_ms: ~41ms
- playback_result: (requires audio playback - not evaluated in headless run)
- qa_decision: fixed
- mismatch_source: rule_overgeneration
- notes: This was present in the pre-fix artifact only. The refreshed 2026-06-29 artifact emits no linking markers for the 5-sentence Brooklyn window. Keep this as a regression note: raw CTC insertion by itself is not enough evidence for learner-facing linking.

## Observation 5: Helpful - assimilation on "What's" (AHT→EI5)

- timestamp_ms: 11505-11526
- sentence / words: "What's up, sunshine?" / "What's"
- phone_range: token 0, phones 1-2
- connected_speech_family: assimilation
- ui_label: "possible assimilation"
- marker_status: detected_in_audio
- playback_window_ms: ~21ms
- playback_result: (requires audio playback - not evaluated in headless run)
- qa_decision: keep
- mismatch_source: real_connected_speech
- notes: "What's" AHT (AH + T) detected as EI5. The /t/ at end of "what's" often assimilates before "up". Could be a glottal stop or unreleased /t/. Worth keeping as a connected speech example, but the IPA label EI5 should be verified.

## Observation 6: Known false positive pattern - sentence-initial deletions

- timestamp_ms: 12446-12524
- sentence / words: "I'm Coy Wired here with your 10 minutes of news..." / "I'm"
- phone_range: token 0, phone 0
- connected_speech_family: deletion
- ui_label: "possible deletion"
- marker_status: possible_by_rule
- playback_window_ms: ~78ms
- playback_result: (requires audio playback - not evaluated in headless run)
- qa_decision: filter
- mismatch_source: alignment
- notes: Sentence-initial "I'm" getting a deletion marker for AY (the diphthong). This is likely an alignment artifact: the CTC model may align the first phone slightly differently. Not a real connected speech phenomenon for sentence onsets.

## Known False Positives

- Sentence-initial deletion markers (e.g., "And" D deletion, "I'm" AY deletion): likely alignment artifacts. All are `possible_by_rule` status. Recommendation: downgrade or hide `possible_by_rule` markers on first token of a sentence.
- Repeated linking markers on same phone with different observed symbols: resolved for learner-facing connected_speech by hiding generic insertion. Keep lower-level deduplication as future diagnostic work.

## Known False Negatives

- none observed (would require manual listening comparison against known weak forms and linking patterns in the audio)
