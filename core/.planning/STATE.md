---
gsd_state_version: 1.0
milestone: v0.7.0
milestone_name: local production engine and lightweight consumer app
status: active
last_updated: "2026-07-10T20:22:00.000+08:00"
---

# LLPlayerNext — 项目活记忆

> 最后更新：2026-07-10 20:22 CST
> 更新原因：Phase 3.6 收口批次二完成：跨媒体采样搜索、语速排序、每切片复习出口
> （sentence anchor）、override/释义笔记/升级建议编辑回补、YouGlish + 词典发音外链兜底。
> 自动化全部完成，仅剩真实媒体手工 QA 与 CLOSEOUT。

## 当前位置

- **当前产品主线**：Phase 3.x 英语听力学习闭环（英语先行）。
- **治理线状态**：Phase 2.23 Architecture Debt Paydown 已于 2026-07-03 收口（详见其 CLOSEOUT）；3.x 开工前置全部就绪。
- **算法线状态**：Phase 2.19 / 2.20 / 2.21 已于 2026-07-02 搁置；audible-structure v1
  contract 保持当前权威 shape，后续质量提升等学习闭环完成后再回到算法线。
- **当前版本**：0.7.0。
- **当前产品定位补充**：本地优先不等于仅限本地；未来 YouTube 等在线来源将与本地内容
  进入统一学习工作台，学习资产与高频播放路径仍默认本地。
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
- 执行序列：Phase 3.1 ~ 3.10 已全部立 PLAN（2026-07-04），分解与依赖见
  `.planning/phases/3.0-english-listening-learning-loop/3.0-PHASE-BREAKDOWN.md`；
  产品输入见 `.planning/discuss/listen-learning-activity-path.zh.md`。

### Phase 3.0.1: Learning Loop Architecture Foundation ✅ 后端地基完成

- 已完成：domain model、application repository traits/service、SQLite schema v15、practice/review API、
  OpenAPI/generated client、contract validation。
- 第一条 backend vertical slice：当前 chunk → cloze/chunk dictation → PracticeAttempt →
  LexicalObservation / ReviewItem / LearningEvent。
- Guardrails：练习失败不静默修改全局 `LearningStatus`；Anki 是 adapter，不是内部权威复习模型；
  dashboard 从 durable attempt / learning event 聚合；L1-aware diagnosis 走 profile/provider。
- 后续 slice：Flutter practice controller/UI、corpus search、difficulty profile、learner profile persistence、
  recording/shadowing 和 dashboard aggregation。
- 收口文档：`.planning/phases/3.0.1-learning-loop-architecture-foundation/3.0.1-CLOSEOUT.md`

### Phase 3.1: Intensive Listening Practice Slice ✅ 精听练习竖切片完成

- 已完成：三姿态入口（Understand/Test/Shadowing planned）、cloze / chunk dictation /
  sentence dictation practice UI、PracticeController、typed Dart DTO + LocalApi wrapper、
  PracticeAttempt diff、失败项一键 ReviewItem、capability gating。
- 诊断升级：C-1 phrase lexical entries 参与 meaning / recognition barrier；C-2 rhythm
  hotspots 可从诊断卡点击复听 evidence range。
- 验证：`flutter analyze`、`flutter test`（168 passed）、`cargo test -p diagnosis-core`、
  `cargo test -p application`、`cargo test -p api-http`、`validate-contracts`、`git diff --check`。
- 收口文档：`.planning/phases/3.1-intensive-listening-practice-slice/3.1-CLOSEOUT.md`

### Phase 3.2: Stuck Points & Session Summary ✅ 卡点闭环切片完成

- 已完成：显式标记卡点 / 跳过、诊断查看事件、读侧 session summary 聚合、悬案区 v0
  回听与手动关闭、精听完毕确认、熟料标记持久化。
- 架构决策：卡点状态继续由 `LearningEvent` + `PracticeAttempt` + `ReviewItem` 派生；
  未升格为独立 domain 状态机实体。手动 review 关联以 `ReviewItem.source.practice_attempt_id`
  为准，不反向改写 attempt JSON。
- 验证：`cargo test -p application -p persistence-sqlite -p api-http`、`cargo clippy -p application
  -p persistence-sqlite -p api-http --all-targets`、`flutter analyze`、`flutter test`（170 passed）、
  `validate-contracts`、`git diff --check`。真实媒体 GUI 手工 QA 仍需 owner 最终确认。
- 收口文档：`.planning/phases/3.2-stuck-points-session-summary/3.2-CLOSEOUT.md`

### Phase 3.3: Extensive Listening & Inbox ⏳ MVP 已落地，待收口

- 已落地：泛听 session、软/硬打断、理解度自报、Listening Inbox 捕获与整理流。
- 待完成：系统级全局热键决策、独立收藏浏览容器决策、真实媒体 30 分钟手工 QA。
- 计划与 QA：`.planning/phases/3.3-extensive-listening-inbox/3.3-PLAN.md`、
  `.planning/phases/3.3-extensive-listening-inbox/3.3-MANUAL-QA.md`。

### Phase 3.35: Listening Workbench UI Redesign ⏸ PAUSED

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
- 待完成：按 `3.35-MANUAL-QA.md` 执行 owner 截图反馈、三种目标窗口尺寸和真实媒体 QA；
  `3.35-CLOSEOUT.md` 当前为 `PAUSED — AWAITING_OWNER_QA`。待 3.4.1 新能力 UI 落地后
  重新建立受影响 surface 的验收基线。
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
- 待完成：真实媒体 ≥8 卡 QA 与阶段收口。旧升级建议目标将在 3.4.1 迁移为 listening
  capability proposal，迁移稳定后再恢复 QA。
- 规划文档：`.planning/phases/3.4-audio-first-review-queue/3.4-PLAN.md`。

### Phase 3.4.1: Learning Capability Model v2 ✅ COMPLETED

- 目标：以 reading / listening / speaking / writing 四通道画像替代单值线性状态；每个通道
  区分 unassessed / not_acquired / acquired。
- 架构：evidence、system projection、user override 和 effective assessment 分层；自动证据
  不静默覆盖用户声明。capability profile 为唯一权威，legacy `LearningStatus` 降级为兼容投影。
- 迁移：schema v22 additive migration，保留 legacy status 兼容窗口；v21 数据按带来源的
  近似映射回填，迁移前备份/重复打开/失败恢复测试通过。
- Slice 0-6 全部完成：domain contract、schema v22 persistence、application use case、
  VocabularyAssetBundle v6、diagnosis/upgrade suggestion 迁移、OpenAPI/SSE/Dart 契约、
  Flutter 四通道 UI、authority switch（诊断和升级建议单一 profile 路径，external import
  补齐 capability sync，legacy 字段标记 deprecated）。
- 验证：`cargo test --workspace` 395 passed、`flutter test` 204 passed。
- 后续：3.4.2 新增 SenseGroup 语义层；3.4.3 验证 Construction 身份。
- 收口文档：`.planning/phases/3.4.1-learning-capability-model-v2/3.4.1-PLAN.md`。

### Phase 3.4.2: Semantic / Prosodic Group Separation ✅ COMPLETED

- 目标：新增 SenseGroup（意群）语义加工层，保留 ChunkTimeline 韵律层独立共存。
- 架构：SenseGroup 是 token-span 句子级文本标注，不是全局学习资产。播放范围通过
  WordTimeline 投影。两层独立管理，对齐关系推迟。ADR 0016 已定稿。
- 已完成：Slice 0-6 全部完成。domain contract、规则回退 partition provider（14 测试）、
  schema v25 持久化（lifecycle + round-trip 测试）、application 7 use cases + 7 API routes +
  LLTimeline 导出导入 + OpenAPI 5 paths、Flutter 3 模型 + 6 API + controller 缓存 +
  showSenseGrouping 设置（默认 off）+ 7 契约测试。Alignment 推迟、ChunkTimeline 改名推迟。
- 验证：`cargo test --workspace` 413 passed、`flutter test` 233 passed、`flutter analyze` 零问题。
- 收口文档：`.planning/phases/3.4.2-semantic-prosodic-group-separation/3.4.2-CLOSEOUT.md`。

### Phase 3.4.3: Construction Modeling Spike ✅ COMPLETED

- 已完成：en/zh/ja manual gold fixture、纯 domain contract/validator 与 focused tests；验证
  `SentenceExemplar`、人工 canonical `Construction`、可重建 `ConstructionOccurrence`、
  用户 `UserSentencePattern` 的身份边界。
- 关键结论：个人模板可从任意 sentence exemplar 提炼并保留来源快照，即使没有系统 occurrence；
  system construction link 可选且不能覆盖用户模板。recognition/production 画像保持简洁，
  evidence 必须记录 reading/listening/speaking/writing modality。
- 生产决定：不在本 spike 建 SQLite/API/UI/LLTimeline schema。后续先验证“收藏句 → 个人模板”的
  用户价值，再决定是否持久化用户资产；canonical construction library 与自动 occurrence provider
  另行决策。
- 收口文档：`.planning/phases/3.4.3-construction-modeling-spike/3.4.3-CLOSEOUT.md`。

### Phase 3.5.5: Intensive Listening UX Fix ✅ COMPLETED

- 交付（9 组走查问题中的 8 组）：播放界面回退首页、循环标注 bug 修复、内容匹配度入口（完整
  卡片上转写 tab）、词汇来源原句 + fire-and-forget 竞态修复、听懂了吗（文案统一 + C 视图按需
  加载 + 移除技术分析按钮）、底部溢出菜单阈值 900、词汇本升级 A+B（后端 `CapabilityFilter`
  json_extract 过滤 + 纳入 Phrase + 四通道摘要 + 能力过滤为主）、意群/chunk 表达统一
  （`groupingMode` 四态，off/prosodic/semantic/compare）。
- 架构守则：意群/chunk **只收表达不合并数据**，ADR 0016 双层分离原封不动;全新安装
  `groupingMode` 默认改为 `off`（老配置迁移为 `prosodic`）。
- 切出：**精听浮动练习小窗**（含 P0，practice UX 重设计 + 移除过度设计机制）→ Phase 3.5.6。
- 验证：`flutter analyze` 零问题、`flutter test` 247 passed、`cargo test -p persistence-sqlite`
  74+5+6 / `-p api-http` 35+11、`validate-contracts.sh` 通过。
- 收口文档：`.planning/phases/3.5.5-intensive-listening-ux-fix/3.5.5-CLOSEOUT.md`。

### Phase 3.5.6: Intensive Practice Floating Window ✅ 已收口

- 可拖动精听练习浮窗、3.2 过度设计机制与历史读侧聚合清理、extensive-only completion 均已完成；
  真实媒体手工 QA 由 owner 豁免。收口：`.planning/phases/3.5.6-intensive-practice-window/3.5.6-CLOSEOUT.md`；
  冻结计划：`.planning/phases/3.5.6-intensive-practice-window/3.5.6-PLAN.md`。

### Phase 3.5.7: Slice Playback Window ✅ 已收口

- 已交付独立第二解码实例、音频优先/可展开视频的可拖动切片窗、跨媒体 resolver 与所有 A 组
  来源句入口迁移；打开暂停主播放器但保持其媒体/位置，精听重播会暂停切片；旧
  `playOccurrence` 劫持路径已删除，B 组 `loopRange` 未动。
- Slice 0 真实 macOS 双实例 spike 通过；`flutter analyze`、`flutter test`（252 passed）与
  `git diff --check` 通过，零后端/契约改动。owner 确认以该证据收口；多切片浏览 UI 留给 3.6。
- 收口：`.planning/phases/3.5.7-slice-playback-window/3.5.7-CLOSEOUT.md`；计划已冻结。

### Phase 3.6: Listening Dictionary MVP ⏳ ACTIVE（自动化全部完成，仅剩真实媒体 QA 与收口）

- Slice 1（资产词典页）：词汇本演进为词典页（master-detail 页内详情，不再是弹窗），
  学习对象 → 切片列表 + 四通道摘要 + 覆盖度诚实展示；词典页自持第二解码切片窗，
  播放例句不离开词典、不触碰主播放器（进入词典路由时经回调暂停主播放器）。
- Slice 2（逐例识别标记）：每切片"听出了/没听出"经 `create_lexical_observation` 走
  ADR 0017 单写入口与 ADR 0019 listening 重投影；无 sentence 关联的旧切片明确禁用。
- Slice 3（corpus 索引与搜索）：schema v28 `corpus_occurrences` 可重建投影（词 token/
  句子/active chunk timeline 的 chunk 三类），导入、改语言、chunk timeline
  activate/archive/delete 均触发重建；`GET /v1/corpus/search` + `POST /v1/corpus/reindex`
  （存量库回填入口，词典页工具栏按钮）；词条详情"在我的媒体库中搜索"支持试听（经切片窗）
  与一键收为该词条来源切片（复用 upsert source 口径）；词汇本零结果时词典退化为纯查询
  工具（corpus 搜索 + 试听）。"加入复习"动作出口已回补到词典详情。
- 接缝回归修复：3.5.6 extensive-only completion 使精听 session 永不完成，3.5 的练习准确率
  校准（content-fit-v2）失去触发点——已改为 attempt 提交时增量折算，completion 只折算
  理解度自报（`record_practice_accuracy_feedback`）。
- 收口批次二（2026-07-10 晚）：corpus 搜索按 media 轮转采样（大词条截断页跨来源多样化 +
  "已跨媒体采样"提示）；切片 wpm 估算与"默认顺序/按语速"排序（UI 状态按 occurrence 身份
  键控）；每切片"加入复习"出口（sentence anchor 时间窗，复习队列按 3.4 卡型派生；范围
  裁决：不内嵌 3.1 practice 会话 UI，词典动作出口收敛到复习队列）；回补四通道 override
  就地编辑、释义/笔记编辑、升级建议确认/拒绝 banner；外链兜底（YouGlish + 词典发音，
  明示仅供参考）。
- 验证：`cargo test -p application -p persistence-sqlite -p api-http` 全绿、
  `validate-contracts.sh` 通过、`flutter analyze` 零问题、`flutter test` 265 passed。
- 待完成：真实媒体手工 QA 与 CLOSEOUT。已知债挂账：phrase LIKE 全扫（FTS5 备选）、
  自由文本 lemma 归一（词条驱动查询不受影响）。
- 规划文档：`.planning/phases/3.6-listening-dictionary-mvp/3.6-PLAN.md`（v2，含 Progress）。

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

## 最近重要决策

1. **2026-07-10** — 个人听力词典与切片播放器评审裁决（见
   `.planning/discuss/personal-listening-dictionary-and-slice-player.zh.md` §9）：词典组织
   确立为"学习对象 →（可选义项）→ 切片"的**视图层级**；高频读端（字幕高亮/词汇本过滤）
   只读词条级画像，义项不进热路径；义项 = 用户文件夹为身份权威，词典 API 义项仅为建议/
   对齐注释；`LexicalEntry` 不改名，construction 不并入（ADR 0020 不动）；B 组 loopRange
   不迁移；图谱视图推迟（纯读端推导、不落库）。落地：新增 Phase 3.5.7 切片回听播放器
   （独立第二解码实例，Slice 0 spike 把门）；3.6 修订为 v2（第一刀零新后端资产词典页，
   corpus index/搜索降为第二刀）；sense spike 从"3.6 前"改排到义项切片（3.6.x）前。
2. **2026-07-10** — Phase 3.5.5 收口 + 精听练习小窗切出：意群/chunk 定为**只收表达不合并数据**
   （伞概念"分组"，`groupingMode` 四态 off/prosodic/semantic/compare;compare = 语流胶囊为底 +
   语义∖语流边界处打差异标记 = 听力 hotspot），ADR 0016 双层分离不动;semantic 因算法仍是
   规则回退而刻意标 provisional;全新安装默认 `off`。精听浮动练习小窗（含 P0，且需反转 3.2 落地的
   卡点/悬案区/session summary 等"过度设计"机制）工作量与风险高于其余接线级修复，切出为 Phase 3.5.6
   独立做。内容匹配度/意群的**命名重设计**、词汇本"学习对象统一抽象"、旧状态 ChoiceChips 移除均留待独立处理。
3. **2026-07-07** — 模型精化评审裁决（见 `.planning/discuss/learning-domain-model-v2-refinement-review.zh.md`
   与共享上下文 §14）：确立复杂度分层原则与字段裁决标准；`CapabilityProjection` 预留
   confidence / evidence_as_of_ms seam；证据通道化 + surface_form + 投影写入者互斥为 3.5 前置
   slice；SenseGroup 用户修正定为 overlay 模式；sense 身份 spike 排在 3.6 前；明确砍掉混淆
   词对、时钟仲裁、override 衰老机制；修复导入路径 projection 来源标注。
4. **2026-07-06** — Learning Domain Model v2：暂停 3.4/3.35 最终 QA，插入 3.4.1~3.4.3；
   `LearningStatus` 不再作为长期权威模型，改为四通道 assessment + evidence/projection/override；
   SenseGroup 与现有音频/韵律 ChunkTimeline 并存。ADR 0015 取代 ADR 0012 的单状态决定。
5. **2026-07-05** — Phase 3.35 收尾复审：走查发现部分 P0 项只有 UI 壳、数据通路是断的
   （首页继续学习、readiness），本轮补齐数据通路而非仅视觉；最近媒体经 settings 持久化，
   词汇总量客户端聚合现有 list 查询，不新增后端端点；文稿跟随以 drag/wheel 判定用户滚动、
   程序化滚动不触发暂停。
6. **2026-07-05** — Phase 3.35 截图反馈第二轮：右侧文稿随播放当前句同步改为基于真实
   列表行位置，移除固定行高估算，适配长字幕可变行高。
7. **2026-07-05** — Phase 3.35 截图反馈第一轮：字幕资源页和右侧资源 tab 的上下资源区
   改为可拖动分栏，timeline 详情独立滚动，修复矮窗口下区域挤压和底部 overflow。
8. **2026-07-04** — Phase 3.35 首轮 UI 实施：来源中立首页、可拖动媒体/字幕工作台、
   紧凑播放控制与统一 `ListenTheme` 已落地；主题采用冷杉绿 + 雾灰 + 暖金，旧学习面板
   已迁移，等待 owner 截图反馈继续收口。
9. **2026-07-04** — 插入 Phase 3.35：在 3.3 与 3.4 之间先重构统一听力工作台 UI；
   参考每日英语听力成熟的内容层级与播放学习组织，但保留 listen 的诊断/证据模型且不复制品牌。
   同时明确 local-first 不等于 local-only，未来 YouTube 等在线来源进入统一内容入口。
10. **2026-07-04** — Phase 3.2 收口：精听卡点闭环落地，包含标记卡点 / 跳过、
   diagnosis viewed evidence、session summary、悬案区 v0、精听完毕确认与
   `familiar_material_marked` 熟料事件；卡点状态保持读侧派生，不新增权威状态机表。
11. **2026-07-04** — Phase 3.1 收口：Test posture 首个精听练习竖切片落地，包含
   cloze / chunk dictation / sentence dictation、失败项 review、phrase-aware diagnosis
   和 rhythm hotspot evidence loop；练习失败继续作为 evidence，不静默修改全局 `LearningStatus`。
12. **2026-07-04** — Phase 3.x 产品形态确立：精听/泛听一级心智，复习/词典/dashboard
   为资产消费层；功能按场景分不按设备分（生产端唯一 PC-only）；可组合不强制流程
   （每个功能可独立使用）；泛听默认零打扰。执行序列落为 Phase 3.1 ~ 3.10；双维难度
   （Meaning/Sound fit）直接实现，换取条件是分数可解释 + heuristic_proxy 标注。
13. **2026-07-03** — ADR 0014：Dart 模型解析保持手写，fixture 契约测试为防漂移标准；
   存量 `timeline.dart` 不做 codegen 迁移，3.x 新 DTO 手写 + 契约测试，体量大再试点。
14. **2026-07-02** — speech-analysis 算法线（2.19/2.20/2.21）搁置，主线转入 Phase 3.x
   英语听力学习闭环；audible-structure v1 contract 保持当前权威 shape。
15. **2026-07-02** — Phase 2.23 只做机械治理，不改产品行为；`main.dart` 收缩是 3.x
   Flutter practice UI 的前置。
16. **2026-07-01** — consumer self-contained invariant：bundled whisper.cpp 产出的
   WordTimeline 必须解锁基础功能，sidecar 只升级质量。
17. **2026-07-01** — 字幕层声音模式统一为 Rhythm A/B/C；phones 是 C 内 L4 evidence，不再是一级模式。
18. **2026-06-30** — 算法/指标/阈值变更必须记录 evidence class，不能把小样本 smoke 或自动标签当真理。
19. **2026-06-27** — 稳定教学标签优先：CTC 是 audio evidence，不是默认 teaching label truth。

## 当前阻塞项

- Phase 3.4 / 3.35 手工 QA 主动暂停，不是外部阻塞。
- （已解除）3.5 的前置 3.4.1 权威模型切换与 3.4.4 证据层均已完成，3.5 已于
  2026-07-07 立项启动。

## 下一步工作

1. 3.6 仅剩真实媒体手工 QA（owner）与 CLOSEOUT；已知债挂账 FTS5 与 lemma 归一。
   义项 spike 排在义项切片（3.6.x）前，图谱视图推迟。
2. Phase 3.4.3 已完成（纯领域建模 spike，不建设生产 schema）；下一步在独立产品 slice 验证
   “收藏句 → 个人模板”的用户价值，再决定 SentenceExemplar/UserSentencePattern 持久化范围。
3. Phase 3.5 已立项启动（Slice 1-8 完成，Slice 9 真实素材 QA 待完成）。
4. 恢复 Phase 3.4/3.35 手工 QA，重新基线化新能力 UI。
5. 完成 Phase 3.3 真实媒体 30 分钟泛听 QA 并收口。
6. 3.x 工作方式约定：learning_loop 纸面抽象按切片验证、允许改形状（C-6）；
   新增 Dart DTO 沿用手写 + fixture 契约测试（ADR 0014）。
7. 长期挂账：C-3 重归一化策略、C-4 冗余投影字段删除（随 3.x API 演进合并做）；
   legacy `LearningStatus` 物理删除推迟到所有 active consumer 迁移后的独立 cleanup phase；
   诊断 profile 批量读取接口、资产导入补写 capability history（见精化评审 §5）。

## 指标

- STATE.md 维护目标：≤ 400 行。
- 当前生产管线吞吐：新闻视频约 1-2 条/天（手工触发）。
- 已完成里程碑：M1.0, M1.5, M1.6, M1.7, M1.8, M1.9。
