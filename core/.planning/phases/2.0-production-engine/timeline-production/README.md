# Timeline Production System

更新时间：2026-06-18 19:30:22 CST

本目录收纳“本地重装生产引擎 + 轻量消费端时间轴资源读取”路线下的长期文档。
后续所有与精准词/音素时间轴、生产端数据管线、评估体系、人工校正和
`.lltimeline.json` 资源格式相关的设计与实施记录，优先放入本目录。

## Product Split

LLPlayerNext 后续围绕两个协同身份推进：

- **本地重装生产引擎**：面向个人高质量内容生产，允许使用 Python、GPU、
  Whisper Large-v3、WhisperX、MFA/BFA、VAD、人声分离和人工校正，目标是
  生成可评估、可复用、可发布的精准时间轴资源。
- **轻量消费端 LLPlayerNext**：面向分发和日常学习，不内置重模型，读取生产端
  产出的 `.lltimeline.json`，驱动词级高亮、chunk 播放和学习交互。

## Directory Layout

```text
.planning/phases/2.0-production-engine/timeline-production/
  README.md
  plans/
    production-engine-roadmap.md
  contracts/
    lltimeline-json-v1.md
  implementation/
    implementation-log.md
  evaluation/
    benchmark-and-metrics.md
  research/
    toolchain-options.md
```

## Current Focus

Phase 1、Phase 2 和 Phase 3 已完成。当前阶段转入客观评估体系：

1. 比较不同 WordTimeline 候选的边界偏移、覆盖率、overlap/gap 和尾词 lag。
2. 建立 CNN10/NBC 自建 gold sample，并接入 TIMIT/Buckeye 小样本。
3. 将 `production-report.json` 与后续 evaluation artifact 关联起来。

Phase 3 已收尾：已落地外部 WhisperX JSON 到 `.lltimeline.json` 的转换桥、
ffmpeg 音频准备入口、预处理 artifact、可插拔外部人声分离命令、
`run-whisperx`/`produce-whisperx` 重模型调用和一键编排入口，以及面向人工复核
入口的 `production-report.json`。
