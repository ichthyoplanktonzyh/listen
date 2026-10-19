# M4 Verification Report

- Date: 2026-06-09
- Result: Passed

The desktop client renders clickable word tokens in the video overlay and
virtualized transcript. It loads all existing profiles through one batch API,
caches them by normalized lemma, and applies SSE updates without reloading the
track.

Global `Unclassified`, `UnknownMeaning`, `KnownNotRecognized`, and
`KnownRecognized` semantics are distinct from append-only
`RecognizedInContext` and `NotRecognizedInContext` observations. The word
dialog explains this difference. Status styles use underline shape and weight
in addition to color and can be disabled.

Evidence:

- Headless API smoke test covers batch state loading, persisted update, and
  context observation.
- SQLite foreign keys associate observations with profiles and sentences.
- Flutter transcript uses `ListView.builder` and the 2,100-cue packaged smoke
  test loads one complete timeline.
- Keyboard shortcuts `1`, `2`, and `3` update the first word in the current
  sentence for rapid training.
