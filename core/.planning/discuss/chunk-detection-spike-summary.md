# Chunk 声学边界检测 Spike 总结

## 日期

2026-06-13

## 目标

在 LLPlayerNext 现有 whisper.cpp DTW 词级时间戳基础上，实现基于词间间隙（inter-word gap）的声学 chunk 边界检测原型。验证「从词时间戳中检测韵律边界」这一方向的可行性。

## 产出物

| 文件 | 说明 |
|---|---|
| `crates/speech-analysis/src/chunk_detection.rs` | 核心检测模块，~320 行 |
| `crates/speech-analysis/tests/chunk_detection_integration_test.rs` | 5 个集成测试 |
| `crates/application/src/lib.rs` | +2 方法：`detect_sentence_chunks`、`detect_track_chunks` |

## 技术决策

### 算法：纯间隙阈值检测

```
gap = next_word.start_ms - current_word.end_ms
if gap >= threshold (default 250ms) → prosodic boundary
confidence = sigmoid-like mapping: gap→[0,1]
```

- 阈值 250ms 基于文献共识（200-300ms）
- 置信度：threshold 处 0.5，threshold+500ms 处 1.0
- Phase 1 仅使用间隙，标点提示/pitch/语速等特征预留于 `BoundaryMarker` 枚举但未实现

### 数据结构设计

`ChunkBoundary` 使用 `position`（timings 数组索引）作为主要位置引用，而非 `token_index`。原因是：当处理跨句面的 flat 列表时，`token_index` 会在每个句子重置为 0。`position` 始终是单调递增的，保证 chunk 构建的正确性。

### 集成方式

- 模块放在 `speech-analysis` crate 内（与 `asr_timing` 同级），而非新建 crate
- 零新增依赖
- 应用层通过 `AppServices::detect_sentence_chunks` 和 `detect_track_chunks` 暴露
- 首版不暴露 HTTP API（接口可能变化）

## 测试结果

### 单元测试：17 个全部通过

覆盖：空输入、单词、宽/窄间隙、threshold 边界值、极大间隙、跨句 track 隔离、gap_confidence 函数

### 集成测试：5 个全部通过

1. **Estimated timings → single chunk**：确认字符权重均匀分布不产生虚假边界
2. **Threshold sensitivity**：50/150/250/500ms 四个阈值下边界数单调递减
3. **Chunk text reconstruction**：chunk 文本拼接与原始词序完全一致
4. **Track isolation**：不同句子的 chunk 不会合并
5. **Real ASR fixture**：真实 whisper.cpp DTW 输出上检测正常运行，不 panic

## 已知限制

### 1. DTW 精度约束

whisper.cpp DTW 的 `t_dtw` 字段单位为厘秒（10ms），实际词时间戳被离散化为 10ms 或 100ms 的倍数。这导致：

- 真实语流中 180ms 和 200ms 的间隙无法区分
- 快速连续的功能词常被归并到同一 DTW 点（gap=0 或 1ms）
- 边界粒度受限于 DTW 帧步长，而非真实声学间隙

**结论：250ms 阈值在 DTW 精度下偏保守。实际检测到的边界偏向于较长停顿（500ms+）。**

### 2. 标点提示未实现

`WordTiming` 不含标点/上下文信息，`use_punctuation_hint` 选项目前是占位符。后续需要可选的 `&SubtitleSentence` 参数。

### 3. 缺少 Duration/Pitch 特征

纯间隙检测无法区分「韵律边界停顿」和「说话人犹豫/呼吸停顿」。文献表明 pitch reset 和 pre-boundary lengthening 能显著降低假阳性。

### 4. Estimated timings 几乎不产生边界

`estimate_word_timings` 按字符权重均匀分布时长，词间间隙接近 0。只有 ASR-reported 或 forced-aligned 的时序才能用于 chunk 检测。

## 敏感性分析

使用 50/150/250/350/500ms 五个阈值在 JFK fixture 数据上测试：

| 阈值 | 边界数 | 观察 |
|---|---|---|
| 50ms | 大量 | 几乎每个词间都是边界 — DTW 离散化导致最小间隙也是 100ms+ |
| 150ms | 很多 | 仍然捕获了 DTW 帧步长边界 |
| 250ms | 中等 | 默认值 — 过滤掉同一 DTW 帧内的连续词 |
| 350ms | 较少 | 仅保留明显的句子内部停顿 |
| 500ms | 很少 | 仅保留最显著的长停顿 |

**注意**：DTW 精度使得阈值敏感性分析的价值有限。真实声学信号中 200ms vs 250ms 的差别有意义，但 DTW 输出中两者的差异被量化噪声掩盖。

## 评估

### 成功标准达成情况

| 标准 | 结果 |
|---|---|
| 功能正确性 | ✓ 17 个单元测试 + 5 个集成测试全部通过 |
| 真实 world 正确性 | ✓ Real ASR fixture 检测运行不 panic，产生合理结果 |
| 跨阈值稳定性 | ✓ 边界数随阈值单调变化 |
| 零新增依赖 | ✓ Cargo.toml 无变化 |
| Clippy 零警告 | ✓ |
| 全项目无破坏 | ✓ `cargo test --workspace` 全部通过 |

### DM 精度对有效性的影响

DTW 的 10ms 粒度严重限制了基于间隙的 chunk 检测的原型价值。在后续工作中：

- **forced alignment（MFA 等）** 可以提供 ms 级精度，显著改善间隙检测
- **PSST 方式（Whisper fine-tune）** 直接端到端检测 IU 边界，绕过间隙分析
- **当前检测器作为架构占位符仍有价值**：接口已定义，切换后端时序源即可提升精度

## 下一步建议

1. **短期**：当 M2.0 Phase 0 产生 forced-aligned 或 phoneme-aligned 时序时，用相同接口重新评估间隙检测精度
2. **中期**：当 ASR-reported 时序精度提升后，加入 pre-boundary lengthening 特征（比较语块末词时长 vs 句内均值）
3. **长期**：评估 PSST 或等价模型的 OT 部署可行性，作为 `TimingSource::ForcedAligned` 或新的 `ProsodicModel` 来源
4. **文字层**：集成 PHRASE List 等语块词典，提供文字层标注作为声学边界的补充视角

## 与 M2.0 的关系

本 spike 与 M2.0 Phase 0 并行进行，共享以下目标：

- 两者都追求「理解真实语流的结构」（M2.0 在音素层，chunk 在韵律层）
- Chunk 检测器设计为可消费 M2.0 产出的更精确时序
- 接口不依赖 M2.0 的任何具体 Provider
