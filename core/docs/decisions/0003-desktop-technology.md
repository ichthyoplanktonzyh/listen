# ADR 0003: Desktop Technology Selection

- Status: Accepted
- Date: 2026-06-09

## Candidates

1. Flutter + media_kit/libmpv
2. React + TypeScript + Tauri + libmpv

## Decision gate

Select a candidate after macOS Apple Silicon verification demonstrates video
and audio playback, stable position events, accurate seeking, interval looping,
track discovery, and a clickable subtitle overlay.

Windows and Linux implementation risks must be recorded but do not block M1.

## Current evaluation

- **React/TypeScript + Tauri + tauri-plugin-libmpv:** rejected for the current
  implementation. It builds and plays media on macOS, but creates a separate
  mpv window, preventing an interactive WebView subtitle overlay.
- **Flutter + media_kit:** accepted. Release build and runtime verification pass
  on macOS Apple Silicon. Video is embedded in the Flutter window, interactive
  subtitle overlay remains available, generated video and audio open, position
  events and track discovery work, and seek/loop diagnostics pass.

## Decision

Use Flutter + media_kit as the macOS MVP desktop client and player adapter
baseline. Proceed into M1 without waiting for Windows or Linux implementation.

Keep the player adapter contract independent of Flutter and media_kit types.
Revisit the decision if CocoaPods/Swift Package Manager compatibility,
packaging, or long-session playback reliability becomes unacceptable.
