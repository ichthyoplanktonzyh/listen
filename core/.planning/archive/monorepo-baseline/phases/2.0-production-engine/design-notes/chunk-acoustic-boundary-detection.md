# Chunk 声学边界检测 — 调研报告

> **Feature:** `feature/chunk-listening-comprehension`
> **Status:** spike completed (gap-based prototype)
> **Related:** [`chunk-based-listening-comprehension.md`](../discuss/chunk-based-listening-comprehension.md), [`chunk-detection-spike-summary.md`](../discuss/chunk-detection-spike-summary.md)

## Overview

本文档记录在实现 Chunk 声学边界检测之前对两个方向的详细调研：

1. **LLPlayerNext 现有词级时间戳基础设施** — 有什么数据可用、数据结构如何、数据怎样从 Rust 核心流向 Flutter 前端
2. **韵律边界检测的学术研究和开源项目** — PSST 等模型的架构、效果、可集成性

## 一、现有词级时间戳基础设施

### 1.1 核心数据类型

所有类型定义在 `crates/domain/src/lib.rs`。

**`TimingSource` 枚举** (lines 235-241)：

```rust
pub enum TimingSource {
    AsrReported,     // priority 3 — whisper.cpp DTW 产出的词时间戳
    ForcedAligned,   // priority 2 — MFA 等强制对齐工具产出
    Estimated,       // priority 1 — 按字符权重估算（fallback）
    UserAdjusted,    // priority 4 — 用户手工修正
}
```

**`WordTiming` 结构体** (lines 244-255)：

```rust
pub struct WordTiming {
    pub sentence_id: SubtitleSentenceId,  // 所属字幕句
    pub token_index: u32,                // 该句内的 token 索引
    pub text: String,                    // 原始词形
    pub start_ms: u64,                   // 开始时间 (ms)
    pub end_ms: u64,                     // 结束时间 (ms)
    pub confidence: Option<f32>,         // 置信度 (DTW 不提供)
    pub timing_source: TimingSource,     // 来源类型
    pub provider_id: String,             // 提供者标识
    pub provider_version: String,        // 提供者版本
}
```

`SubtitleSentenceId` 通过 `string_id!` 宏生成，自动派生 `Debug + Clone + PartialEq + Eq + Hash + Serialize + Deserialize`，可用作 HashMap key。

**`SubtitleSentence` 结构体** (lines 124-133)：

```rust
pub struct SubtitleSentence {
    pub id: SubtitleSentenceId,
    pub index: u32,
    pub start: TimeMs,           // 句级开始时间
    pub end: TimeMs,             // 句级结束时间
    pub original_text: String,
    pub display_text: String,
    pub tokens: Vec<SubtitleToken>,  // 含 Word/Whitespace/Punctuation/Other
}
```

**`SubtitleToken` 结构体** (lines 144-152)：

```rust
pub struct SubtitleToken {
    pub index: u32,
    pub kind: SubtitleTokenKind,       // Word | Whitespace | Punctuation | Other
    pub text: String,
    pub normalized: Option<String>,    // 规范化形式（小写等）
    pub start_char: u32,
    pub end_char: u32,
}
```

### 1.2 ASR 时序提取流程

核心模块：`crates/speech-analysis/src/asr_timing.rs`

**数据流：**

```
whisper.cpp -ojf JSON
  │  WhisperSegment { text, tokens: WhisperToken { text, t_dtw } }
  │  t_dtw 单位：厘秒（centisecond），-1 表示不可用
  │
  ├─ extract_word_timings_from_json(json_bytes, sentences)
  │   │ 要求 segment 数与 sentence 数 1:1 匹配
  │   │
  │   └─ extract_sentence_word_timings(segment, sentence)
  │       ├─ 过滤：仅保留 Word 类 token
  │       ├─ merge_tokens_to_words(whisper_tokens)
  │       │   ├─ 以 leading-whitespace 切分新词
  │       │   ├─ 无前导空格的 token 追加到当前词
  │       │   ├─ 跳过特殊 token ([_BEG_]_, <|...|>)
  │       │   └─ 跳过 t_dtw=-1 的 token
  │       ├─ word_count 验证：merged 词数 == 词汇 token 数
  │       │   不匹配 → 静默回退（返回空 Vec，不报错）
  │       └─ word_boundaries(merged_words, sentence_range)
  │           ├─ DTW centiseconds → milliseconds (x10)
  │           ├─ 每词 start=首子词 t_dtw, end=下词 start
  │           ├─ 重复 DTW 点强制 +1ms 分离
  │           └─ 夹紧到句边界 + 单调性验证
```

**ASR 时序的精度约束：**

- DTW `t_dtw` 以厘秒为单位（10ms 精度），**实际被量化为 100ms 步长**（whisper.cpp 的 mel 帧步长）
- 连续功能词常归并到同一 DTW 点，词间 gap 为 0 或 1ms
- `confidence` 字段始终为 `None`（whisper.cpp DTW 不提供逐词置信度）

### 1.3 Fallback 时序估算

`crates/speech-analysis/src/lib.rs` — `estimate_word_timings()`

- 按字符权重（clamped 2-12 字符/词）均匀分配句时长
- `timing_source = Estimated`，`confidence = Some(0.35)`
- 词间 gap 接近 0（均匀分配），**几乎不产生 chunk 边界**

### 1.4 持久化与 API

**SQLite 存储**（migration `0008_pronunciation.sql`）：

```sql
CREATE TABLE word_timings (
  sentence_id TEXT PRIMARY KEY REFERENCES subtitle_sentences(id) ON DELETE CASCADE,
  timing_source TEXT NOT NULL,
  provider_id TEXT NOT NULL,
  provider_version TEXT NOT NULL,
  timings_json TEXT NOT NULL,    -- Vec<WordTiming> 序列化为 JSON
  updated_at_ms INTEGER NOT NULL
);
```

- 整句的所有 `Vec<WordTiming>` 序列化为一个 JSON blob 存入 `timings_json`
- `timing_source`、`provider_id`、`provider_version` 为冗余索引列

**HTTP API：**

```
GET  /v1/subtitles/{track_id}/word-timings
POST /v1/subtitles/{track_id}/word-timings   (upsert)
```

**应用层缓存：**

`AppServices::word_timings(sentence_id)` 的缓存策略：
- 若已缓存且非 Estimated（或为特定 estimator v1）且所有 start < end → 返回缓存
- 否则 → fallback 到 `estimate_word_timings` → 保存到缓存

### 1.5 与 Chunk 检测的关系

| 现有能力 | Chunk 检测的利用方式 |
|---|---|
| `WordTiming.start_ms` / `WordTiming.end_ms` | 计算词间 gap：`next.start_ms - current.end_ms` |
| `TimingSource::AsrReported` | 有意义的 chunk 检测需要 ASR 时序（Estimated 几乎无 gap） |
| `SubtitleSentence.tokens` | 未来可用于标点提示（token kind = Punctuation → 降低 threshold） |
| Track 级 API | `word_timings_for_track` 返回逐句时序，chunk 检测逐句独立运行 |
| **不存在** 任何 gap/silence/pause 分析 | Chunk 检测是完全新增的能力 |

### 1.6 文件索引

| 关注点 | 文件 |
|---|---|
| `WordTiming`、`TimingSource`、`SubtitleSentence` 定义 | `crates/domain/src/lib.rs` (lines 124-255) |
| ASR DTW 时序提取 | `crates/speech-analysis/src/asr_timing.rs` |
| Fallback 估算 | `crates/speech-analysis/src/lib.rs` (lines 256-298) |
| ASR 时序集成测试 | `crates/speech-analysis/tests/asr_timing_integration_test.rs` |
| 应用服务层缓存与聚合 | `crates/application/src/lib.rs` (lines 798-859) |
| HTTP API handler | `crates/api-http/src/lib.rs` (lines 545-593) |
| 转写 → ASR 时序 pipeline | `crates/api-http/src/transcription.rs` (lines 517-565) |
| SQLite 表结构 | `crates/persistence-sqlite/migrations/0008_pronunciation.sql` |
| SQLite 读写 | `crates/persistence-sqlite/src/lib.rs` (lines 1230-1276) |
| Flutter Dart 模型 | `apps/desktop/lib/models/timeline.dart` (lines 65-104) |

---

## 二、韵律边界检测：学术研究与开源项目

### 2.1 PSST — 当前最优方案

**全称**：Prosodic Speech Segmentation with Transformers
**出处**：Roll, Graham & Todd (2023), CoNLL 2023
**代码**：[github.com/Nathan-Roll1/PSST](https://github.com/Nathan-Roll1/PSST)
**模型**：[huggingface.co/NathanRoll/psst-medium-en](https://huggingface.co/NathanRoll/psst-medium-en)

#### 核心思路

对 OpenAI Whisper（medium.en，764M 参数）进行端到端 fine-tune，直接输出带 Intonation Unit (IU) 边界标记的文本。通过重新利用 Whisper tokenizer 中的低频 token（`!!!!!` 五个连续感叹号）作为 IU 边界标记。

#### 效果

| 指标 | 值 | 说明 |
|---|---|---|
| **Accuracy** | 95.8% | 在 Santa Barbara 口语语料库测试集上 |
| **F1** | 0.87 | 当前英语韵律切分的 state-of-the-art |
| **Labeler ceiling** | 93.4% | 人工标注者间一致性的理论上限 |

#### 消融实验（揭示特征贡献）

| 变体 | F1 | 含义 |
|---|---|---|
| **Full PSST** (acoustic + lexical) | 0.87 | 融合最优 |
| **PSST-Acoustic-only** (syntax-masked) | 0.71 | 仅声学特征 |
| **Lexical-only** (GPT-Neo 1.2B, text only) | 0.77 | 仅词汇句法特征 |

**结论**：lexical（句法）特征贡献约 60%，acoustic（声学）特征贡献约 40%，两者互补。

#### 跨方言泛化

- **IViE 语料库**（英式英语，不同标注方案）：F1 = 0.73，Accuracy = 93%
- **关键发现**：acoustic-only 模型在跨方言场景完全崩溃（F1 = 0.00），**lexical 特征对跨域泛化至关重要**

#### 信号过滤实验

- 3.2 kHz 低通滤波带来微弱提升（~0.1%）
- 200-1600 Hz 频段（约 F1-F2 共振峰区域）承载了最多有用信息
- **这一发现出乎意料**：作者预期 F0 在语调中的作用更大，但结果表明共振峰结构对边界检测同样重要

#### 架构细节

- 基于 Whisper 的 encoder-decoder transformer
- Encoder：2 层卷积 (GELU) + sinusoidal positional encoding + transformer blocks
- Decoder：标准 transformer decoder + cross-attention to encoder
- 训练：2 epochs（400 steps），单卡 V100 32GB，约 2h20m
- Batch size 32 + gradient accumulation 2 (effective 64)，lr = 1e-5

#### 与 LLPlayerNext 的集成可能性

- **高**：与 whisper.cpp 技术栈概念一致（都是 Whisper 系列）
- **挑战**：需要 OT 部署（模型体积 1.5GB+），不适合实时客户端本地运行
- **替代**：可参考 PSST 的思路，对 whisper.cpp 的 encoder 输出做轻量后处理来检测边界

---

### 2.2 纯间隙检测方法 — 最简单可行方案

#### 文献共识的阈值

| 阈值 | 来源 | 场景 |
|---|---|---|
| **100ms** | Johnson & Kang (2016) 列为简单方案 | 显著高估边界数 (p < 0.01) |
| **150-200ms** | Johnson & Kang (2016) 最优组合算法 | 与 pitch reset + slow pace 组合使用 |
| **200ms** | Kane et al. (2014) | 避免爆破音静音段造成的假阳性 |
| **200-300ms** | **最常用范围** | 权衡假阳性与漏检 |
| **300ms** | WhisperX / stable-ts 默认值 | 保守切分 |
| **500ms** | WhisperX VAD merge 容差 | 仅检测主要边界 |

#### Johnson & Kang (2016) 的组合方法

论文提出将三个 cue 组合：

1. **Pause** (>100ms)
2. **Pitch reset**（F0 在边界处的不连续性）
3. **Slow pace**（边界前 2-3 词的 speaking rate 降低）

仅 pause：显著高估边界数 (p < 0.01)  
组合三 cue：与人工标注的差异不显著 (p > 0.05)

#### 各 cue 对提升的贡献度

基于 Zhang (2012) 的 cue-weighting 研究和 Chow (2005) 的分析：

1. **Pitch reset** — 最大单项提升（英语中 F0 slope/dynamics 是主要 pitch cue）
2. **Pre-boundary lengthening** — 可靠出现在 ~64% 的边界
3. **Post-boundary shortening (anacrusis)** — 边界后首音节缩短
4. **Lexical 特征** — PSST 消融实验中 +0.06 F1 的提升（acoustic → full）

#### 实用实现优先级

```
1. Gap/Pause threshold (baseline, 捕获 ~70% 边界)
2. Lexical/syntactic 特征 (+ ~6% F1)
3. Pitch 特征 (+ ~3-5% F1)
4. Duration-based 特征 (pre-boundary lengthening, 较小的增益)
```

---

### 2.3 其他开源工具

#### WhisperX

**代码**：[github.com/m-bain/whisperX](https://github.com/m-bain/whisperX)
**论文**：Interspeech 2023

- VAD (Voice Activity Detection) 预切分 + Whisper 转录 + wav2vec2.0 强制音素对齐
- 默认 VAD merge gap tolerance: 500ms
- 词边界检测精度：84.1% precision / 60.3% recall
- 批处理可达 70x realtime
- 与 LLPlayerNext 的关系：你们已有 whisper.cpp DTW，精度类似；可参考其 VAD 切分策略

#### stable-ts

**代码**：[github.com/jianfch/stable-ts](https://github.com/jianfch/stable-ts)

- 提供 `split_by_gap()` 和 `merge_by_gap()` 方法
- 使用 DTW on cross-attention weights 获得比 vanilla Whisper 更稳健的时序

#### CoPaSul

**作者**：Reichel
**下载**：http://clara.nytud.hu/~reichelu/copasul.zip

- Python 3 + Praat 脚本
- 自动韵律标注：chunk 分割 + 音节核检测 + 无监督韵律边界检测
- Chunk 方法：基于移动窗口能量比的 pause 检测
- 边界分类：pause 时长 + F0 不连续性 + 元音延长 → nearest-centroid

#### 其他 Praat 工具

| 工具 | 功能 |
|---|---|
| **SGdetector / SalienceDetector** (Barbosa) | VV-unit 时长 z-score 峰值检测 stress group 边界 |
| **ProsodyPro** (Yi Xu, UCL) | F0/intensity 时间归一化分析 |
| **ProsodyAD Plugin** (Atria & Pressman) | 长语音的 pause/syllable nuclei/speech rate 检测 (GPL v3) |

---

### 2.4 相关语料资源

| 语料库 | 内容 | 用途 | 许可 |
|---|---|---|---|
| **Santa Barbara Corpus (SBCSAE)** | ~20h 美式自然会话，IU 级标注 | PSST 训练数据，IIU 检测基准 | 研究许可 |
| **Buckeye Corpus** | ~38h 美式自然对话，实际音素标注 | 真实语流分析（见 M2.0 文档） | 需单独确认 |
| **IViE Corpus** | 英式英语，不同标注方案 | 跨方言泛化基准 | 研究许可 |
| **TIMIT** | 朗读语音，精细音素标注 | 朗读语流变化有限 | LDC 许可 |
| **Switchboard** | 电话对话 | 对话风格分析 | LDC 许可 |

---

## 三、对 LLPlayerNext 的启示

### 3.1 当前可用的最佳路径

```
优先级 1（本次 spike 已完成）：Gap-based
  已有数据 → 零成本接入 → 受限于 DTW 精度
  
优先级 2（M2.0 产出后）：Gap + lengthening
  forced alignment 提供 ms 级时序 → 可加入 pre-boundary lengthening
  
优先级 3（远期）：PSST 或等价模型
  Whisper encoder 特征 + 轻量分类器 → 端到端 IU 检测
```

### 3.2 架构预留

本次 spike 的数据结构已为后续扩展预留了空间：

- `BoundaryMarker` 枚举：`PreBoundaryLengthening`、`PitchReset`、`PunctuationHint`、`Hesitation` — 后续特征可直接填入
- `ChunkDetectionConfig`：`use_punctuation_hint`、`punctuation_threshold_multiplier` — 标点提示开关已就位
- `ChunkBoundary.position`：基于数组位置，不依赖 token_index — 已为跨句场景做好准备

### 3.3 技术栈匹配度

| 方案 | 精度 | 复杂度 | 客户端可行性 | 许可证 |
|---|---|---|---|---|
| Gap-based (当前) | 低（DTW 限制） | 极低 | ✓ 零依赖 | — |
| Gap + lengthening | 中（需 ms 时序） | 低 | ✓ 零依赖 | — |
| Gap + pitch | 中高 | 中（需 F0 提取） | ✓ 可用 librosa/Praat | — |
| PSST 端到端 | 高 | 高 | ✗ 模型体积大 | Apache 2.0 |
| Fine-tuned whisper.cpp | 高 | 高 | 待验证 | 取决于策略 |

---

## Sources

- [PSST paper (CoNLL 2023)](https://aclanthology.org/2023.conll-1.31/)
- [PSST GitHub](https://github.com/Nathan-Roll1/PSST)
- [PSST HuggingFace model](https://huggingface.co/NathanRoll/psst-medium-en)
- [WhisperX paper (Interspeech 2023)](https://arxiv.org/abs/2303.00747)
- [WhisperX GitHub](https://github.com/m-bain/whisperX)
- [stable-ts GitHub](https://github.com/jianfch/stable-ts)
- [Johnson & Kang (2016) — automatic tone unit detection](https://www.isca-archive.org/speechprosody_2016/johnson16_speechprosody.html)
- [Zhang (2012) — cue-weighting in prosodic boundary perception](https://deepblue.lib.umich.edu/handle/2027.42/96107)
- [Chow (2005) — prosodic cues for syntactically-motivated junctures](https://www.isca-archive.org/interspeech_2005/chow05_interspeech.pdf)
- [Kane et al. (2014) — Interspeech 2014](https://www.isca-archive.org/interspeech_2014/kane14_interspeech.pdf)
- [CoPaSul](http://clara.nytud.hu/~reichelu/copasul.zip)
- [Whisper timing.py heuristic](https://github.com/openai/whisper/blob/main/whisper/timing.py)
- 已有文档：[`pronunciation-rules-and-connected-speech-references.md`](../discuss/pronunciation-rules-and-connected-speech-references.md)
- 已有文档：[`real-connected-speech-analysis-and-speech-to-ipa.md`](../discuss/real-connected-speech-analysis-and-speech-to-ipa.md)
