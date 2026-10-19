# Stack

- Rust edition 2024, minimum Rust `1.94`, workspace version `0.7.0`
- Axum `0.8`, Tokio `1`, Serde, Reqwest/rustls
- SQLite through bundled `rusqlite`
- Python 3 tooling for production/evaluation/release helpers
- Bash wrappers for local validation and runtime assembly
- OpenAPI 3.1 canonical document validated with OpenAPI Generator `7.24.0`
- macOS arm64 runtime bundle containing `api-http`, `whisper-cli` (owned by
  learner-recording transcription), FFmpeg/ffprobe (shared by sound-line, media
  scanning and other Core paths) and notices/manifest

Heavy research dependencies live in isolated script-managed environments and
are not normal Rust/consumer runtime dependencies.
