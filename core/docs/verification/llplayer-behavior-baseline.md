# LLPlayer Clean-room Behavior Baseline

This document records externally observable behavior to reproduce or redefine.
It does not copy implementation code from LLPlayer.

## Timeline behavior

| Scenario | Expected behavior |
|---|---|
| Before first cue | No current cue; next points to the first cue. |
| At cue start | Cue becomes current immediately. |
| At cue end | Cue remains current at the exact end timestamp. |
| Between cues | No current cue; previous and next navigation remain available. |
| After final cue | No current cue; previous points to the final cue. |
| Overlapping cues | M0 prototypes use the latest-starting active cue and record the choice. |
| Subtitle offset | The same offset applies to current-cue lookup, seek, and loop boundaries. |

## Playback behavior

| Scenario | Expected behavior |
|---|---|
| Click subtitle | Seek to its effective start time using an accurate seek when available. |
| Previous/next | Navigate by cue order and clamp at the first or last cue. |
| Loop cue | Repeat the effective cue interval until disabled or the selected cue changes. |
| Position events | Drive local subtitle selection without an HTTP round trip. |
| Backend unavailable | Already loaded media and timeline continue basic playback and sync. |

## M0 acceptance scenarios

1. Open generated video and audio fixtures.
2. Observe position events while playing and paused.
3. Seek forward and backward to each cue start.
4. Click an interactive subtitle overlay.
5. Loop the second cue for at least five iterations.
6. Confirm gaps show no current subtitle.
7. Confirm overlap selection matches the documented latest-starting rule.
8. Confirm playback rate, volume, and track discovery are observable.
