---
gsd_state_version: 1.0
milestone: v0.5.0
milestone_name: milestone
status: unknown
last_updated: "2026-06-22T01:04:00.000Z"
progress:
  total_phases: 10
  completed_phases: 0
  total_plans: 4
  completed_plans: 0
  percent: 0
---

# LLPlayerNext — 项目活记忆

> 最后更新：2026-06-22 09:04 CST
> 更新原因：Phase 2.5 Sound Pattern / PhoneTimeline 收口

## 当前位置

- **里程碑**：Milestone 2 — 本地重装生产引擎
- **Phase**：Phase 2.5 Sound Pattern / PhoneTimeline 已完成；准备进入 Phase 2.6 或后续 provider research
- **分支**：`feature/forced-alignment-research`
- **版本**：0.7.0

## 项目双路线

自 2026-06-18 起，项目拆分为两条协同路线：

| 路线 | 目标 | 当前状态 |
|---|---|---|
| 本地重装生产引擎 | 生成精准 WordTimeline / ChunkTimeline / LLTimeline JSON | ✅ 阶段性收口，转长期研究 |
| 轻量消费端 LLPlayerNext | 稳定读取 `.lltimeline.json` 并播放学习 | ⏳ Phase 2.3 第一版实现完成，待真实媒体 QA |

## 当前 Phase 状态

### Phase 1: LLTimeline JSON v1 核心契约 ✅

- Schema `llplayer.timeline.v1` 已定义
- metadata / segments / words / phonemes / chunks / artifacts 结构完整
- 导入导出 round-trip 测试通过

### Phase 2: 时间轴资源生命周期 ✅

- 版本化 WordTimeline 资源 CRUD
- activate / publish / archive 状态机
- `lltimeline-resource.py` 管理工具

### Phase 3: 生产管线 V1 ✅

- WhisperX ASR + 强制对齐集成
- `produce-whisperx` 端到端命令可用
- 音频预处理（16kHz mono WAV 提取）
- 可选人声分离（Demucs）
- WhisperX JSON → LLTimeline v1 转换
- `production-report.json` 记录覆盖率、overlap/gap、provider 和人工复核准备状态

### Phase 4: 客观评估体系 ✅ 暂时收口

- TIMIT 已接入为高质量 gold resource。
- `compare-lltimeline` 可比较同一 `.lltimeline.json` 内的 baseline/candidate/gold
  word timeline，并输出 P95、tail lag、coverage、overlap/gap 等指标。

- 已完成 MMS_FA、完整 WhisperX CLI、WhisperX+MMS_FA、MFA `align-one` 的首轮
  TIMIT TEST 100 对比。

- 结论：MFA `english_us_arpa + align-one` 是当前高质量 transcript 条件下最强的
  已观测词边界对齐器；MMS_FA 保留为轻量 fallback；Qwen3/BFA 等路线进入长期研究。

### Phase 2.1: 对齐管线加固 ✅ 阶段性结束

- P0 word_index 占位契约已完成。
- P1 tokenizer/evaluation guardrail 已完成。
- application `WordTimelinePipeline` 编排下沉已完成，api-http 转录流程不再直接调用
  `speech_analysis::{asr_timing, forced_align, pause_refinement}`。

- phonetic research fixture 的 phone alignment / finding 构造已下沉到 application。
- `crates/api-http/src` 已移除对 `speech_analysis` 的直接引用。
- production pipeline 已支持可插拔 post-aligner：
  `none|auto|mfa|mms-fa`。

- `auto` / `mfa` 按 MFA -> MMS_FA -> WhisperX 原始时间轴降级。
- P3 evaluate stats 去重已完成。
- persistence/application 巨型文件拆分、monotonicity 消融转为独立后续架构债，
  不阻塞 Phase 2.2。

### Phase 2.2: App Timeline Resource UI Alignment ✅ 已完成

- 目标：让 app 端能导入、展示、选择、激活和消费 `.lltimeline.json` 里的
  WordTimeline 资源。

- 当前生产端资源策略：
  `WhisperX -> optional post-aligner auto|mfa|mms-fa|none -> LLTimeline JSON`。

- `auto` / `mfa` 按 MFA -> MMS_FA -> WhisperX 原始时间轴降级。
- app 端已新增 Timeline Resource Summary，可导入 `.lltimeline.json`、展示
  active/candidate WordTimeline、生产 artifacts 和 readiness，并激活候选 timeline。

- LLTimeline metadata/artifacts 已持久化，导入后 export 可保留 production report /
  post-alignment artifacts。

- 播放器词级高亮继续通过 `trackWordTimings()`，后端优先返回 active WordTimeline，
  无资源时回落 legacy word timings。

- 人工复核入口占位已就绪，完整编辑器进入 Phase 2.3。

- 2026-06-20 正式收口确认：
  - SRT / WebVTT / ASR 字幕 / LLTimeline JSON 已统一为“字幕资源”语义。
  - 字幕资源导入后进入 SQLite，并由顶层“字幕资源”页面从数据库读取。
  - 字幕资源支持导入、刷新、激活、归档、恢复、删除、导出。
  - LLTimeline 可挂载到当前媒体；fingerprint mismatch 由用户确认后允许强制挂载。
  - active WordTimeline 驱动词级高亮，chunk / phone / pronunciation 独立降级。
  - 真实本地数据库已迁移到 schema v12，包含 `word_timeline_runs`、
    `lltimeline_resources` 和 `subtitle_tracks.status`；Phase 2.4 后端变更将 schema
    提升到 v13，新增 `chunk_timeline_runs`。
  - 已修正开发环境 stale release sidecar 优先的问题，避免旧 core 阻塞数据库迁移。
  - 收口文档：
    `.planning/phases/2.2-app-timeline-resource-ui/subtitle-resource-semantics-and-lifecycle.md`

### Phase 2.3: 人工校对 UI ⏳ 第一版实现完成，待手动 QA

- 目标：完成 app 端人工校正闭环。
- 初版不做完整 waveform editor，先做句子级 Word Timing Inspector。
- 从 Timeline Resource Summary 的 Manual Review 入口进入。
- 用户可查看当前句 word timings，微调 start/end，试听句子/词片段。
- 保存时创建 `created_by=user` / `timing_source=user_adjusted` WordTimeline，
  不覆盖 production candidate。

- 保存后自动激活 user-adjusted timeline，并刷新播放器高亮。
- 2026-06-21 第一版实现完成：
  - Flutter client 支持读取完整 WordTimeline 和创建 user-adjusted WordTimeline。
  - WordTiming / WordTimeline 模型支持完整 contract 解析和毫秒级保存 payload。
  - 新增 ManualReviewDraft，负责完整 timeline draft、dirty tracking、校验和保存
    payload。
  - 新增句子级 ManualTimelineReviewDialog，支持 Prev/Next、毫秒输入、±10/±50ms
    微调、播放当前句/词、Reset sentence 和 Save revision。
  - 保存后通过现有 `status=active` create path 自动激活，并刷新 summaries 与
    `trackWordTimings()`。
  - Manual Review 入口已调整为带文字按钮；点击字幕单词会打开 Word Learning 面板。
  - Manual Review 试听退出后会恢复进入前的 source loop，避免残留循环当前句。
  - 字幕资源导出入口已支持选择 SRT 或 LLTimeline JSON。
  - Timeline Resource Summary 已新增直接导出 LLTimeline JSON 的入口，便于从
    manual/original WordTimeline 版本视图直接导出完整资源。
  - 自动化验证：`flutter analyze`、`flutter test` 通过。
  - 仍需真实媒体手动 QA 后再最终收口。
- 规划文档：
  - `.planning/phases/2.3-manual-timeline-review-ui/2.3-CONTEXT.md`
  - `.planning/phases/2.3-manual-timeline-review-ui/2.3-PLAN.md`
  - `.planning/phases/2.3-manual-timeline-review-ui/2.3-ACCEPTANCE.md`
  - `.planning/phases/2.3-manual-timeline-review-ui/2.3-CLOSEOUT.md`
  - `.planning/phases/2.3-manual-timeline-review-ui/2.3-RESEARCH.md` (2026-06-20 调研完成)

### Phase 2.3.5: Rust 巨型单文件拆分 ✅ 已完成

- 目标：在 Phase 2.3 人工校对闭环之后、Phase 2.4 ChunkTimeline 之前，集中处理
  `persistence-sqlite`、`application`、`api-http` 的巨型 `lib.rs` 技术债。
- 阶段原则：只做 mechanical decomposition，不改业务行为、不改 API contract、不改
  SQLite schema、不新增产品能力。
- 完成内容：
  - `persistence-sqlite` 已按 connection / migrations / support / repository 表域拆分；
    root `lib.rs` 保留 module declarations、re-export 和 tests module。
  - `application` 已拆出 DTO、error、repository/provider traits、util 和 use case 模块；
    root `lib.rs` 保留 `AppServices` 装配、re-export 和共享 timeline helper。
  - `api-http` 已按 `routes/` route group 拆分 handler；root `lib.rs` 保留 router 装配、
    auth、SSE、错误响应和 coordinator 状态。
  - `api-http` 对 `speech-analysis` 的 Cargo 直接依赖已移除，HTTP 层通过
    `application` 编排访问语音分析能力。
- 收口体量：
  - `crates/persistence-sqlite/src/lib.rs`：约 19 行。
  - `crates/application/src/lib.rs`：约 609 行。
  - `crates/api-http/src/lib.rs`：约 496 行。
  - `crates/domain/src/lib.rs`：约 1317 行，暂不作为 Phase 2.4 前置项。
- 自动化验证：`cargo test --workspace --quiet` 通过。
- 规划文档：
  - `.planning/phases/2.3.5-rust-module-decomposition/2.3.5-CONTEXT.md`
  - `.planning/phases/2.3.5-rust-module-decomposition/2.3.5-PLAN.md`
  - `.planning/phases/2.3.5-rust-module-decomposition/2.3.5-CLOSEOUT.md`

### Phase 2.4: ChunkTimeline 生成与消费 ✅ 已完成

- 目标：把 chunk 从临时算法结果升级为可管理、可激活、可导出、可播放消费的
  ChunkTimeline 资源。
- 阶段第一优先级不是继续调算法，而是打通 ChunkTimeline 资源契约：
  `active WordTimeline -> ChunkTimeline candidates -> active ChunkTimeline -> player consumption`。
- 第一版 provider 采用 acoustic-first + semantic-assisted 策略：
  - 非 estimated WordTimeline 的 gap / duration evidence。
  - 标点、短语、语义边界启发式。
  - chunk 长度和学习可用性约束。
  - estimated timing 降级为 approximate / text-only，不声称精确声学边界。
- UI 目标：字幕资源管理中可见 ChunkTimeline candidates，并支持生成、激活、归档、
  删除、导出；播放器支持当前 chunk 高亮、点击跳转、chunk 循环、Prev/Next chunk 和
  渐进展开训练。
- 2026-06-21 完成内容：
  - `domain` 新增 `ChunkTimeline`、`ChunkTimelineChunk`、`ChunkTimelineSummary`、
    `ChunkTimelinePrecision` 和 `ChunkBoundarySource`。
  - SQLite schema v13 新增 `chunk_timeline_runs`，支持 candidate / active / archived
    生命周期与 active 唯一性。
  - `application` 已能从 active WordTimeline 生成 `acoustic_semantic_v1`
    ChunkTimeline candidate/active；estimated timing 标记为 approximate。
  - `api-http` 新增 ChunkTimeline list / summary / generate / get / activate / archive /
    delete / export 路由。
  - LLTimeline export/import 已保留 ChunkTimeline candidates 和 active id。
  - OpenAPI contract 已同步 ChunkTimeline schema 与路由。
  - Flutter API client/model 已接入 ChunkTimeline，并优先消费 active ChunkTimeline；
    无 active resource 时保留旧 `chunk-partitions` 降级路径。
  - 字幕资源管理 UI 已展示 ChunkTimeline candidates，并支持生成、激活、归档、删除、
    导出完整 LLTimeline。
  - 播放器已消费 active ChunkTimeline：当前 chunk 高亮、点击 chunk 跳转、
    Prev/Next chunk、Loop chunk、Expand chunk 和原有 Loop sentence 组成渐进训练路径。
  - 自动化验证：`cargo test --workspace --quiet`、`flutter analyze`、`flutter test`、
    `./scripts/validate-contracts.sh` 通过。
- 规划文档：
  - `.planning/phases/2.4-chunktimeline-generation-consumption/2.4-CONTEXT.md`
  - `.planning/phases/2.4-chunktimeline-generation-consumption/2.4-PLAN.md`
  - `.planning/phases/2.4-chunktimeline-generation-consumption/2.4-CLOSEOUT.md`

### Phase 2.5: Sound Pattern / PhoneTimeline ✅ 已完成

- 目标：把真实声音模式从“文字字幕的附属解释”升级为一等学习对象，让用户可以从
  sound pattern 直接建立到文字、chunk 和意义的映射。
- 产品动机：听力理解不只是 `audio -> words -> meaning`，更接近
  `audio -> sound patterns -> chunks / phrase patterns -> meaning`；word/text 是解释层
  和对齐层，不是唯一入口。
- 阶段第一优先级是 provider benchmark + PhoneTimeline 资源契约，而不是先做音标 UI：
  - 评估 MFA phone alignment、Wav2IPA/Wav2Vec2Phoneme、ZIPA、Allosaurus baseline。
  - 验证候选是否保留弱读、省音、闪音、缩约，而不是规范化回字典发音。
  - 定义 PhoneTimeline candidate / active / archived 生命周期。
  - 将 completed phonetic analysis 转换为可管理、可导入导出、可播放消费的
    PhoneTimeline resource。
- UI 目标：Sound Pattern View 显示 detected audio、canonical pronunciation 和 rule
  prediction 三层；支持 current phone 高亮、点击循环、finding 证据展开和用户反馈。
- 2026-06-21 首块实现：
  - `PhoneTimeline` 升级为一等资源模型，支持 candidate / active / archived 生命周期。
  - SQLite 新增 `phone_timeline_runs`，LLTimeline export/import 开始保留
    PhoneTimeline candidates 和 active id。
  - completed `PhoneticAnalysis` 会桥接生成 PhoneTimeline candidate。
  - 新增 PhoneTimeline list / summary / get / activate / archive / delete / export API。
  - `research-fixture` 桥接结果标记为 `approximate`，保持 synthetic / 非真实检测语义。
  - TIMIT benchmark dataset phone timeline 输出迁移到新资源契约。
- 2026-06-22 收口：
  - app 端 `LocalApi`、timeline models、`SubtitleController` 和 Timeline Resource Summary
    已接入 PhoneTimeline。
  - 资源面板可展示 PhoneTimeline candidates，并支持激活、归档、删除。
  - 播放/诊断侧优先消费 active PhoneTimeline；无 active resource 时回退旧
    `phonetic-analyses`。
  - `2.5-BENCHMARK.md` 明确 provider gate：当前 no release provider selected。
  - `scripts/verify-m20-phase0.sh` research infrastructure 验证通过。
- 规划文档：
  - `.planning/phases/2.5-sound-pattern-phonetictimeline/2.5-CONTEXT.md`
  - `.planning/phases/2.5-sound-pattern-phonetictimeline/2.5-PLAN.md`
  - `.planning/phases/2.5-sound-pattern-phonetictimeline/2.5-BENCHMARK.md`
  - `.planning/phases/2.5-sound-pattern-phonetictimeline/2.5-CLOSEOUT.md`

### Phase 2.6: 多语言学习基础 ⏳ 已规划

- 目标：将 LLPlayerNext 从“英语优先学习播放器”扩展为“语言能力可插拔的学习播放器
  底座”，首批真实验收语言为 English + Chinese。
- 阶段定位：延后到 2.3 / 2.3.5 / 2.4 / 2.5 之后，不打断当前资源主线。
- 当前判断：
  - 播放、字幕资源、时间轴资源、SQLite、来源快照等底座具备多语言扩展性。
  - 逐词学习、词汇状态、字典、lemma、发音和诊断仍明显英语优先。
  - 汉语是第二语言基线，用于迫使 tokenizer、LexicalUnit、拼音/声调和诊断模型从
    英语假设中解耦。
- 核心工作：
  - 定义 language capability matrix。
  - 引入 language-aware tokenizer。
  - 从英语 `lemma` 扩展为语言相关 `LexicalUnit`。
  - 清理 Flutter/API client 中的 `language=en` 硬编码。
  - 接入汉语最小词典 / 拼音 provider。
  - 建立英语 + 汉语双语言回归测试。
- 规划文档：
  - `.planning/phases/2.6-multilingual-learning-foundation/2.6-CONTEXT.md`
  - `.planning/phases/2.6-multilingual-learning-foundation/2.6-PLAN.md`

### 强制对齐研究 🧭 长期推进

- torchaudio MMS_FA sidecar（`scripts/forced-align/align-cli.py`）。
- MFA research sidecar（`scripts/forced-align/mfa-align-cli.py`）。
- Qwen3-ForcedAligner、BFA/easytranscriber/CTC 暂列 deferred research。
- 研究结果必须通过统一 LLTimeline schema、tokenizer 和 benchmark 体系后再晋级主线。

## 最近重要决策

1. **2026-06-18 14:50** — 产品重构：从单一消费端拆分为生产引擎 + 消费端两条路线
2. **2026-06-18** — 引入 GSD 文档体系，建立 `.planning/` 目录
3. **生产端策略**：WhisperX 负责高质量 transcript/VAD，后处理 aligner 可选
   MFA/MMS_FA/未来候选，最终统一输出可复用 `.lltimeline.json`

4. **降级策略**：生产端 `auto` 路线按 MFA -> MMS_FA -> WhisperX 原始时间轴降级；
   app 端不得依赖重型 runtime
5. **Phase 2.2 收口边界**：字幕资源生命周期和 LLTimeline 消费闭环已完成；chunk
   语义质量、ChunkTimeline 资源化、chunk 候选选择和人工修正进入后续 Phase 2.4 /
   chunk 专项阶段，不再塞回 Phase 2.2。
6. **Sound Pattern 产品原则**：真实发声模式是听力学习的一等对象；PhoneTimeline /
   phonetic findings 的目标不是装饰性 IPA，而是帮助用户从真实声音模式直接建立到
   chunk、文字和意义的映射。
7. **Phase 2.3.5 架构关口已通过**：Rust 巨型单文件拆分已完成，后续
   ChunkTimeline / PhoneTimeline 新能力应进入对应 module，而不是继续堆入 root
   `lib.rs`。
8. **多语言策略**：产品长期支持主要语言，但不承诺世界所有语言；首批扩展验收语言
   为英语和汉语，先建立语言能力矩阵、语言感知 tokenizer 和 LexicalUnit 模型。

## 当前阻塞项

无。

## 下一步工作

1. Phase 2.3：用真实媒体完成 Manual Timeline Review 手动 QA，并决定是否正式收口。
2. 后续 provider research：填充 licensed reviewed development cases，复跑 ZIPA /
   Wav2IPA / MFA phone alignment benchmark；通过 gate 前不进入默认 product path。
3. Phase 2.6：多语言学习基础，以英语 + 汉语建立扩展范式。

## 指标

- 已完成里程碑：M1.0, M1.5, M1.6, M1.7, M1.8, M1.9
- 活跃分支领先 main：持续增长，以 git log 为准
- 生产管线每天可处理的新闻视频：1-2 条（当前为手工触发）
