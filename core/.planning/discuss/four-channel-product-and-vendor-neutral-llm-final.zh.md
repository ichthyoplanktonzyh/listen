# 真实内容驱动的四通道语言学习 —— 产品方向与厂商中立 LLM 边界（最终讨论版）

> 日期：2026-07-11
> 状态：FINAL DISCUSSION DECISION
> 上游讨论：`four-skills-speaking-reading-writing-expansion.zh.md`、
> `four-skills-expansion-review-and-llm-boundary.zh.md`
> 范围：产品定位、听说读写扩展、两层复述、语义判定证据边界与厂商中立 LLM provider。
> 本文是后续 phase / ADR 的产品输入，不修改既有冻结 phase 的历史范围。

---

## 1. 最终产品定位

LLPlayerNext 不再只定位为“听力理解播放器”，而是：

> **以用户喜欢的真实内容为共同语境、听力先行的四通道语言学习工作台。**

听力仍是当前产品楔子和 Phase 3.x 主线，因为真实声音流理解是项目已经形成最深资产与
差异化能力的方向；但听力不是永久边界。系统最终帮助用户完成：

```text
听懂真实内容
  -> 读透其文字与篇章
  -> 用自己的话说出来
  -> 在新语境中写出来
  -> 回到新的真实内容继续输入与迁移
```

四通道共享用户自己的媒体与文章、句子与片段、个人语料库、跨媒体切片、学习资产、
append-only attempt/evidence、四通道 capability profile、复习、诊断与 Dashboard。

“听力先行”表示执行顺序和产品优势，不表示其他三通道只是听力的附属品。每个通道必须
有独立任务、独立证据和独立用户价值。

## 2. 四通道的共同学习路径

| 通道 | 核心问题 | 代表任务 |
|---|---|---|
| Listening | 能否从真实声音流中提取意义？ | 泛听、精听、无字幕识别、听力狩猎 |
| Reading | 脱离音频后能否理解文字和篇章？ | 伴生阅读、主旨/推断、读听差异诊断 |
| Speaking | 不看完整原句时能否组织并表达意义？ | 片段复述、角色接话、情境迁移 |
| Writing | 不复制原文时能否重构、改写并表达？ | dictogloss、摘要、回应、场景改写 |

优先功能是片段复述与角色接话、媒体伴生阅读与读听差异诊断、dictogloss 重构与摘要、
以及从真实句子提炼的个人表达模板。

既有 Phase 3.7–3.10 继续完成听力主线，不因本次定位更新被重写；四通道 Studio 在听力
主线真实 QA 后按独立 phase 逐个验证，不一次并行建设三个大型 surface。

## 3. Speaking：从模仿到构造性产出

Speaking 分两个独立 slice：

- **Shadowing**：chunk 跟读、录音、A/B/A、时长和停顿客观对比；属于模仿证据。
- **Constructed speaking**：隐藏完整原句后的片段复述、角色接话和新情境表达；
  才能产生较强的主动 speaking evidence。

Shadowing 成功不能自动升级为独立口语产出 acquired。

### 3.1 两层复述

构造性复述允许两个层级：

- L1 意义复述：用户用母语说明听懂了什么；
- L2 表达复述：用户用目标语言重新组织和表达。

默认直接进入 L2。只有当 L2 失败、用户不确定是否听懂或主动请求诊断时，才显示 L1
复述。L1 是归因工具，不是固定前置步骤，避免养成先翻译再开口的固定路径。

| 观察 | 允许的解释 |
|---|---|
| L1 覆盖充分、L2 覆盖充分 | 当前片段理解与 L2 表达均有正向证据 |
| L1 覆盖充分、L2 覆盖不足 | 较强 receptive–productive gap 信号 |
| L1 覆盖不足 | 可能是理解、回忆、投入或 ASR 问题；建议回听确认 |
| L1 覆盖不足、L2 覆盖充分 | 合法情况，不应强行改判 |
| 任一转写不可靠 | abstain，不产生自动结论 |

## 4. Reading 与 Writing 的优先楔子

Reading v1 先复用现有 transcript 建媒体伴生阅读姿态：独立阅读位置、段落/场景组织、
语境查词、段落理解与对应原音播放。核心差异化是只听、只读、读后听和听后读的比较，
据此区分声音识别、文字理解和材料难度障碍。

Writing v1 使用 dictogloss：听完整片段、记关键词、停止音频后重构、对照信息点并修改
第二稿。后续扩展摘要、观点回应、角色回复、语域改写和个人句模。逐字听写只提供
listening + spelling 信号；模型改写文本也不能冒充用户自己的 writing evidence。

## 5. 四种不同事实必须分开

```text
片段级理解 / 表达 attempt
    != LLM 对一次 attempt 的语义判定
    != 某个词条或 construction 的长期 capability evidence
    != 用户对长期 capability 的 override
```

L1 复述默认写入 clip-level `PracticeAttempt` 或未来 comprehension assessment。它属于
listening domain evidence，但不能因为用户复述了剧情，就给片段中所有词生成 lexical
listening observation。只有任务显式锚定某个词、phrase 或 construction，且回答确实证明
识别或产出了该目标时，才生成 target-level observation。

用户把“信息点 3 未覆盖”改为“其实说到了”，是对一次自动判定的 adjudication；它不等于
“我已具备该词 speaking 能力”的 capability override：

```text
LLM 原始判断 -> 用户纠正本次判断 -> projection 消费纠正后的 attempt evidence
长期 capability override -> 用户对一个能力通道的显式声明
```

## 6. 固定语义评分尺

LLM 不应在每次 attempt 中临时发明信息点并评价用户。系统先生成并缓存版本化评分尺：

```text
SemanticRubric
- source segment identity / snapshot
- required / optional information points
- accepted paraphrase notes
- language pair
- rubric version
- generator provenance
- user corrections
```

```text
SemanticJudgment
- attempt / transcript identity
- per-point covered | partial | missing | uncertain
- exact supporting response spans
- ASR uncertainty
- model / prompt / rubric versions
- raw structured output
- user adjudications
```

LLM 返回的引用必须能在 transcript 中精确定位。立即重说、延迟复述和不同模型判断只有
引用同一 rubric version 时才可直接比较。

## 7. 厂商中立的 LLM provider

### 7.1 核心裁决

LLPlayerNext 接受远程或本地 LLM 作为语义能力来源，但**不绑定任何厂商、SDK、模型名称
或单一 wire format**。领域层定义项目自己的任务契约，provider adapter 映射外部 API：

```text
Flutter / HTTP route
        ↓
application use case
        ↓
SemanticRubricProvider / SemanticJudgeProvider / WritingFeedbackProvider
        ↓
protocol adapter
        ├─ OpenAI Responses
        ├─ OpenAI Chat Completions / OpenAI-compatible
        ├─ Anthropic Messages
        ├─ Google Gemini native content / interaction API
        └─ future local or remote adapters
```

不能把 OpenAI `messages`、Anthropic content blocks 或 Gemini `contents/parts` 暴露为
application trait；否则名义上多厂商，领域仍被某一协议绑架。

### 7.2 初始主流协议覆盖

首个实现阶段覆盖协议族，而不是硬编码厂商品牌：

1. **OpenAI Responses**；
2. **OpenAI Chat Completions-compatible**：base URL、headers、model ID 可配置；
3. **Anthropic Messages**；
4. **Gemini native API**：支持 content / interaction 路径，不要求经 OpenAI 代理；
5. **本地 OpenAI-compatible 服务**：如 Ollama，但必须探测其实际 structured output、
   streaming 和模型能力，不能因 endpoint 兼容就假设语义完全兼容。

外部 API 会演进，支持列表由 adapter capability descriptor 表达。新增协议只新增 adapter，
不改变 rubric、judgment 或 capability 语义。

### 7.3 Provider profile 与安全

`LlmProviderProfile` 至少包含：adapter kind/protocol version、endpoint/base URL、model ID、
authentication reference、timeout/并发/费用预算/重试、data retention preference、已声明或
探测的 structured output/streaming/multilingual/audio/context 能力，以及允许用途。

密钥进入系统 keychain 或等价安全存储，不得写入普通 SQLite、日志、portable bundle 或
LLTimeline。自定义 endpoint 必须明确提示数据去向由用户配置决定。

### 7.4 能力差异与降级

- 缺结构化输出：严格 JSON fallback + schema 校验重试，或声明不支持该任务；
- 内容被拒绝：保存标准化 refusal reason，不当作学习失败；
- 响应截断或 schema 无效：不写 judgment；
- 无精确模型版本：保存最具体标识并标记 provenance 不完整；
- 不支持跨语言判断：该用途不可选，不静默改变任务语义。

## 8. LLM 判定的证据与审计

LLM 来源和可靠性是两个正交维度：

```text
source_kind = llm_judgment
validation_class = heuristic_proxy | manual_product_qa | ...
```

每次判定保存 provider profile、adapter、模型、prompt/rubric/schema version、输入快照 hash、
结构化输出、token/cost metadata、validation class 和用户 adjudication。模型升级不回写
历史判断；重新评价生成新 judgment。供应商隐藏推理过程不保存，也不作为教学依据。

## 9. LLM-judge spike 与资格门禁

十余条样本只足以验证管线，不能授予 capability 写入资格。Spike 必须：

1. 先定义 Rubric/Judgment contract；
2. 开发集与独立留出集分离；
3. 覆盖 narrative/dialogue/explanation、好/中/差回答、同义改写、ASR 噪声、L1/L2、abstain；
4. 人工逐信息点标注，测 precision、recall、误判、漏判、引用真实性和重复稳定性；
5. 至少对两类协议 adapter 做一致性对照；
6. 通过后先获得“显示可纠正 heuristic feedback”的资格；
7. 扩大人工评估并明确 projection 规则后，才允许影响长期 capability。

失败时降级为客观事实加用户自评，不阻塞录音、复述或写作本身。

## 10. 对现有 Phase 的影响

- **3.7**：不为未来四通道强行泛化 Hunting List；有真实需求时优先评估通用
  `FocusTarget`，不以避免未来迁移为唯一理由。
- **3.8**：现有 shadowing 为 3.8A；复述/接话为独立 3.8B 或 Speaking Studio，前置是
  recording → ASR 用例和 LLM-judge spike。
- **3.9**：v1 保持 listening diagnosis；未来说写迁移解释基于真实输出，只表达 possibilities。
- **3.10**：允许四通道与 cross-modal 区块独立缺席；未主动验证显示“尚未评估”，不显示 0 分。

## 11. 行动顺序

1. Gate Q：关闭或逐项明确豁免 3.3/3.35/3.4/3.5 的真实媒体 QA 债务；
2. 完成 Phase 3.7–3.10 听力主线；
3. Phase 3.11：Semantic Task & Evidence Foundation；
4. Phase 3.12：Vendor-neutral LLM Provider & Judge Qualification；
5. Phase 3.13：Reading Studio v1；
6. Phase 3.14：Speaking Studio v1；
7. Phase 3.15：Writing Studio v1；
8. Phase 3.16：Personal Expression；
9. Phase 3.17：Four-channel Projection & Cross-modal Review；
10. Phase 3.18：Cross-modal Coach & Four-channel Closeout。

一次只推进一个 Studio，不把 Reading/Speaking/Writing 合并成单次大爆炸交付。

## 12. 外部协议与研究参考

- OpenAI Responses / Chat Completions：<https://platform.openai.com/docs/api-reference/responses>
- Anthropic Messages：<https://platform.claude.com/docs/en/api/messages>
- Google Gemini API：<https://ai.google.dev/api/generate-content>
- Ollama OpenAI compatibility：<https://docs.ollama.com/api/openai-compatibility>
- 多语言 LLM-as-a-Judge 一致性限制：<https://aclanthology.org/2025.findings-emnlp.587/>
- LLM / human judge 偏差：<https://aclanthology.org/2024.emnlp-main.474/>
- L2 free recall 的任务与回忆语言影响：
  <https://www.cambridge.org/core/journals/studies-in-second-language-acquisition/article/abs/on-the-use-of-the-recall-task-to-measure-l2-reading-comprehension1/8BD47BD60F08659CEB5DC70598FB6F2D>
- CEFR Companion Volume：<https://rm.coe.int/cefr-companion-volume-with-new-descriptors-2020/16809ea0d4>

## 13. 最终一句话

> LLPlayerNext 从真实内容的听懂出发，以厂商中立且可审计的语义能力为辅助，让学习者把
> 听到和读到的语言，逐步变成自己能够说出、写出并迁移到新语境中的语言。
