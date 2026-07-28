# Realtime 语音对话、输出性词汇产出语料与系统模型类别地图（讨论版）

> 日期：2026-07-16
> 状态：DISCUSSION DECISION（作为后续 phase 划分与 ADR 的产品输入）
> 上游讨论：`four-channel-product-and-vendor-neutral-llm-final.zh.md`、
> `four-skills-speaking-reading-writing-expansion.zh.md`（§item 12「真实媒体场景驱动的 AI 对话」、
> §cross-modal「能认但不能产出」）。
> 范围：realtime 语音对话作为独立中立模型类别、说/写统一的输出性词汇产出语料、
> 跨通道 gap 复盘、以及从整个产品需求推导的模型类别地图。
> 本文不修改任何已冻结 phase 的历史范围；它为新 phase 划分提供产品裁决。

修订记录：

- v2（2026-07-16）：三个划分分叉裁定——P2/P3 独立立 phase、3.18 Cross-modal Coach 收窄为
  聚合叙述、3.17 保留 usage→projection 确认门；顺序 P1→P2→P3→P4，P5/P6 增补；realtime 首批
  异构厂商为 OpenAI Realtime + 千问 Qwen Omni。§11 由「待裁决」改为「Phase 划分与顺序（已裁决）」。
- v1（2026-07-16）：初版。定 realtime 为独立中立类别、输出产出语料（说+写）、
  gap-(c) 复盘、10 类模型地图与本地/云落位。

---

## 1. 背景与触发

Speaking Studio v1（3.14）刻意把「开放式 AI 陪聊、实时语音 agent」列为 out of scope，
先交付结构化复述与角色接话。本次讨论决定把「realtime 语音对话」正式纳入产品，并围绕它
澄清了三件更基础的事：厂商中立的正确定义、输出性词汇的证据模型、以及系统整体需要哪些
模型类别。这些结论共同构成后续 phase 划分的产品输入。

## 2. 核心裁决摘要（速查）

1. **厂商中立 = 同一能力类别内不锁单一厂商**，不是「一个 seam 通吃所有模型」。模型按
   能力类别划分，不同类别有不同 seam、各自在类别内证中立。
2. **Realtime 全双工语音对话是一个独立的中立模型类别**，塞不进 3.12 的文本 LLM seam；
   采用原生 realtime（非本地 ASR→文本 LLM→TTS 管线），类别内以 ≥2 个异构厂商证中立。
3. **对话厂商与证据文稿解耦**：用户麦克风音频统一走本地 whisper.cpp 得到权威 user
   transcript 用于复盘；realtime 厂商只负责「聊得像真人」，证据口径不吊在厂商身上。
4. **输出性词汇统一（说 + 写）**：建一个「个人产出语料库」，同时接口语产出（realtime
   对话）与写作产出（3.15 已有 immutable attempts），每条打 channel 标签。
5. **复盘 = 描述性用词分布画像，不是单次评分**；在大 N 下对 ASR 噪声鲁棒。核心呈现是
   **跨通道 gap-(c)：能认（听/读证据）但从不产出**。
6. **证据分层保持**：产出语料（事实）→ 用词分布（描述性派生）→〔3.17 confirmation
   gate〕→ capability projection。**不自动写 projection**。
7. **模型按能力类别共用同一 provider-seam 模式**：中立 trait + draft-not-authority +
   provenance + 诚实降级；新类别是复制模式，不是发明架构。
8. **3.12.1 的留出集人工 gold 资格门取消**（个人工具 + 现代模型能力下过度）；改为更便宜的
   显示诚实边界：LLM 反馈标注为「可纠正的辅助反馈」、可 adjudicate、但不自动写能力投影。

## 3. 厂商中立的再定义：模型按能力类别划分

3.12 / ADR 0022 建立厂商中立时，隐含地把「中立」实现为「一个 `LlmChatAdapter` 文本 seam +
两个异构 adapter」。本次澄清：那只是**文本结构化输出这一个类别**内的中立。正确的中立原则是：

> 中立在**能力类别**这一层成立——同一类别内不被单一厂商/wire format 俘获——而不同能力
> 类别（文本推理 / 全双工语音 / 语音合成 / 向量嵌入 …）本就该有各自的 seam。

这与 ADR 0022 的精神一致（它防的是被单一 wire format 绑架），只是把「类别」显式化。判据不变：
一个类别要宣称中立，必须真的实现 ≥2 个**异构**厂商 adapter 并过同一契约套件。

## 4. Realtime 语音对话作为独立模型类别

- **为什么不能复用文本 seam**：文本 seam 是请求/响应的结构化 JSON；realtime 是全双工音频
  流 + server VAD + turn 事件 + transcript 事件（+可选 function call）。交互形状根本不同。
- **路线选择：原生 realtime**（OpenAI Realtime / Qwen Omni / 豆包 …），不走「本地 ASR →
  文本 LLM → 本地 TTS」管线。理由：管线的延迟与轮流自然度打折严重，而原生 realtime 在
  「像真人对话」这一核心体验上不可替代；类别内已有 ≥2 家异构厂商，中立性可在类别内证明。
- **中立 seam 要抽象的对象**：session 生命周期、音频双向流、turn 边界、transcript 事件、
  （可选）function call。realtime 协议比文本**更不标准**，这是一个新 seam 家族，工程量需
  如实预期，不是「加个 adapter」。
- **证据文稿解耦（关键）**：用户发言的权威文稿**不采信 realtime 厂商各异的 ASR**，而是把
  麦克风音频统一喂本地 whisper.cpp（3.14 已在用）。换厂商不改变产出语料口径，也进一步把
  证据关键路径留在本地。

## 5. 输出性词汇：个人产出语料库（说 + 写统一）

四通道天然是「输入 = 听/读接收，输出 = 说/写产出」。说和写都是输出性词汇，应共用一个资产：

- **个人产出语料库（personal production corpus）**：与已有「媒体 corpus 索引 + FTS/lemma」
  同构，只是索引对象从媒体变成**用户自己的产出**；每条打 channel 标签（说过 / 写过）、带
  来源锚点（段落/媒体）、时间戳、lemma 归一。
- **两个数据源**：
  - 口语产出 ← realtime 对话（本地 whisper.cpp 权威文稿）；
  - 写作产出 ← **3.15 Writing Studio 已存在的 immutable typed attempts**（现成产出文本，
    零新采集）。
- **抢跑红利**：产出语料 + 分布/gap 画像这条链**可以先用写作数据跑起来**，不必等 realtime
  seam 就位。这不是「先验证再上」的关卡（realtime 已定要做），而是「先用现成数据点亮产品
  价值、让 realtime 一上线就有复盘归宿」的排序红利。
- **Scaffolding 排除**：对话里 AI 先说过、用户复读的词，在入库时打 scaffolding 标记、
  不计入自主产出。

## 6. 复盘 = 跨通道 gap-(c) 画像（能认不能产出）

- **复盘不是单次评分**，而是**描述性用词分布画像**。它不下能力结论，只统计频次与分布；
  这恰好绕开 3.14 speaking observation 的红线（"ASR 转写正确不自动证明 speaking acquired"）。
- **大 N 是特性不是缺陷**：分布在大量记录下对个别 ASR 幻听鲁棒，只有系统性模式才显现。
- **核心呈现 = gap-(c)**：把产出语料 × 已有的听/读**识别证据**一比，指出「**这些词你在
  听/读里反复见过、甚至标过认识，但在产出里从没出现**」。可再分「从没说过」/「从没写过」。
  这是本项目独有的能力——别家陪聊/写作产品没有四通道证据底座。
- **裸频次无用**，参照系候选：(a) 通用词频分级、(b) 词汇多样性、(c) 跨通道识别-产出 gap、
  (d) 主题覆盖。**选定 (c) 为 v1 核心**，其余为增补。
- **近义 gap 需要语义嵌入**（见 §8 类别 7）：如「只会用 big，从不用 enormous/vast」需要
  语义相似度支撑，属增补层。

## 7. 证据分层与显示诚实边界

- 分层：**产出语料（事实）→ 用词分布（描述性派生，读端）→〔3.17 confirmation gate〕→
  capability projection**。v1 **不自动写 projection**。
- 产出语料始终记录 usage（事实）；复盘允许用户确认；**用户确认过的产出**可写对应输出
  通道（speaking/writing）的 observation（证据），沿用 3.14「显式确认」纪律；**projection
  仍归 3.17**。这是既有架构纪律，不是新增防御性关卡。
- **Studio LLM 反馈**（Reading/Speaking/Writing 的 rubric 生成与判定）：取消 3.12.1 的留出集
  资格门，改为显示诚实边界——LLM 判定显示为「可纠正的辅助反馈」、可 adjudicate、evidence_class
  保持 `heuristic_proxy`、**不自动写 observation/projection**。核心 manual 路径仍为一等公民。

## 8. 系统需要的模型类别地图

从整个产品（四通道 · 个人内容学习闭环）往回推，共 **10 个能力类别**，按学习闭环三段分组：

### 输入侧（把内容变成可学资源，主要生产端/本地）

| # | 类别 | 产品角色 | 现状 |
|---|---|---|---|
| 1 | ASR 语音转文本 | 媒体转写、口语录音、realtime 复盘权威文稿 | ✅ whisper.cpp / WhisperX |
| 2 | 强制对齐（词时轴） | WordTimeline，高亮/切片/跟读根基 | ✅ MFA / WhisperX（生产端） |
| 3 | 音素 / G2P 发音分析 | 连读、语流、发音结构 | ⏸ 有，研究线搁置 |
| 4 | 说话人分离 diarization | 多说话人分段、角色接话、轮次归属 | 🔶 现靠字幕 speaker 近似 |

### 理解与富化（语言结构）

| # | 类别 | 产品角色 | 现状 |
|---|---|---|---|
| 5 | 句法分析 | B / SenseGroup / construction | ✅ spaCy sidecar |
| 6 | 文本 LLM 结构化推理 | rubric/判定/写作反馈/按需翻译/义项消歧/coach 叙述 | ✅ 3.12 中立 seam |
| 7 | 语义嵌入 / 相似度 | 个人语料语义检索、产出**近义 gap**、义项聚类、语料去重 | 🔶 明确要做（可本地） |

### 产出与交互（输出侧）

| # | 类别 | 产品角色 | 现状 |
|---|---|---|---|
| 8 | realtime 全双工语音 | 口语对话练习 → 产出语料 | 🆕 待建（独立中立类别） |
| 9 | TTS 语音合成 | 生词发音、例句朗读、写作读回、L1 语音提示、最小对立对听辨 | 🔶 明确要做（可本地 Piper） |
| 10 | 发音评测 / GOP | 口语「说得清不清楚」反馈（区别于类别 6 判「意思对不对」） | 🔶 后置（3.14 out of scope，研究线搁置） |

**排除项**：词典查询 / lexical normalization 是数据+规则 provider；翻译当前来自字幕轨，
按需翻译复用类别 6；嵌入仅在类别 7 立项。

## 9. 本地优先 vs 云中立的落位

- **需要「云 + 中立多 adapter」seam 的只有类别 6（文本 LLM ✅）和 8（realtime 待建）。**
- **类别 7、9 优先本地**（本地嵌入模型 / Piper TTS），既守 self-contained 不变量，又避免
  再增两个云依赖；需要时再评估云 adapter。
- 类别 1/2/3 生产端或本地内置；类别 4/10 后置。
- **同一 provider-seam 模式贯穿所有类别**：文本 seam 抽「结构化 JSON」，realtime seam 抽
  「音频流+turn+transcript」，TTS seam 抽「文本→音频」，嵌入 seam 抽「文本→向量」。

## 10. 对现有 Phase 与 3.12.1 的关系

- **3.12.1（LLM Judge Qualification）取消**：留出集人工 gold 的三级资格评估对个人工具过度；
  以 §7 的显示诚实边界替代。3.13–3.15 的 LLM 反馈据此直接接线，不再等资格门。
- 本文的「产出语料 + gap 复盘」与既有 **3.17（四通道 projection/review）**、**3.18（Cross-modal
  Coach）**在概念上重叠：gap-(c) 本质是 cross-modal coach 能力，产出语料是 projection 的
  上游证据。三者的**边界与顺序需要在 phase 划分时明确**（吸收 / 前置 / 并行），见 §11。

## 11. Phase 划分与顺序（已裁决 2026-07-16）

三个划分分叉已定：(1)「产出语料 + gap 复盘」**独立立 phase**，3.18 Cross-modal Coach 收窄为
「更广的 coach 叙述/聚合」，3.17 保留「usage→projection 的确认门」；(2) **先收口已启动的
Studio LLM 反馈接线**，再按 P2→P3→P4 节奏；(3) realtime 首批异构厂商为 **OpenAI Realtime +
千问 Qwen Omni**。

| 代号 | Phase | 范围 | 新模型类别 | 依赖 |
|---|---|---|---|---|
| P1 | Studio LLM 反馈接线（替代 3.12.1，folder `3.12.2`） | LLM rubric 生成 + judgment 显示接入 Reading→Speaking→Writing；显示诚实边界 | 无（复用 6） | 后端 judge 路由已就绪 |
| P2 | 输出产出语料库地基 | personal production corpus；先从 3.15 写作 attempts 入库 | 无 | 3.15 |
| P3 | 跨通道 gap-(c) 复盘 v1 | 产出语料 × 听读识别证据 → 能认不能产出 + 基础分布 | 无 | P2 |
| P4 | Realtime 语音对话 | realtime 中立 seam（OpenAI+千问）+ 当前段落对话 + 本地 whisper.cpp 权威文稿 | 8 realtime | P2/P3 |
| P5 | 语义嵌入增补 | 近义 gap + 语义语料检索；本地嵌入 | 7 嵌入 | P3 |
| P6 | TTS 语音合成 | 生词发音/例句/写作读回/L1 提示；本地 Piper | 9 TTS | 无（正交） |

顺序：**P1 → P2 → P3 → P4**；P5 增强 P3、P6 正交按需插入。后置：diarization(4)、GOP(10)。

仍开放（各自 phase 开工时裁）：

- 类别 7（嵌入）、9（TTS）本地实现选型与首个消费 surface。
- 产出 observation 写入的确认粒度（复盘逐词确认 vs 会话级确认）。

## 12. 一句话

> 把 realtime 语音对话作为一个**独立中立模型类别**引入，用它 + 写作产出共同喂养一个
> **个人输出产出语料库**，并以**跨通道「能认不能产出」gap 复盘**把已有的听读证据变成
> 说写练习靶子——全程只增证据、不自动下能力结论。
