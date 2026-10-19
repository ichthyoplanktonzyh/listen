# 基于 Chunk（语块）的听力理解

## 核心结论

> 真实听力理解的基本单位是 **chunk（语块/意群/tone unit）**，不是单个单词。这是由人类工作记忆容量（7±2 单位）、语速要求（150-180 wpm 无法逐词处理）和声学现实（自然语流中不存在词边界静音）共同决定的。

LLPlayerNext 当前以单词为最小分析单位（token 化、词汇状态、词级时间同步），这是必要的基础——没有单词就没有语块。但听力诊断的下一步必须向语块层演进，因为很多「词都认识但就是听不懂」的根本原因在于：**学习者无法将连续语流实时切分为语块进行处理**。

Chunk 不是英语特有的现象，而是所有自然语言的共性。但不同语言中语块的表现形式、声学标记和检测方式有显著差异。LLPlayerNext 应以「语言无关的架构 + 英语优先的实现」来设计。

---

## Chunk 的两个层次

这是本次讨论最重要的设计洞察：chunk 存在于两个截然不同的层次。

### 文字层 Chunk：哪些词构成一个语义整体

| 维度 | 说明 |
|---|---|
| **定义来源** | 语料统计：n-gram 频率、搭配强度（MI score）、程式语词典 |
| **边界标记** | 统计概率、句法结构 |
| **回答的问题** | "这几个词是不是经常一起出现、一起表达一个意思？" |
| **示例** | "in terms of"、"on the other hand"、"I was wondering if" |

### 声音层 Chunk：哪些音段在物理上构成一个整体

| 维度 | 说明 |
|---|---|
| **定义来源** | 声学现实：说话人的实际韵律切分 |
| **边界标记** | 停顿（>100ms silence）、音高重置（pitch reset）、尾音延长（final lengthening）、强度下降（intensity dip）、边界调（boundary tone） |
| **回答的问题** | "这段声音听起来到哪里是一个自然的断点？" |
| **示例** | "Ithinkthat" [停顿] "it'simPORtant" [停顿] "tonote" |

### 关键区别

文字层告诉你「这些词在语义上是一体的」，声音层告诉你「这些词**听起来**就是一个东西」。

母语者听到的是：`[音流A] [停顿+音高重置] [音流B]`

学习者听到的是：一连串不可分割的声音，每个词都糊在一起。

**听力训练的核心不在于知道哪些词构成语块（文字层），而在于训练耳朵去感知声音层面的语块边界和内部结构。** 因此，LLPlayerNext 的 chunk 功能应以声音层为优先，文字层为辅助。

---

## 听力学习者的核心困难

1. **没有建立对韵律边界信号的敏感性**——不会自动注意到停顿、音高重置这些 cues
2. **词边界被连续语流现象模糊后无法回溯**——听到 "gonna" 后无法拆回 "going to"
3. **内部处理速度不够**——即使能识别单个词，也赶不上语块被整体抛出的速度
4. **连接语流只在语块内部发生**——连读、弱读、省音、同化主要作用在语块内部，语块之间有更强的边界信号

---

## 技术路线

### 路线总览

```
第一优先级（核心）：声音层 Chunk 感知
  ├── 利用已有 whisper.cpp DTW 词间间隙 → 检测声学语块边界
  ├── 音频波形/音高显示 + 语块边界可视化
  ├── 语块级循环播放和逐步展开训练
  ├── 实际发音的简化标注
  └── 连接语流现象在语块内部的展示

第二优先级（辅助）：文字层 Chunk 标注
  ├── 程式语词典匹配（Martinez & Schmitt PHRASE List 等）
  ├── n-gram 频率标记
  └── 帮助用户理解「哪些词在语义上是一体的」

第三优先级（诊断）：语块级诊断
  └── 基于以上两层，解释为什么没听懂
      - "这句话中有 X 个声学语块，Y 个包含不认识或听不出的词"
      - "Z 个语块虽然词都认识，但实际发音与书写形式差异大"
```

### Phase A：文本级语块识别（可立即开始）

完全不依赖音频，利用已有字幕 token 化基础设施。对每个句子做 n-gram 扫描（n=2..5），与预置语块词典匹配，输出哪些 token 序列构成语块。

**预置语块词典来源：**

| 来源 | 覆盖内容 | 规模 |
|---|---|---|
| **Martinez & Schmitt (2012) PHRASE List** | 505 个最常见的英语程式语，针对二语学习者筛选 | 505 条目 |
| **Simpson-Vlach & Ellis (2010) AFL** | Academic Formulas List，覆盖学术口语和书面语 | 核心 207 + 扩展 400+ |
| **Biber et al. (2004) Lexical Bundles** | 大学口语语域的高频词串，按功能分类 | 数百条目 |
| **COCA n-gram 频率** | 基于 5.6 亿词美国当代英语语料库 | 可自定义 |

这些词典作为编译时嵌入的静态资源，不需要运行时外部 API 调用。

### Phase B：声学语块边界检测（利用已有数据）

**方法 A — 基于停顿的词间间隙分析（零成本接入）：**

LLPlayerNext 已在 M1.9 通过 whisper.cpp DTW 获得词级时间戳（`timing_source = asr_reported`）。当词间间隙超过阈值（如 >200ms）时，标记为韵律边界：

```text
字幕句中的 token:
  "I"      [100ms-250ms]
  "think"  [250ms-450ms]
  [gap: 180ms]           ← 韵律边界
  "that"   [630ms-750ms]
  "it's"   [750ms-920ms]
  "important" [920ms-1250ms]

→ 语块1: "I think"
→ 语块2: "that it's important"
```

计算在客户端本地完成，符合 ARCH-005 的实时路径要求。

**方法 B — 韵律特征综合分析（中期）：**

在词间隙之外，增加更多声学维度的分析：

- 音高变化（pitch contour）：新语块起始通常伴随音高重置
- 尾音延长程度：语块末音节的时长通常比句内音节长 20-40%
- 强度变化：语块边界常有强度下降

### Phase C：语块级交互与训练

**视觉呈现：**

```
当前字幕句:
┌─────────────────────────────────────────────────┐
│ I think  │  that it's important  │  to note    │
│ ▁▁▁▁▁▁▁ │  ▂▂▂▂▂▂▂▄▄▄▄▄▄▄▄▄▄▄ │  ▃▃▃▃▃▃▃▃  │
│ chunk 1  │  chunk 2             │  chunk 3    │
│ 320ms    │  180ms pause → 450ms │  420ms ↘    │
└─────────────────────────────────────────────────┘
```

- 语块边界用浅色竖线或间距标记
- 每个语块显示实际发音简化版和音高走向
- 当前播放的语块动态高亮（利用词级时间戳 + 停顿检测）
- 语块内部标注连续语流规则（从 PRON-003 的 18 条规则提升到语块内部）

**循环训练模式：**

- 循环播放单个语块（而不只是整句）
- 逐步展开：先听语块1 → 再听语块1+2 → 再听完整句
- 对比模式：TTS 逐词发音 vs 真实说话人发音

---

## 可参考的研究

| 研究者/论文 | 核心发现 | 关联性 |
|---|---|---|
| **Wray (2002)** *Formulaic Language and the Lexicon* | 语块是大脑存储和检索语言的基本单位 | 语言学理论基础 |
| **Michael Lewis (1993, 1997)** *The Lexical Approach* | 语言学习应围绕语块展开 | 产品哲学依据 |
| **Martinez & Schmitt (2012)** PHRASE List | 505 个对二语学习者最有价值的英语程式语 | 可直接作为第一个语块词典 |
| **Simpson-Vlach & Ellis (2010)** Academic Formulas List | 学术口语高频语块 | 学术内容场景 |
| **Yeldham (2018)** | 语块帮助二语听者在高难度文本中解码功能词，减少认知负担 | 解释了 chunk 对听解的机制 |
| **Lu (2024)** | L2 学习者对程式语的加工速度显著快于非程式语，熟悉度是关键 | 支持语块整体处理的训练价值 |
| **2020 Lingua 研究** | Phraseological knowledge 是 L2 听力的独立显著预测因子，超越单词词汇量 | 量化证据 |

## 可参考的项目与工具

### 韵律边界检测

| 项目 | 用途 | 集成可能性 |
|---|---|---|
| **[PSST](https://github.com/Nathan-Roll1/PSST)** | 基于 Whisper fine-tune 的 Intonation Unit 边界检测，F1=0.87，CoNLL 2023 | 高 — 与 whisper.cpp 技术栈相近 |
| **[WhisperX](https://github.com/m-bain/whisperX)** | ASR + 强制对齐 + 词级时间戳 + 说话人分离 | 中等 — 已有 DTW 对齐，可参考精度提升方法 |
| **SGdetector / SalienceDetector (Barbosa)** | Praat 脚本，基于音节时长 z-score 峰值检测韵律边界 | 低 — 面向实验研究，适合离线验证 |
| **CoPaSul (Reichel)** | 自动韵律标注：chunk 分割 + 音高轮廓 + 无监督韵律边界检测 | 中等 — Python，可用于构建验证数据或离线预处理 |
| **Purdue Prosodic Feature Extraction Tool** | 词边界的 F0、时长、能量特征提取 | 低 |

### 连续语流分析

| 项目 | 用途 | 集成可能性 |
|---|---|---|
| **Montreal Forced Aligner (MFA)** | 词级和音素级强制对齐，含概率发音词典（多种弱读变体） | 见 `pronunciation-rules-and-connected-speech-references.md` |
| **Misaki-RS** | Rust 移植的上下文 G2P 引擎 | 见 `pronunciation-rules-and-connected-speech-references.md` |
| **Festival Postlexical Rules** | TTS 系统中「标准发音 → 后词汇规则 → 连续语流发音」的架构 | 设计模式参考 |
| **Allosaurus / Wav2Vec2Phoneme / ZIPA** | 音频 → IPA phone 序列 | 见 `real-connected-speech-analysis-and-speech-to-ipa.md` |

### 语言学习工具（概念参考）

| 工具 | 相关特性 |
|---|---|
| **[YouGlish](https://youglish.com)** | 搜索 YouTube 中真实视频片段中的词/短语发音，语块 + 真实语境 |
| **ELSA Speak** | AI 发音反馈，主要单词/句子层面，可与其语块级互补 |

### 语料资源

| 资源 | 内容 | 用途 |
|---|---|---|
| **Buckeye Corpus** | 美式英语自然对话，含实际音素标注和时间对齐 | 规则验证、测试集构建 |
| **Santa Barbara Corpus** | 美式英语自然会话，含语调单元标注（PSST 的训练数据） | 韵律边界检测基准 |
| **COCA / BNC** | 大规模英语语料库 | n-gram 频率统计 |

---

## 语言普适性设计

Chunk 是人类语音理解的通用机制，不是英语特有的。但语块的**检测方式**因语言而异：

| 语言 | 文本级检测 | 声学级检测 |
|---|---|---|
| 英语 | n-gram 频率 + 程式语词典 + 搭配统计 | 停顿间隙 + 音高重置 + 尾音延长（stress-timed） |
| 汉语 | 分词结果 + 成语/惯用语词典 | 音节时长模式 + 边界调 + 变调域（syllable-timed） |
| 日语 | 形态素解析 + 助词附着模式 | pitch accent 重置 + 停顿（mora-timed） |
| 法语 | 程式语词典 + liaison 规则 | 音节等时性 + liaison 实现与否 |

### 推荐架构

```rust
// 语块数据结构：语言无关
struct Chunk {
    id: ChunkId,
    language: Language,          // 与 WORD-007 的语言维度一致
    tokens: Vec<TokenPosition>,  // 从第 n 到第 m 个 token
    chunk_type: ChunkType,
    boundary_source: BoundarySource,  // text_corpus | acoustic_gap | prosodic_model
    confidence: f32,
}

enum ChunkType {
    FormulaicSequence,    // 程式语
    ProsodicUnit,         // 韵律单元
    Collocation,          // 搭配
    UserDefined,          // 用户自定义
}

// 检测器：按语言实现
trait ChunkDetector {
    fn detect_text_chunks(&self, sentence: &Sentence) -> Vec<Chunk>;
    fn detect_acoustic_boundaries(&self, timings: &[WordTiming]) -> Vec<BoundaryMarker>;
}
```

数据设计时从第一天就带 `language` 字段，为未来多语言扩展预留空间。当前阶段英语优先，因为字幕引擎目前只支持英语 token 化（TXT-001）。

---

## 与现有架构的衔接

### 已有资产

| 已有能力 | 来源 | 与 Chunk 的关系 |
|---|---|---|
| 字幕 token 化 | TXT-001 | 提供语块匹配所需的单词序列 |
| 词级时间戳（asr_reported） | M1.9 whisper.cpp DTW | 提供声学边界检测所需的词间间隙数据 |
| 规则型语流提示 18 条 | PRON-003 | 可直接应用于语块内部的发音变化展示 |
| 当前词同步 | PRON-002 | 可升级为当前语块同步 |
| 单句循环 | PLAY-007 | 可升级为语块级循环 |
| 语言维度 | WORD-007 | 复用为 chunk 的语言维度 |

### 需要新增

| 新增模块 | 说明 |
|---|---|
| `chunk_detector` (Rust) | ChunkDetector trait + EnglishChunkDetector 实现 |
| 语块词典数据 | 编译时嵌入的 JSON/PHRASE List 数据 |
| `chunk_boundary_analyzer` (Rust) | 基于词间间隙的韵律边界分析 |
| Chunk 数据模型 | 新增 `chunk_id`、`chunk_type`、`boundary_source` 等字段 |
| 前端语块展示 | 播放画面 + 文稿中的语块视觉分组 |
| 语块级循环控制 | 循环单个语块、逐步展开播放 |

### 对现有模型的侵入性

- 语块信息作为字幕 token 列表上的**附加层**，不改变现有 token 模型结构
- 已有的 `WordTiming` 可直接用于边界检测，不需要修改数据模型
- PRON-003 的规则引擎输出可直接关联到语块级别的上下文
- 语块状态模型（如果未来引入）应复用 `Language + lemma` 的唯一性概念

---

## 设计原则

1. **语块是辅助线索，不是绝对标注**。类比当前诊断的「提示」而非「结论」。
2. **允许多层级展示**。用户可以切换「常见语块」（文字层）和「韵律语块」（声音层）两种视角。
3. **用户可覆盖/修正**。用户可以标记「这不是一个语块」或自定义语块边界，类似于 WORD-010 的 lemma 修正。
4. **声学层优先**。功能重心放在训练耳朵感知声音结构，而非仅仅展示语言知识。

---

## Sources

- [Wray (2002) Formulaic Language and the Lexicon](https://doi.org/10.1017/CBO9780511519772)
- [Martinez & Schmitt (2012) A Phrasal Expressions List](https://doi.org/10.1093/applin/ams010)
- [Simpson-Vlach & Ellis (2010) An Academic Formulas List](https://doi.org/10.1093/applin/amp058)
- [Yeldham (2018) The influence of formulaic language on L2 listener decoding](https://www.tandfonline.com/doi/abs/10.1080/17501229.2015.1103246)
- [PSST: Prosodic Speech Segmentation with Transformers](https://github.com/Nathan-Roll1/PSST)
- [PSST paper (CoNLL 2023)](https://aclanthology.org/2023.conll-1.31/)
- [WhisperX](https://github.com/m-bain/whisperX)
- [Montreal Forced Aligner](https://montreal-forced-aligner.readthedocs.io/)
- [Buckeye Corpus](https://buckeyecorpus.osu.edu/)
- [CoPaSul](http://clara.nytud.hu/~reichelu/copasul.zip)
- [YouGlish](https://youglish.com)
- [Lewis (1993) The Lexical Approach](https://www.amazon.com/Lexical-Approach-State-Language-Teaching/dp/090671799X)
- 本讨论中关联的已有文档：
  - [`pronunciation-rules-and-connected-speech-references.md`](./pronunciation-rules-and-connected-speech-references.md)
  - [`real-connected-speech-analysis-and-speech-to-ipa.md`](./real-connected-speech-analysis-and-speech-to-ipa.md)
