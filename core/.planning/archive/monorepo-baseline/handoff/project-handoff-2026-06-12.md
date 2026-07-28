# LLPlayerNext Project Handoff: 2026-06-12

## Current Status

- Milestone 1.8 / version 0.6.0 is complete.
- The release includes the playback-progress restoration fix that prevents a
  video from visibly starting at zero and jumping to its saved position later.
- Milestone 1.9 is the next active milestone.

## Accepted Playback Decision

The general macOS black-frame regression caused by media_kit_video's deprecated
OpenGL path was addressed by migrating to video_player/fvp/libmdk with Metal.
Ordinary video playback is accepted.

The reported AV1 MP4 and AV1 WebM samples can still play audio with a black
video frame. This limitation is deferred and does not block version 0.6.0.
Use H.264 downloads or an H.264 compatibility copy until an upstream fix or a
separately planned player evaluation is available.

The branch `fix/webm-vp8-vp9-decoders` records the investigation. Do not merge
its custom FFmpeg replacement: the actual sample is AV1, the replacement did
not solve the black frame, and it increases ABI and packaging risk.

## Milestone 1.9 Start

The authoritative plan is `docs/planning/milestone-1.9.md`. Begin with Phase 0:

1. Audit subtitle tokens, ASR timing metadata, and the local playback timeline.
2. Verify CMUdict format, stress data, coverage, and license.
3. Verify whisper.cpp word/token timestamp capability.
4. Design deterministic estimated word timings for ordinary SRT/VTT.
5. Produce an ADR selecting the first pronunciation provider, internal phoneme
   set, IPA mapping, and timing-source priority.

Milestone 1.9 must not claim rule-based speech hints were detected in the real
audio. Actual audio phoneme recognition remains Milestone 2.0.
