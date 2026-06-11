# Milestone 1.8 Acceptance Report

Status: **awaiting Metal-player and download revalidation**

Latest automated acceptance: **2026-06-11**

Package:

- `dist/LLPlayerNext-macos-arm64.zip`
- SHA-256:
  `d2e97ad1bc9af34ea205cde3d6dfa0cbec3b0e89af01e5a0753fe0694a86d0bd`

## Automated Gates

- [x] Rust formatting, tests, and clippy
- [x] Flutter analysis and widget tests
- [x] Contract validation and historical verification
- [x] M1.8 lexical/provider verification
- [x] macOS Apple Silicon package and smoke test
- [x] Subtitle-native phrase underline interaction
- [x] Vocabulary asset v3 conflict merge and repeated-import idempotency
- [x] OpenSubtitles visible setup/search workflow
- [x] Provider-supplied pronunciation audio contract and widget action
- [x] Xcode 26.5 OpenGL black-frame diagnosis and software-rendering workaround
- [x] Replace the degraded software-rendering workaround with an fvp/libmdk
  VideoToolbox and Metal playback backend
- [x] Add explicit background yt-dlp video download with destination, progress,
  cancel, H.264 preference, bundled-ffmpeg stream merge, and open-after-download

## Manual Acceptance

Record each item as pass, fail, or pending:

1. Existing playback, dual subtitles, learning panel, notes, and ASR work.
2. Current assets survive schema v7 migration and v3 export/import; repeated
   import preserves newer local state and does not duplicate sources.
3. Common `go` forms normalize correctly and a user correction survives restart.
4. A phrase candidate appears as an underline in the current subtitle, requires
   confirmation, can differ from its component words, and retains its source
   sentence and token range.
5. ECDICT and CMUdict show provenance, install explicitly, and remove safely.
6. OpenSubtitles title, filename, and media-hash searches work; downloads import
   as primary and secondary learning tracks.
7. Invalid credentials or no network do not affect playback, and the API key
   is absent from logs and asset exports.
8. Chinese/English UI and the packaged app behave normally.
9. A dictionary result with pronunciation audio shows a play action and plays
   without interrupting the current video.
10. Metal playback avoids black video frames for ordinary local media, the
    reported AV1 MP4 and WebM samples, and remains smooth for representative
    high-resolution and long-running playback.
11. yt-dlp download runs in the background without blocking playback, shows
    progress, can be cancelled, leaves one merged final MP4 in the selected
    directory, and opens the completed local file on request.

The release commit and `v0.6.0` tag remain blocked on revalidation of items 1,
6, 8, 9, 10, and 11 after the player-backend migration.
