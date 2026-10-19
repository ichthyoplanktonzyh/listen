# 从听力主线扩展到说、读、写 —— 四通道功能调研与产品建议

> 日期：2026-07-11
> 状态：DISCUSSION DRAFT
> 范围：基于 Phase 3.7–3.10 与现有四通道 capability model 的后续产品方向调研；
> 本文不构成已排期 PLAN，也不修改现有 phase 的冻结边界。

---

## 1. 背景与问题

Phase 3.4.1 已将词汇能力建模为 reading / listening / speaking / writing 四通道，
并严格区分 evidence、system projection、user override 与 effective assessment。
但 Phase 3.7–3.10 的实际学习行为仍几乎完全围绕 listening：

| Phase | 功能 | 实际主要证据 |
|---|---|---|
| 3.7 | 猎词单、泛听提示和语境识别 | listening |
| 3.8 | Shadowing、录音和 A/B 对比 | 模仿与听觉自检，尚不是独立口语产出 |
| 3.9 | L1-aware 声音障碍诊断 | listening |
| 3.10 | 事实聚合和教练建议 | 上游事实仍以 listening 为主 |

现有 cloze、听写与 shadowing 也不能直接填满另外三个通道：

- 阅读字幕不自动证明 reading acquired；
- 逐字听写主要验证听觉解码与拼写复现，不等于完整 written production；
- shadowing 主要验证模仿，不等于脱离原句组织和表达意义；
- ASR 转写正确不自动证明 speaking acquired；
- 一次成功不能证明跨语境迁移或延迟保持。

因此，后续不宜只增加几个“说、读、写练习按钮”。更合适的产品方向是：

> 以用户喜欢的真实媒体为共同语境，从理解输入逐步过渡到复述、改写、表达与交互，
> 并让四种行为各自产生诚实、可追溯、强度不同的能力证据。

## 2. 总体产品主线

同一个真实媒体片段可以自然生成四类活动：

```text
听：我能不能从真实语流中识别出来？
读：脱离音频后，我能不能理解文字及其组织？
说：不给完整原句时，我能不能把意思讲出来？
写：不给完整原句时，我能不能重构、改写并清楚表达？
```

这条路线保留 LLPlayerNext 已有的差异化资产：真实媒体、精确时间轴、个人语料库、
跨媒体切片、听力词典、Construction 边界和长期 capability profile。它不是另建一套
口语课、阅读课和作文课，而是让同一份个人内容沿四种语言行为继续生长。

## 3. “说”方向

### 3.1 片段复述（优先级最高）

播放 10–60 秒片段，隐藏完整字幕后让用户：

- 用自己的话复述事件；
- 概括人物观点；
- 回答“为什么这样说”；
- 复述一段步骤、解释或论证。

录音后展示可验证的客观信息：

- ASR 文本及不确定区段；
- 原片关键信息点覆盖；
- 是否主动使用目标词、phrase 或 construction；
- 时长、语速、句中长停顿、自我修正次数；
- 原音 → 用户录音 → 原音的 A/B/A 对比；
- 多次 attempt 的变化，以及数日后的延迟复述。

不应首先给出不可解释的综合口语分数。更诚实的表达是“覆盖 4/6 个信息点”、
“使用了目标表达”、“句中长停顿由 5 次降至 2 次”，并明确 ASR 与自动分析的置信边界。

### 3.2 角色接话

在影视或访谈对话中暂停于某个角色开口之前，让用户替角色回答：

1. 看完整原句朗读；
2. 只看关键词或意群；
3. 不看原句，用自己的话回应。

完成后播放原角色答案。比较重点不是与原句逐字一致，而是：

- 是否完成交际意图；
- 是否覆盖必要信息；
- 使用了哪些个人语料表达；
- 原角色提供了哪些更自然但非唯一正确的表达。

这比无上下文的开放式 AI 陪聊更适合项目，因为场景、人物关系和后续反应均来自真实媒体。

### 3.3 个人表达模板

将 Phase 3.4.3 的 `UserSentencePattern` 变成用户可见功能：

```text
原句：I ended up staying there for another week.
模板：I ended up [doing something] for [duration].
用户句：I ended up debugging it for the whole weekend.
```

用户可以：

- 从任意字幕句提炼模板；
- 标记可替换槽位和适用场景；
- 填入自己的内容；
- 朗读、脱稿说出或写出新句；
- 在数天后的新情境重新调用。

这同时服务 speaking 与 writing，并能先验证个人模板的价值，而不依赖 canonical
construction library 或自动 occurrence provider。

### 3.4 限时复述与情境迁移

- 4/3/2 类限时复述：逐步压缩表达时间，观察停顿与冗余变化；
- 同意/反驳片中观点；
- 用两个已学表达解释一个新问题；
- 把采访者的问题改成回答自己的经历；
- 数天后对同一内容做延迟复述。

立即重复可帮助口语流利度，但密集重复可能对不同流利度指标产生不同影响，因此产品上
宜采用“立即重说一次 + 延迟重说”，而非机械连续重复。

## 4. “读”方向

### 4.1 媒体伴生阅读器

第一步不必成为完整电子书平台。可先把现有 transcript 升级为真正的阅读姿态：

- 阅读时不随播放位置自动滚动；
- 以段落、场景、章节组织，而不是只显示字幕行；
- 点击词、phrase、句子查看释义和个人语料例句；
- 可标记“看得懂但听不出”；
- 从阅读位置播放对应原音；
- 支持隐藏翻译、生词提示渐隐；
- 保存独立于播放位置的阅读进度。

后续再扩展网页、TXT、Markdown、EPUB 和带 transcript 的播客，不必在首个切片承担
PDF 排版和通用电子书生态。

### 4.2 阅读—听力差异诊断（差异化核心）

同一段内容可以分别做：

- 只听理解；
- 只读理解；
- 阅读后再听；
- 听后再读。

由此形成对用户有解释力的二维诊断：

| 表现 | 更可能的障碍 |
|---|---|
| 读懂、听不懂 | 声音识别、切分、弱读、语速 |
| 听懂、读不懂 | 拼写、复杂句、书面表达 |
| 都不懂 | 词义、背景知识、句法或内容难度 |
| 都懂 | 可转入巩固、复述或写作 |

该功能可直接消费现有 meaning fit / sound fit 双维模型，并使 reading capability
不再只是 listening 诊断的辅助字段。

### 4.3 段落级理解任务

Reading 不应退化为“读了多少词”或“点了多少生词”。每一小节只设置少量高价值任务：

- 选择主旨或标题；
- 找出人物立场；
- 判断因果与转折；
- 段落或事件排序；
- 识别代词、省略与指代关系；
- 用一句话概括。

这些任务分别产生主旨、信息、推断和篇章组织层面的证据，不能全部折成一次词汇识别。

### 4.4 泛读与阅读狩猎

泛读继承泛听的低打扰原则：

- 默认零打扰；
- 查词不强制离开文本；
- 阅读结束后再整理生词；
- 材料难度由已知词覆盖、句法复杂度和主题熟悉度解释；
- Dashboard 不做时长排行和打卡装饰。

3.7 猎词单可扩展 reading encounter，但不应一开始就醒目标红目标。更自然的验证是：

- 读完一段后询问是否出现某个目标表达；
- 让用户在文本中定位它；
- 再检查其当前语境意义。

## 5. “写”方向

### 5.1 Dictogloss 式重构（优先级最高）

这是现有 sentence dictation 最自然的升级：

1. 听一段完整内容；
2. 只记关键词；
3. 音频停止后用自己的语言重构；
4. 对照原文；
5. 区分内容遗漏、表达差异和语法问题；
6. 提交第二稿。

它同时训练听力理解、意义保持、篇章组织、词汇主动提取和修改，而不是要求逐字复制。

### 5.2 片段摘要与观点回应

- 一句话概括；
- 50–100 词摘要；
- 写出同意或不同意的理由；
- 给视频人物写一条回复；
- 将口语片段改写成邮件、笔记或报告。

任务需要保存目标、体裁和必要信息点，避免只按语法错误数量评价。

### 5.3 场景续写与对话改写

- 预测下一句或下一幕；
- 给角色写另一种回答；
- 将冲突对话改写得更委婉；
- 将非正式对话改成正式邮件；
- 在第一人称与第三人称之间转换。

这类任务直接复用媒体语境，并把语域、礼貌和语气纳入 written production。

### 5.4 分层反馈与修订

若引入 LLM 或其他 writing feedback provider，建议按以下顺序反馈：

1. 是否完成表达目标；
2. 是否遗漏关键信息；
3. 组织与衔接；
4. 用词是否适合语境；
5. 语法与拼写；
6. 给出数量有限、可操作的修改建议；
7. 要求用户提交修订稿。

系统保存原稿、反馈、用户接受/拒绝项、修订稿和后续复发情况。不能直接用“完美答案”
替换用户文字，也不能将模型改写后的正确文本当作用户 writing acquired 证据。

## 6. 四通道证据边界

新增功能前应补一份权威 evidence matrix，至少区分以下行为：

| 行为 | 通道 | 建议证据语义 |
|---|---|---|
| 看字幕时点词查义 | reading | 行为信号，不足以判定 acquired |
| 正确回答段落理解题 | reading | 有语境理解证据 |
| 在阅读中认出目标表达 | reading | 语境识别证据 |
| Shadowing 接近原句 | speaking | 模仿证据，不等于独立产出 |
| 脱稿复述并使用目标表达 | speaking | 较强生产证据 |
| 角色接话完成交际意图 | speaking | 交互型生产证据 |
| 逐字听写正确 | listening + spelling | 不直接等于完整 writing acquired |
| 用目标表达写新句 | writing | 有提示生产证据 |
| 在新情境写出目标表达 | writing | 较强迁移证据 |
| 修改后才正确 | writing | 学习与修订证据；保留首稿事实 |

Projection 不宜由一次练习直接升级：

- 同语境重复成功只说明练习熟练；
- 不同媒体、不同句子成功更接近语境迁移；
- 延迟后成功提供保持证据；
- 无提示主动产出强于有提示产出；
- user override 始终与 system projection 分离。

## 7. 推荐优先级

### P0：补齐真实输出闭环

1. **将 3.8 扩为 Speaking Studio v1**：保留 shadowing，新增片段复述、角色接话、
   ASR transcript、信息点/目标表达覆盖、立即与延迟重说，开始产生 speaking evidence。
2. **新增 Dictogloss / 片段重构**：复用精听练习浮窗，从逐字听写走向意义重构，
   开始产生有限但真实的 writing evidence。
3. **新增媒体伴生阅读姿态**：先消费现有 transcript，支持独立阅读、段落理解与
   读听差异诊断，开始产生 reading evidence。

### P1：把个人语料变为生产工具

4. 个人句子模板与 construction slots；
5. 片段摘要、观点回应和场景改写；
6. speaking / writing 复习卡；
7. 四通道猎词：听到、读到、说出、写出；
8. Dashboard 的跨通道差异诊断。

### P2：扩展内容与高级反馈

9. 网页、Markdown、EPUB 导入；
10. 泛读 Inbox 与阅读难度分拣；
11. 可选 AI writing feedback provider；
12. 真实媒体场景驱动的 AI 对话；
13. 跨材料主题写作和口头陈述。

## 8. 对 Phase 3.7–3.10 的建议

### 3.7 Hunting List

首版仍可保持 listening-only，但猎词资产模型应避免永久绑定 listening。后续可增加
target modalities、reading encounter、prompted speaking use 与 prompted writing use。

### 3.8 Shadowing & Recording Comparison

建议拆成两个可独立验收的 slice：

- 3.8A：现有 Shadowing & Recording Comparison；
- 3.8B：Clip Retelling & Role Reply。

3.8B 必须要求用户在看不到完整原句时组织语言，否则该 phase 仍只形成模仿能力，
不能兑现 speaking 通道。

### 3.9 L1-aware Diagnosis

v1 保持 Mandarin → English listening diagnosis。后续 provider 可增加 speaking 与 writing
的迁移候选，但必须表达为 possibilities，并依赖用户自己的实际输出证据，不能仅凭 L1
给用户贴固定错误标签。

### 3.10 Coach Dashboard

Dashboard 应预先允许四通道区块独立缺席：

- listening：语境识别与语流障碍；
- reading：文本理解、推断与阅读识别；
- speaking：复述完整度、主动使用与客观流利度变化；
- writing：任务完成、修订、反复问题与主动使用；
- cross-modal：读懂但听不出、听懂但说不出、能认但不能产出。

缺少数据时显示“尚未进行该通道的主动验证”，而不是显示 0 分。

## 9. 推荐的后续 phase 形状

如果不扩大 3.8 的边界，可将新功能独立排期：

| 建议 Phase | 目标 | 最小成立切片 |
|---|---|---|
| Speaking Studio v1 | 从模仿走向独立表达 | 片段复述 + 角色接话 + speaking evidence |
| Reading Studio v1 | 从字幕消费走向主动阅读 | transcript 阅读姿态 + 段落理解 + 读听差异 |
| Writing Studio v1 | 从听写走向意义生产 | dictogloss + 摘要/回应 + revision history |
| Personal Expression | 让媒体语言迁移到用户生活 | UserSentencePattern + slots + 说写复用 |

这些功能继续遵循 3.x 的全局规则：可组合、不强制流程、非课程化、非游戏化、
capability gating、证据诚实以及学习资产 outlive media。

## 10. 研究与产品参考

- Council of Europe, CEFR Companion Volume (2020)：将语言活动区分为 reception、
  production、interaction 与 mediation，并细分 reading、oral production、written
  production、planning、monitoring 和 repair：
  <https://rm.coe.int/cefr-companion-volume-with-new-descriptors-2020/16809ea0d4>
- Lambert, Kormos & Minn：相同口语任务重复与流利度变化，不同指标的改善次数并不相同：
  <https://www.cambridge.org/core/journals/studies-in-second-language-acquisition/article/abs/task-repetition-and-second-language-speech-processing/0EA95A4C7D9E90CD2AB30043F84A4635>
- Suzuki：密集任务重复对流利度发展存在正反两面，支持产品采用有限立即重说与延迟复述：
  <https://www.cambridge.org/core/journals/studies-in-second-language-acquisition/article/massed-task-repetition-is-a-doubleedged-sword-for-fluency-development/D28EDD7E3D0FA15630165538D706E80F>
- Clinton-Lisell et al.：阅读与听力理解比较的元分析；自定速阅读在部分理解条件下有独立优势：
  <https://doi.org/10.3102/00346543211060871>
- Liu & Zhang：泛读对英语词汇学习总体有积极作用，材料与配套活动会调节效果：
  <https://eric.ed.gov/?id=EJ1179114>
- Yanguas：dictogloss 比对照任务产生更多显式 language-related episodes，支持将逐字听写
  扩展为意义重构：
  <https://www.cambridge.org/core/journals/recall/article/abs/effects-of-task-type-in-synchronous-computermediated-communication/79890601769D4F80DFC70218C20277AD>
- Storch：协作写作可为二语学习提供机会，但效果受任务类型、水平差异与协作关系影响：
  <https://www.cambridge.org/core/journals/annual-review-of-applied-linguistics/article/abs/collaborative-writing-in-l2-contexts-processes-outcomes-and-future-directions/7BDC9F3256EF7573447387110724DEE4>
- Readlang 产品参考：导入真实内容、即时语境释义、词汇沉淀与写作纠正：
  <https://readlang.com/features>

## 11. 最终产品判断

下一轮最值得做的四项功能是：

1. 片段复述与角色接话，让 speaking 从模仿走向表达；
2. 媒体伴生阅读与读听差异诊断，形成项目独特的 reading 价值；
3. Dictogloss 重构与摘要/回应，让 writing 从听写走向意义生产；
4. 个人句子模板，让真实媒体中的语言迁移到用户自己的生活。

它们共同指向一个比“补齐四项技能”更清晰的产品：

> 从喜欢的真实内容中听懂一句、读透一段，再把它变成自己能够说出和写出的语言。
