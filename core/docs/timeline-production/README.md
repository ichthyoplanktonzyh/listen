# Timeline Production System

更新时间：2026-06-18 15:36:01 CST

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
docs/timeline-production/
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

Phase 1 已完成。当前阶段转入 Resource Lifecycle：

1. 让一个媒体拥有多个可管理 timeline 版本。
2. 补齐删除/归档/激活/导入后的 active resource 语义。
3. 为生产端重管线、评估体系和人工校正 UI 准备稳定资源生命周期。
