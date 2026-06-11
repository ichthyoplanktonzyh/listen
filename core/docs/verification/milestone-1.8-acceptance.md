# Milestone 1.8 Acceptance Report

Status: **awaiting collaborative manual acceptance**

Latest automated acceptance: **2026-06-11**

Package:

- `dist/LLPlayerNext-macos-arm64.zip`
- SHA-256:
  `443f26ac1194b3712b20660db9466b3cf0caceb92f940219499b29a4b4eaf4e1`

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
10. Software rendering avoids black video frames and remains acceptable for
    representative high-resolution and long-running playback.

The release commit and `v0.6.0` tag remain blocked on user confirmation.
