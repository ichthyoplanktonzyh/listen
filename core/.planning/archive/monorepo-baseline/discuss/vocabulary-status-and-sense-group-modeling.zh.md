# 词汇状态与意群建模讨论

> 日期：2026-07-06
> 参与者：用户 + Claude
> 背景：从业务建模角度分析 LLPlayerNext 学习领域模型的优化空间

---

## 一、词汇状态分类框架

### 1.1 起点：词汇对学习者的分类

用户提出词汇对学习者可以分为以下几类：
- 完全不认识
- 阅读词汇（看到能认识）
- 听力词汇（能认识，能听懂）
- 口语词汇（能用来表达）

### 1.2 语言学理论校验

这个分类的核心逻辑与语言学中 receptive vocabulary（接受性词汇）和 productive vocabulary（产出性词汇）的区分高度一致，且比二分法更细致。

**值得推敲的地方：**

1. **阅读词汇和听力词汇之间的关系未必是单向递进的。** 排列暗示"听力词汇"是比"阅读词汇"更高的层级，但实际情况取决于语言和学习路径。学中文的外国人可能一个词听得懂但不认识对应的汉字，听力词汇先于阅读词汇。而英语学习者中更常见的是反过来——读得懂但听不出来。这两者之间更像是两个可以独立发展的维度，而非严格的递进阶梯。

2. **缺少"写作词汇"这一环。** 口语产出和书面产出对词汇的要求不同。有些词能说但拼写不确定，有些词能写但口语中从来不会用。

3. **即便在同一个层级内部，"认识"本身也有程度之分。** Paul Nation 提出的词汇知识框架包含形式、意义、用法三个大维度，每个维度下又有好几个层面。

### 1.3 共识：多维度而非线性阶梯

用户确认这些不是线性阶梯，而是一个词汇对于用户可以有不同状态。写作词汇的补充也被接纳。

关键共识：每个词汇对于不同用户属于不同类别。对典型中国英语学习者而言，阅读词汇显著高于其他类别，口语词汇最少。这是一个结构性现象，由教育体系（阅读和考试为核心驱动）决定。

补充观察：很多中国学习者的阅读词汇中有相当部分是"虚胖"的——能在阅读语境中大致猜出意思，但对发音、重音、搭配、语域都不清楚。从阅读词汇转化为听力或口语词汇的路径比想象中更长。

---

## 二、Chunk 在句子理解中的作用

### 2.1 Chunk 的核心概念

从理解一句话的角度，词汇理解是一部分，chunk 的理解是另一部分。句子可以分为 chunk 来拆分理解。

这里的 chunk 定义为**组成句子中语义表征的最小单元**。例如 "I like the green apple"，"green apple" 应该作为一个 chunk。

### 2.2 与学界 chunk 概念的区别

这个定义与 Michael Lewis 的 Lexical Approach 中的 chunk（lexical chunks）有微妙但重要的区别：

- **Lewis 的 lexical chunk** 强调"固定性"和"预制性"——make a decision 是 chunk 因为是约定搭配
- **本项目的 chunk** — "green apple" 不是固定搭配（red apple、big apple 都行），它之所以是 chunk，是因为在语义结构中是一个完整的指称单位，拆开就失去了指向一个具体事物的能力

### 2.3 Chunk 在听力中的关键作用

听力不像阅读，没有回看机会，语音信号转瞬即逝。如果逐词处理，工作记忆会被迅速占满。而将语流切分为有意义的组块，每个组块占一个工作记忆单元，认知负荷大幅降低。George Miller 经典的"7±2"理论：工作记忆容量以 chunk 为单位计算，不是以单个词为单位。

核心观点：在听力理解中 chunk 比单词更重要。真正的理解瓶颈往往不在于是否认识每个单词，而在于能否在实时语流中快速完成组块化的切分。

---

## 三、学习资源的粒度层级

### 3.1 文字层面的学习资源

沿语言单位粒度往上：word → collocation → phrase → sentence → paragraph → text / dialogue。

Collocation（搭配，如 heavy rain、commit a crime）比自由组合的 phrase 更固定，但又不完全是一个 phrase，取决于建模精细程度。

### 3.2 最终共识：止于 Sentence

Paragraph 和 text/dialogue 的意义不大，最多到 sentence。理由：paragraph 以上是**内容组织单位**，不是**学习资产单位**。学习者学习的对象是可以被诊断、练习、复习、记忆的离散单元。

---

## 四、当前系统建模落差分析

### 4.1 LearningStatus 是听力单维线性的

当前模型（`domain::LearningStatus`）：
```
null → UnknownMeaning → KnownNotRecognized → KnownRecognized
```

本质是一条听力理解维度的线性阶梯。无法表达"阅读时认识但听力中听不出"和"听力中认识但阅读时不确定"这两种状态。对中国英语学习者的"阅读词汇远大于听力词汇"的结构性不均衡是盲区。

### 4.2 Chunk 被建模为声学切分产物

当前 `ChunkTimelineChunk` 的核心身份是 `sentence_id + chunk_index + start_word_index + end_word_index + timing`，边界来源（`ChunkBoundarySource`）包括 Pause、Punctuation、Semantic 等，Semantic 只是众多来源之一。

学习者真正需要掌握的 chunk 应该从语义结构自顶向下定义，而非从语音信号自底向上切出。两者经常重合但不等价。

### 4.3 学习资源粒度不完整

当前 `LexicalEntryKind` 只有 Word 和 Phrase。Collocation 没有独立身份。Sentence 存在于 `SubtitleSentence` 但是字幕资源概念，不是学习资产概念。

---

## 五、新建模方案讨论

### 5.1 词汇状态：四通道独立维度

**"完全不认识"不是第五个通道**，它是所有通道都为零时的状态。实际通道是四个：阅读、听力、口语、写作。

每个通道内先保持二值（unknown / known），理由：
1. 证据系统已承载深度信息——LexicalObservation、PracticeAttempt、ReviewAttempt 记录每次具体表现
2. 用户认知负担——"认识/不认识"比三档更快、更不容易犹豫
3. 对学习策略的指导差异有限——二值已能驱动关键决策

关于三值中"被动掌握"与"主动掌握"的区别讨论：

| 通道 | 被动掌握 | 主动掌握 |
|---|---|---|
| 阅读 | 有上下文时能认出 | 脱离语境也精确知道 |
| 听力 | 正常语速能听出 | 连读弱读快速语流也能识别 |
| 口语 | 被提示时能说出来 | 自发使用，发音准确 |
| 写作 | 能写但需要想 | 拼写和用法都准确自如 |

结论：边界模糊、难以通过单次交互可靠判定。**通道内用二值，深度由观测证据承载。**

### 5.2 Chunk 改名为 SenseGroup（意群）

当前系统的"chunk"与学界 chunk 含义不同，需要换名。

| 候选 | 优点 | 缺点 |
|---|---|---|
| SenseGroup（意群） | 中文教学界有共识，含义精确 | 英语学术界用得少 |
| MeaningUnit | 自解释，语言无关 | 无学术传统 |
| Constituent | 句法学标准术语 | 太技术化 |

倾向 **SenseGroup**。

### 5.3 Sentence 的本质：骨架 > 具体内容

Sentence 真正有学习价值的不是具体那句话的具体词，而是结构骨架——对应 Construction Grammar（构式语法，Goldberg）中的 construction（构式）。

例：
- "The more X, the more Y" — 构式
- "It is X that Y" — 强调构式
- "把 X V 了" — 中文把字句构式

Sentence 作为学习对象是两层东西：
1. **具体句子**（exemplar）— 用于收藏、练习回听、做素材
2. **句式/构式**（pattern/construction）— 用于句模系统、语法学习

用户确认 sentence 的三个重要用途：
1. 构建自己的句模系统
2. 学习相应的语法结构
3. 用作收藏

### 5.4 SentencePattern 的状态模型

SentencePattern 不适合套四通道模型——句式的识别不依赖特定感知通道（不存在"读得出但听不出"一个句式的情况），产出也不需要区分口语/写作。

最终模型：
```
recognition: unknown | known  （遇到能识别）
production:  unknown | can_use （需要时能调用）
```

四种组合：
- (0, 0) — 完全不认识
- (1, 0) — 见过能认出但不会用（最常见中间态）
- (1, 1) — 认识也能用
- (0, 1) — 不认识但能用（理论上不太可能，可忽略）

状态转移由练习驱动。

---

## 六、学习对象与状态模型总览

| 学习对象 | 本质 | 状态维度 | 每个维度的值 |
|---|---|---|---|
| **Word** | 最小词汇单元 | 阅读 / 听力 / 口语 / 写作 | unknown · known |
| **Phrase/Collocation** | 固定多词单元 | 阅读 / 听力 / 口语 / 写作 | unknown · known |
| **SenseGroup（意群）** | 句内语义加工单元 | 听力 / 口语 | unknown · known |
| **SentencePattern（句式）** | 抽象结构模板 | 认识 / 能用 | unknown · known |

共性原则：
- 状态维度内都是二值（unknown / known），深度由证据链承载
- "完全不认识"不是独立状态，是所有维度为 unknown 的自然组合
- 所有学习对象和状态维度设计均语言无关
- 状态变迁由练习/复习过程驱动，不由用户手动逐维度标记（但允许用户覆盖）

---

## 七、SenseGroup 切分方法

### 7.1 层次性问题

意群切分不像分词有唯一正确答案——它是层次性的。同一句话可以在不同粒度上切分。对于听力理解训练，中粒度最有价值——大致对应工作记忆的加工单位（每句 3-5 个意群）。

### 7.2 可行方法

**方法 1：句法分析（Syntactic Parsing）**

最有理论根基。成分句法直接产出 NP、VP、PP 等短语结构；依存句法以中心词为核心收集依赖词构成子树。Universal Dependencies (UD) 项目覆盖 100+ 语言，语言无关性最好。

问题：切分粒度需要额外规则控制。

**方法 2：LLM 切分**

优点：理解语义意图，处理非标准句式，天然多语言。
问题：确定性差、延迟和成本高、难以离线。

**方法 3：浅层句法分块（Shallow Parsing / NP Chunking）**

NLP 领域已有的"chunking"任务——识别基础短语。
优点：简单、快速、确定性高。
问题：粒度有时太细，需要后处理合并。

**方法 4：混合方法（推荐路线）**

```
句法依存分析（UD）定义结构骨架
        ↓
粒度控制规则：在合适层级截断
        ↓
韵律/停顿信号作为验证证据（而非定义）
        ↓
LLM 兜底处理句法分析器失败的边缘情况
```

### 7.3 语言无关性

UD 依存分析语言无关性最强，60+ 语言一致标注框架。粒度控制规则可能需要少量语言相关调整（参数级别，不是算法重写）：
- 英语：介词短语通常整体算一个意群
- 中文：的字结构可以很长，需控制意群长度
- 日语：助词是天然意群边界标记

### 7.4 消费端实现方案

**UDPipe**（C++）是消费端最佳候选：
- 模型极小：英语 ~15 MB，中文 ~15 MB，日语 ~10 MB
- 纯 C++，通过 FFI 从 Rust sidecar 调用
- 全套 pipeline：tokenization → POS tagging → dependency parsing
- 离线运行，CPU 推理毫秒级

消费端架构：
- 有 LLTimeline 预计算结果时直接用
- 没有时消费端通过 UDPipe 自己算
- 与现有"bundled whisper.cpp 保底，sidecar 升级质量"逻辑一致
- 语言模型按需下载，类似已有的 LearningResource 下载机制

---

## 八、架构变更难度评估

### 8.1 变更 A：LearningStatus 单值枚举 → 四通道模型（难度：中高）

贯穿 domain、diagnosis-core、persistence-sqlite、application、api-http、Flutter 六层。

关键工作：
- domain：LearningStatus 枚举重定义为四通道结构体
- diagnosis-core：核心诊断逻辑重写（44 处非测试引用硬编码了具体枚举值）
- persistence：schema v21，`status TEXT` 单列 → 多列或 JSON
- API/Flutter/export-import：契约和 UI 全面适配

性质：不是技术上复杂，而是接触面广、需要同步推进。diagnosis-core 是唯一需要重新思考逻辑的地方。

### 8.2 变更 B：Chunk → SenseGroup 语义切分重塑（难度：中等，工作量大）

关键工作：
- speech-analysis 的 `chunk_partition.rs`（1292 行）：纯声学切分算法需要替换为 UD 依存分析驱动的语义切分
- 新依赖：UDPipe C++ FFI 集成（未知量，需先做 spike）
- Rust 全局 219 处、Flutter 111 处 chunk 引用重命名
- 资源生命周期（candidate → active → archived）可保留

### 8.3 变更 C：SentencePattern 新增学习对象（难度：最低）

纯增量，无存量代码改动。需要新增 domain 类型、repository、API 路由、Flutter UI。需要设计"从具体句子抽象出句式"的逻辑。

### 8.4 建议执行顺序

```
变更 A（LearningStatus 多通道）  ← 最先做，其他两个依赖状态模型
        ↓
变更 B（SenseGroup 语义切分）   ← 第二，改造现有 chunk 体系
        ↓
变更 C（SentencePattern）       ← 最后，纯增量
```

### 8.5 总体判断

| 维度 | 判断 |
|---|---|
| 总工作量 | 大。六层全改 + 一个新 C++ 依赖集成 |
| 技术难度 | 中等。主要是模型重塑 + 机械传播 + FFI 集成 |
| 风险点 | ① diagnosis-core 逻辑重写正确性 ② UDPipe FFI 跨平台可行性 ③ Schema 迁移 |
| 可增量推进 | 是。三个变更之间有依赖但内部可以切片 |
