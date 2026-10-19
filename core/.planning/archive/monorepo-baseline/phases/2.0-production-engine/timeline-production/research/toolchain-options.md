# Toolchain Options

更新时间：2026-06-18 15:11:06 CST

本文件记录生产端可选工具链。当前结论：生产端可以重，消费端必须轻。

## Candidate Tools

- ASR：Whisper Large-v3 / future stronger ASR models。
- Word alignment：WhisperX。
- Phone alignment：MFA / BFA / future Rust+ONNX aligner。
- Audio preprocessing：ffmpeg、Demucs、UVR、VAD。
- Speaker evidence：pyannote 或其他 diarization provider。

## Integration Rule

所有工具最终都输出或补充 `LLTimeline JSON v1`。生产端工具链可以替换，消费端资源
契约必须稳定。

