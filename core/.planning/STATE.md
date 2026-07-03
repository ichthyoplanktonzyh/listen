---
gsd_state_version: 1.0
milestone: v0.7.0
milestone_name: local production engine and lightweight consumer app
status: active
last_updated: "2026-07-02T22:59:00.000+08:00"
---

# LLPlayerNext — 项目活记忆

> 最后更新：2026-07-02 22:59 CST
> 更新原因：Phase 2.23 T2 文档事实源修复。STATE.md 从历史流水账压缩为当前状态机；
> 已完成 phase 只保留索引，分支等瞬时事实改由 git 命令读取。

## 当前位置

- **当前产品主线**：Phase 3.x 英语听力学习闭环（英语先行）。
- **当前治理线**：Phase 2.23 Architecture Debt Paydown，进入 3.x 前清理架构债。
- **算法线状态**：Phase 2.19 / 2.20 / 2.21 已于 2026-07-02 搁置；audible-structure v1
  contract 保持当前权威 shape，后续质量提升等学习闭环完成后再回到算法线。
- **当前版本**：0.7.0。
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

### Phase 2.23: Architecture Debt Paydown 🧭 当前治理线

- 目标：在不改产品行为 / API contract / 算法语义的前提下，偿还 2026-07-02 架构审核确认的债务：
  `main.dart` god file、`sound_analysis.rs` 单文件膨胀、文档事实源漂移、Dart 手写解析无契约守卫、
  巨型测试文件。
- 已修：A-1..A-7 高优先级审核缺陷；T1/B-1 删除 unused SQLite `learning_resources` 表并升
  schema v17；T8/B-3 双家退役条件入档；T9/B-5 active partial index JSON 引号耦合入档。
- Handoff tasks T1-T7 已由交接执行人完成（T2 文档事实源修复、T3 基线、
  T4 sound_analysis 模块拆分、T5 巨型测试拆分、T6 零散 payload typed 化、
  T7 Dart LLTimeline 解析测试 + codegen 调研）；T8/T9 前批已入档。
- **Step 3 ✅ 完成（2026-07-03）**：main.dart 3601 → 1457 行（gate ≤1500）、
  setState 107 → 10（gate ≤30）。新增 ResourceActions/MediaSession/
  PlaybackActions 三个 context-free coordinator、PlayerStage/SidePanel/
  PlaybackBar layout widget、settings/媒体导入/OpenSubtitles/manual review
  flow 函数；status 单源化到 `PlayerController.status`；controller + Store
  定调为唯一 UI 状态模式（详见 `2.23-PLAN.md` Step 3 回填）。
  `flutter test` 162 passed。待办：用户按 `2.22-FRONTEND-E2E-QA.md` P0 路径
  跑真实媒体手工 smoke。
- 剩余：Step 6 closeout（待手工 smoke 回填后收口）。
- 规划文档：
  - `.planning/phases/2.23-architecture-debt-paydown/2.23-PLAN.md`
  - `.planning/phases/2.23-architecture-debt-paydown/2.23-HANDOFF-TASKS.md`
  - `.planning/phases/2.23-architecture-debt-paydown/2.23-REVIEW-FINDINGS-REGISTER.md`

### Phase 3.0: English Listening Learning Loop ⏳ 当前产品主线

- 目标：在 Phase 2 的真实声音流资源和 Phase 2.18 的学习资产架构上，把英语先做成完整学习闭环。
- 核心闭环：真实输入 → 可理解度判断 → 诊断 → 主动练习 → 复习巩固 → 进度反馈 → 回到真实输入。
- 产品原则：
  - 语言能力来自听力突破和大量可理解输入。
  - 常见语言学习功能重写为听力本位能力。
  - 首个真实组合为 Mandarin L1 → English L2，L1/L2 理论进入诊断层。
  - Cloze、听写、字幕渐隐、chunk replay、本地 YouGlish-like 个人语料库是关键体验。
- 前置：Flutter 侧新 practice UI 开工前先完成 Phase 2.23 的 `main.dart` 收缩，避免继续堆入 god file。
- 规划文档：`.planning/phases/3.0-english-listening-learning-loop/3.0-PLAN.md`

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
| 2.22 User-Facing Workflow Semantics | 用户可见工作流语义收口，真实媒体 smoke 待用户跑 | `.planning/phases/2.22-user-facing-workflow-semantics/2.22-CLOSEOUT.md` |

## 最近重要决策

1. **2026-07-02** — speech-analysis 算法线（2.19/2.20/2.21）搁置，主线转入 Phase 3.x
   英语听力学习闭环；audible-structure v1 contract 保持当前权威 shape。
2. **2026-07-02** — Phase 2.23 只做机械治理，不改产品行为；`main.dart` 收缩是 3.x
   Flutter practice UI 的前置。
3. **2026-07-01** — consumer self-contained invariant：bundled whisper.cpp 产出的
   WordTimeline 必须解锁基础功能，sidecar 只升级质量。
4. **2026-07-01** — 字幕层声音模式统一为 Rhythm A/B/C；phones 是 C 内 L4 evidence，不再是一级模式。
5. **2026-06-30** — 算法/指标/阈值变更必须记录 evidence class，不能把小样本 smoke 或自动标签当真理。
6. **2026-06-27** — 稳定教学标签优先：CTC 是 audio evidence，不是默认 teaching label truth。
7. **2026-06-18** — 产品拆为本地重装生产引擎 + 轻量消费端两条协同路线。

## 当前阻塞项

无。

## 下一步工作

1. Phase 2.23：继续 T2 收口验证；随后推进 T6 SSE payload typed 化余项、T7 Dart contract
   解析安全网、T4/T5 机械拆分。
2. Phase 2.23 Step 3：由原审核会话推进 `main.dart` 收缩，避免 3.x practice UI 继续进入 god file。
3. Phase 3.x：在当前 audible-structure v1 和 2.22 用户语义上推进输入难度、精听/泛听、
   主动验证、听力驱动词汇、L1-aware diagnosis、shadowing 和 dashboard。

## 指标

- STATE.md 维护目标：≤ 400 行。
- 当前生产管线吞吐：新闻视频约 1-2 条/天（手工触发）。
- 已完成里程碑：M1.0, M1.5, M1.6, M1.7, M1.8, M1.9。
