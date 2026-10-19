# ADR 0002: Local Platform-neutral Player Contract

- Status: Accepted
- Date: 2026-06-09

## Decision

Player rendering and high-frequency playback behavior remain inside the desktop
client. Commands and events use the schemas under `contracts/player-adapter`.
Time values are integer milliseconds. Adapter types must not expose media_kit,
mpv, or native platform types.

The target position-event interval is at most 250 ms. Initial seek and loop
boundary error targets are at most 300 ms; M0 verification records actual
results rather than treating these targets as guaranteed capabilities.

## Consequences

- Subtitle synchronization and interval looping do not depend on HTTP.
- Future Windows, Linux, Android, and iOS adapters reuse the same contract tests.
- Rust application services remain transport- and player-independent.
