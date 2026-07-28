# Deferred Aligner Directions

更新时间：2026-06-19 15:51:14 CST

本文记录 2026-06-19 关于 WhisperX、MFA、Qwen3-ForcedAligner、BFA/easytranscriber
等路线的阶段性判断。当前不继续扩展实验和测评，先把已验证主线推进到“本地重装
生产环境可直接跑”。本文作为后续重新评估对齐器路线时的参考。

## 当前主线判断

短期生产主线应保持可插拔、可降级：

```text
WhisperX / Whisper Large-v3
  -> 生成高质量 transcript、VAD segment、初始 word timeline
  -> 统一 tokenizer / normalization
  -> 可选声学后处理：MFA align-one / MMS_FA / future aligner
  -> 降级链：MFA -> MMS_FA -> WhisperX 原始时间轴
  -> 写入新的 WordTimeline 候选/active timeline
  -> 生成 .lltimeline.json 资源
  -> 后续人工校正、chunk timeline 生成、发布消费
```

WhisperX 适合作为长音频生产入口，而不是唯一的边界真理。它的优势是成熟的
长音频管线：VAD 切分、Whisper ASR、批处理、对齐输出。我们的 TIMIT 对照显示，
完整 WhisperX CLI 的 transcript 可用性很好，但词边界精度不是当前最强。

MFA 适合作为当前生产端高精度后处理器。已验证的 `english_us_arpa + align-one`
路线在 TIMIT TEST 100 上显著优于 MMS_FA 和 WhisperX CLI 的词边界结果。因此短期
优先目标是让 `WhisperX transcript + MFA align-one` 在生产命令中跑通，并保留
MMS_FA 与 WhisperX 原始时间轴作为可回退资源。

## 延后研究候选

### Qwen3-ForcedAligner

Qwen3-ForcedAligner-0.6B 是非常值得后续验证的新路线。它是面向文本-语音对齐的
NAR timestamp predictor，宣称在多语言、速度和资源占用上优于若干强基线。

后续进入候选评估时，需要先确认：

- 模型权重和推理脚本是否稳定可得。
- license 是否允许本地生产使用。
- macOS 本地 CPU/GPU 可运行性。
- 输出粒度是否能稳定映射到 LLTimeline word/phone schema。
- 在同一批 TIMIT/Buckeye 样本上的 start/end/tail 指标是否优于 MFA。

### BFA / easytranscriber / CTC 工具链

BFA 和 easytranscriber 代表更轻、更快、更适合未来本地化的 CTC forced alignment
方向。它们可能成为生产端加速或消费端轻量候选，但当前不抢主线优先级。

后续验证重点：

- 是否能输出稳定的 word + phone 边界。
- 是否显式建模 silence/gap，能否改善 chunk 划分。
- offset/tail 边界是否受 CTC peaky posterior 影响。
- 是否比 MFA 更容易部署到 Rust/ONNX/本地 runtime。

### MMS_FA

MMS_FA 仍保留为轻量级研究/回退路线。它在高质量 transcript 条件下表现可用，但
目前不是生产端边界精度最强路线。未来可以作为：

- 重型 MFA 不可用时的 fallback。
- Rust/ONNX 本地化前的轻量声学对齐参考。
- 与消费端轻量能力相关的长期候选。

## 暂停事项

当前暂停继续扩大 benchmark 和新工具实验，不再立刻跑 Qwen3/BFA/Buckeye/CNN10
样本。恢复研究时，再统一使用同一套 LLTimeline schema、tokenizer、normalization
和 TIMIT/Buckeye gold 对照矩阵。

## 当前执行优先级

1. 让 production pipeline 在重装生产环境中一条命令可跑。
2. 让 WhisperX 原始时间轴、MFA 后处理时间轴、MMS_FA 回退时间轴都落成同一种
   `.lltimeline.json` WordTimeline 资源。
3. 让 `production-report.json` 能指示当前 active timeline 是否可进入人工复核。
4. 开始把资源导入、时间轴选择、人工复核和后续 chunk 生成与 app 端 UI 对齐。
