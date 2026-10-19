# Studio Phases 3.13–3.16 外部参考库

日期：2026-07-15
来源：owner 委托 codex 的外部项目调研（2026-07-15 交付），经 Claude 对照
3.13 落地现状与 3.14–3.16 PLAN 批判性修订后入库。
定位：**交互与数据形状参考地图**，不是依赖清单；任何借鉴不得违反本项目
契约不变量（见 §0）。

## 0. 使用前提：参考的边界

所有外部参考只覆盖交互/流程/schema 灵感层，**均不具备本项目的证据模型**。
借鉴任何交互前，先回答它落在哪个既有契约上：

- 3.11 semantic 事实族：rubric（版本化、fingerprint 身份）→ attempt
  （conditions 快照）→ judgment（逐点、含 abstain、evidence_class）→
  adjudication（人工纠正），全部 append-only。
- observation 不跨通道污染；批量写入禁止；projection 由 3.17 统一处理。
- judge 三级资格（3.12.1）：未校验不进学习 surface。
- 用户产出权威：模型建议不能覆盖用户文本/模板身份。
- 无 LLM 默认路径是一等公民（3.13 已钉死：manual rubric + 用户自评）。

3.13 的教训直接适用：v2"同 rubric 双条件配对"被 3.11 validator 证伪，被迫
改为同 segment 双 rubric 并置。**照外部交互设计、不先过契约校验，会再撞一次。**

每个 phase 开工修订时按 §5 模板建立该 phase 的 Reference Matrix。

## 1. 总览表

| 参考对象 | 对应 Phase | 最值得看的部分 | 使用方式 | 证据等级 |
| --- | --- | --- | --- | --- |
| Read Frog | 3.13 后置 | 双语显示、选区工具栏、provider UX | Slice 7 接线时的交互参考 | 开源可核（[repo](https://github.com/mengxi-ream/read-frog)） |
| Lute v3 | 3.13 后置 | 不中断阅读的查词、阅读位置 | GUI 走查对照基准 | 开源可核（[repo](https://github.com/LuteOrg/lute-v3)） |
| Lector / Aprelendo | 3.13、3.16 | 从真实内容捕获词句进入输出练习 | 跨 Studio 流程参考 | 文档/产品页转述 |
| H5P 系列 | 3.13–3.15 | Essay、Dictation、Speak the Words、任务状态机 | 任务交互参考 | 开源可核 |
| iSpraak | 3.14 | 录音循环：权限、状态、重试、历史 | 录音流程参考 | 开源可核（MIT） |
| Sentence Paths | 3.14、3.16 | Sentence Recall、Dialogue Role、Language Islands | 高价值产品参考 | **闭源，营销页观察（heuristic_proxy）** |
| Harper | 3.15 | Rust、本地、结构化语法 finding | 首选技术 spike | 开源可核（Apache 2.0） |
| ERRANT | 3.15 | learner error 分类、span、revision diff | 数据结构/离线评测参考 | 开源可核 |
| LanguageTool | 3.15 | 多语言规则分类体系 | 分类体系/备选 provider | 开源可核 |
| Tatoeba | 3.16 | 例句、翻译链接、provenance | 外部 exemplar 参考 | 开放数据/API 可核 |

原调研 B 级清单中的 ReadingTree、InsightGUIDE 正文未给出任何依据，**不入库**；
若将来需要，先补来源与具体参考点再收录。

## 2. 3.13 Reading Studio（已 CODE COMPLETE，参考降级为回顾用途）

3.13 已于 2026-07-15 CODE COMPLETE（见 phase CLOSEOUT），原调研建议参考的
阅读位置、查词不中断、双语渐隐均已按项目自己的裁决落地（v37 cursor、派生
段落、切片窗回听）。本节参考只剩两个用途：

1. **owner GUI 走查对照**（`3.13-REAL-MEDIA-QA.md` §3）：走查"回听后恢复
   阅读上下文""查词不打断阅读"时，可用 Lute 的手感做对照基准。词汇状态
   着色按 owner 2026-07-15 裁决定为**词汇透镜**（3.13.5 PLAN guardrail）：
   干净正文与状态视图一键切换、来源诚实分视图；仍不借鉴 Lute 的"必须逐词
   处理才能清除高亮"记账语义与默认满屏着色。
2. **Slice 7 LLM 接线预备**（随 3.12.1 资格裁决）：Read Frog 的
   Translate/Explain/Speak 分层、provider 切换/批量请求/失败回退 UX 是届时的
   主要交互参考；其"用整页上下文提升局部解释"可对应 rubric source 快照的
   上下文利用。

H5P Interactive Book/Question Set 的任务卡状态（答题前/已提交/自评完成/可
重做、feedback 展开后保留原回答）已被 `ReadingTaskController` 状态机实质覆盖，
留作回顾对照即可。注意 H5P 的 completion/score 分离**不照搬**——本项目刻意
无综合分数。

## 3. 3.14 Speaking Studio（下一执行 phase，A 级参考集中于此）

开工修订 PLAN 前应实际体验/阅读：

1. **Sentence Paths**（最贴合）：Sentence Recall / Chunk Recall / Dialogue
   Role / Delayed Copying 与 3.14 的复述、角色接话、立即重说、延迟复述几乎
   一一对应。值得参考的交互顺序：先听/看来源 → assistance 逐级减少 → 用户
   主动说 → 回放或显示参考 → 自评 → 延迟后再次召回。其"真实文本与用户
   句子保持中心地位"与本项目用户产出权威一致。**证据等级警示**：闭源商业
   产品，机制描述来自营销页观察，入 Reference Matrix 时标 heuristic_proxy，
   具体机制以实际试用为准。
2. **H5P Speak the Words**（[repo](https://github.com/h5p/h5p-speak-the-words)）：
   麦克风任务状态机——waiting/listening/processing/result/error、麦克风不可
   用降级、transcript 与预期并列展示、retry 不覆盖第一次事实（对应本项目
   append-only attempt）。**不借鉴**其固定答案匹配与浏览器语音识别评分。
3. **iSpraak**（[about](https://oss-slu.github.io/projects/ispraak/about)）：
   只参考录音循环——prompt 来源三态（TTS/上传/现场）、权限与录音状态、
   提交后即时结果、再试一次、历史表现。**不借鉴**逐词评分（3.14 是开放
   复述不是朗读，且 guardrail 禁止综合口语分）。

ASR 路线与 3.14 PLAN Key Work 1 已一致，维持：whisper.cpp 短录音 spike →
用户核对/修正 transcript → raw 与 corrected 分开保存 → 不够用才评估
FunASR（provider 候选，非交互参考）。

## 4. 3.15 / 3.16 参考要点

### 3.15 Writing Studio

- **Harper**（[repo](https://github.com/Automattic/harper)，Apache 2.0）：
  首选技术 spike，可提前排（Rust crate，spike 成本低，结论影响 3.15
  WritingFeedbackProvider 的本地 provider 形态）。Rust 原生、完全本地、
  返回局部 lint 而非整段重写、首版专注英语——全部命中本项目约束（消费端
  无 Python 重运行时、用户文本权威、English L2 首版）。它只承担分层
  feedback 的最底层（语法拼写 finding：span/message/suggestion/rule
  provenance），**判断不了**信息遗漏、观点完成度、组织结构——那是 rubric
  层的职责，不因引入 Harper 而下移。
- **ERRANT**（[repo](https://github.com/chrisjbryant/errant)）：只作 schema
  与离线评测参考，不集成 runtime（Python，且违反消费端约束）。其 edit 形状
  `original span / corrected span / operation(M|R|U) / error type /
  correction / annotator` 直接对应 3.15 Key Work 3 的 feedback schema 与
  revision diff、user disposition、同类问题再现。
- **H5P Essay**（[repo](https://github.com/otacke/h5p-essay)）：**定位修正
  （与原调研不同）**——不作为"无 LLM 默认路径"参考。本项目无 LLM 路径已
  钉死为 rubric 对照 + 用户自评（3.13 先例、3.15 PLAN 明文），而 H5P Essay
  的 keyword fuzzy match 是自动表面匹配冒充内容判断，与"内容完成优先于
  语言表面"直接冲突。合法落点只有一个：**目标表达字面命中的客观事实展示**
  （对应 3.14 已计划的"目标表达字面命中"），作为显示层交互参考。可借鉴的
  外围机制：草稿自动保存、最小/最大字数、学生原文始终保留、可关总分只显
  feedback。
- **H5P Dictation**（[repo](https://github.com/otacke/h5p-dictation)）：只
  参考 assistance snapshot 持久化（播放次数、慢速版本、tolerance 配置随
  提交记录），**不借鉴**逐字评分——3.15 明文"逐字 dictation 成功不映射为
  writing acquired"。
- **LanguageTool**：仅作 finding category 分类体系参考与远期备选 provider；
  Java sidecar 仅在 Harper spike 失败后考虑。

### 3.16 Personal Expression

- **Sentence Paths Language Islands**：与 `UserSentencePattern` 对应关系最强
  的产品参考——用户把自己的习惯/工作/家庭/故事做成个人 speaking deck，句子
  可人工修改、多练习方式、跨时间复习。核心原则同频：**用户生活内容是一级
  资产，不是模型生成内容的附属**。对照表（同为 heuristic_proxy 观察）：
  从个人故事创建句子 ↔ 从媒体句创建 pattern；人工修改 ↔ 用户模板身份权威；
  多练习方式 ↔ slot/hidden template/speaking/writing；跨时间复习 ↔ delayed
  reuse history；自定义 gloss ↔ system construction 可缺席。
- **Tatoeba**（[api](https://api.tatoeba.org/)）：只参考 provenance 数据形状
  （sentence id/language/text/translations/tags/contributor/license/audio
  provenance），用于将来给个人 pattern 补充"其他真实例句"。**硬边界**：
  外部例句不能覆盖用户模板、不能自动算作用户掌握证据（3.16 guardrail 与
  Out 明文）。
- **Lector / Aprelendo**：参考"来源句 → 保存上下文 → 解释 → cloze → 写
  自己的句子 → 说出来 → 复习"的 handoff 流程，不搬其词汇中心数据模型。

## 5. Reference Matrix 模板（每 phase 开工修订时建立）

在 phase 目录建 `<phase>-REFERENCE-MATRIX.md`（先例：3.35），列：

```
参考项目
→ 具体页面/功能
→ 要解决的问题
→ 准备借鉴的交互或数据形状
→ 对应既有契约/不变量（3.11 事实族 / observation 通道 / 资格分级 / 用户权威 …）
→ 证据等级（开源可核 / 文档转述 / 营销页观察 heuristic_proxy）
→ 明确不借鉴的部分及原因
→ 对应 Slice
```

前两列之外，**"对应既有契约/不变量"与"证据等级"为必填**——前者防止
再次发生"外部交互过不了本项目 validator"（3.13 v2→v2.1 教训），后者沿用
项目 evidence-class 纪律（AGENT.md Algorithms And Metrics）。

## 6. 推荐优先级（修订后）

### A 级（3.14 开工修订前实际体验/阅读源码）

- Sentence Paths（实际试用，标 heuristic_proxy）
- H5P Speak the Words（状态机源码）
- iSpraak（录音循环）
- **Harper spike 可提前排**（结论影响 3.15 provider 形态，成本低）

### B 级（对应 phase 开工时补充局部设计）

- 3.13 GUI 走查对照：Lute；Slice 7 预备：Read Frog
- 3.15：ERRANT（schema）、H5P Essay（字面命中展示层）、H5P Dictation
  （assistance snapshot）、LanguageTool（分类体系）
- 3.16：Sentence Paths Language Islands、Tatoeba、Lector/Aprelendo

### 仅在 spike 失败后考虑

- FunASR（whisper.cpp 短录音 spike 不达标时）
- nlprule / LanguageTool Java sidecar（Harper spike 失败时）
