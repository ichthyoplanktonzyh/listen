# Initial Third-party License Inventory

This is an M0 inventory, not legal advice.

| Dependency | Purpose | License / note |
|---|---|---|
| Flutter SDK | Flutter candidate UI | BSD-3-Clause |
| video_player | Flutter playback contract | BSD-3-Clause |
| fvp | Flutter libmdk adapter and Metal playback backend | BSD-3-Clause |
| libmdk binary SDK | Playback engine, VideoToolbox decoding, and Metal rendering | Bundled by fvp; distribution and commercial-use terms require final release review |
| Tauri | Tauri candidate shell | Apache-2.0 OR MIT |
| tauri-plugin-libmpv | Tauri libmpv embedding | MPL-2.0 |
| libmpv-wrapper | Plugin native wrapper | Verify release artifact license before distribution |
| Rust, Tokio, Axum, Serde | Shared core foundation | Review crate manifests before distribution |
| hound | Local PCM WAV parsing for audible-pause timing refinement | Apache-2.0 |
| reqwest/rustls | HTTPS dictionary provider | MIT OR Apache-2.0 |
| Free Dictionary API | Online definitions and phonetics | API described as free; server GPL-3.0; returned content provenance requires review before commercial distribution |
| file_selector | Native file selection | BSD-3-Clause |
| desktop_drop | Desktop file drag and drop | Apache-2.0 |
| ffmpeg / ffprobe | Embedded text-subtitle extraction and ASR audio conversion | Milestone 1.7 bundles a reproducible 8.0.1 arm64 build with GPL, nonfree, and version3 features disabled; release script verifies configuration |
| yt-dlp | Optional online-media URL resolution and explicit user-initiated download | Unlicense; supported sites and downloaded extractor dependencies may have separate terms; LLPlayerNext does not bypass DRM or access controls |
| whisper.cpp | Local ASR provider for generated learning subtitles | Milestone 1.7 bundles v1.7.6 arm64 from pinned source commit under MIT; models are explicit checksum-verified user downloads and are not redistributed |
| ECDICT | Optional offline English dictionary and lemma data | MIT; downloaded explicitly from a pinned source revision and checksum-verified |
| CMU Pronouncing Dictionary | Optional canonical en-US pronunciation data | BSD-style CMU license; downloaded explicitly from pinned revision `74790861` and checksum-verified |
| OpenSubtitles.com REST API | User-initiated subtitle search and download | User supplies an API key; requests obey service authentication, quotas, and terms |

The bundled `llplayer-prosodic-linear@v1` chunk-boundary model is
project-authored and distributed under MIT. It contains no third-party model
weights and does not add an external runtime dependency.

No LLPlayer source code is copied into this repository.
