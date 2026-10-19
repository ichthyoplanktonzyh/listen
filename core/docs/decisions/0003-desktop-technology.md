# ADR 0003: Desktop Technology Selection

- Status: Accepted
- Date: 2026-06-09

## Candidates

1. Flutter + media_kit/libmpv
2. Flutter + video_player/fvp/libmdk
3. React + TypeScript + Tauri + libmpv

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
- **Flutter + video_player/fvp:** selected after Xcode 26.5 clean builds made
  media_kit_video's deprecated OpenGL texture path output black frames. fvp
  uses VideoToolbox hardware decoding and a Metal renderer on macOS while
  preserving embedded track selection and the Flutter subtitle overlay. The
  repository vendors a minimal macOS fvp patch that creates the Flutter texture
  through `CVMetalTextureCache` and waits for the Metal blit command buffer
  before publishing each frame.

## Decision

Use Flutter + video_player/fvp as the macOS desktop player baseline. Keep
player controls behind the project-owned adapter and do not expose fvp or
video_player track types to the rest of the client.

The packaged libmdk framework is sanitized to remove Homebrew and `/usr/local`
runtime search paths before signing. Revisit the decision if distribution
terms, packaging, or long-session playback reliability becomes unacceptable.
