# Initial Third-party License Inventory

This is an M0 inventory, not legal advice.

| Dependency | Purpose | License / note |
|---|---|---|
| Flutter SDK | Flutter candidate UI | BSD-3-Clause |
| media_kit packages | Flutter playback candidate | MIT |
| libmpv/mpv | Playback engine | Build-dependent GPL/LGPL implications; review before distribution |
| Tauri | Tauri candidate shell | Apache-2.0 OR MIT |
| tauri-plugin-libmpv | Tauri libmpv embedding | MPL-2.0 |
| libmpv-wrapper | Plugin native wrapper | Verify release artifact license before distribution |
| Rust, Tokio, Axum, Serde | Shared core foundation | Review crate manifests before distribution |
| reqwest/rustls | HTTPS dictionary provider | MIT OR Apache-2.0 |
| Free Dictionary API | Online definitions and phonetics | API described as free; server GPL-3.0; returned content provenance requires review before commercial distribution |
| file_selector | Native file selection | BSD-3-Clause |
| desktop_drop | Desktop file drag and drop | Apache-2.0 |
| ffmpeg / ffprobe | Optional embedded text-subtitle extraction | Distribution build and codec license implications must be reviewed before bundling; M8 initially discovers a user-installed executable |
| yt-dlp | Optional online-media URL resolution | Unlicense; supported sites and downloaded extractor dependencies may have separate terms; M8 does not bypass DRM or access controls |
| whisper.cpp | Planned local ASR provider for generated learning subtitles | MIT; model provenance, model download terms, bundled binaries, Metal/Core ML artifacts, and release notices require review before distribution |

No LLPlayer source code is copied into this repository.
