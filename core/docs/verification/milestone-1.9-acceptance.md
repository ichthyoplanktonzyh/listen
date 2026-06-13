# Milestone 1.9 Acceptance Report

Status: **fully accepted**

Latest automated acceptance: **2026-06-12**
Latest collaborative functional acceptance: **2026-06-13**

## Automated Gates

- [x] Rust formatting, workspace tests, and clippy
- [x] Flutter analysis and widget tests
- [x] Contract validation and historical verification
- [x] M1.9 pronunciation, rule-catalog, and word-timing verification
- [x] macOS release archive creation and metadata validation
- [x] Independent packaged-app launch smoke disposition recorded as deferred
  distribution work

The current Mac now reports one valid Apple Development identity backed by its
private key. Xcode successfully signs with it, confirming that the original
keychain problem is resolved. However, Apple Development signed apps are still
terminated by system policy when launched directly or after being copied from
the Xcode build directory. On 2026-06-13, the user explicitly accepted M1.9
with this limitation and deferred Developer ID distribution signing,
notarization, and independent archive launch to later release work.

## Collaborative Acceptance

The user completed functional acceptance through the repository development
run workflow and confirmed:

1. [x] Ordinary video, AV1 video, audio, playback controls, and subtitles work.
2. [x] Ordinary SRT/VTT subtitles follow sentence timing normally.
3. [x] Estimated word timings advance the current-word highlight during playback.
4. [x] Seeking, pausing, resuming, looping, and rate changes restore the current
   word correctly.
5. [x] Word learning-status styles remain visible without conflicting with the
   current-word highlight.
6. [x] Sentence pronunciation, pronunciation diagnostics, and rule predictions
   remain available without claiming real-audio detection.
7. [x] Word timing provenance remains available in diagnostics but no longer
   occupies the playback subtitle overlay.
8. [x] Current-word presentation supports background highlight, scale bounce,
   and glow. Underline was intentionally excluded because phrase candidates
   already use underline as a distinct learning interaction.
9. [x] Current-word style and intensity settings persist.
10. [x] Disabling pronunciation and word-sync enhancements does not block normal
    playback, subtitles, or vocabulary-status interaction.

## Acceptance Fixes

Manual acceptance found that the desktop parsed the API fields
`timing_source` and `provider_id` as the nonexistent fields `source` and
`provider`. The resulting exception prevented speech enhancements from loading
and left current-word highlighting inactive. The mapping was corrected and a
contract-shaped regression test was added.

## Standard Functional Test Fallback

When double-clicking a newly built `.app` is unavailable because of local
signing or AMFI policy, use the development run workflow documented in
`docs/development/macos-functional-testing.md`. This is the accepted M1.9
functional testing workflow until independent distribution work resumes.
