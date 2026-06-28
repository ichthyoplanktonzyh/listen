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
- [ ] PhoneTimeline with sound_analysis.learning_phones
- [ ] sound_analysis.connected_speech markers present

## Generation Steps

### Step 1: Generate base LLTimeline (completed)

```sh
# Extract audio
ffmpeg -hide_banner -loglevel error -y \
  -i "~/Desktop/视频/How a cell phone ban...mp4" \
  -vn -ac 1 -ar 16000 -sample_fmt s16 \
  /tmp/p217-brooklyn/media/audio-16k-mono.wav

# Run WhisperX
~/Library/Caches/LLPlayerNext/research/timeline-production/venv/bin/whisperx \
  /tmp/p217-brooklyn/media/audio-16k-mono.wav \
  --model small --output_dir /tmp/p217-brooklyn/whisperx \
  --output_format json --language en --device cpu \
  --compute_type float32 --batch_size 16

# Convert to LLTimeline
python3 scripts/timeline-production/production_pipeline.py from-whisperx-json \
  --input /tmp/p217-brooklyn/whisperx/audio-16k-mono.json \
  --media-fingerprint "brooklyn-news-2026" \
  --media-title "Brooklyn middle school cell phone ban - June 9 2026" \
  --algorithm-id "whisperx-small-en" --algorithm-version "small-cpu-v1" \
  --language en --output /tmp/p217-brooklyn/p217-brooklyn-news-001.lltimeline.json
```

Output: 114 segments, 1771 words, schema `llplayer.timeline.v1`.
This full transcript timeline is local-only and must not be committed to the repo.

### Step 2: Generate PhoneTimeline with sound_analysis (pending)

REQUIRES: App running with audio file accessible via track import.
The Flutter app triggers phonetic analysis through the Rust API server.
After phone analysis completes, the LLTimeline will contain:
- `phone_timelines` with `sound_analysis.learning_phones`
- `sound_analysis.connected_speech` markers

Then export via:
```sh
python3 scripts/lltimeline-resource.py export --track-id <track_id> \
  --output /tmp/p217-brooklyn/p217-brooklyn-news-001.with-phones.lltimeline.json
```

## Observation 1

- timestamp_ms:
- sentence / words:
- phone_range:
- connected_speech_family:
- ui_label:
- marker_status:
- playback_window_ms:
- playback_result:
- qa_decision: keep | filter | downgrade | needs_provider_investigation
- mismatch_source: timing | phone_identity | transcript_alignment | unclear | none
- notes:

## Observation 2

- timestamp_ms:
- sentence / words:
- phone_range:
- connected_speech_family:
- ui_label:
- marker_status:
- playback_window_ms:
- playback_result:
- qa_decision: keep | filter | downgrade | needs_provider_investigation
- mismatch_source: timing | phone_identity | transcript_alignment | unclear | none
- notes:

## Observation 3

- timestamp_ms:
- sentence / words:
- phone_range:
- connected_speech_family:
- ui_label:
- marker_status:
- playback_window_ms:
- playback_result:
- qa_decision: keep | filter | downgrade | needs_provider_investigation
- mismatch_source: timing | phone_identity | transcript_alignment | unclear | none
- notes:

## Known False Positives

## Known False Negatives
