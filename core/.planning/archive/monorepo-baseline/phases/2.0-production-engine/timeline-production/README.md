# Timeline Production System

更新时间：2026-06-19 15:51:14 CST

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
    gold-dataset-strategy.md
  research/
    toolchain-options.md
```

## Current Focus

Phase 1、Phase 2 和 Phase 3 的基础能力已完成。客观评估体系已经证明 MFA
`english_us_arpa + align-one` 是当前高质量 transcript 条件下最强的已观测词边界
对齐器；继续扩大实验暂时暂停。本目录进入长期研究和生产脚本维护状态。下一阶段
将启动 app 端时间轴资源 UI 对齐，规划见：

- [`Phase 2.2 Context`](../2.2-app-timeline-resource-ui/2.2-CONTEXT.md)
- [`Phase 2.2 Plan`](../2.2-app-timeline-resource-ui/2.2-PLAN.md)

当前 production pipeline 的阶段性收口形态：

1. `produce-whisperx` 继续作为一键入口，负责媒体准备、WhisperX 转录和
   `.lltimeline.json` 输出。
2. `--post-aligner auto|mfa|mms-fa|none` 将对齐阶段做成可插拔策略；
   `auto` 和 `mfa` 默认按 MFA -> MMS_FA -> WhisperX 原始时间轴降级。
3. `apply-mfa-alignment` / `apply-mms-fa-alignment` 支持对已有
   `.lltimeline.json` 和音频单独追加对齐时间轴。
4. `production-report.json` 继续作为进入人工复核前的质量入口。
5. 下一步开始和 app 端 UI 对齐：资源导入、WordTimeline 选择/激活、人工校正入口、
   chunk timeline 生成与消费端高亮/播放体验。
