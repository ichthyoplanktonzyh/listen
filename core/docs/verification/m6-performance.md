# M6 Performance Verification

- Date: 2026-06-09
- Platform: macOS Apple Silicon

The packaged application imported and persisted a generated 2,100-cue subtitle
track through one API request. The transcript uses `ListView.builder`, word
profiles load through one deduplicated batch request, and the client timeline
uses binary partitioning before overlap resolution. Rust and Flutter each have
a fixed 2,100-cue final-position lookup test.

Playback position remains inside media_kit and the local cursor; it does not
send high-frequency HTTP requests. Progress is saved asynchronously every five
seconds rather than on each position event.

No blocking issue was observed during packaged smoke or visual runtime
inspection. This is an MVP functional budget, not a formal frame-time or memory
benchmark.
