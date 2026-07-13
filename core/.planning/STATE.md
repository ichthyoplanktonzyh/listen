---
gsd_state_version: 1.0
milestone: v0.7.0
milestone_name: local production engine and lightweight consumer app
status: active
last_updated: "2026-07-13T18:45:00.000+08:00"
---

# LLPlayerNext — 项目活记忆

> 最后更新：2026-07-13 18:45 CST
> 更新原因：新增 Phase 3.9.2，纠正句法 gold/产品保守策略混淆并推进单 Provider 产品激活。

## 当前位置

- **当前执行主线**：Phase 3.12 Vendor-neutral LLM Provider **CODE COMPLETE**（见其
  CLOSEOUT；分支 `codex/3.12-vendor-neutral-llm-provider`，三 commit）。下一执行 phase 为
  Phase 3.13 Reading Studio v1（首个真实消费 3.11 契约 + 3.12 provider 的 Studio），或
  Phase 3.12.1 LLM Judge Qualification（可与 3.13 并行）；开工前按现状修订各自 PLAN。3.12
  剩余仅 owner 真实 provider 端到端产品 QA 与 owner 按需的增量协议（Slice 4）。已落地并全绿：
  中立契约层（domain
  `llm_provider` + application 两层 seam）；**两个异构协议 adapter（OpenAI Chat-compatible +
  Anthropic Messages）过同一 fake-server 契约套件 = 中立性证明**（`crates/llm-provider/`，
  10 契约测试，`drafts[0]==drafts[1]`）；draft→judgment use case（身份服务端铸造、过 3.11
  validator、四层分离经 LLM 路径仍成立、5 种失败均不写 judgment 的诚实降级）；`SecretStore`
  抽象 + in-memory 实现 + schema v36 profile 持久化（只存 auth_ref，守卫测试证明密钥不落 DB）。
  **Slice 2b 已补全**：`BuiltSemanticProvider` 工厂（profile→adapter）；真实 macOS keychain
  `KeychainSecretStore`（security-framework，cfg-gated，composition root 注入）；四条
  `/v1/llm/providers*` HTTP 路由（CRUD + probe 实测 + provider-backed judge），响应用
  secret-free `ProviderProfileView`；OpenAPI 契约齐全；集成测试证明 secret 不回显/删除移除/
  未知 provider 404。**Slice 3 已完成**：Flutter 最小设置 UI（AI providers 类目：provider
  列表 + 添加表单 + 连通/能力 probe + 删除；密钥只写提交即清空、数据去向警告、"未获显示
  资格"提示、has_credential 徽标不显 secret）；手写 DTO + fixture 契约测试（ADR 0014）；
  flutter analyze 零问题、flutter test 288 全通过。ADR 0022 已立。PLAN 修订为 v3（含远端案例
  证伪）。判定默认**不获显示资格**（属 3.12.1）。**剩余**：增量协议 OpenAI Responses/Gemini
  （Slice 4，owner 按需，只加 adapter 不改契约）、CLOSEOUT。
- Phase 3.11 Semantic Task Evidence Foundation 已 CODE COMPLETE（见其 CLOSEOUT）。
  Phase 3.9 不作为后续 Studio phase 的硬依赖。Phase 3.9.1 已建立共享句法契约、B/SenseGroup
  consumer 与 Construction matcher seam；后续复核发现唯一否决样本混淆歧义句产品 policy
  与 parser gold。Phase 3.9.2 已启动，以修正版 holdout 重新资格评估 spaCy，并在通过后接入
  单 Provider 共享产品编排；当前激活前仍保留 B/SenseGroup fallback。
- **治理线状态**：Phase 2.23 Architecture Debt Paydown 已于 2026-07-03 收口（详见其 CLOSEOUT）；3.x 开工前置全部就绪。
- **算法线状态**：Phase 2.19 / 2.20 / 2.21 全局质量线仍搁置；Phase 3.9 仅恢复与 L1 学习
  价值直接相关的 A/B/C audible-structure contract、linking 结构生成和证据门控。
- **当前版本**：0.7.0。
- **当前产品定位**：以用户真实内容为共同语境、听力先行的四通道语言学习工作台。听力是
  当前楔子而非永久边界；后续 reading / speaking / writing 逐个 phase 验证独立任务和证据。
  本地优先不等于仅限本地；在线内容与厂商中立 LLM provider 可作为可选能力进入系统，
  学习资产与高频播放路径仍默认本地。
- **语义能力边界**：LLM 不绑定单一厂商或 wire format；application trait 下先以两个
  异构协议（OpenAI-compatible + Anthropic Messages）证明中立，其余协议增量适配。
  LLM judge 资格分三级：未经 3.12.1 留出集校验不进学习 surface，通过后仅显示可纠正
  feedback，更大评估 + confirmation gate 后才可作 supporting evidence。
- **代码分支状态**：以 `git status` / `git log` 为准，不在 STATE 记录静态分支名。

## 项目双路线

| 路线 | 目标 | 当前状态 |
|---|---|---|
| 本地重装生产引擎 | 生成精准 WordTimeline / ChunkTimeline / LLTimeline JSON | 阶段性收口，转长期研究与质量提升 |
| 轻量消费端 LLPlayerNext | 稳定读取 `.lltimeline.json` 并播放学习 | Phase 2.22 用户工作流语义已收口；3.x 转入学习闭环 |

## 活跃 / 搁置 Phase

### Phase 2.11: Architecture Seam Consolidation ⏳ 部分完成

- 已完成：能力矩阵 API、学习语言来源、domain 拆分。
- 待推进：Step 4-5 依赖后续路线优先级；Step 6 低优先。
- 规划文档：`.planning/phases/2.11-architecture-seam-consolidation/2.11-PLAN.md`

### Phase 2.19: Real Benchmark Scoring ⏸ 已搁置

- 初始 scorer 已落地：TIMIT `.PHN` phone PER、Buckeye `.phones` windowed PER、TED-LIUM
  transcript/timing exact match。
- 初始结论：pipeline 可评估，但 phone-level 质量尚未 release-grade；TIMIT/Buckeye
  异常窗口、espeak symbol mapping、lead-in filtering 和 boundary metrics 待算法线重启后处理。
- 搁置原因：2026-07-02 起 speech-analysis 算法线暂停，主线转入 Phase 3.x。
- 规划文档：`.planning/phases/2.19-real-benchmark-scoring/2.19-PLAN.md`

### Phase 2.20: Rhythm-first Listening Analysis ⏸ 已搁置

- 已落地：deterministic RhythmFrame v0、Flutter compact rhythm 区块、Rhythm A/B/C 视图、
  RhythmFrame QA/scorer fixture gate、Helsinki/LibriTTS weak-label adapter、benchmark role manifest、
  duration/RMS manual QA 对比工具与算法/指标 evidence-class 规则。
- 路线校正：当前产品 contract 正确，但 generator 主线应迁移到 forced-aligned WordTimeline +
  duration/rate + RMS energy/F0 的 layered hybrid；CTC phone evidence 降级为 segmental evidence。
- 搁置原因：算法质量提升让位于 Phase 3.x 学习闭环。
- 规划文档：`.planning/phases/2.20-rhythm-first-listening-analysis/2.20-PLAN.md`

### Phase 2.21: Audible Structure Architecture ⏸ 已搁置

- 已落地：audible-structure v1 contract、A/B/C references、WordTimeline-first document-level
  `rhythm_frames`、Reference B connected-speech rule engine、word acoustic cues、Rust RMS/F0
  baseline、Flutter document-level rhythm fallback。
- 当前权威：document-level `LLTimelineDocument.rhythm_frames` 优先；`PhoneTimeline.sound_analysis`
  内的 rhythm frame 是 transitional fallback。
- 搁置原因：W8 人工标注/阈值校准与端到端回归待算法线重启。
- 规划文档：`.planning/phases/2.21-audible-structure-architecture/2.21-PLAN.md`

### Phase 3.0: English Listening Learning Loop ⏳ 当前产品主线

- 目标：在 Phase 2 的真实声音流资源和 Phase 2.18 的学习资产架构上，把英语先做成完整学习闭环。
- 核心闭环：真实输入 → 可理解度判断 → 诊断 → 主动练习 → 复习巩固 → 进度反馈 → 回到真实输入。
- 产品原则：
  - 语言能力来自听力突破和大量可理解输入。
  - 常见语言学习功能重写为听力本位能力。
  - 首个真实组合为 Mandarin L1 → English L2，L1/L2 理论进入诊断层。
  - Cloze、听写、字幕渐隐、chunk replay、本地 YouGlish-like 个人语料库是关键体验。
  - 2026-07-04 新增：精听/泛听一级心智；复习/词典/dashboard 是资产消费层；可组合
    不强制流程；功能按场景分不按设备分（生产端唯一 PC-only）；泛听默认零打扰。
- 前置已就绪：Phase 2.23 已收口，`main.dart` 为 composition root（1457 行），controller + Store 为唯一 UI 状态模式，practice UI 可直接开工。
- 规划文档：`.planning/phases/3.0-english-listening-learning-loop/3.0-PLAN.md`
- 执行序列：Phase 3.1 ~ 3.18（含 3.12.1）已全部立 PLAN（3.11–3.18 于 2026-07-11 新增，
  为方向承诺，开工前须按现状修订），分解与依赖见
  `.planning/phases/3.0-english-listening-learning-loop/3.0-PHASE-BREAKDOWN.md`；
  产品输入见 `.planning/discuss/listen-learning-activity-path.zh.md` 与
  `.planning/discuss/four-channel-product-and-vendor-neutral-llm-final.zh.md`。

### Phase 3.3: Extensive Listening & Inbox ✅ Gate Q 基线通过

- 已落地：泛听 session、软/硬打断、理解度自报、Listening Inbox 捕获与整理流。
- 2026-07-11 owner 明确确认 Gate Q Q1 通过；当前泛听行为成为 3.7 的已验收基线，3.7
  不承接 3.3 全量 QA。
- 计划与 QA：`.planning/phases/3.3-extensive-listening-inbox/3.3-PLAN.md`、
  `.planning/phases/3.3-extensive-listening-inbox/3.3-MANUAL-QA.md`。

### Phase 3.35: Listening Workbench UI Redesign ✅ Gate Q 基线通过

- 代码完成：来源中立首页、分组工具栏与播放条、可拖动且持久化的工作台、右侧学习面板、
  资源技术详情折叠、诊断摘要/证据、词汇学习层级、六类设置导航和产品化添加来源流程。
- 视觉系统：集中式 `ListenTheme` 已覆盖浅色工作面、media overlay、节奏、音素、学习状态、
  loading/error/degraded/disabled 等语义色；当前句按真实列表行位置稳定跟随。
- UX 走查 P0-P2 全部完成；参考取舍见 `3.35-REFERENCE-MATRIX.md`。
- 收尾复审（P3）：修复首页“继续学习”死代码（持久化最近媒体，继续播放按后端进度恢复）、
  readiness 冷启动全零（预取全局收件箱/词汇量，字幕就绪改用最近媒体）、倍速下拉不刷新、
  分栏拖动逐帧写盘（`saveSoon` 防抖），并做文稿跟随暂停/回到当前句、窄窗口媒体区可拖动、
  姿态栏上下文显示、Test 姿态描边化、文稿空态与无媒体播放条精简；详见 `3.35-UX-REVIEW-CHECKLIST.md` P3 节。
- 验证：`flutter analyze`、`flutter test`（188 passed）、`git diff --check` 通过。
- 2026-07-11 owner 明确确认 Gate Q Q2 通过；当前工作台/capability UI 成为 3.7 新入口
  的稳定基线，不因 3.7 重新打开全面视觉改版。
- 边界：不复制参考产品，不实现新 YouTube provider，不改变学习领域语义。
- 规划文档：`.planning/phases/3.35-listening-workbench-ui-redesign/3.35-PLAN.md`。

### Phase 3.4: Audio-first Review Queue ⏸ PAUSED

- 已完成第一条竖切片：schema v19 `review_schedules`、历史卡回填、到期查询、三档评分调度、
  `ReviewAttempt` / `ReviewCompleted` 事件、Flutter ReviewController/Store 与声音卡页面。
- 四类卡型已完成：后端 `ReviewCard` 读模型根据来源和锚点派生听音识词、chunk cloze、
  phrase 出现判断、原句回听；Flutter 分别提供翻词、填写空白、二选一判断和原句对照交互。
  卡型不是持久化权威字段，历史 `ReviewItem` 无需 schema 迁移。
- schema v20 新增 `hunting_candidates`。复习评为 `again` 时，有效词条+句子语境写入
  `NotRecognizedInContext` observation，同时按词条/复习项聚合候选与失败次数；来源已丢失时
  仍保留 snapshot 候选，不伪造 observation，也不静默修改 `LearningStatus`。
- 复习入口已进入 3.35 工作台首页和学习工具菜单；词汇本可手动入队，来源媒体不匹配时不会
  误播当前媒体，而是使用 prompt snapshot 降级。
- schema v21 新增 `recognition_evidence` / `upgrade_suggestions`：practice、review 和逐例
  `RecognizedInContext` 成功证据按不同句子/媒体去重，5 个语境生成 `heuristic_proxy` 建议；
  复习结束页与词汇详情可确认/拒绝，确认写入既有状态历史和 `StatusChanged` 事件，拒绝冷却
  30 天；pending 与完整历史均有查询 API。
- QA 状态：owner 明确延期 Q3；复习 UX/功能后续调整完成后再做真实媒体 ≥8 卡及完整链路
  QA。3.7 只验证 `hunting_candidates` 候选接缝，不代替该验收。
- 规划文档：`.planning/phases/3.4-audio-first-review-queue/3.4-PLAN.md`。

### Phase 3.5: Difficulty & Content Triage ⏸ Slice 9 QA 延期

- Slice 1–8 已完成：双维 fit、可解释信号、三队列、listening-projection-v1、反馈校准与
  冷启动标注均已落地。
- 唯一剩余的 Slice 9 人工分档 QA 由 owner 明确延期；待内容分档 UX/功能调整完成后重做，
  3.7 不消费分档结果，也不把狩猎作答写入 fit 校准。
- 计划：`.planning/phases/3.5-difficulty-content-triage/3.5-PLAN.md`。

### Phase 3.7: Hunting List ✅ COMPLETE

- Gate Q 已于 2026-07-11 通过：Q1/Q2 明确通过，Q3/Q4 带清晰风险归属主动延期。
- Slice 1–5a 已落地：独立资产/管理 UI；当前 media/track 的 lemma/FTS 出现点定位；无索引
  一键重建；显式会话级狩猎模式；总预算 5、每目标最多 2；priming/check 与“是/否/没注意”
  三态作答；completion 理解度对话展示“命中 N 次 / 听出 M 次”，四类计数随
  `listening_completed` event 持久化且不进入 content-fit。“没注意”只记 LearningEvent，
  不写 observation。
- 2026-07-11 owner 明确确认真实媒体狩猎模式功能通过；阶段已创建 CLOSEOUT 并冻结。
- 计划与结论：`.planning/phases/3.7-hunting-list/3.7-PLAN.md`、
  `.planning/phases/3.7-hunting-list/3.7-CLOSEOUT.md`。

### Phase 3.9: L1-aware Diagnosis v1 ⏳ 已恢复，A/B/C 算法与 UI 重构中

- 2026-07-13 规则第二批：B 规则源 v3 新增构式门控与 `gotta/hafta/hasta`、habitual
  `used to`、`supposed to/ought to`、`lemme/gimme/kinda/sorta/outta/lotta/lotsa/dunno`；`gonna`
  阻断 motion + NP/地点歧义，`wanna` 阻断 wh-extraction 歧义，`be used to` 不误判 habitual。
  weak form 补标点、话语起始 `/h/`、`the + vowel` 阻断。下一批为 `/nt/`、syllabic-`n`、
  schwa deletion 与 `and/of` 音段删除。
- 2026-07-13 建立 General American 语流规则权威目录：规则按 `B-safe`、`B-context`、
  `C-only`、`dialect` 分层，全部常见规则进入目录但只有文本证据充分者进入 B。第一批新增
  `/t,d,s,z/ + /j/` coalescence、`/n/` 部位同化、V#V `[j]/[w]` 连接、跨词 flap；词内
  flap 加入重音条件，`/t,d/` 删除收紧为词尾辅音簇环境。下一步补最小 POS/重音/边界/
  构式上下文后接入其余 `B-context` 规则，并用真实字幕统计误报/漏报。
- 2026-07-13 真实媒体 QA 修复：A/B/C 共用跟随式长句视口，紧凑态自动定位当前结构并提示
  横向溢出，展开态按结构节点换行显示完整句；B 的普通文本跨度也参与 token 跟随。
- 2026-07-13 真实媒体 QA 修复：C 不再接受 text/WordTimeline 预测 frame 作为降级替代；仅当
  当前句音素已加载且 frame 的 phone evidence coverage 大于零时显示实际可听结构。
- 2026-07-13 真实媒体 QA 修复：Flutter 刷新 LLTimeline 时以当前后端导出为权威，只从旧
  导入文档补回缺失 artifacts，不再丢弃由现有 WordTimeline 新派生的 RhythmFrame。
- 2026-07-13 A/B/C 重构第二批完成：B 已覆盖 weak form、contraction、assimilation、
  deletion、flapping。Deletion 现在基于完整短语删除预测弱化的词尾 `/t|d/`，flapping
  基于完整词将元音间 `/t|d/` 替换为 `/ɾ/`；所有纯文本规则仍严格不生成 C。
- 2026-07-12 于独立分支 `codex/3.9-l1-aware-diagnosis` 落地（基于 3.7 tip，与 3.8 并行）：
  LearnerProfile L1 持久化（schema v34，v33 保留给 3.8 in-flight 的 recording_assets）+
  统一读取面 + 设置入口；diagnosis-core zh→en 九类难点 profile provider（研究依据见
  `3.9-L1-PROFILE-EVIDENCE.md`，识别规则 evidence class 一律 heuristic_proxy）；诊断卡 L1
  短提示（可复听 span 强制、possibilities 语气、无 L1/组合不支持/无证据三级干净降级）；
  幂等 `l1_difficulty_hit` LearningEvent（(sentence, kind) 指纹，供 3.10 难点分布）；corpus
  family 标注投影（kind=connected_speech 可重建行 + word timeline 生命周期/转写管线/导入的
  reindex 触发点）；`/v1/learner/l1-specialty` 全库同类片段聚合 + corpus 缺席降级为当前
  track 内存聚合 + 诊断卡同类片段对话框（试听走 3.5.7 切片窗，当前 track 条目可进 3.5.6
  句听写练习）。
- 已完成的实现与自动化验证保留：cargo test --workspace、flutter analyze/test（278）、
  validate-contracts 全部通过；与 3.8 合流后的 v33/v34 迁移顺序已复核。
- **延期裁决（2026-07-12）**：不进行当前 exit-signal QA，且不创建 CLOSEOUT。当前 UX 将
  L1 解释置于“词汇状态/历史 observation → 基础诊断 → RhythmFrame 规则命中”的多重前置之后，
  不是从用户明确表达“这句没听懂”自然进入；规则时间段也可能来自 text prior / 估算 timing，
  不能在产品上表述为音频已确证的个人困难。
- **恢复条件**：先重新设计并实现用户触发的学习闭环——“本句没听懂 → 区分词义与听辨 →
  定位可回听片段 → 同类短练习”——并清楚呈现无结果原因和规则/音频证据边界；随后以真实媒体
  QA 重新裁决是否收口。
- **恢复裁决（2026-07-13）**：Owner 实测确认 L1 区域在语流标记准确时有显著学习价值；
  先恢复 audible-structure 上游重构。A=词典/书写词界，B=文本规则预测的可听分组，C=真实
  音素 + timing/prosody 支持的实际可听分组；类别退为解释标签。首条竖切片聚焦
  `pick up: /pɪk | ʌp/ → /pɪ.kʌp/`，纯 B 不填充 C。
- 计划：`.planning/phases/3.9-l1-aware-diagnosis-v1/3.9-PLAN.md`。

### Phase 3.9.2: Syntax Provider Qualification Correction and Product Activation ⏳ ACTIVE

- 不修改已冻结的 3.9.1 fixture/report；新建 v2 holdout，将争议句改为
  `ambiguous_policy_abstain`，加入清晰 want-to subject/object 最小对照。
- 首选 spaCy 作单一产品候选；consumer seam 已完成，主要工作是 corrected qualification、可选
  runtime/model lifecycle、composition single-call/shared-artifact 与真实媒体降级 QA。
- 工作量评估为小到中等；若必须捆绑 Python、大改 LLTimeline schema 或新增复杂安装 UI，则
  另立部署 phase，不在本阶段假装成简单接线。
- 文档：`.planning/phases/3.9.2-syntax-provider-product-activation/3.9.2-PLAN.md`、
  `3.9.2-CONTEXT.md`。

### 下一执行序列：Phase 3.11–3.18

- **Gate Q（已通过）**：Q1/Q2 通过；Q3/Q4 因后续 UX/功能调整明确延期且 QA 债留在
  原 phase。裁决见 `3.7-GATE-Q-CHECKLIST.md`。
- **3.7 / 3.8 / 3.10 已完成收口，3.9 并行恢复**：3.7 保持 listening-only；3.8 是
  shadowing 模仿层且非评分 completion 不伪造 speaking success；3.9 重构 A/B/C 后再做
  真实媒体 QA；3.10 只展示已有事实，但提供 channel-ready envelope。
- **3.11–3.18（已立 PLAN，方向承诺）**：Semantic evidence foundation → vendor-neutral
  LLM provider（两个异构协议先证中立）→ 3.12.1 judge 资格评估（可与 Reading 并行）→
  Reading Studio → Speaking Studio → Writing Studio → Personal Expression → four-channel
  projection/review → Cross-modal Coach closeout。各 PLAN 开工前须按上游现状修订。
  共享约束（含 seam 裁决标准 §3.6、judge 三级资格 §3.5）：
  `.planning/phases/3.0-english-listening-learning-loop/3.11-3.18-FOUR-CHANNEL-SHARED-CONTEXT.md`。

## 已完成 Phase 索引

| Phase | 结论 | 文档 |
|---|---|---|
| 2.0 Production Engine | LLTimeline JSON v1 / 生产管线基础建成 | `.planning/phases/2.0-production-engine/2.0-PLAN.md` |
| 2.1 Alignment Pipeline Hardening | 对齐管线阶段性加固 | `.planning/phases/2.1-alignment-pipeline-hardening/2.1-PLAN.md` |
| 2.2 App Timeline Resource UI | 字幕资源生命周期与 LLTimeline 消费闭环完成 | `.planning/phases/2.2-app-timeline-resource-ui/2.2-CLOSEOUT.md` |
| 2.3 Manual Timeline Review UI | 人工校对 UI 完成 | `.planning/phases/2.3-manual-timeline-review-ui/2.3-CLOSEOUT.md` |
| 2.3.5 Rust Module Decomposition | Rust 巨型单文件拆分关口完成 | `.planning/phases/2.3.5-rust-module-decomposition/2.3.5-CLOSEOUT.md` |
| 2.4 ChunkTimeline | ChunkTimeline 生成与消费完成 | `.planning/phases/2.4-chunktimeline-generation-consumption/2.4-CLOSEOUT.md` |
| 2.5 Sound Pattern / PhoneTimeline | PhoneTimeline 与 sound pattern 基础完成 | `.planning/phases/2.5-sound-pattern-phonetictimeline/2.5-CLOSEOUT.md` |
| 2.5.5 Language Learning Abstraction | 多语言学习抽象校验完成 | `.planning/phases/2.5.5-language-learning-abstraction-validation/2.5.5-CLOSEOUT.md` |
| 2.6 Multilingual Learning Foundation | en + zh 多语言学习基础完成 | `.planning/phases/2.6-multilingual-learning-foundation/2.6-CLOSEOUT.md` |
| 2.7 Pronunciation Provider Dispatch | 发音 provider dispatch 完成 | `.planning/phases/2.7-pronunciation-provider-dispatch/2.7-CLOSEOUT.md` |
| 2.8 Token Timing Alignment | token timing alignment 完成 | `.planning/phases/2.8-token-timing-alignment/2.8-CLOSEOUT.md` |
| 2.9 Production Multilingual Decoupling | 生产管线英语强绑定解除 | `.planning/phases/2.9-production-multilingual-decoupling/2.9-CLOSEOUT.md` |
| 2.10 English Real Speech Analysis | 英语真实语音分析 provider 集成完成 | `.planning/phases/2.10-english-real-speech-analysis/2.10-PLAN.md` |
| 2.12 UI State Management Refactoring | Store/Builder 与 controller 状态层完成 | `.planning/phases/2.12-ui-state-management-refactoring/2.12-CLOSEOUT.md` |
| 2.13 Phoneme Ribbon Interaction | 文字线音素 ribbon 收口完成 | `.planning/phases/2.13-phoneme-ribbon-interaction/2.13-CLOSEOUT.md` |
| 2.14 Sound-First Learning Architecture | 声音线学习架构完成 | `.planning/phases/2.14-sound-first-learning-architecture/2.14-CLOSEOUT.md` |
| 2.15 Sound Line Learning UX | 声音线学习 UX 完成 | `.planning/phases/2.15-sound-line-learning-ux/2.15-CLOSEOUT.md` |
| 2.16 Real Connected Speech Model v1 | 真实语流解释层完成 | `.planning/phases/2.16-real-connected-speech-model-v1/2.16-CLOSEOUT.md` |
| 2.17 Real Media Sound-Line QA | 真实媒体 sound-line QA pack 完成 | `.planning/phases/2.17-real-media-sound-line-qa/2.17-CLOSEOUT.md` |
| 2.18 Codebase Architecture Refactor | 代码架构全面重构完成 | `.planning/phases/2.18-codebase-architecture-refactor/2.18-CLOSEOUT.md` |
| 2.22 User-Facing Workflow Semantics | 用户可见工作流语义收口（真实媒体 smoke 已于 2026-07-03 通过） | `.planning/phases/2.22-user-facing-workflow-semantics/2.22-CLOSEOUT.md` |
| 2.23 Architecture Debt Paydown | 架构债集中偿还完成：main.dart 1457 行 / setState 10、sound_analysis 模块化、schema v17、契约测试安全网、ADR 0014 | `.planning/phases/2.23-architecture-debt-paydown/2.23-CLOSEOUT.md` |
| 3.0.1 Learning Loop Foundation | 学习闭环后端地基与首条 cloze/dictation 竖切片 | `.planning/phases/3.0.1-learning-loop-architecture-foundation/3.0.1-CLOSEOUT.md` |
| 3.1 Intensive Listening Practice | 三姿态入口、cloze/dictation UI、失败入复习、phrase/rhythm 诊断接缝 | `.planning/phases/3.1-intensive-listening-practice-slice/3.1-CLOSEOUT.md` |
| 3.2 Stuck Points & Session Summary | 卡点闭环切片完成；相关机制后由 3.5.6 撤除 | `.planning/phases/3.2-stuck-points-session-summary/3.2-CLOSEOUT.md` |
| 3.4.1 Learning Capability Model v2 | 四通道 tri-state capability + evidence/projection/override 分层成为权威 | `.planning/phases/3.4.1-learning-capability-model-v2/3.4.1-PLAN.md` |
| 3.4.2 Semantic/Prosodic Separation | SenseGroup 与 ChunkTimeline 按 ADR 0016 分离共存 | `.planning/phases/3.4.2-semantic-prosodic-group-separation/3.4.2-CLOSEOUT.md` |
| 3.4.3 Construction Modeling Spike | exemplar/construction/UserSentencePattern 身份验证；生产价值由 3.16 兑现 | `.planning/phases/3.4.3-construction-modeling-spike/3.4.3-CLOSEOUT.md` |
| 3.5.5 Intensive Listening UX Fix | 8 组走查修复；意群/chunk 只收表达不合并数据（groupingMode 四态） | `.planning/phases/3.5.5-intensive-listening-ux-fix/3.5.5-CLOSEOUT.md` |
| 3.5.6 Intensive Practice Window | 精听练习浮窗 + 3.2 过度设计机制撤除 + extensive-only completion | `.planning/phases/3.5.6-intensive-practice-window/3.5.6-CLOSEOUT.md` |
| 3.5.7 Slice Playback Window | 独立第二解码切片窗 + 跨媒体 resolver；A 组入口迁移 | `.planning/phases/3.5.7-slice-playback-window/3.5.7-CLOSEOUT.md` |
| 3.6 Listening Dictionary MVP | 词典页 + 逐例识别标记 + corpus 索引/FTS5/lemma 搜索 | `.planning/phases/3.6-listening-dictionary-mvp/3.6-CLOSEOUT.md` |
| 3.6.1 Sense Folders | 义项文件夹（用户文件夹为身份权威）；schema v30/v31 | `.planning/phases/3.6.1-sense-folders/3.6.1-CLOSEOUT.md` |
| 3.6.2 Dictionary Inline Clip UX | 词典详情内嵌切片卡 + PageView 横向轨道取代 overlay | `.planning/phases/3.6.2-dictionary-inline-clip-ux/3.6.2-CLOSEOUT.md` |
| 3.7 Hunting List | 用户确认猎词资产 + 泛听会话级预算提示 + 三态听力证据 + completion 小结 | `.planning/phases/3.7-hunting-list/3.7-CLOSEOUT.md` |
| 3.8 Shadowing & Recording Comparison | chunk 跟读 + 本地录音 + A/B/A + 客观波形/时长/停顿比较；非评分 completion | `.planning/phases/3.8-shadowing-recording-comparison/3.8-CLOSEOUT.md` |
| 3.9.1 Shared Syntactic Analysis Provider | 中立 token-aligned artifact + B/SenseGroup/matcher seam；Stanza/spaCy 负资格，产品保持 fallback | `.planning/phases/3.9.1-shared-syntactic-analysis-provider/3.9.1-CLOSEOUT.md` |
| 3.10 Coach Dashboard | 诊断型 dashboard 聚合 durable 事实 + 规则建议 + channel-ready envelope + starter 降级 | `.planning/phases/3.10-coach-dashboard/3.10-CLOSEOUT.md` |
| 3.11 Semantic Task Evidence Foundation | 四层事实分离（attempt/judgment/observation/capability）+ 版本化 rubric + 逐点判定含 abstain + adjudication；schema v35 append-only；ADR 0021；零 observation/projection writer | `.planning/phases/3.11-semantic-task-evidence-foundation/3.11-CLOSEOUT.md` |
| 3.12 Vendor-neutral LLM Provider | 两异构协议 adapter（OpenAI Chat + Anthropic Messages）过同一契约套件证中立；draft-not-domain-type + 四层分离经 LLM 路径成立；OS keychain + auth_ref 密钥不落普通存储；诚实降级；Flutter 设置 UI；schema v36；ADR 0022；判定默认不获显示资格（属 3.12.1）。CODE COMPLETE，owner 真实 provider 端到端 QA 待做 | `.planning/phases/3.12-vendor-neutral-llm-provider/3.12-CLOSEOUT.md` |

## 最近重要决策

1. **2026-07-11** — 3.7–3.10 计划先按落地现状修订为 v2，再对齐四通道最终讨论修订为
   v3，并新建 3.11–3.18 全量落地计划。v2 共性修订：状态语言全部换四通道 capability
   口径、证据链路对齐
   ADR 0017/0019、播放对齐 3.5.7 双实例架构、文案走 localization。关键个性修订：
   3.7 目标定位优先复用 corpus 投影（lemma 归一）、"没注意"不写观察证据、狩猎小结挂
   extensive-only completion；3.8 入口宿主为 3.5.6 练习浮窗第四题型、shadowing 单位
   锁定韵律层 chunk、attempt 不进 content-fit 折算；3.9 corpus family 检索明确为新增
   可重建投影工程量、LearnerProfile 收窄为补 L1；3.10 删除悬案区回访与卡点解决率
   （3.5.6 已撤机制）、精听不虚构 session 时长、数据来源对齐 v19–v31 schema。
   v3 裁决：3.7 不提前泛化、3.8 非评分 shadowing 不伪造 speaking success、3.9 不提前接
   LLM/两层复述、3.10 建 channel-ready envelope；3.7 前新增 Gate Q 清偿 3.3/3.35/3.4
   真实 QA 债。后续顺序为 semantic evidence → vendor-neutral LLM → Reading → Speaking →
   Writing → Personal Expression → projection/review → Cross-modal Coach。同日 3.6.1 审计
   修复落地 schema v31（义项边 BEFORE UPDATE 触发器）与导入脏边显式跳过谓词。
   **同日评审修订（12:55）**：3.12 判定为超载 phase，judge 资格评估（fixture + 人工
   gold + 留出集 + 三级资格裁决）独立为 Phase 3.12.1，3.12 首批收窄为两个异构协议
   adapter（OpenAI-compatible + Anthropic Messages）先证中立、其余协议增量；judge
   三级资格口径统一（未校验不进 surface / 仅可显示 / supporting evidence）；seam 预留
   裁决标准写入共享上下文 §3.6（additive 响应形状可预留，固化资产身份的泛化必须等
   真实 consumer）；3.11–3.18 PLAN 定性为方向承诺，开工前必须按上游现状修订。
2. **2026-07-10** — 个人听力词典与切片播放器评审裁决（见
   `.planning/discuss/personal-listening-dictionary-and-slice-player.zh.md` §9）：词典组织
   确立为"学习对象 →（可选义项）→ 切片"的**视图层级**；高频读端（字幕高亮/词汇本过滤）
   只读词条级画像，义项不进热路径；义项 = 用户文件夹为身份权威，词典 API 义项仅为建议/
   对齐注释；`LexicalEntry` 不改名，construction 不并入（ADR 0020 不动）；B 组 loopRange
   不迁移；图谱视图推迟（纯读端推导、不落库）。落地：新增 Phase 3.5.7 切片回听播放器
   （独立第二解码实例，Slice 0 spike 把门）；3.6 修订为 v2（第一刀零新后端资产词典页，
   corpus index/搜索降为第二刀）；sense spike 从"3.6 前"改排到义项切片（3.6.x）前。
3. **2026-07-10** — Phase 3.5.5 收口 + 精听练习小窗切出：意群/chunk 定为**只收表达不合并数据**
   （伞概念"分组"，`groupingMode` 四态 off/prosodic/semantic/compare;compare = 语流胶囊为底 +
   语义∖语流边界处打差异标记 = 听力 hotspot），ADR 0016 双层分离不动;semantic 因算法仍是
   规则回退而刻意标 provisional;全新安装默认 `off`。精听浮动练习小窗（含 P0，且需反转 3.2 落地的
   卡点/悬案区/session summary 等"过度设计"机制）工作量与风险高于其余接线级修复，切出为 Phase 3.5.6
   独立做。内容匹配度/意群的**命名重设计**、词汇本"学习对象统一抽象"、旧状态 ChoiceChips 移除均留待独立处理。
4. **2026-07-07** — 模型精化评审裁决（见 `.planning/discuss/learning-domain-model-v2-refinement-review.zh.md`
   与共享上下文 §14）：确立复杂度分层原则与字段裁决标准；`CapabilityProjection` 预留
   confidence / evidence_as_of_ms seam；证据通道化 + surface_form + 投影写入者互斥为 3.5 前置
   slice；SenseGroup 用户修正定为 overlay 模式；sense 身份 spike 排在 3.6 前；明确砍掉混淆
   词对、时钟仲裁、override 衰老机制；修复导入路径 projection 来源标注。
5. **2026-07-06** — Learning Domain Model v2：暂停 3.4/3.35 最终 QA，插入 3.4.1~3.4.3；
   `LearningStatus` 不再作为长期权威模型，改为四通道 assessment + evidence/projection/override；
   SenseGroup 与现有音频/韵律 ChunkTimeline 并存。ADR 0015 取代 ADR 0012 的单状态决定。
6. **2026-07-05** — Phase 3.35 收尾复审：走查发现部分 P0 项只有 UI 壳、数据通路是断的
   （首页继续学习、readiness），本轮补齐数据通路而非仅视觉；最近媒体经 settings 持久化，
   词汇总量客户端聚合现有 list 查询，不新增后端端点；文稿跟随以 drag/wheel 判定用户滚动、
   程序化滚动不触发暂停。
7. **2026-07-05** — Phase 3.35 截图反馈第二轮：右侧文稿随播放当前句同步改为基于真实
   列表行位置，移除固定行高估算，适配长字幕可变行高。
8. **2026-07-05** — Phase 3.35 截图反馈第一轮：字幕资源页和右侧资源 tab 的上下资源区
   改为可拖动分栏，timeline 详情独立滚动，修复矮窗口下区域挤压和底部 overflow。
9. **2026-07-04** — Phase 3.35 首轮 UI 实施：来源中立首页、可拖动媒体/字幕工作台、
   紧凑播放控制与统一 `ListenTheme` 已落地；主题采用冷杉绿 + 雾灰 + 暖金，旧学习面板
   已迁移，等待 owner 截图反馈继续收口。
10. **2026-07-04** — 插入 Phase 3.35：在 3.3 与 3.4 之间先重构统一听力工作台 UI；
   参考每日英语听力成熟的内容层级与播放学习组织，但保留 listen 的诊断/证据模型且不复制品牌。
   同时明确 local-first 不等于 local-only，未来 YouTube 等在线来源进入统一内容入口。
11. **2026-07-04** — Phase 3.2 收口：精听卡点闭环落地，包含标记卡点 / 跳过、
   diagnosis viewed evidence、session summary、悬案区 v0、精听完毕确认与
   `familiar_material_marked` 熟料事件；卡点状态保持读侧派生，不新增权威状态机表。
12. **2026-07-04** — Phase 3.1 收口：Test posture 首个精听练习竖切片落地，包含
   cloze / chunk dictation / sentence dictation、失败项 review、phrase-aware diagnosis
   和 rhythm hotspot evidence loop；练习失败继续作为 evidence，不静默修改全局 `LearningStatus`。
13. **2026-07-04** — Phase 3.x 产品形态确立：精听/泛听一级心智，复习/词典/dashboard
   为资产消费层；功能按场景分不按设备分（生产端唯一 PC-only）；可组合不强制流程
   （每个功能可独立使用）；泛听默认零打扰。执行序列落为 Phase 3.1 ~ 3.10；双维难度
   （Meaning/Sound fit）直接实现，换取条件是分数可解释 + heuristic_proxy 标注。
14. **2026-07-03** — ADR 0014：Dart 模型解析保持手写，fixture 契约测试为防漂移标准；
   存量 `timeline.dart` 不做 codegen 迁移，3.x 新 DTO 手写 + 契约测试，体量大再试点。
15. **2026-07-02** — speech-analysis 算法线（2.19/2.20/2.21）搁置，主线转入 Phase 3.x
   英语听力学习闭环；audible-structure v1 contract 保持当前权威 shape。
16. **2026-07-02** — Phase 2.23 只做机械治理，不改产品行为；`main.dart` 收缩是 3.x
   Flutter practice UI 的前置。
17. **2026-07-01** — consumer self-contained invariant：bundled whisper.cpp 产出的
   WordTimeline 必须解锁基础功能，sidecar 只升级质量。
18. **2026-07-01** — 字幕层声音模式统一为 Rhythm A/B/C；phones 是 C 内 L4 evidence，不再是一级模式。
19. **2026-06-30** — 算法/指标/阈值变更必须记录 evidence class，不能把小样本 smoke 或自动标签当真理。
20. **2026-06-27** — 稳定教学标签优先：CTC 是 audio evidence，不是默认 teaching label truth。

## 当前阻塞项

- Phase 3.4 / 3.35 手工 QA 主动暂停，不是外部阻塞。
- （已解除）3.5 的前置 3.4.1 权威模型切换与 3.4.4 证据层均已完成，3.5 已于
  2026-07-07 立项启动。

## 下一步工作

1. **Phase 3.9（当前测试与修正线）**：A/B/C audible-structure 已覆盖 linking、weak form、
   contraction、assimilation、deletion、flapping；在主工作区运行真实媒体 QA，修正触发准确度、
   多现象 UI 冲突与 C observed-phone 分组后再裁决收口。
2. **Phase 3.13 / 3.12.1（下一主线）**：3.12 已 CODE COMPLETE；Reading Studio 与 LLM Judge
   Qualification 按各自 PLAN 开工。3.12 增量协议 Slice 4 仍按 owner 真实需求排期。
3. "收藏句 → 个人模板"的用户价值验证收敛到 Phase 3.16（3.4.3 结论待兑现）。
4. 3.x 工作方式约定：learning_loop 纸面抽象按切片验证、允许改形状（C-6）；
   新增 Dart DTO 沿用手写 + fixture 契约测试（ADR 0014）。
5. 长期挂账：C-3 重归一化策略、C-4 冗余投影字段删除（随 3.x API 演进合并做）；
   legacy `LearningStatus` 物理删除推迟到所有 active consumer 迁移后的独立 cleanup phase；
   诊断 profile 批量读取接口、资产导入补写 capability history（见精化评审 §5）；
   四技能扩展稿 §10 研究引用在被 PLAN 引用前逐条核实（评审发现 Yanguas 引用可疑）。

## 指标

- STATE.md 维护目标：≤ 400 行。
- 当前生产管线吞吐：新闻视频约 1-2 条/天（手工触发）。
- 已完成里程碑：M1.0, M1.5, M1.6, M1.7, M1.8, M1.9。
