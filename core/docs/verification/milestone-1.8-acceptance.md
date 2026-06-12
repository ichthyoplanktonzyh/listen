# Milestone 1.8 Acceptance Report

Status: **complete with documented AV1 playback limitation**

Latest automated acceptance: **2026-06-12**
Latest collaborative acceptance: **2026-06-12**

Package:

- `dist/LLPlayerNext-macos-arm64.zip`
- SHA-256:
  `9854b0639b36a8c01fd686835aa40132f79178550b7e9517995abbb3071428d3`

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
- [x] Restore saved playback position before starting playback, avoiding a
  visible jump from the beginning and preventing progress writes to the
  previously opened media

## Manual Acceptance

The user completed the original 20-item collaborative checklist and confirmed
ordinary video playback after the final player migration. Final disposition:

1. [x] Existing playback, dual subtitles, learning panel, notes, and ASR work.
2. [x] Current assets survive schema v7 migration and v3 export/import; repeated
   import preserves newer local state and does not duplicate sources.
3. [x] Common `go` forms normalize correctly and a user correction survives restart.
4. [x] A phrase candidate appears as an underline in the current subtitle, requires
   confirmation, can differ from its component words, and retains its source
   sentence and token range.
5. [x] ECDICT and CMUdict show provenance, install explicitly, and remove safely.
6. [x] OpenSubtitles title, filename, and media-hash searches work; downloads import
   as primary and secondary learning tracks.
7. [x] Invalid credentials or no network do not affect playback, and the API key
   is absent from logs and asset exports.
8. [x] Chinese/English UI and the packaged app behave normally.
9. [x] A dictionary result with pronunciation audio shows a play action and plays
   without interrupting the current video.
10. [x] Metal playback avoids the previous general black-frame regression and
    ordinary local video playback is accepted. AV1 video in the reported MP4
    and WebM samples remains a documented deferred limitation.
11. [x] yt-dlp download runs in the background without blocking playback, shows
    progress, can be cancelled, leaves one merged final MP4 in the selected
    directory, and opens the completed local file on request.
12. [x] A video with saved progress begins from the restored position without
    visibly playing from zero and jumping forward later.

The remaining AV1 playback limitation is accepted for `v0.6.0` and does not
block the release. No further player-backend investigation is planned during
Milestone 1.9.
