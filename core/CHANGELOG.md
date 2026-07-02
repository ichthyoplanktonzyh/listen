# Changelog

## Unreleased

- 2026-07-02 22:59 CST: Phase 2.23 handoff T2 — 修复文档事实源漂移。
  `ARCHITECTURE.md` 依赖图改为 `dictionary-provider` 与 `persistence-sqlite`
  同级适配器（均依赖 `application` 并实现其 trait），依赖方向图同步为
  `domain <- core engines <- application <- api-http / persistence-sqlite / dictionary-provider`。
  `STATE.md` 从 1208 行压缩为当前状态机 + 活跃/搁置 phase + 已完成 phase 索引，
  删除静态分支字段和不一致 progress 账；`MAINTENANCE.md` 增加 STATE ≤400 行、
  phase 收口压缩索引、不记录瞬时 git 事实等防复发规则。

- 2026-07-02 22:52 CST: Phase 2.23 handoff T1/T8/T9 — SQLite schema v17 drops
  the unused `learning_resources` table without touching historical migrations;
  migration tests now assert upgraded databases no longer contain that table.
  `DATA-MODEL.md` records WordTimeline vs legacy `word_timings` authority,
  document-level `rhythm_frames` vs transitional `PhoneTimeline.sound_analysis`
  rhythm frames, and the JSON-quoted `status = '"active"'` partial-index coupling.
  `ARCHITECTURE.md` / `STACK.md` now reflect schema v17 and the removed table;
  the 2.23 review register marks B-1, B-3, and B-5 closed.

- 2026-07-02 20:52 CST: Phase 2.23 分工落定 — 新增交接任务包 `2.23-HANDOFF-TASKS.md`。
  剩余待修项（B-1 僵尸表、B-2 文档漂移、B-3 双家退役条件、B-5 小项）与 PLAN
  Step 0/2/4/5（基线、sound_analysis 拆分、Dart contract 安全网、tests 拆分）整理为
  T1-T9 自包含任务（步骤/验收/铁律/依赖冲突提示），交其他执行人；Step 3（main.dart
  收缩）由原审核会话执行人负责。顺带核实并修正一处事实：`state/store.dart` 的
  `Store<T>` 已被 player/learning/subtitle 三大控制器使用（非死雏形），Step 3 的
  "状态模式定调"决策消解为 controller + Store 转正唯一模式（PLAN/CONTEXT 已同步修正）。
  仅规划文档，无代码变更。

- 2026-07-02 20:36 CST: Phase 2.23 审核缺陷收口第二批 — B-4 与 C-7 主切片。
  (1) **B-4 learning-loop 双表示写入收敛**：五个 upsert 的 `ON CONFLICT DO UPDATE` 从
  只更新 `*_json`（practice_items/practice_attempts/review_attempts 完全不更新查询列）
  改为完整非主键列更新，列与 JSON 永远出自同一 struct 同一语句；round-trip 测试扩展
  覆盖改 kind/result/status 后列值与 JSON 投影一致、按 status 过滤正确。
  (2) **C-7 SSE payload 生产端 typed 化 + 跨语言 golden 契约**：新增
  `api-http/src/event_payloads.rs`（6 个 typed payload struct，统一
  `speech-cache-invalidated` 两处不一致形状），迁移 6 处 ad-hoc `json!` 发射点；
  新增 `contracts/events/examples.json` golden 信封，Rust 侧
  `event_contract_examples_match_producers`（`UPDATE_EVENT_EXAMPLES=1` 再生成）与
  Dart 侧 `test/contract/backend_event_contract_test.dart` 双端锁定 Flutter typed
  消费的全部 6 个事件的 wire shape。register 同步更新（B-4→A-6、C-7→A-7+剩余项）。
  验证：`cargo test --workspace` 358 passed、`flutter analyze` 无问题、
  `flutter test` 156 passed（+6 契约测试）、`./scripts/validate-contracts.sh` 通过。

- 2026-07-02 20:13 CST: Phase 2.23 审核缺陷收口 — 修复五项高优先级架构缺陷（Rust 内部契约，
  API/JSON shape 零变化）。(1) 诊断归一化接缝：`diagnosis-core::diagnose` 新增 token→词条 key
  映射参数，application 用 provider 归一化链解析后传入，屈折形式（"went"）不再误判 unclassified；
  (2) 观察身份统一：新增 `domain::lexical_observation_id(entry, sentence)` 确定性单源函数，
  三处生成点（API/practice/import）收敛，同句新观察覆盖 result 但 ID 稳定，
  `generated_observation_ids` 不再悬挂，import 幂等改善；(3) SSE 事件契约：schema 补
  `sound-line-changed/completed` 漂移，api-events 新增 `EventName::ALL` + 编译期穷尽守卫 +
  双向 parity 测试；(4) LLTimeline 导入身份重写所有权归一：`remap_lltimeline_sentence_ids`
  更名 `remap_lltimeline_identity` 并吸收调用方 track/media 重写循环，新增全文档
  "原始 ID 零残留"不变量测试（覆盖 W8 脱钩 bug 类）；(5) `LexicalEntry` 双身份轴硬化：
  kind↔granularity 映射收进 domain，`validate_unit_coherence()` 在 persistence 写读两侧
  强制四轴一致。新增 `2.23-REVIEW-FINDINGS-REGISTER.md` 登记全部审核发现的归属
  （已修/交接他人/归 3.x/defer）；同步 `DATA-MODEL.md`（观察身份语义）与
  `ARCHITECTURE.md`（diagnosis-core 输入契约）。
  验证：`cargo test --workspace` 357 passed、`./scripts/validate-contracts.sh` 通过、
  clippy 无新增警告；Flutter 未运行（shape 不变，无需改动）。

- 2026-07-02 13:50 CST: 方向决策 — speech-analysis 算法线搁置，主线转入 Phase 3.x 学习闭环。
  Phase 2.19/2.20/2.21 整体搁置（STATE.md 标记 ⏸ 并注明重启条件；audible-structure v1
  contract 保持权威 shape，3.x 按现状消费）；Phase 3.0 升为当前主线。Phase 2.23 相应调整：
  Step 3（main.dart 收缩）升为 P0 并提前到 Rust 拆分之前执行（3.x Flutter practice UI 前置），
  Step 2（sound_analysis 拆分）降为 P1、改在算法线静默窗口内零冲突完成。同步更新
  ROADMAP.md 路线注记、`2.23-CONTEXT.md` / `2.23-PLAN.md`。仅规划文档，无代码变更。

- 2026-07-02 13:35 CST: 新增 Phase 2.23 Architecture Debt Paydown（建档，未开工）。
  基于 2026-07-02 全库架构审核（依赖方向 / api-http 越层 / 端口-适配器 / 测试基线均验证成立），
  立案五项累积债务：A1 `main.dart` god file + UI 状态双轨（3601 行 / 107 setState）、
  A2 `sound_analysis.rs` 单文件膨胀（3383 行，contract 已锁 v1）、A3 文档事实源漂移
  （ARCHITECTURE.md dictionary-provider 依赖方向画反、STATE.md 1149 行且 frontmatter 与正文矛盾）、
  A4 Dart 手写模型解析无契约守卫（timeline.dart 2596 行）、A5 巨型 tests.rs（2534/2021 行）。
  新增 `2.23-CONTEXT.md` / `2.23-PLAN.md`（6 步、全可测量验收、机械治理不改行为），
  STATE.md 登记 Phase 2.23 section。仅规划文档，无代码变更。

- 2026-07-02 10:45 CST: Phase 2.22 defer 清零 (2/5) — SM-04 下载栏消失行为。
  Failed 下载栏在可配置延时后自动消失（`DownloadController.failedAutoDismiss`，默认 10s，
  因失败态无可留操作）；Completed 栏保留以保住 “Open”，点 Open 时顺带 dismiss 消栏。旧 failed
  timer 被 generation 守卫，不会误清后续新下载。新增 3 个单测。
  验证: `flutter analyze` 无问题、`flutter test` 150 passed。

- 2026-07-02 10:15 CST: Phase 2.22 defer 清零 (1/5) — SM-05 副字幕缺失提示。
  副字幕开启但根本没有副字幕轨道（`secondaryTrack == null`）时，overlay 显示克制的
  “No secondary subtitle / 无副字幕”提示；已有轨道内的空档保持空（字幕空档正常，不提示）。
  用 `secondaryTrack` vs `currentSecondaryCue` 区分两种情况。顺带删除第二个死代码 overlay
  widget `widgets/layout/subtitle_overlay.dart`（与旧 side_panel 同型孤儿，main.dart 用内联渲染）。
  验证: `flutter analyze` 无问题、`flutter test` 147 passed。

- 2026-07-02 09:45 CST: Phase 2.22 判定达成、转收口。
  阶段三目标（确认功能工作流/路径、建立用户可见状态机、据状态机找出问题）按 journey/状态机层面
  判定达成：`2.22-USER-VISIBLE-STATE-MACHINE.md`（R0-R8 + Section C 就绪 lane）已建，Defect
  Register 产出并闭环修复 SM-01/02/03/07b（+ 记录 F1-F8）。剩余 SM-04/05/06/07剩余/08 明确 defer
  （待 UX / polish / YAGNI / 候选下一后端阶段）。新增
  `2.22-CLOSEOUT.md`，`STATE.md` 标记 Phase 2.22 ✅ 已收口（真实媒体手工 smoke 待用户跑）。
  逐功能模板化（约 40 个 checklist 功能）journey 层已覆盖、价值低，刻意不做。
  自动化：`flutter analyze` 无问题、`flutter test` 147 passed。

- 2026-07-02 09:15 CST: Phase 2.22 转绿 + SM-01 缩范围收口。
  (1) **转绿**: `diagnosis_card_test` 的 `rhythm frame renders before phone evidence`
  因 `stressAnchors` 文案由 `Anchors` 改为 `Heard anchors`（information-anchors 语义重构）
  而断言过时，更新为 `Heard anchors:`；其余断言仍匹配当前诊断卡渲染。
  (2) **SM-01（缩范围，收口标准 #5）**: 全量审计确认自由字符串 `status` 只有一处被读值驱动
  行为（manual-review 关闭守卫的 `status == 'Loading manual review timeline...'` 魔法字符串），
  其余全是写入/显示。该处改为 typed `_manualReviewStatusPristine` 标志，自由字符串不再驱动
  任何行为（行为由 typed lane 驱动：readiness / `DownloadController` / `UserTaskStatus`）。
  ~99 处显示型 `status` 写入的全量枚举化判定为镀金，未做。
  验证: `cd apps/desktop && flutter analyze` 无问题、full `flutter test` 147 passed。

- 2026-07-02 00:52 CST: 为 Rhythm C 正式引入 `information_anchors`。
  `RhythmFrame` 新增兼容字段 `information_anchors`，用于建模“人耳实际抓到哪些音素/声音点并据此推断句义”，
  不再把 `stress_anchors` 当作 C 的核心语义；生成器会从 phone timing 或 word timing + canonical phones
  产出音素级信息锚点（保留否定、指示、疑问等高信息功能词），C UI 优先渲染 information anchors，
  旧资源缺字段时才回退到 stress anchors。Readiness 同步把 information anchors 计入音频支持判定。

- 2026-07-02 00:30 CST: 优化 Rhythm C 的真实可听锚点表达。
  C `This audio` 不再把前景锚点过度收窄为“重读音节”：后端允许短但有音频时序支持的
  content sound 成为 audio-supported listening anchor，并将 anchor confidence 与
  nucleus prominence 分开校准，让能量/音高突出优先决定主核；前端将锚点 label 从单个重读元音
  扩展为“语义锚点词 + 元音核/临近辅音边缘”的可听信息节点（如 `changed` + `/tʃeɪndʒd/`），
  弱读团仍保持低对比背景。同步将 C 的文案从 stress/rhythm 调整为 heard information anchors。
  新增短时序 content anchor 与 consonant-vowel shape 的回归测试。

- 2026-07-02 00:15 CST: 优化 Rhythm B 默认语流规则的底层算法口径。
  B 的 text-prior 规则现在从发音 provider 取得 ARPABET 音素序列，跨词 linking、
  同辅音保持、t/d weakening 与 American flap 都按音素特征判断，不再按拼写字母猜测；
  修复 t/d weakening 错把“下一个词尾是辅音”当作条件的问题，改为真正的“下一个词首为辅音”；
  弱读/短语规则会过滤 canonical 与 reduced 完全相同的 no-op 标注，并在 fallback 发音不可靠时
  回退到规则表的强读音素。同步更新旧 `analyze_rules` 出口和规则目录说明，删除旧拼写 helper，
  新增 no-op、phone-boundary linking、t/d vowel/consonant 条件等回归测试。

- 2026-07-01 23:11 CST: 重构 Rhythm B/C 字幕视图的学习语义与视觉层级。
  B `Common speech` 不再把规则拆成卡片列表，而是按原句 token range 就地显示弧线、
  下划线、规则名和 A → B IPA 变化，未变化文本退为上下文；C `This audio` 从诊断标签集合
  收敛为可听前景/背景：用词典音素标记音频支持的重音与 nucleus，弱读音团低对比显示，
  phrase boundary 仅作分隔，compression/hotspot 不再占用默认表面，详细 phone evidence
  仍由 C 内按需展开；音频支持的 C 视图会逐项排除仅有 text-prior 的预测 anchor，防止预测项
  混入真实听感。同步更新中英文提示和 Flutter widget 回归测试，并完成真实桌面渲染检查。

- 2026-07-01 21:30 CST: 声音线彻底解耦为独立后台工作流。
  新增 `SoundLineCoordinator`（`crates/api-http/src/sound_line.rs`）：拥有自己的 job
  生命周期（queued/running/completed/cancelled/failed）、独立 temp 目录与独立音频提取，
  订阅 `transcription-job-changed(completed)` 后自动入队，并暴露
  `/v1/sound-line/jobs` 的 create/list/get/cancel/retry。转录流程 `process_job` 不再
  内嵌声音线 spawn 与延迟清理，只负责文字线（存 active `whisper-dtw` timeline）并在完成后
  立即清理 work_dir——文字线路径上不再有任何声音线代码。事件拆分：文字线用
  `word-timings-completed(line=text)`，声音线改用新的 `sound-line-changed` /
  `sound-line-completed`；前端新增 `SoundLineCompletedEvent`，文字线静默刷新、声音线单独
  报告就绪。红线（声音线永不 activate、绝不改动 active 文字线）由 api-http 测试
  `sound_line_resources_never_disturb_active_text_timeline` 固化。共用的 ffmpeg 参数
  构造抽为 `ffmpeg_wav_args`。验证覆盖 `application`/`api-http`/`api-events` 测试、
  OpenAPI contract 与 Flutter backend event coordinator 测试。

- 2026-07-01 20:10 CST: ASR 文字线与声音线解耦。
  whisper.cpp + DTW 现在只负责文字线，生成 active `whisper-dtw` WordTimeline 后即可完成
  ASR job，保留词级跳动、chunk 与词典音标的原有路径；forced alignment、pause refinement
  与 word-acoustic cues 改为后台声音线任务，产出 `line=sound` candidate WordTimeline 与
  RhythmFrame 资源，不再覆盖 active text timeline。LLTimeline 导出优先让 RhythmFrame
  挂到带声学 cues 的声音线 timeline，前端监听 `word-timings-completed` 后刷新当前资源。
  验证覆盖 `application`、`api-http` 后端测试与 Flutter backend event coordinator 测试。

- 2026-07-01 19:16 CST: ASR word-timeline 后处理恢复安全降级。
  修复最新提交后 ASR 任务会因 `word timing boundary must not be empty` 标红的问题：
  whisper.cpp DTW 重复时间点现在会被拆成单调、非空词区间，裁到句子边界后仍为 0
  长度的句子会回退而不是写入非法 timing；转录导入后的 WordTimeline、pause refinement
  与 word-acoustic cue 保存重新改为 best-effort，失败时保留已生成字幕轨并返回 0 cue/legacy
  fallback 状态，不再中断主 ASR job。验证覆盖 `speech-analysis`、`application` 与
  `api-http` 测试。

- 2026-07-01 18:34 CST: Phase 2.21 Rhythm A/B/C subtitle views。
  字幕层主切换从历史 `rhythm` / `phones` 改为三个都属于 Rhythm 的 reference：A
  `citation` 显示词典独立读音，B `connected` 显示规则预测的语流形式及 A → B 音标差异，
  C `actual` 显示当前音频 RhythmFrame。Phones 继续保留，但降为 C 内按需展开的 L4
  evidence，不再占用一级模式。Rust/OpenAPI/Flutter 为 B 增加 surface、rule family/hint、
  canonical/default symbols 与 display IPA；旧设置值安全迁移到 C。验证包含 Rust
  sound-analysis、domain/application/api-http、OpenAPI contracts 和 Flutter 定向测试。

- 2026-07-01 17:48 CST: Phase 2.21 consumer self-contained audible structure。
  明确轻量消费端必须以 bundled whisper.cpp + Rust 自成完整基础生态，sidecar 只提升质量。
  新增 `speech-analysis::word_acoustics`：在本机转录 WAV 删除前提取 per-word RMS energy、
  F0 median/range、pitch prominence 和 pitch reset，并持久化到
  `rhythm_word_acoustic_cues` artifact。RhythmFrame 现在让 pitch 参与 anchor/nucleus，
  允许明显 pitch reset 支持 phrase boundary；`AsrReported` 作为低精度音频时序参与
  duration/compression/boundary，只有 `Estimated` 保持纯文本预测。转录链路不再静默吞掉
  WordTimeline/acoustic persistence 错误。W8 QA 改为阈值校准与回归，不再作为 RMS/F0
  是否进入消费端的采用门槛；架构边界记录于 ADR 0013。

- 2026-07-01 16:05 CST: Phase 2.22 SM-07b — overlay predicted-only listening 徽标。
  当前句 listening structure 若无音频信号源（纯 text-prior 预测），overlay 的
  `RhythmFrameRibbon` 现在显示 `predicted` 徽标 + “基于文本预测、非实测音频” tooltip，
  不再让预测读起来像实测音频。`_rhythmFrameHasAudioSupport` 提升为公开
  `rhythmFrameHasAudioSupport(RhythmFrame)`，overlay 与 listening-structure readiness
  共用同一判据。修复了徽标在窄 leading 区的 `RenderFlex` 溢出（由 widget 测试发现）。
  过程记录：SM-07a（readiness 去重）经读码证伪为低价值纠缠改动——两处 readiness 实为不同的
  word-timing-count fallback，非纯重复——已 deprioritize。
  验证: `cd apps/desktop && flutter analyze` 无问题、full `flutter test` 134 passed
  （`capability_readiness_test.dart` 新增谓词 + predicted 徽标 widget 测试）。

- 2026-07-01 15:45 CST: Phase 2.22 建模重建 + 前端拆分增量（SM-02 / SM-03）。
  复核发现 GPT 的 2.22 遗漏了用户可见状态机建模、Capability Stack 的 L 层号自相矛盾、
  readiness 仅覆盖 5/11 层，且“前端 closeout 已完成”属高估。
  (1) **权威模型**: 新增
  `.planning/phases/2.22-user-facing-workflow-semantics/2.22-USER-VISIBLE-STATE-MACHINE.md`
  （R0-R8 surface 区域 + Section C 能力就绪 lane + Defect Register SM-01..08 / SM-F1..F8）；
  修正 `2.22-FEATURE-SEMANTICS-MODEL.md` 的 L 层号并新增 Model↔Code 对账；
  `2.22-CURRENT-FEATURE-INVENTORY.md` 改为覆盖清单 + 已验证 P0 模板 F1-F8。
  (2) **记账纠正**: `STATE.md` / `2.22-PLAN.md` 去除“closeout 已完成”高估，列清 OPEN 项。
  (3) **SM-02**: 删除死且分叉的 `apps/desktop/lib/widgets/layout/side_panel.dart`
  （其 Resources tab 用旧 `TimelineResourceSummaryPanel`，接线会退化 Resources tab，故删非接）。
  (4) **SM-03**: 下载状态从散落 5 处（`activeDownload` / `downloadError` /
  `downloadGeneration` + PlayerState `downloadProgress` / `downloadedMediaPath`）
  收敛为单一 `DownloadController`（generation + disposed 守卫，仅依赖 Stream/Future 原语，
  与下载服务解耦以便单测）；`main.dart` −84 行，`PlayerState` 去掉 2 个死字段。
  验证: `cd apps/desktop && flutter analyze` 无问题、full `flutter test` 131 passed
  （新增 `test/download_controller_test.dart` +5）。

- 2026-07-01 15:15 CST: 修复 Whisper 生成字幕后的 Timeline resource 状态误判。
  当当前字幕已加载 generated word timings 但没有 active `WordTimelineSummary` 时，
  Timeline resource 面板现在会把 Word sync 显示为可用，并显示词级 timing 数量；
  generated LLTimeline document 也会被视为可导出资源，不再显示成“旧时间轴降级”导致
  生成语块和导出 LLTimeline JSON 被禁用。

- 2026-07-01 14:45 CST: 修复点击字幕单词后右侧面板不立即跳到词汇学习的问题。
  `LearningWorkflowController.openWord` 现在会在词条、词典、发音和语言画像查询完成前，
  立即记录 selected token/cue 并切换到 Word learning tab；异步查询完成后再填充详情。
  新增回归测试覆盖 lookup 未返回时 side panel 已切换到词汇学习。

- 2026-07-01 14:25 CST: Phase 2.22 frontend workflow semantics closeout slice。
  (1) **Typed task feedback**: 新增 `UserTaskStatus`，把本机 Whisper 字幕生成和
  Phone evidence/audio-analysis job 映射为 `working/success/warning/error/cancelled/unknown`
  等前端状态；`BackendEventCoordinator` 先写 typed task state，再保留摘要文字。
  (2) **Playback controls**: 底部控制栏显示字幕生成与音素证据分析 task chip，
  不再只依赖自由字符串表达 ASR/audio-analysis 进度；切换媒体会清除旧任务状态。
  (3) **Closeout docs**: 新增
  `.planning/phases/2.22-user-facing-workflow-semantics/2.22-BACKEND-CONTRACT-GAPS.md`
  和 `2.22-FRONTEND-E2E-QA.md`，把前端语义审计暴露的后端契约缺口记录为后续输入，
  同时固定前端端到端 smoke 路径。
  验证: `cd apps/desktop && dart format ...`、
  `cd apps/desktop && flutter analyze`、focused
  `flutter test test/backend_event_coordinator_test.dart test/task_status_test.dart`、
  full `flutter test`、`git diff --check` 通过。

- 2026-07-01 14:15 CST: Phase 2.22 Step 3 subtitle resource capability-first。
  字幕资源 tile 现在以用户能力为主，直接展示 Subtitles、Word sync、Chunk replay、
  Phone evidence 的可用/不可用状态和数量；Listening structure 不再被假装成逐资源已知事实，
  active resource 指向下方 timeline details，inactive resource 明确需要激活后检查。
  同步记录一个后端闭环发现：当前 API 能逐字幕资源提供 sentence/word/chunk/phone
  能力计数，但没有直接的 per-subtitle-resource Listening structure readiness 查询，
  该事实目前只能在激活/export track timeline 后获得。

- 2026-07-01 13:58 CST: 推进 Phase 2.22 P0 user-facing workflow semantics。
  (1) **Local Whisper path**: 生成字幕弹窗现在返回是否真正创建任务；主界面在任务创建后显示
  主/副字幕生成预期，生成主字幕自动载入后会汇总 Word sync、Chunk replay、Listening
  structure、Phone evidence readiness。
  (2) **Overlay missing states**: Phone evidence 模式在已有分析对象但无 detected phones
  时不再静默消失，而是显示明确不可用提示。
  (3) **Layout semantics**: 隐藏字幕不再隐藏 transcript/resources/diagnosis side panel；
  no-media 状态改为简洁打开媒体控制条；副字幕与 chunk 控件在不可用时提供明确原因。
  (4) **Download status**: 下载条改用 typed `DownloadStatusSnapshot`
  区分 downloading/completed/failed；开始下载会清掉旧完成路径，取消/关闭会使后到的
  yt-dlp future 失效，避免 dismissed bar 复活。
  验证:
  `/Users/shadow/.local/share/flutter/bin/dart format ...`、
  `cd apps/desktop && /Users/shadow/.local/share/flutter/bin/flutter analyze`、
  `cd apps/desktop && /Users/shadow/.local/share/flutter/bin/flutter test`、
  `git diff --check` 通过。

- 2026-07-01 13:30 CST: 完成 Phase 2.22 Step 0 UI audit 文档化。
  新增
  `.planning/phases/2.22-user-facing-workflow-semantics/2.22-STEP0-UI-AUDIT.md`，
  按当前 Flutter 工作树核对用户可见入口、状态区域、端到端路径、标签语义债务和 P0/P1 owner steps；
  同步 `2.22-PLAN.md` 与 `2.22-CURRENT-FEATURE-INVENTORY.md` 指向该 Step 0
  产物。本次补充为 documentation-only，没有新增产品代码。

- 2026-07-01 13:22 CST: Phase 2.22 Step 0 audit checkpoint and first P0
  readiness slice.
  (1) **Current UI audit**: verified the current Flutter entry/state surfaces
  against `main` for media open/playback, URL/download, drag/drop,
  SRT/VTT/imported/embedded/OpenSubtitles/local Whisper subtitle paths, subtitle
  resources, timeline resources, overlay listening/phone layers, side panel,
  controls, diagnostics, vocabulary, settings, and task/status feedback.
  (2) **Capability readiness model**: added a typed frontend
  `CapabilityReadinessSnapshot` covering Subtitles, Word sync, Chunk replay,
  Listening structure, and Phone evidence with Phase 2.22 states
  `available/degraded/unavailable/stale/error`.
  (3) **Resource panel UX**: timeline resource summary now shows a compact
  user-facing "Learning capabilities" readiness strip before advanced
  WordTimeline/ChunkTimeline/PhoneTimeline details, including honest degraded
  states for estimated/predicted listening structure and unavailable phone
  evidence.
  (4) **Language cleanup**: renamed primary UI copy from `sound pattern` /
  `Listening rhythm` to `Listening structure` / `Phone evidence` while keeping
  internal setting keys and resource names stable for compatibility.
  验证: `cd apps/desktop && flutter analyze`、`cd apps/desktop && flutter test`
  通过。

- 2026-07-01 12:59 CST: 新增 Phase 2.22 User-Facing Workflow Semantics。
  (1) **Phase shell**: 新建
  `.planning/phases/2.22-user-facing-workflow-semantics/`，包含 context、feature
  semantics model、current feature inventory 和 plan，明确当前问题是所有用户功能的入口、状态、降级和端到端路径混乱，
  不是单个 `rhythm_frames` 开关。
  (2) **Product contract**: 定义用户可见能力栈：Media source、Playback、Subtitles、
  Transcript/overlay、Word sync、Chunk replay、Listening structure、Phone evidence、
  Vocabulary、Diagnosis、System/task feedback、Practice/Review readiness；
  readiness states 统一为 available/generating/degraded/unavailable/unsupported/stale/error。
  (3) **UI worktree input**: `2.22-CURRENT-FEATURE-INVENTORY.md` 参考
  `worktree-ui-feature-semantic-mapping` 的功能描述，先覆盖媒体、字幕、播放、资源、词汇、
  诊断、听感/音素、设置和任务反馈等当前全部功能，后续 Step 0 按当前 main 校验。
  (4) **Roadmap/requirements sync**: PROJECT、ROADMAP、STATE、handoff 和 REQUIREMENTS 已同步
  Phase 2.22；新增 `M2-UX` 阶段与 `UX-001` 至 `UX-008` 需求，覆盖能力模型、本机
  Whisper 默认路径、资源面板、Listening structure / Phone evidence 语义、typed status、
  布局入口和端到端验证。
  验证: documentation-only change；`git diff --check` 通过。

- 2026-07-01 10:36 CST: 修复 Phase 2.18 后旧本地库 schema 漂移导致的媒体/字幕断链。
  (1) **Destructive repair migration**: SQLite schema 升到 v16，新增
  `0016_destructive_lexical_reset.sql`，重建 `LexicalEntry + LexicalUnit`
  所需的 lexical/learning-resource 表，清理旧 v7 lexical schema。
  (2) **Runtime impact**: 修复已有库 `user_version=15` 但缺少
  `lexical_observations`、`granularity`、`normalization`、`normalized_key`
  时，媒体注册、SRT 导入和字幕增强加载被 `no such table/column` 阻断的问题。
  (3) **Custom Whisper DTW**: 自定义 whisper.cpp 模型不再因为
  `family=custom` 跳过 `-dtw`；现在会从 `display_name`/`local_path`
  解析 stock preset，覆盖 `ggml-large-v3-q5_0.bin` 等量化文件名，恢复
  Whisper 生成字幕后的 WordTimeline/Chunk 材料。
  (4) **Regression**: 新增坏库回归测试，模拟旧 0007 已跑完且版本号已到 15 的真实形态，
  确认迁移到 v16 后表结构恢复且旧词库数据按当前断代策略丢弃。
  验证: `cargo test -p persistence-sqlite -- --nocapture`、
  `cargo test -p api-http dtw -- --nocapture`、
  `cargo test -p api-http --test api_integration_test -- --nocapture`、
  `./scripts/test.sh --quick --json` 通过；复制坏库的真实 HTTP media register + SRT import
  smoke 通过。

- 2026-07-01 CST: 合并 testing-system-buildout 后清理 main 既有 analyze 告警——
  移除 `test/controllers_test.dart:233` 与 `test/timeline_resource_summary_panel_test.dart:33`
  中 `rhythmFrames: const []` 冗余的 `const`（`unnecessary_const`，随 Phase 2.21 韵律
  提交引入，非本次合并造成）。零行为变化，`flutter analyze` 恢复 0 issue。

- 2026-07-01 00:46 CST: Phase 2.21 W8 local product QA pack。
  (1) **Artifact remap fix**: LLTimeline import now remaps
  `rhythm_word_acoustic_cues.payload.timeline_id` and cue `sentence_id` alongside
  WordTimeline/sentence ids, so imported production-side energy artifacts remain
  attached to generated RhythmFrames.
  (2) **Local W8 pack**: refreshed Brooklyn product media into
  `.tmp/rhythm-frame-qa/w8-product/brooklyn-w8.lltimeline.json` with 114
  `wordtimeline_timing_acoustic_prominence_v1` RhythmFrames; selected 10 QA
  sentences and generated `annotations-template.jsonl`, `selected-sentences.md`,
  and 10 wav clips under `.tmp/rhythm-frame-qa/w8-product/`.
  (3) **Gate honesty**: empty annotation templates validate but no longer count
  as manual annotations; the generated W8 template still reports
  `annotated_sentence_count = 0` until human labels are filled.
  验证: `cargo test -p application --quiet`、`python3 scripts/test_evaluate_rhythm_frame.py`
  通过；Brooklyn W8 readiness gate reports 114 WordTimeline+energy RhythmFrames.

- 2026-07-01 00:18 CST: Phase 2.21 W8 product QA tooling checkpoint。
  (1) **Manual QA contract**: RhythmFrame annotation schema, sample labels,
  committed fixture labels, and scorer now include `nuclei` and
  `connected_speech_refs` as first-class manual QA fields.
  (2) **W8 gates**: `evaluate-rhythm-frame.py` can emit capped templates that
  skip missing RhythmFrame rows and can gate minimum RhythmFrame sentence count,
  WordTimeline RhythmFrame count, and energy-prominence RhythmFrame count.
  (3) **Readiness honesty**: current local Phase 2.17 real-media artifacts are
  measurable but not closeout-ready: 47 selected sentences have only 1 old v0
  phone-timeline RhythmFrame, 0 WordTimeline RhythmFrames, 0 energy-prominence
  RhythmFrames, and 0 manual labels. Next step is regeneration with the current
  production pipeline, then manual labels.
  验证: `python3 scripts/test_evaluate_rhythm_frame.py` 通过；fixture W8 gate 通过。

- 2026-06-30 23:32 CST: Phase 2.21 review backlog W6 information-structure
  prominence prior。
  (1) **Text prior**: RhythmFrame anchor scoring now lightly down-weights repeated
  content words and gives phrase-final content a small focus boost.
  (2) **Honesty invariant**: this remains `TextPrior`; it adjusts prominence and
  confidence but never upgrades a claim to `AudioSupported` without timing,
  energy, pitch, or phone evidence.
  (3) **Tests/docs**: added a unit test for repeated-content downweighting and
  phrase-final focus boost; synced phase/codebase docs.
  验证: `cargo test -p speech-analysis --quiet` 通过。

- 2026-06-30 23:29 CST: Phase 2.21 review backlog W5 Reference A OOV fallback
  hardening。
  (1) **Fallback v2**: `speech-analysis` pronunciation provider version updated
  to `74790861+fallback-v2`; CMUdict-missing words now use a deterministic G2P
  fallback with common English digraphs, soft c/g, final silent e, and x handling.
  (2) **Stress honesty**: fallback phones now assign a single primary stress to
  the first fallback vowel and mark later fallback vowels unstressed, instead of
  treating every OOV vowel as primary stress.
  (3) **Tests/docs**: added a unit test for fallback stress behavior and synced
  phase/codebase docs.
  验证: `cargo test -p speech-analysis --quiet` 通过。

- 2026-06-30 23:24 CST: Phase 2.21 review backlog W4 energy cue live path
  arch slice。
  (1) **Production-side provider**: `scripts/timeline-production/production_pipeline.py`
  now computes per-word RMS relative energy from extracted 16k mono wav and writes
  a `rhythm_word_acoustic_cues` LLTimeline artifact with `energy_prominence`,
  `dbfs`, and sentence-median delta diagnostics. Failures degrade to a diagnostics
  artifact instead of breaking WordTimeline production.
  (2) **Application consumption**: LLTimeline export parses active WordTimeline
  matching acoustic cue artifacts and passes them into `RhythmWordAcousticCue`;
  generated document-level RhythmFrames can now report
  `wordtimeline_timing_acoustic_prominence_v1` and include `energy` in
  `quality.prominence_sources`.
  (3) **Tests/docs**: API export/import regression now verifies artifact →
  RhythmFrame energy provenance; added production pipeline synthetic-wav test and
  synchronized phase/codebase docs. W8 manual QA remains required before RMS
  calibration becomes a release gate.
  验证: `python3 scripts/timeline-production/test_production_pipeline_acoustic_cues.py`、
  `python3 scripts/test_prepare_rhythm_acoustic_qa.py`、
  `cargo test -p application -p api-http -p speech-analysis --quiet` 通过。

- 2026-06-30 23:13 CST: Phase 2.21 review backlog W3 Reference B connected-form
  rule engine。
  (1) **Reference B engine**: 新增
  `speech-analysis::connected_speech_rules`，用英语文本生成 default connected forms，
  覆盖 closed weak-form lexicon、`could have -> K UH D AH V`、want/going to、did you、
  linking、t/d weakening、contraction、assimilation 和 flapping candidates。
  (2) **A/B/C divergence**: `SoundAnalysis.connected_speech` 和
  `RhythmFrame.connected_speech_refs` 会合并 B rules 与 CTC L4 evidence；B-matched
  audio 标为 `teachable_rule` 并带 `text_prior + phone_segmental`，B-unmatched audio
  才标为 `clip_specific`。纯 B prediction 保持 `TextPrior` / `Predicted`。
  (3) **Fixtures/UI tests**: default_connected source 统一为
  `english_connected_speech_rules_v1`；no-phone document-level fixture 现在包含
  text-prior connected refs，但 `phone_evidence_coverage` 仍为 `0.0`。
  (4) **Planning sync**: 同步 PLAN、CONTEXT、STATE、handoff、ARCHITECTURE、
  DATA-MODEL、TESTING 和 QA README；后续优先级前移到 W4 product-side energy QA 和
  W5/W6 text-prior hardening。
  验证: `cargo test -p speech-analysis --quiet`、
  `cargo test -p domain -p application -p api-http -p speech-analysis --quiet`、
  `python3 scripts/test_evaluate_rhythm_frame.py`、
  `python3 scripts/test_evaluate_helsinki_prosody.py`、
  `cd apps/desktop && $HOME/.local/share/flutter/bin/flutter test test/timeline_test.dart test/phoneme_ribbon_test.dart test/diagnosis_card_test.dart` 通过。

- 2026-06-30 22:57 CST: Phase 2.21 review backlog W2 first-class WordTimeline →
  RhythmFrame path。
  (1) **Named resource path**: `LLTimelineDocument` 新增 document-level
  `rhythm_frames`，OpenAPI / Rust domain / Flutter typed model 同步解析；export 会
  从 active WordTimeline + dictionary/canonical stress 生成 `wordtimeline-rhythm-frame`
  resource，不经 phonetic-analysis job、PhoneTimeline 包装或 synthetic phones。
  (2) **UI consumption**: subtitle rhythm layer 现在按 sentence 优先使用
  `LLTimelineDocument.rhythm_frames`，没有 document-level frame 时才 fallback 到
  `PhoneTimeline.sound_analysis.rhythm_frame`。
  (3) **Scorer + fixture**: RhythmFrame scorer 会消费 document-level rhythm frames；
  no-phone committed fixture 已迁移为 `phone_timelines: []` + `rhythm_frames`，证明
  WordTimeline-only JSON 消费路径。
  (4) **Planning sync**: 同步 PLAN、CONTEXT、STATE、handoff、ARCHITECTURE、
  DATA-MODEL、TESTING 和 QA README；后续优先级前移到 W3 default connected-form B
  reference、W4 product-side energy provider 和 W5/W6 text-prior hardening。
  验证: `cargo test -p domain -p application -p api-http -p speech-analysis --quiet`、
  `python3 scripts/test_evaluate_rhythm_frame.py`、
  `python3 scripts/test_evaluate_helsinki_prosody.py`、
  `python3 scripts/test_prepare_rhythm_acoustic_qa.py`、
  `./scripts/validate-contracts.sh`、
  `cd apps/desktop && $HOME/.local/share/flutter/bin/flutter test test/timeline_test.dart test/controllers_test.dart test/timeline_resource_summary_panel_test.dart test/phoneme_ribbon_test.dart test/diagnosis_card_test.dart`、
  `cargo fmt --check`、Flutter bundled `dart format --set-exit-if-changed`
  和 `git diff --check` 通过。

- 2026-06-30 22:32 CST: Phase 2.21 review backlog W1 honesty fix。
  (1) **Timing-source provenance**: `speech-analysis::sound_analysis` 的
  `RhythmToken` 现在记录 `timing_audio_supported`，只有 `ForcedAligned` /
  `AsrAligned` / `UserAdjusted` WordTiming 会把 duration/gap/rate 解释成 `Timing`
  signal source；`Estimated` timing 输出 `wordtimeline_estimated_prominence_v1`、
  `quality.timing_source = word_timeline_estimated` 和 text-prior-only provenance。
  (2) **Claim status**: stress anchors、weak groups、compression spans、phrase
  boundaries 和 listening hotspots 不再因为 estimated timing 被标成
  `AudioSupported`；estimated timing 反例不会选 phrase-scoped nucleus。
  (3) **Planning sync**: 同步 2.21 PLAN、STATE 和 handoff，把后续优先级切到 W2
  first-class WordTimeline → RhythmFrame path、W3 default connected-form rules 和
  W4 product-side energy provider。
  验证: `cargo test -p domain -p application -p speech-analysis --quiet`、
  `python3 scripts/test_evaluate_rhythm_frame.py`、
  `python3 scripts/test_evaluate_helsinki_prosody.py`、
  `python3 scripts/test_prepare_rhythm_acoustic_qa.py`、
  `./scripts/validate-contracts.sh`、
  `cd apps/desktop && $HOME/.local/share/flutter/bin/flutter test test/phoneme_ribbon_test.dart test/diagnosis_card_test.dart`、
  `cargo fmt --check`、Flutter bundled `dart format --set-exit-if-changed`
  和 `git diff --check` 通过。

- 2026-06-30 18:27 CST: Phase 2.21 Step 2 补齐 energy cue seam 与 no-phone
  committed fixture。
  (1) **Energy provenance seam**: `SoundAnalysisConfig` 新增 sentence-scoped
  `RhythmWordAcousticCue`，`speech-analysis::sound_analysis` 会把 word-level
  `energy_prominence` 传播到 stress anchor prominence、phrase-scoped nucleus
  selection、`generated_from = wordtimeline_timing_acoustic_prominence_v1`、
  `references.actual.source = word_timeline_duration_energy` 和
  `quality.prominence_sources`；application builder 当前显式传 `None`，等待正式
  product audio feature provider。
  (2) **No-phone JSON proof**: 新增
  `testdata/rhythm-frame-qa/fixture-no-phone-rhythm.lltimeline.json` 并纳入 committed
  manifest/scorer smoke，覆盖 `phone_evidence_coverage = 0.0`、无
  `connected_speech_refs` 但仍可消费 anchors/nuclei/weak/compression/boundary/hotspot。
  (3) **Tests/docs**: Rust 单测覆盖 energy cue provenance 与 nucleus selection；
  Python scorer 单测断言 no-phone fixture 的 coverage/source/counts；同步 STATE、
  handoff、codebase docs 和 QA README。
  验证: `cargo test -p domain -p application -p speech-analysis --quiet`、
  `python3 scripts/test_evaluate_rhythm_frame.py`、
  `python3 scripts/test_evaluate_helsinki_prosody.py`、
  `python3 scripts/test_prepare_rhythm_acoustic_qa.py`、
  `./scripts/validate-contracts.sh`、
  `cd apps/desktop && $HOME/.local/share/flutter/bin/flutter test test/phoneme_ribbon_test.dart test/diagnosis_card_test.dart`、
  `cargo fmt --check`、Flutter bundled `dart format --set-exit-if-changed`
  和 `git diff --check` 通过。

- 2026-06-30 18:13 CST: Phase 2.21 Step 2 先接入 WordTimeline-driven RhythmFrame
  generation boundary。
  (1) **Generator seam**: `SoundAnalysisConfig` 新增 sentence-scoped `WordTiming`
  输入，`speech-analysis::sound_analysis` 在构造 RhythmFrame L1-L3 时优先使用 active
  WordTimeline timing + dictionary/canonical syllable stress，输出
  `generated_from = wordtimeline_timing_prominence_v1` 和
  `quality.timing_source = word_timeline`；无 WordTimeline 时才退回
  `phone_timeline_transitional`。
  (2) **Application wiring**: research fixture 和 CTC phonetic-analysis builder 在生成
  `sound_analysis` 前读取 active WordTimeline 的当前句 timings 并传入 generator，
  让 API refresh/export 产生的 JSON 开始走 WordTimeline-first L1-L3 substrate。
  (3) **No-phone proof**: 新增 Rust 单元测试，证明 observed CTC phone evidence absent
  时仍能从 WordTimeline + canonical stress 生成 anchors、phrase-scoped nuclei、weak groups、
  compression spans 和 phrase boundaries；CTC phone evidence coverage 保持 `0.0`。
  (4) **Planning sync**: 同步 STATE、handoff 和 ARCHITECTURE；下一刀继续把 RMS
  energy/loudness cue 从 experiment harness 接入 product-side generator。
  验证: `cargo test -p speech-analysis --quiet`、`cargo test -p application --quiet`、
  `python3 scripts/test_evaluate_rhythm_frame.py`、`python3 scripts/test_evaluate_helsinki_prosody.py`、
  `python3 scripts/test_prepare_rhythm_acoustic_qa.py`、
  `cd apps/desktop && $HOME/.local/share/flutter/bin/flutter test test/phoneme_ribbon_test.dart test/diagnosis_card_test.dart`、
  `./scripts/validate-contracts.sh` 通过。

- 2026-06-30 18:00 CST: Phase 2.21 Step 1 重写 `RhythmFrame` contract 到 audible
  structure v1。
  (1) **Contract/model**: `crates/domain/src/sound_analysis.rs`、OpenAPI 和 Flutter
  typed model 新增 A/B/C `references`、`RhythmSignalSource`、`RhythmEvidenceClass`、
  `RhythmClaimStatus`、prominence cues、phrase-scoped `nuclei`、
  `connected_speech_refs` 和 signal-source aware `quality`。
  (2) **Generator bridge**: 当前 `speech-analysis` 输出改为
  `legacy_phone_timing_adapter_v1` / `phone_timeline_transitional`，以新字段表达
  predicted vs audio-supported provenance；CTC phone evidence 只通过 L4
  connected-speech refs/hotspots 暴露，不再作为 L1-L3 contract truth。
  (3) **UI/evaluation/fixtures**: 字幕 rhythm ribbon 和 diagnosis card 显示 nucleus 与
  provenance；RhythmFrame QA scorer 和 Helsinki scorer 输出 signal source / evidence
  class 汇总；committed RhythmFrame/Helsinki fixtures 替换为 2.21 shape，不保留 v0
  `quality.timing_source = phone_timeline` 假设。
  (4) **Planning sync**: 同步 `.planning/STATE.md`、handoff 和 codebase
  ARCHITECTURE/DATA-MODEL/TESTING，把 Phase 2.21 下一步改为 WordTimeline +
  duration/energy generation boundary。
  验证: `cargo test -p domain -p speech-analysis --quiet`、`cargo test -p domain -p application --quiet`、
  `python3 scripts/test_evaluate_rhythm_frame.py`、`python3 scripts/test_evaluate_helsinki_prosody.py`、
  `python3 scripts/test_prepare_rhythm_acoustic_qa.py`、
  `cd apps/desktop && $HOME/.local/share/flutter/bin/flutter test test/phoneme_ribbon_test.dart test/diagnosis_card_test.dart`、
  `./scripts/validate-contracts.sh`、`cargo fmt --check`、Flutter bundled `dart format --set-exit-if-changed`
  和 `git diff --check` 通过。

- 2026-06-30 17:37 CST: 将 actual audible structure contract 从 Phase 2.20 中拆出为
  独立 Phase 2.21。
  (1) **New phase**: 新增
  `.planning/phases/2.21-audible-structure-architecture/2.21-CONTEXT.md`、
  `2.21-PLAN.md` 和 `2.21-AUDIBLE-STRUCTURE-MODEL.md`，单独推进 audible-structure
  架构锁、RhythmFrame contract rewrite、WordTimeline + duration/energy substrate 和
  provenance model。
  (2) **Compatibility decision**: 明确旧 `RhythmFrame` v0、旧 fixture、旧本地 artifact
  兼容性不再阻塞本 phase；正确 structure 优先。
  (3) **Model normalization**: 将 rhythm group/foot 改为可吸附前置或后置 weak material，
  将 default connected form 定义为 ranked/contextual variants，将 nucleus 改为 phrase-scoped
  candidate 并允许低证据 abstain，同时加入 syllable timing seam。
  (4) **Planning sync**: 同步 `STATE.md`、`ROADMAP.md` 和 handoff，把 Phase 2.20 定位为
  UI/实验/评测铺垫，把 Phase 2.21 设为当前结构主线。
  验证: documentation-only phase split, `git diff --check` 通过。

- 2026-06-30 13:41 CST: 为 Phase 2.20 D -> F 路线补上 duration/RMS manual QA
  对比实验工具。
  (1) **Experiment harness**: 新增 `scripts/prepare-rhythm-acoustic-qa.py`，
  读取 manifest / LLTimeline / 本地音频，按句输出 current CTC-derived
  `RhythmFrame`、active WordTimeline duration/rate 特征和 per-word RMS energy/loudness
  对比；非 wav 媒体通过本机 `ffmpeg` 解码，所有新 evidence 标为
  `heuristic_proxy` / `manual_product_qa_input`，不写回产品资源。
  (2) **Manual QA template**: 脚本支持 `--emit-template` 输出兼容现有
  RhythmFrame manual annotation schema 的 JSONL，并把三路系统候选放入
  `system_compare`，用于 5-10 句人工听感标注。
  (3) **Tests/docs**: 新增 `scripts/test_prepare_rhythm_acoustic_qa.py`，用合成 wav
  fixture 覆盖 active WordTimeline、current RhythmFrame、duration/rate candidate、
  RMS prominence candidate 和 template CLI；同步 Phase 2.20 evaluation、STATE 和
  handoff。
  验证: `python3 -m py_compile scripts/prepare-rhythm-acoustic-qa.py scripts/test_prepare_rhythm_acoustic_qa.py`、
  `python3 scripts/test_prepare_rhythm_acoustic_qa.py`、
  `python3 scripts/test_evaluate_rhythm_frame.py`、
  `python3 scripts/prepare-rhythm-acoustic-qa.py --manifest testdata/sound-line-real-media/manifest.jsonl --case-id p217-brooklyn-news-001 --limit 1`
  的等价 import smoke（1 句 scored，ffmpeg 音频加载成功，WordTimeline timing present）、
  `git diff --check` 通过。
- 2026-06-30 21:05 CST: 收口修复——移除 `test/builder_test.dart` 冗余的
  `package:flutter/foundation.dart` import（`material.dart` 已提供 `@immutable`），
  全项目 `flutter analyze` 恢复 0 issue。收口验证：`flutter analyze` 干净、
  `flutter test`（115）、`cargo test -p api-http -p persistence-sqlite` 全绿。

- 2026-06-30 20:52 CST: 兑现 A1——用新解锁的 transport seam 为两个 workflow controller
  补测试（此前因 `LocalApi` 不可注入完全无法单测）。
  (1) **`learning_workflow_controller_test.dart`**（7 测试）：`refreshDiagnosis` 的
  generation guard——happy、null cue 清空、**新请求超越时丢弃 stale 结果**、切换 cue 后
  丢弃、diagnose 错误映射为 null；`loadPhraseCandidates` 经 `LocalApi.withTransport`
  端到端加载与 null-api 清空。
  (2) **`speech_enhancement_workflow_controller_test.dart`**（2 测试）：
  `loadTimelineResource` 降级——4 个子资源全失败→`unavailable`、部分失败→warning 且不
  误报 unavailable。
  验证: `flutter analyze`（0 issue）、`flutter test`（106→115 全绿）。

- 2026-06-30 20:30 CST: 收口 Tier A 测试，并修复架构债 A1（`LocalApi` transport 非注入），
  这是第一处"架构修复解锁测试"的闭环。
  (1) **A1 seam（生产代码，行为不变）**：`apps/desktop/lib/services/api_service.dart`
  抽出 `ApiTransport` typedef + `LocalApi.withTransport(...)` 测试构造器；`_request`
  （79 个调用点）改走 `_transport ?? _httpClientTransport`，默认实现保留原样 header/请求
  逻辑。生产路径字节级不变；SSE 与上传/下载 3 处特殊 `_client` 裸调暂留。
  (2) **解锁的测试**：新增 `apps/desktop/test/api_service_transport_test.dart`（3 测试）：
  GET 经 seam 解码、非 2xx → `HttpException`、PUT body 编码经 seam 转发。
  (3) **文档**：`CONCERNS.md` A1 标记已修复（§1/§6），记录后续补方法级/controller 测试；
  `TESTING.md` 同步。
  验证: `flutter analyze`（api_service + 新测试，0 issue）、`flutter test`（103→106 全绿）。
  合并摩擦评估：main（Phase 2.21 韵律）未触及 `api_service.dart` 及本 worktree 测试目标，
  唯一保证冲突是 CHANGELOG.md（琐碎可解）。

- 2026-06-30 20:05 CST: Tier A 续作——补 SQLite 迁移失败恢复刻画测试（CONCERNS §2/§3
  点名的脆弱区，至今无自动化）。新增
  `crates/persistence-sqlite/tests/migration_recovery_test.rs`（4 测试）：
  (1) 升级落后版本旧库时创建 `<path>.pre-migration.bak`，备份保留迁移前版本与内容；
  (2) 全新库（路径不存在）不创建备份；
  (3) 重开最新版本库幂等、不再创建备份；
  (4) **迁移失败时**（预置 `media_items` 表与裸 `CREATE TABLE` 迁移 0001 冲突）原库
  完整保留在备份中可恢复，且 live 库 `user_version` 不前进。
  刻画当前真实行为，作为后续迁移系统重构的安全网。
  验证: `cargo test -p persistence-sqlite --test migration_recovery_test`（4/4）。

- 2026-06-30 14:34 CST: Tier A 续作——api-http 集成测试覆盖 lexical entry 学习核心
  生命周期。`api_integration_test.rs` 新增 1 条：PUT `/v1/lexical-entries` upsert（word，
  status=unknown_meaning）→ GET 列表按 language/kind 命中 → GET `/{id}` 详情往返 →
  PUT `/{id}/learning-content` 持久化 user_definition / personal_note。新增 `put_json` 助手。
  验证: `cargo test -p api-http --test api_integration_test`（11/11）。

- 2026-06-30 14:28 CST: Tier A 续作——补 Flutter 状态层 widget 测试，并记录 A1 对
  workflow controller 测试的硬阻塞。
  (1) **Store builder 测试**: 新增 `apps/desktop/test/builder_test.dart`，覆盖
  `StoreBuilder` / `StoreBuilder2` 的选择性重建（无关字段不重建、选中字段才重建、
  equal-state no-op，4 测试）。
  (2) **A1 证据加固**: `CONCERNS.md` §1 记录 `LocalApi` 只有私有构造 `LocalApi._`、
  唯一入口 `connect()` 起真实 sidecar，测试连子类伪造都做不到；`LearningWorkflowController`
  / `SpeechEnhancementWorkflowController` 直接持有 `LocalApi`，单测被此 seam 挡死，
  确认延后到 A1 修复后。
  验证: `flutter test test/builder_test.dart`（4/4）。

- 2026-06-30 14:21 CST: 在测试体系建设期对架构做证据化审计并记录到 `CONCERNS.md`，
  决定走"测试优先安全网"——先记录、继续铺测试、收口后再统一修架构。
  (1) **新增待修复登记**（§6）：A1 `LocalApi` transport 非注入（`api_service.dart:49`，
  挡住 Tier A 客户端单测，该项测试延后到 seam 修复后）；A2 `build_word_timeline` /
  `save_word_timeline_snapshot` 参数过多（`application/src/lib.rs:213`/`:292`，clippy
  `too_many_arguments`）；A3 workspace clippy warning 漂移；A4 `speech-analysis` 拆 crate、
  A5 `domain/lib.rs` 拆分（结构性大改，先出评审再动）。
  (2) **已证伪**：`AppServices::new` 8 参数是接口隔离（ISP），非 smell，不修。
  (3) **刷新过期条目**：§3 测试缺口表中 application/api-http 集成测试更新为"🟡 部分"，
  指向 `crates/api-http/tests/api_integration_test.rs`。
  验证: documentation-only，`git diff --check` 通过。

- 2026-06-30 14:07 CST: Tier A 续作——扩 `api-http` 全栈集成测试路由覆盖，
  仍为纯测试改动。`api_integration_test.rs` 新增 3 条：
  (1) **LLTimeline 资源契约**: 导入 `testdata/lltimeline/v1-minimal.lltimeline.json`
  完整文档 → 200 SubtitleTrack，并验证捆绑的 word timeline 随文档持久化。
  (2) **Word timeline 生命周期**: `create`（candidate）→ `activate`（active），
  覆盖播放器消费的核心资源激活路径。
  (3) **Diagnosis 端点**: 对导入字幕的句子返回结构良好的 `SentenceDiagnosis`。
  验证: `cargo test -p api-http --test api_integration_test`（10/10）；
  测试文件零新增 clippy warning（workspace 既有 lint 漂移与本改动无关）。

- 2026-06-30 14:01 CST: 启动测试体系建设 Tier A（worktree `testing-system-buildout`），
  落地跨语言后端栈与前端状态/推送层的基础测试，零生产代码改动。
  (1) **Rust 全栈集成**: 新增 `crates/api-http/tests/api_integration_test.rs`，
  以真实 `router(ApiState::new(...))` + `SqliteRepository::in_memory()`、`tower::oneshot`
  进程内驱动 `api-http → application → persistence` 整栈（鉴权拒绝、health、media
  注册/读取/404、字幕导入往返、archive/restore/delete 生命周期，7 测试）。
  (2) **Flutter SSE 推送核心**: 新增 `apps/desktop/test/backend_event_coordinator_test.dart`，
  覆盖 `BackendEventCoordinator` 全部分发分支（service-started、转写 job completed/in-progress/
  跨 media、音素 job primary/非 primary、lexical-entry 转发、未知事件 no-op，9 测试）。
  (3) **Flutter 状态容器**: 新增 `apps/desktop/test/store_test.dart`，覆盖 `Store<T>`
  selector 身份 memoize、字段级精准通知、equal-state no-op、replace 刷新（6 测试）。
  (4) **路线决策**: `api_service.dart`（`dart:io HttpClient`，非注入式）的全栈消费契约
  归入 Tier B 真实 sidecar E2E，本阶段不为凑覆盖改造生产客户端；`.planning/codebase/TESTING.md`
  第 9 节记录 Tier A/B/C 建设路线与缺口状态。
  验证: `cargo test -p api-http`（7/7）、`flutter test`（84→99 全绿）、`flutter analyze` 干净。
  既有遗留: `api-http` lib `lib.rs:823` 有 3 个既有 clippy let-chains warning（非本次引入），
  `--strict` 下会红，留待单独清理。

- 2026-06-30 13:29 CST: Phase 2.20 路线复盘后更新交接文档，准备新 session 继续推进。
  (1) **Route correction**: 新增
  `.planning/phases/2.20-rhythm-first-listening-analysis/2.20-ROUTE-CORRECTION.md`，
  明确 Phase 2.20 的目标是 actual audible structure，而不是 default predicted reading；
  `RhythmFrame` contract/UI/QA 继续保留，但 generator 主线从 CTC-derived rhythm skeleton
  迁移到 forced-aligned WordTimeline + duration/rate + RMS energy/loudness，F0/pitch reset
  作为校准后的正式候选。
  (2) **Acoustic path revision**:
  `2.20-ACOUSTIC-FEATURE-PATH.md` 已改为路线修订说明，重新定位
  `pre_boundary_lengthening` 为 fallback/diagnostic `heuristic_proxy`，不再把本地缺少
  `librosa`/Parselmouth 等包当作不上 production-side acoustic prosody 的理由。
  (3) **Handoff**: 重写 `.planning/handoff/continue-here.md`，记录最新 20 句
  Helsinki/LibriTTS diagnostic（stress anchor F1 `0.574949`、phrase boundary F1
  `0.210145`、boundary evidence `pause=218` / `pre_boundary_lengthening=17`）和下一步
  D -> F 对比实验：current CTC-derived RhythmFrame vs forced-aligned WordTimeline +
  duration/rate vs WordTimeline + RMS energy。
  (4) **Planning sync**: 同步 `2.20-PLAN.md`、`2.20-ALGORITHM-METRICS-RESEARCH.md`、
  `2.20-EVALUATION.md` 和 `.planning/STATE.md`，明确 CTC phone evidence 降级为
  flapping/deletion/weak-form/phone-mismatch 等 segmental evidence，不再当 rhythm skeleton。
  验证: documentation-only handoff update, `git diff --check` 通过。

- 2026-06-30 12:57 CST: 将 Phase 2.20 算法/指标原则写入 agent 入口，并让
  Helsinki/LibriTTS scorer 输出基准上下文。
  (1) **Agent rule**: `AGENT.md` 新增 Algorithms And Metrics 原则，明确项目已有数据、
  小样本 smoke、自动标签和当前指标不默认视为正确答案；算法、指标和阈值应尽量来自
  published research、corpus annotation convention、reported tool baseline 或 manual product
  QA；有依据时可以大胆试，但要记录 `gold` / `silver_label` / `heuristic_proxy` /
  `manual_product_qa` / `coverage` evidence class。
  (2) **Benchmark context**: `scripts/evaluate-helsinki-prosody.py` 在每个报告中输出
  `benchmark_context`，标明 Helsinki/LibriTTS 是 `weak_prosody_regression` /
  `silver_label`，记录 prominence/boundary label 语义、Talman et al. 2019 BERT text-model
  prominence baselines（2-way accuracy `0.832`、3-way accuracy `0.686`）和不能直接与
  end-to-end audio RhythmFrame F1 比较的 caveat。
  (3) **Docs/tests**: 同步 rhythm-prosody README、Phase 2.20 evaluation/plan 和
  `.planning/STATE.md`，并让 Helsinki scorer 单测校验报告上下文。
  验证: `python3 -m py_compile scripts/evaluate-helsinki-prosody.py scripts/test_evaluate_helsinki_prosody.py`、
  `python3 scripts/test_evaluate_helsinki_prosody.py`、
  `python3 scripts/evaluate-helsinki-prosody.py --prosody-dir /Users/shadow/prosody --split dev --limit 3 --lltimeline-manifest .tmp/helsinki-libritts-rhythm-dev-smoke/manifest.jsonl`、
  `git diff --check` 通过。

- 2026-06-30 10:40 CST: 为 Phase 2.20 补齐算法/指标校准原则并跑通首个
  Helsinki/LibriTTS 真实 smoke。
  (1) **Research calibration**: 新增
  `.planning/phases/2.20-rhythm-first-listening-analysis/2.20-ALGORITHM-METRICS-RESEARCH.md`，
  明确当前项目指标、小样本 smoke、Helsinki automatic labels 都只是 diagnostic/silver
  signal；后续算法与 gate 需要对齐 published prosody/phonetics baselines、corpus annotation
  convention 或 manual product QA。
  (2) **Local smoke**: 使用 `.tmp/helsinki-libritts-rhythm-dev-smoke/manifest.jsonl`
  跑通本地 API refresh，3/3 LibriTTS/Helsinki dev 样本生成 `sound_analysis.rhythm_frame`；
  diagnostic Helsinki silver-label score 为 stress anchor F1 `0.827586`、phrase boundary F1
  `0.285714`。该结果只记录为 pipeline diagnostic，不作为 closeout gate。
  (3) **Scorer/algorithm hygiene**: `scripts/evaluate-helsinki-prosody.py` 修正 LLTimeline
  raw token index 到 word index 的映射，并在 API 导入重映射 sentence id 后回退到文本匹配；
  `speech-analysis` 的默认 stress anchor 规则避免把 function words 作为主 anchor，并扩展
  常见英语 function-word 列表。
  验证: `PATH="/opt/homebrew/opt/rustup/bin:$PATH" cargo test -p speech-analysis sound_analysis --quiet`、
  `PATH="/opt/homebrew/opt/rustup/bin:$PATH" cargo fmt --check`、
  `python3 scripts/test_evaluate_helsinki_prosody.py`、
  `python3 scripts/test_prepare_helsinki_libritts_benchmark.py`、
  `python3 scripts/evaluate-helsinki-prosody.py --prosody-dir /Users/shadow/prosody --split dev --limit 3 --lltimeline-manifest .tmp/helsinki-libritts-rhythm-dev-smoke/manifest.jsonl`
  通过。

- 2026-06-30 10:20 CST: 打通 Helsinki/LibriTTS 本地 benchmark baseline 准备链路。
  (1) **Prep script**: 新增 `scripts/prepare-helsinki-libritts-benchmark.py`，可从 Helsinki
  Prosody labels 选择小样本，定位 LibriTTS `.wav`，生成 ignored baseline `.lltimeline.json`
  和 dual-use manifest；支持 extracted split directory，也支持
  `/Users/shadow/Downloads/dev-clean.tar.gz` / `test-clean.tar.gz` 这类 split archive，只抽取
  selected wav 到 `.tmp/.../audio`。
  (2) **Evaluator fix**: `scripts/evaluate-helsinki-prosody.py` 在 baseline artifact 尚无
  `phone_timelines` 时会基于 `segments` 识别句子，并报告 `missing_rhythm_frame`，不再误报
  `missing_sentence`。
  (3) **Tests/docs**: 新增 `scripts/test_prepare_helsinki_libritts_benchmark.py`，覆盖目录输入、
  archive 输入、missing audio 和 baseline LLTimeline shape；同步 rhythm-prosody README、
  Phase 2.20 evaluation/plan、`.planning/STATE.md` 和 `.planning/codebase/TESTING.md`。
  验证: `python3 -m py_compile scripts/evaluate-helsinki-prosody.py scripts/test_evaluate_helsinki_prosody.py scripts/prepare-helsinki-libritts-benchmark.py scripts/test_prepare_helsinki_libritts_benchmark.py`、
  `python3 scripts/test_evaluate_helsinki_prosody.py`、
  `python3 scripts/test_prepare_helsinki_libritts_benchmark.py`、
  `python3 scripts/prepare-helsinki-libritts-benchmark.py --prosody-dir /Users/shadow/prosody --libritts-archive /Users/shadow/Downloads/dev-clean.tar.gz --split dev --limit 3 --output-dir .tmp/helsinki-libritts-rhythm-dev-smoke`、
  `python3 scripts/evaluate-helsinki-prosody.py --prosody-dir /Users/shadow/prosody --split dev --limit 3 --lltimeline-manifest .tmp/helsinki-libritts-rhythm-dev-smoke/manifest.jsonl --include-sentences`
  通过。

- 2026-06-30 09:55 CST: 建立 Phase 2.20 Helsinki/LibriTTS weak-label prosody benchmark adapter。
  (1) **Scorer**: 新增 `scripts/evaluate-helsinki-prosody.py`，解析 Helsinki Prosody split
  文件，并用 prominence labels 评估 `RhythmFrame.stress_anchors`，用 word-boundary labels
  评估 `RhythmFrame.phrase_boundaries`；支持 `--prosody-dir`、`--labels`、
  `--lltimeline-manifest`、`--lltimeline-dir`、threshold 和 quality gate 参数。
  (2) **Fixture/tests**: 新增 `testdata/rhythm-prosody-benchmarks/`，包含可提交的
  Helsinki-style label fixture、LLTimeline fixture、manifest 和 README；新增
  `scripts/test_evaluate_helsinki_prosody.py` 覆盖 label parsing、RhythmFrame matching、
  missing-rhythm 状态和 committed fixture CLI gate。
  (3) **Docs**: 同步 Phase 2.20 benchmark research/evaluation/plan、`.planning/STATE.md`
  和 `.planning/codebase/TESTING.md`，明确 Helsinki labels 是 stress/boundary silver-label
  regression，不替代 weak group/compression/hotspot 的 manual product QA。
  验证: `python3 -m py_compile scripts/evaluate-helsinki-prosody.py scripts/test_evaluate_helsinki_prosody.py`、
  `python3 scripts/test_evaluate_helsinki_prosody.py`、
  `python3 scripts/evaluate-helsinki-prosody.py --labels testdata/rhythm-prosody-benchmarks/fixture-helsinki.txt --lltimeline-manifest testdata/rhythm-prosody-benchmarks/fixture-manifest.jsonl --min-scored-sentences 1 --min-anchor-f1 1.0 --min-boundary-f1 1.0 --fail-on-quality-gate`、
  `python3 scripts/evaluate-helsinki-prosody.py --prosody-dir /Users/shadow/prosody --split dev --limit 5`
  通过。

- 2026-06-30 00:00 CST: 重新组织 Phase 2.20 benchmark 方向为 stress/rhythm-first。
  (1) **Research**: 新增
  `.planning/phases/2.20-rhythm-first-listening-analysis/2.20-BENCHMARK-RESEARCH.md`，
  调研 Helsinki Prosody/LibriTTS、BU Radio Speech、Rhythm and Pitch Corpus、
  Aix-MARSEC/ProPOSEC、Buckeye、TED-LIUM、IViE、NXT Switchboard、Wav2ToBI 和
  ToBI references，并明确没有单一公开集能覆盖完整 learner-facing RhythmFrame 产品链路。
  (2) **Evaluation pivot**: `2.20-EVALUATION.md` 增加 benchmark roles：
  `evidence_quality`、`weak_prosody_regression`、`human_prosody_gold`、
  `product_listening_qa`、`robustness_probe`。
  (3) **Plan sync**: `2.20-PLAN.md` 将 TIMIT 调整为 evidence-layer sanity，
  将 Helsinki/LibriTTS 设为首选公开弱标签回归方向，将 BU/RaP/Aix 设为可选 human
  prosody gold，将 Buckeye/TED/product media 保留为 weak group/compression/hotspot
  产品 QA gate。
  验证: documentation-only change, `git diff --check` 通过。

- 2026-06-29 20:16 CST: 为 Phase 2.20 字幕层 rhythm 模式补齐 expected pronunciation reference。
  (1) **UI**: 新增 `ExpectedPronunciationReference`，按词展示词典 IPA，并按当前 token
  高亮当前词；无逐词 variant 时降级显示句级 `display_ipa`。
  (2) **Rhythm surface**: 主播放器在 sound pattern `rhythm` 模式中把 expected pronunciation
  放在 RhythmFrame 上方，使“预期读音”和“真实听感节奏”同屏出现；`phones` 模式仍保留为
  phone evidence 证据层。
  (3) **Localization/tests**: 新增中英本地化文案，`phoneme_ribbon_test.dart` 覆盖 expected
  reference 的词级 IPA 和 tooltip。
  验证: `$HOME/.local/share/flutter/bin/dart format --set-exit-if-changed apps/desktop/lib/main.dart apps/desktop/lib/localization.dart apps/desktop/lib/widgets/subtitle/expected_pronunciation_reference.dart apps/desktop/test/phoneme_ribbon_test.dart`、
  `cd apps/desktop && $HOME/.local/share/flutter/bin/flutter analyze`、
  `cd apps/desktop && $HOME/.local/share/flutter/bin/flutter test test/phoneme_ribbon_test.dart`、
  `cd apps/desktop && $HOME/.local/share/flutter/bin/flutter test`
  通过。

- 2026-06-29 20:07 CST: 为 Phase 2.20 字幕层 sound pattern 增加 rhythm/phones 就地快切。
  (1) **UI**: 新增 `SoundPatternModeToggle` 图标控件，在字幕层声音时间带旁用 rhythm /
  phone evidence 两个图标切换显示模式，不需要进入设置弹窗。
  (2) **State wiring**: 主播放器把快切接入现有 `sound_pattern_display_mode` 持久化设置，
  保持默认 rhythm-first，同时保留 phone evidence ribbon 作为可切换证据层。
  (3) **Tests**: `phoneme_ribbon_test.dart` 覆盖图标快切只在切到另一模式时触发回调。
  验证: `$HOME/.local/share/flutter/bin/dart format --set-exit-if-changed apps/desktop/lib/main.dart apps/desktop/lib/widgets/subtitle/sound_pattern_mode_toggle.dart apps/desktop/test/phoneme_ribbon_test.dart`、
  `cd apps/desktop && $HOME/.local/share/flutter/bin/flutter test test/phoneme_ribbon_test.dart`、
  `cd apps/desktop && $HOME/.local/share/flutter/bin/flutter analyze` 通过。

- 2026-06-29 20:03 CST: 为 Phase 2.20 字幕层 RhythmFrame ribbon 增加 cue loop 交互。
  (1) **UI**: `RhythmFrameRibbon` 新增可选 `onLoopCue` 回调，rhythm cue chip 在有回调时变为
  可点击目标，并保留 tooltip/semantics。
  (2) **Playback wiring**: 字幕层 rhythm 模式接入现有 source loop 逻辑，点击 anchor/weak/
  compression/hotspot chip 可循环播放对应听感区间；phone evidence ribbon 的原有 loop 行为不变。
  (3) **Tests**: `phoneme_ribbon_test.dart` 新增 rhythm cue loop callback 覆盖。
  验证: `$HOME/.local/share/flutter/bin/dart format --set-exit-if-changed apps/desktop/lib/widgets/subtitle/rhythm_frame_ribbon.dart apps/desktop/lib/main.dart apps/desktop/test/phoneme_ribbon_test.dart`、
  `cd apps/desktop && $HOME/.local/share/flutter/bin/flutter test test/phoneme_ribbon_test.dart`
  通过。

- 2026-06-29 20:02 CST: 为 Phase 2.20 RhythmFrame QA/scorer 增加仓库内可重复运行的
  committed fixture gate。
  (1) **Fixture**: 新增 `testdata/rhythm-frame-qa/fixture-manifest.jsonl`、
  `fixture-rhythm.lltimeline.json` 和 `fixture-annotations.jsonl`，用两句合成
  LLTimeline 覆盖 stress anchors、weak groups、compression spans、phrase boundaries
  与 listening hotspots，不依赖本地真实媒体或 ignored `.tmp` artifacts。
  (2) **Regression**: `scripts/test_evaluate_rhythm_frame.py` 新增 CLI smoke，验证
  strict annotation validation、`--fail-on-quality-gate`、1.0 rhythm coverage、2 条
  annotated sentences、0 misleading/unsupported hotspot gates。
  (3) **Docs**: 同步 `testdata/rhythm-frame-qa/README.md`、Phase 2.20 evaluation/plan、
  `.planning/STATE.md` 和 `.planning/codebase/TESTING.md`，明确 committed fixture 与
  本地真实媒体 QA 的边界。
  验证: `python3 -m py_compile scripts/evaluate-rhythm-frame.py scripts/test_evaluate_rhythm_frame.py`、
  `python3 scripts/test_evaluate_rhythm_frame.py`、
  `python3 scripts/evaluate-rhythm-frame.py --manifest testdata/rhythm-frame-qa/fixture-manifest.jsonl --annotations testdata/rhythm-frame-qa/fixture-annotations.jsonl --strict-annotations --min-rhythm-coverage 1.0 --min-annotated-sentences 2 --min-overall-useful-rate 1.0 --max-hotspot-misleading-rate 0.0 --max-hotspot-unsupported-rate 0.0 --fail-on-quality-gate`
  通过。

- 2026-06-29 19:40 CST: 建立 Phase 2.20 RhythmFrame QA/scorer 初版。
  (1) **Manual QA schema**: 新增 `testdata/rhythm-frame-qa/`，包含 annotation schema、
  sample JSONL 和标注/评分说明，覆盖 stress anchors、weak groups、compression spans、
  phrase boundaries、listening hotspots 与 `correct/useful_but_incomplete/unclear/misleading/unsupported`
  rubric。
  (2) **Scorer**: 新增 `scripts/evaluate-rhythm-frame.py`，可读取 Phase 2.17 manifest 和
  local-only LLTimeline artifacts，输出 `rhythm_frame` 覆盖率、每句结构摘要、manual label
  matching、hotspot score distribution 和 `summary.manual_qa` 聚合；支持 `--emit-template`
  生成标注模板，并支持 `--strict-annotations` 校验 duplicate、invalid score 和 unknown
  sentence target。新增 closeout quality gates：`--min-rhythm-coverage`、
  `--min-annotated-sentences`、`--min-overall-useful-rate`、
  `--max-hotspot-misleading-rate`、`--max-hotspot-unsupported-rate` 和
  `--fail-on-quality-gate`。
  (3) **Baseline**: 当前旧 `.tmp/sound-line-real-media` artifacts 为 8 cases / 51 phone timelines /
  0 rhythm frames，符合预期，因为这些 artifact 生成早于 Phase 2.20 `rhythm_frame` 字段；本机
  smoke 重跑 `p217-brooklyn-news-001 --sentence-limit 1` 后 scorer 可读到 1 条 refreshed
  RhythmFrame（ignored `.tmp` artifact，不提交）。
  验证: `python3 -m py_compile scripts/evaluate-rhythm-frame.py scripts/test_evaluate_rhythm_frame.py`、
  `python3 scripts/test_evaluate_rhythm_frame.py`、
  `python3 scripts/evaluate-rhythm-frame.py --manifest testdata/sound-line-real-media/manifest.jsonl`、
  `PATH="/opt/homebrew/opt/rustup/bin:$PATH" python3 scripts/run-sound-line-real-media-case.py --case-id p217-brooklyn-news-001 --sentence-limit 1`
  通过。

- 2026-06-29 15:28 CST: 将 Phase 2.20 RhythmFrame 推进到字幕层主显示。
  (1) **Subtitle layer**: 新增 `RhythmFrameRibbon`，在字幕下方直接展示 listening rhythm
  时间线、stress anchors、weak groups、compression spans、listening hotspots 和当前播放位置。
  (2) **Mode switch**: `sound_pattern_display_mode` 持久化为 `rhythm` / `phones` 两种模式；
  声音模式时间带默认 rhythm-first，原 phone evidence ribbon 保留为可切换证据层。
  (3) **Settings/UI**: 设置弹窗新增“声音时间带模式”，中英本地化同步；右侧诊断卡继续保留
  compact rhythm detail。
  验证: `dart format --set-exit-if-changed`、`git diff --check`、
  `cd apps/desktop && $HOME/.local/share/flutter/bin/flutter analyze`、
  `cd apps/desktop && $HOME/.local/share/flutter/bin/flutter test`、
  `cargo fmt --check`、`cargo test --workspace --quiet`、`./scripts/validate-contracts.sh` 通过。

- 2026-06-29 15:07 CST: 推进 Phase 2.20 RhythmFrame v0 纵切片。
  (1) **Resource shape**: `SoundAnalysis` 新增可选 `rhythm_frame`，OpenAPI 同步
  `RhythmFrame` / stress anchors / weak groups / compression spans / phrase boundaries /
  listening hotspots / quality schema；`SoundLearningPhone` 保留可选 lexical stress。
  (2) **Algorithm**: `speech-analysis::sound_analysis` 生成 deterministic rhythm-first
  baseline，融合 CMUdict/fallback lexical stress、function-word grouping、phone timing
  pause/duration 和 connected-speech evidence；raw phone mismatch 不会单独生成高置信默认听感解释。
  (3) **Flutter**: typed timeline model 解析 `rhythm_frame`，诊断卡在 phone evidence 前展示
  compact rhythm-first 区块（anchors、weak groups、compressed spans、hotspots、confidence）。
  (4) **Planning sync**: 更新 `.planning/STATE.md` 与 codebase 架构/数据模型/测试事实源。
  验证: `cargo test --workspace --quiet`、`./scripts/validate-contracts.sh`、
  `cd apps/desktop && flutter analyze`、`cd apps/desktop && flutter test` 通过。
  备注: `cargo clippy --workspace --all-targets -- -D warnings` 仍被既有 unrelated lint 阻塞
  （`chunk_partition.rs`、`phone_recognition.rs`、`forced_align.rs`）。

- 2026-06-29 14:37 CST: 补充 Phase 2.20 rhythm-first listening analysis 调研记录。
  新增 `.planning/phases/2.20-rhythm-first-listening-analysis/2.20-RESEARCH.md`，
  从英语听力认知、L2 connected speech、prosody annotation、参考工具/数据集和产品形态
  判断 rhythm-first 方向基本成立但需避免把 stress-timed English 当成绝对物理定律。
  同步 `2.20-PLAN.md` 指向该 research basis。
  验证: documentation-only change, not run.

- 2026-06-29 14:32 CST: 建立 Phase 2.20 rhythm-first listening analysis 新方向。
  (1) **Product pivot**: 将真实语流分析的默认产品中心从 phone-level ribbon 调整为
  rhythm-first listening frame，优先展示 stress anchors、weak groups、compression spans、
  phrase boundaries 和 listening hotspots；phone-level expected/observed alignment 保留为
  evidence layer 和长期模型质量工作。
  (2) **Phase docs**: 新增
  `.planning/phases/2.20-rhythm-first-listening-analysis/2.20-CONTEXT.md`、
  `2.20-PLAN.md` 和 `2.20-EVALUATION.md`，明确 UI surface、RhythmFrame resource shape、
  deterministic baseline、benchmark/manual QA 分层和 pipeline bottleneck attribution。
  (3) **Planning sync**: 同步 `.planning/PROJECT.md`、`.planning/REQUIREMENTS.md`、
  `.planning/ROADMAP.md`、`.planning/codebase/TESTING.md` 和 `.planning/STATE.md`，
  新增 RHY-001 至 RHY-008 需求，并把 Phase 2.19 phone benchmark scoring 定位为底层
  evidence-quality 支撑。
  验证: documentation-only change, not run.

- 2026-06-29 10:26 CST: 启动 Phase 2.19 real benchmark scoring 初始评估。
  (1) **Scorer**: 新增 `scripts/evaluate-sound-line-benchmarks.py`，从 Phase 2.17 manifest
  和 ignored `.tmp` artifacts 读取结果，并对 TIMIT `.PHN`、Buckeye `.phones`、TED-LIUM `.stm`
  做本地 reference 对比。
  (2) **初始结果**: TED-LIUM transcript/timing 对齐为 exact；Buckeye s0201a/s0301a 初始
  PER 分别约 0.304/0.352；Buckeye s0101a 与 TIMIT Phase 2.17 artifact 暴露明显窗口/映射问题，
  其中 TIMIT 小窗口 PER 约 0.874，显著差于历史 fb-espeak TIMIT dev baseline 0.304636。
  (3) **规划**: 新增 `.planning/phases/2.19-real-benchmark-scoring/2.19-PLAN.md` 和
  `2.19-INITIAL-RESULTS.md`，明确后续要排查 TIMIT sentence window、espeak symbol mapping、
  Buckeye lead-in filtering、boundary metrics 和 product-media manual listening precision。
  验证: `python3 -m py_compile scripts/evaluate-sound-line-benchmarks.py`、
  `python3 scripts/evaluate-sound-line-benchmarks.py --manifest testdata/sound-line-real-media/manifest.jsonl`、
  `python3 scripts/phonetic-eval.py score testdata/phonetic-analysis/reference-dev-v1-content-only.jsonl testdata/phonetic-analysis/prediction-fb-espeak-timit-mapped-v1.jsonl` 通过。

- 2026-06-29 10:15 CST: 收口 Phase 2.17 real-media sound-line QA。
  (1) **Headless runner**: 新增 `scripts/run-sound-line-real-media-case.py`，通过临时
  `api-http` + SQLite 执行 register media、LLTimeline import、句级 CTC phonetic job、poll 和
  export，不再依赖手点 UI 生成 PhoneTimeline。
  (2) **Runtime 修复**: CTC sidecar 启动环境现在自动注入 Homebrew `PATH` 和可用的
  `PHONEMIZER_ESPEAK_LIBRARY`；修复 `phonetic_alignment::backtrace` 在 detected index zero
  deletion 路径上的 `usize` 下溢 panic，避免 background job 卡在 `analyzing`。
  (3) **Artifact refresh**: 8 个 Phase 2.17 local-only 小窗口 artifacts 已刷新到 ignored
  `.tmp/sound-line-real-media/cases/`，manifest `lltimeline.sha256` 同步当前本机 artifact。
  Brooklyn / Venezuela 保留 deletion、weak_form、assimilation、flapping markers；TED-LIUM /
  Buckeye / TIMIT 不再从 raw insertion 生成 `linking` 爆炸。
  (4) **Closeout**: `2.17-CTC-MISMATCH-FINDINGS.md` 更新为 accepted findings，新增
  `2.17-CLOSEOUT.md`，同步 `2.17-PLAN.md`、`.planning/STATE.md` 和 QA README/case note。
  验证: `PATH="/opt/homebrew/opt/rustup/bin:$PATH" cargo fmt --check`、
  `PATH="/opt/homebrew/opt/rustup/bin:$PATH" cargo test -p speech-analysis`、
  `python3 -m py_compile scripts/run-sound-line-real-media-case.py scripts/verify-sound-line-real-media.py`、
  `python3 scripts/verify-sound-line-real-media.py --manifest testdata/sound-line-real-media/manifest.jsonl --strict-local --require-ready`、
  `python3 scripts/verify-sound-line-real-media.py --manifest testdata/sound-line-real-media/manifest.jsonl --json` 通过。

- 2026-06-29 09:35 CST: 收敛 Phase 2.17 local-only artifact 与 benchmark 评估边界。
  (1) **Artifact 边界**: 将 8 个生成的 `.lltimeline.json` 保持在 ignored
  `.tmp/sound-line-real-media/cases/`，manifest 通过 `lltimeline.local_path` 引用；repo 继续只提交
  manifest、notes、checksum 和 verifier，不提交 local-only 派生 transcript/timeline。
  (2) **Verifier**: 支持 `lltimeline.local_path`，并统一 marker playback window 阈值文案。
  `--strict-local`、`--require-ready` 和 `--json` 在当前本机 artifacts 上均通过。
  (3) **评估边界**: `2.17-PLAN.md` 明确 benchmark case 用于 pipeline vs reference/gold
  比较，product-media case 用于 UI/听感 QA；当前 Buckeye/TED-LIUM/TIMIT artifacts 暴露
  `linking` marker 爆炸，说明链路 ready 但学习质量未 ready。
  (4) **Findings**: 新增 `2.17-CTC-MISMATCH-FINDINGS.md` draft，并同步 Brooklyn 当前 family
  breakdown 与下一步过滤/去重方向。

- 2026-06-29 09:52 CST: 收紧 Phase 2.17 linking marker 生成与 verifier 质量警告。
  (1) **算法门控**: `speech-analysis::sound_analysis` 不再把 generic CTC insertion 自动提升为
  learner-facing `linking` marker；没有跨词边界上下文时只保留底层 alignment，不生成教学解释。
  (2) **Verifier 质量警告**: `verify-sound-line-real-media.py` 现在会 warning 缺少 WordTimeline 的
  phone-only artifact，以及单一 connected-speech family 占比过高的 marker 爆炸。
  (3) **重跑策略**: `2.17-PLAN.md` 与 `2.17-CTC-MISMATCH-FINDINGS.md` 明确当前 `.tmp`
  timelines 是旧逻辑 artifact，应先重跑 Brooklyn + 一个 Buckeye/TED-LIUM 代表 case，再决定是否
  全量重跑 8 个 local-only artifacts。
  验证: `cargo test -p speech-analysis sound_analysis`、`python3 scripts/verify-sound-line-real-media.py --manifest testdata/sound-line-real-media/manifest.jsonl --strict-local`、
  `python3 scripts/verify-sound-line-real-media.py --manifest testdata/sound-line-real-media/manifest.jsonl --json`、
  `python3 -m py_compile scripts/verify-sound-line-real-media.py` 通过。

- 2026-06-28 22:58 CST: 推进 Phase 2.17 real-media QA pack 中间态。
  (1) **QA pack 骨架**: 新增 `testdata/sound-line-real-media/` README、8-case manifest
  和 case notes stub，覆盖 local news、TED-LIUM、Buckeye、TIMIT；local-only 资源只记录
  locator/checksum，不提交媒体或完整 transcript timeline。
  (2) **Verifier**: 新增 `scripts/verify-sound-line-real-media.py`，支持 default /
  `--strict-local` / `--json` / `--require-ready`，并按当前 inclusive phone range 契约从
  `sound_analysis.learning_phones` 推导 marker playback window。
  (3) **CTC sidecar 环境**: `speech-analysis` 启动 wav2vec2 phoneme sidecar 时补入常见
  Homebrew PATH，避免 Rust 子进程找不到 `espeak`。
  (4) **计划更新**: `2.17-PLAN.md` 记录当前完成项、未完成项、真实阻塞点、下一步 headless
  QA runner 方向，以及 UI E2E 当前只有组件级测试、缺少体系化端到端覆盖的判断。
  验证: `python3 scripts/verify-sound-line-real-media.py --manifest testdata/sound-line-real-media/manifest.jsonl`、
  `python3 scripts/verify-sound-line-real-media.py --manifest testdata/sound-line-real-media/manifest.jsonl --json`、
  `python3 scripts/verify-sound-line-real-media.py --manifest testdata/sound-line-real-media/manifest.jsonl --require-ready`
  按预期失败于 readiness、`cargo test -p speech-analysis` 通过。

- 2026-06-28 20:29 CST: 扩展 Phase 2.17 — Real Media Sound-Line QA 执行计划。
  (1) **Benchmark 分层**: 明确 TIMIT 作为 phone-level sanity check，Buckeye 作为优先
  natural connected speech benchmark，本地新闻/TED-LIUM/LibriSpeech/VCTK/Common Voice
  作为 product-like 或 supplemental regression 材料。
  (2) **可交接执行方案**: `2.17-PLAN.md` 新增 manifest schema、local-only 许可策略、
  verifier 规则、manual QA observation 模板、CTC mismatch decision table 要求、执行步骤和
  下一智能体 handoff checklist。

- 2026-06-28 19:37 CST: 落地 Phase 3.0.1 学习行为架构代码地基。
  新增 domain learning-loop 模型与 ID，application practice service、Practice / Review /
  LearningEvent repository traits，SQLite schema v15 与 `practice_sessions`、`practice_items`、
  `practice_attempts`、`review_items`、`review_attempts`、`learning_events` 表，最小
  `/v1/practice/*` 与 `/v1/review/*` API 路由，OpenAPI/generated client/contract validation
  同步，以及 persistence/API 测试。同步刷新 `.planning/codebase/ARCHITECTURE.md`、
  `.planning/codebase/DATA-MODEL.md`、`.planning/codebase/STRUCTURE.md` 和
  `.planning/codebase/STACK.md`。新增
  `.planning/phases/3.0.1-learning-loop-architecture-foundation/3.0.1-CLOSEOUT.md` 记录后端地基收口。

- 2026-06-28 17:31 CST: 新增 Phase 3.0.1 学习行为架构地基规划。
  新增 `.planning/phases/3.0.1-learning-loop-architecture-foundation/3.0.1-CONTEXT.md`、
  `3.0.1-ARCHITECTURE.md` 和 `3.0.1-PLAN.md`，定义 Practice / Review / LearningEvent /
  Corpus / Difficulty / LearnerProfile / Recording 边界，以及 cloze + chunk dictation 第一条
  vertical slice；同步更新 Phase 3.0 plan、`.planning/PROJECT.md`、`.planning/REQUIREMENTS.md`、
  `.planning/ROADMAP.md` 与 `.planning/STATE.md`。

- 2026-06-28 17:14 CST: 建立 Phase 3.0 英语听力学习闭环规划参考。
  新增 `.planning/phases/3.0-english-listening-learning-loop/3.0-CONTEXT.md` 和
  `.planning/phases/3.0-english-listening-learning-loop/3.0-PLAN.md`，将真实输入、
  可理解度判断、诊断、cloze/听写/字幕渐隐、听力驱动词汇、本地 YouGlish-like 语料库、
  Mandarin -> English L1-aware diagnosis、shadowing 和诊断型 dashboard 收敛为后续
  Phase 3.0 对齐依据；同步更新 `.planning/PROJECT.md`、`.planning/REQUIREMENTS.md`、
  `.planning/ROADMAP.md` 与 `.planning/STATE.md`。

- 2026-06-28 16:26 CST: 同步 Phase 2.18 后的入口文档。
  更新 `AGENT.md`、`.planning/PROJECT.md`、`.planning/REQUIREMENTS.md`、
  `.planning/ROADMAP.md`、`.planning/MAINTENANCE.md` 和 `.planning/STATE.md`：
  当前阶段/版本改为 Milestone 2 / 0.7.0，学习资产权威模型改为
  `LexicalEntry + LexicalUnit + LearningStatus`，旧 `WordProfile` / `WordObservation`
  兼容路径不再作为 active path；phase 完成模板统一为 `X.X-CLOSEOUT.md`。

- 2026-06-28 16:19 CST: Phase 2.18 正式收口。
  新增 `.planning/phases/2.18-codebase-architecture-refactor/2.18-CLOSEOUT.md`，
  将 `2.18-PLAN.md` 标记为 `COMPLETED`，并更新 `.planning/STATE.md` 的当前阶段、兼容性决策、
  剩余非阻塞后续项和收口记录。删除过期 `.planning/DEFERRED-ITEMS.md`；跨阶段遗留项以后以
  各 phase closeout、`.planning/STATE.md` 和后续 phase plan 为准。
  当前未彻底完成但不阻塞收口的事项：`main.dart` media/session/resource wiring 继续拆分、
  route manifest 共享事实源、显式 UI async state、`speech-analysis` 子域拆分、真实媒体 QA。

- 2026-06-28 08:59 CST: Phase 2.18 前端 typed payload 与 workflow 收口。
  (1) **Typed payload**: Flutter 新增/补齐 `DictionaryLookupBundle`、`WordPronunciation`、
  `PronunciationAnalysis`、`PhoneticAnalysis`、`PhoneticFinding` 等 DTO，`LearningController` /
  `SubtitleController` 不再以裸 `Map<String, dynamic>` 保存 dictionary、pronunciation、phonetic-analysis
  业务状态。
  (2) **Widget boundary**: `WordLearningPanel` 和 `DiagnosisCard` 改为消费 typed DTO。
  (3) **Workflow extraction**: phrase candidate、word entry load/open/update、lexical observation、
  learning-content save 下沉到 `LearningWorkflowController`；timeline resource refresh、word timing、
  sentence pronunciation、chunk partition、phone/sound-pattern analysis 加载下沉到
  `SpeechEnhancementWorkflowController`，`main.dart` 进一步收缩为 UI wiring/status。
  验证: `flutter analyze apps/desktop`、`flutter test --reporter compact` 通过。

- 2026-06-27 18:20 CST: Phase 2.18 主路径重构完成候选。
  (1) **旧学习资产路径删除**: active code path 收敛为 `LexicalEntry + LexicalUnit`；
  旧 word-profile domain/repository/API/OpenAPI/generated client/script/Flutter fixture 路径已移除。
  (2) **词汇与诊断**: diagnosis、lexical observation、vocabulary v5 export/import 均使用 lexical entry。
  (3) **Flutter typed state**: `LearningController` 改为 typed lexical entries、phrase candidates、
  selected details、language profile 和 diagnosis；TokenLine 使用 typed phrase candidate/lexical entry。
  (4) **Timeline envelope**: Rust 与 Flutter 新增 `TimelineMetrics` / `ChunkEvidence` typed envelope，
  保留 object-shaped `metrics_json` / `evidence_json` wire/storage 字段。
  (5) **文档事实源**: 刷新 `.planning/codebase/ARCHITECTURE.md` 与
  `.planning/codebase/DATA-MODEL.md`。
  验证: `cargo check -p domain -p application -p persistence-sqlite -p api-http`、
  `cargo test -p application -p persistence-sqlite -p api-http --quiet`、
  `flutter analyze apps/desktop`、`flutter test --reporter compact` 通过。

- 2026-06-27 16:45 CST: Phase 2.18 重构首轮落地。
  (1) **契约**: 补齐缺失 OpenAPI/generated client 路由，并让 contract validation 双向校验 router
  与 OpenAPI path set。
  (2) **Rust 边界**: `AppServices` 拆出 subtitle track、pronunciation、timeline resource、
  LLTimeline resource repository 依赖；learning asset 边界更名为 `LearningAssetRepository`。
  (3) **学习资产模型**: `LexicalEntry` 新增权威 `LexicalUnit`，SQLite lexical 唯一性改为
  `language + granularity + normalization + normalized_key`；`WordStatus` 更名为 `LearningStatus`。
  (4) **应用 DTO**: `application::dto` 不再公开 `speech_analysis` 类型别名。
  (5) **Timeline 生命周期**: SQLite word/chunk/phone timeline runs 增加每 track 单 active partial unique
  index，并新增 schema-level 测试。
  (6) **Flutter 状态流**: 新增 typed `BackendEvent`、`BackendEventCoordinator` 和带 generation guard 的
  `LearningWorkflowController.refreshDiagnosis()`。
  验证: `cargo test -p application --quiet`、`cargo test -p api-http openapi --quiet`、
  `cargo test -p persistence-sqlite --quiet`、`./scripts/validate-contracts.sh`、
  `./scripts/test.sh --quick --low-memory` 通过。

- 2026-06-27 15:38 CST: Phase 2.18 明确为非兼容式断代重构。
  (1) **兼容性决策**: 用户确认不需要考虑历史兼容性，旧 SQLite 数据、旧 LLTimeline 资源、
  旧 WordProfile 资源、旧 API/UI adapter 均可抛弃。
  (2) **规划调整**: Phase 2.18 文档从“legacy adapter / 可迁移”改为“新模型优先 / 旧路径删除”，
  默认以 `LexicalEntry + LexicalUnit`、统一 timeline lifecycle、typed Flutter state 和新 contract 为准。

- 2026-06-27 15:33 CST: 扩展 Phase 2.18 为 Codebase Architecture Refactor。
  (1) **范围升级**: 根据用户追加要求，将原“架构契约与项目卫生”阶段升级为代码层面的全面重构阶段，
  覆盖核心学习资产模型、timeline lifecycle、repository/use-case/API 边界、Flutter 状态机与
  async generation guard。
  (2) **新增审计**: 新增
  `.planning/phases/2.18-codebase-architecture-refactor/2.18-REFACTOR-AUDIT.md`，
  记录 `WordProfile` / `LexicalEntry` / `LexicalUnit` 并存、`SubtitleRepository` 过宽、
  `application::dto` 泄漏 `speech_analysis` DTO、`main.dart` orchestrator 过重和动态 JSON 状态等问题。
  (3) **规划同步**: 将 Phase 2.18 文档迁移到
  `.planning/phases/2.18-codebase-architecture-refactor/`，并更新 `.planning/STATE.md`。

- 2026-06-27 12:50 CST: 创建 Phase 2.17 — Real Media Sound-Line QA。
  (1) **阶段目标**: 从继续扩展模型能力转向真实英语媒体回归包，验证
  `sound_analysis.connected_speech`、声音线 marker、evidence 回放和 raw CTC mismatch
  过滤边界是否能支撑真实学习体验。
  (2) **规划交付**: 新增 `.planning/phases/2.17-real-media-sound-line-qa/2.17-CONTEXT.md`
  和 `2.17-PLAN.md`，定义 manifest、checksum、lightweight verifier、manual listening
  observations 和 `2.17-CTC-MISMATCH-FINDINGS.md`。
  (3) **repo 边界**: 明确不提交无再分发许可的媒体本体，repo 内优先保留 manifest、验证脚本、
  QA notes 和过滤决策记录。

- 2026-06-27 10:47 CST: Phase 2.3 正式收口 + 声音线 evidence 回放入口。
  (1) **Phase 2.3 closeout**: 真实媒体手动 QA 已通过，`.planning/STATE.md` 与
  `2.3-CLOSEOUT.md` 从“待手动 QA”更新为正式完成。
  (2) **Listen to this moment**: sound pattern ribbon 的 evidence marker cell 可点击，
  触发 source loop 播放 marker 覆盖的 `LearningPhone` 时间窗，让 connected-speech
  explanation 从静态标签进入可听验证。
  (3) **测试**: `phoneme_ribbon_test.dart` 覆盖 marker tap -> loop callback。
  验证: `flutter analyze`、`flutter test test/timeline_test.dart test/phoneme_ribbon_test.dart`、
  `cargo test -p speech-analysis`、`./scripts/validate-contracts.sh` 通过。

- 2026-06-27 10:38 CST: Phase 2.16 — Real Connected Speech Model v1 收口。
  (1) **真实语流解释层**: `SoundAnalysis` 新增向后兼容的 `connected_speech` metadata，
  分离 expected symbols、stable learning symbols、observed acoustic symbols、family/status/confidence
  和 learner-facing label/hint。
  (2) **核心现象 v1**: `speech-analysis` 从 phone alignment pattern 生成 weak form/reduction、
  deletion、linking、assimilation、contraction、flapping 六类 explanation；generic high-confidence
  substitution 不会生成 connected-speech teaching explanation，避免 raw CTC mismatch 污染教学标签。
  (3) **UI 消费**: Flutter timeline model 解析/导出 `connected_speech`，声音线 marker 可直接使用
  explanation label/hint；无旧 `findings` 时也能展示学习者解释。
  (4) **契约与文档**: OpenAPI 同步 `ConnectedSpeechExplanation` schema；新增
  `.planning/phases/2.16-real-connected-speech-model-v1/2.16-CLOSEOUT.md`，并更新 `STATE.md`。
  验证: `cargo test -p speech-analysis`、`flutter analyze`、
  `flutter test test/timeline_test.dart test/phoneme_ribbon_test.dart`、
  `./scripts/validate-contracts.sh` 通过。

- 2026-06-27 10:23 CST: Phase 2.15 — Sound Line Learning UX 收口。
  (1) **声音线 UX 语义化**: `PhonemeRibbon` 新增 text/sound lane，声音线使用独立音频图标、
  颜色组和圆角形态，继续显示音节间隔、韵律短语边界与 evidence marker；文字线和声音线均
  增加 tooltip 解释各自学习语义。
  (2) **真实 sound_analysis 门控**: 新增 `buildSoundPatternPhones()`，声音线只在当前句存在
  `sound_analysis.learning_phones` 时渲染；缺失时显示轻量不可用状态，不做词典 fallback，
  也不显示 raw CTC-only 教学标签。
  (3) **学习者文案**: evidence marker tooltip 从内部 finding/status 改为
  `supported by audio`、`possible linking`、`possible reduction`、`possible deletion` 等低风险学习表达。
  (4) **测试稳定性**: 新增 `phoneme_ribbon_test.dart`，扩展 `timeline_test.dart` 覆盖无
  `sound_analysis` 不 fallback、CTC observed mismatch 不污染教学标签和 evidence 文案映射；修复
  `phonetic_analysis_ui_test.dart` 在周期 Timer 页面上使用 `pumpAndSettle` 的既有超时。
  验证: `flutter analyze`、`flutter test test/timeline_test.dart test/phoneme_ribbon_test.dart`、
  `flutter test test/phonetic_analysis_ui_test.dart`、`flutter test` 通过。
  收口文档: `.planning/phases/2.15-sound-line-learning-ux/2.15-CLOSEOUT.md`。

- 2026-06-27 10:12 CST: 新增根目录 `AGENT.md`，作为 coding agent 新会话入口。
  记录 `.planning` 首读顺序、双路线项目形态、架构边界、代码放置规则、工具链
  `CARGO` / `FLUTTER` / `PATH` 环境准备、常用验证命令、文档维护规则和收尾检查事项。

- 2026-06-27 CST: Phase 2.15 / 2.16 路线确认。
  (1) Phase 2.15 定义为 **Sound Line Learning UX**：把第二条声音线推进为用户能理解、
  能开启、能训练、能信任的产品闭环，聚焦真实媒体 QA、独立 UI 语义、空状态和
  evidence marker 的学习化表达。
  (2) Phase 2.16 定义为 **Real Connected Speech Model v1**：在 2.15 产品闭环稳定后，
  系统化覆盖弱读、吞音/省音、连读、同化、缩约、flapping 等高频真实语流现象；明确
  不承诺一次实现完整 Prosodic Hierarchy。

- 2026-06-26 CST: Phase 2.14 — Sound-First Learning Architecture 收口。
  (1) **稳定教学标签优先**: 明确并落地
  `CTC provides audio evidence and timing; expected pronunciation provides teaching labels`。
  Phoneme ribbon 不再直接显示 raw CTC label；当 expected `/s/` 遇到 CTC 误判 `/k/`
  时，默认训练 UI 仍显示稳定 `/s/`，CTC 只提供 timing/confidence/mismatch evidence。
  (2) **SoundAnalysis 资源化**: 新增 `SoundAnalysis`、`SoundLearningPhone`、
  `SoundSyllable`、`SoundProsodicPhrase` 等领域模型；`PhoneticAnalysis` 与
  `PhoneTimeline` 均携带可选 `sound_analysis`，旧 JSON 兼容，SQLite 继续复用完整
  `timeline_json` 持久化，LLTimeline export/import 通过 PhoneTimeline 资源路径保留。
  (3) **声音组织算法**: 新增 `speech_analysis::sound_analysis`，将 expected phones 与
  observed CTC phones 对齐为 `LearningPhone`，实现 SSP 音节化、pause-aware onset
  boundary 和 pause-based prosodic phrase detection。
  (4) **Flutter 消费**: `PhoneTimeline` 解析 `sound_analysis`；前端拆分为两个独立入口：
  文字线 phoneme ribbon 使用文本/词典 expected phone，并只借用 observed CTC timing/evidence；
  没有 expected phone 时不显示 raw CTC-only 教学标签。
  声音线 sound pattern ribbon 只在存在 `sound_analysis` 时显示，消费 `learning_phones`、
  音节间隔、韵律短语边界和 finding evidence marker，不做词典 fallback。marker 会映射到
  stable learning phone 上，`detected_in_audio` 强标记、alignment/uncertain 弱标记，不改写
  教学标签。observed insertion/linking evidence 会锚定到最近 learning phone marker，保持证据
  可见但不新增教学 phone。
  `detected_in_audio` 后端升级策略同步收紧：高置信 generic `phone_substitution`
  不再声明为真实语流检测，只有弱读、flapping、同化、缩约、省音等已知 connected-speech
  family 可升级。
  (5) **研究边界文档化**: 补充 Phase 2.14 context 与 Prosodic Hierarchy alignment 文档，
  明确当前实现是 `Phone -> LearningPhone -> Syllable -> pause-based ProsodicPhrase`
  的最小可靠子集，不声称完整实现 Foot / Prosodic Word / Phonological Phrase /
  Intonation Phrase。
  验证: `cargo test --workspace --quiet`、`flutter analyze`、
  `flutter test test/timeline_test.dart`、`./scripts/validate-contracts.sh` 通过。
  收口文档: `.planning/phases/2.14-sound-first-learning-architecture/2.14-CLOSEOUT.md`。

- 2026-06-26 CST: Phase 2.13 — Text-Centered Phoneme Ribbon 收口。
  (1) **长短句自适应显示**: 短句完整显示音素带；长句自动切换为分页窗口，只显示当前
  音素附近的一页，避免把过多音素压缩成不可读噪音。
  (2) **低疲劳交互**: 移除长句模式下的波浪、脉冲、连续居中滑动和底部进度条；窗口
  内容保持稳定，当前音素只在当前页内轻量高亮，跨页时才整体换页。
  (3) **设置与降级链闭合**: 设置中新增音素带显示方式，短句可选轻量 wave；CTC 真实
  音素优先，无 CTC 时从词典发音 + 词级时间戳合成 `DetectedPhone`，无可用数据则隐藏。
  收口文档: `.planning/phases/2.13-phoneme-ribbon-interaction/2.13-CLOSEOUT.md`。
  验证: `git diff --check` 通过；当前 shell 未提供 `flutter`/`dart`，未运行 analyze/test。

- 2026-06-26 CST: 音素设置精简 + PhonemeRibbon 降级策略 + 双主线架构规划。
  (1) **设置精简**: 11 个音素相关设置项收敛为 4 个（phonemeRibbonVisible /
  phonemeRibbonStyle / phoneticAnalysisPreference / learningLanguage）。移除的 6 项硬编码为合理默认值：
  pronunciationVisible 跟随 ribbon 开关、phonemeDisplay 固定 IPA、
  precomputePronunciation 始终开启、phonemeHighlightVisible 联动 ribbon、
  showExperimentalPhoneticResults 始终显示、phoneticCachePolicy 固定 keep_completed。
  涉及 settings_dialog.dart / main.dart / settings_controller.dart / localization.dart /
  subtitle_overlay.dart，settings.dart 保留字段用于 JSON 向后兼容。
  (2) **Ribbon 降级逻辑修正**: 开关逻辑修复（ribbon 开=显示音素信息，关=全部隐藏）；
  CTC 数据优先、无 CTC 时回退 IPA 文字、均无则隐藏；新增
  `synthesizePhonesFromDictionary()` 函数从词典发音 + 词级时间戳合成 DetectedPhone。
  (3) **双主线架构确立**: 文字线（Whisper 转录 → 词 → chunk → 词典音素，回答"说了
  什么"）和声音线（CTC 音素 → 音节 → 韵律短语，回答"怎么说的"），sentence 为共享
  作用域。Phase 2.13 修订为文字线音素收口，新建 Phase 2.14 声音线学习架构。
  验证: `dart analyze` 0 issues。

- 2026-06-25 CST: CTC 音素分析链路端到端打通 + 任务生命周期管理。
  (1) **链路修复**: 创建项目根目录 `.venv`（torch 2.12 + torchaudio 2.11 +
  transformers 5.12 + torchcodec + phonemizer），`phone_recognition.rs` 新增
  `sidecar_python()` 自动从 `current_exe`/`current_dir` 向上搜索 `.venv/bin/python3`；
  后端 `models()` 过滤掉 `research-fixture` provider 避免 Flutter 误选；
  `main.dart` `_analyzePhonetics()` 改用 SnackBar 反馈替代不可见的 `status` 变量。
  (2) **任务生命周期管理**: 后端新增 `DELETE /v1/phonetic-analysis/jobs/{id}`
  和 `POST /v1/phonetic-analysis/jobs/clear` 端点；repository trait 增加
  `delete_phonetic_job` 和 `delete_terminal_phonetic_jobs`，SQLite 层实现。
  Flutter `phonetic_analysis_ui.dart` 全面重写：状态图标（颜色区分完成/失败/进行中/
  排队）、本地化状态标签芯片、活跃任务 1s 轮询空闲降为 5s、任务计数徽章、
  单任务删除（带确认）、批量"清除已完成"、创建时间相对显示、错误信息卡片内展示。
  中英文各新增 13 个本地化键。验证: Rust 编译通过, `dart analyze` 0 issues。

- 2026-06-25 CST: 修复模型下载三个 bug：(1) 脚本路径解析用相对路径导致 App 运行时
  找不到 `download-phoneme-model.py`，改为从 `current_exe()`/`current_dir()` 向上搜索
  `scripts/` 目录；phoneme-cli sidecar 同步修复。(2) 下载进度无反馈 —— `snapshot_download()`
  阻塞无回调，新增后台线程每 3s 轮询模型目录大小并输出 JSON 进度。(3) Flutter 进度条
  运算符优先级 bug（`?? 0.0 / size`），提取 `_installProgress()` 方法。新增：模型
  下载失败时红色错误提示；启动时 `reset_stale_installs()` 自动将卡住的 `installing`
  状态重置为 `downloadable`。模型下载已验证成功（~1.26GB fb-espeak）。
  验证: Rust 299 tests + Flutter 65 tests 全部通过。

- 2026-06-25 CST: 修复桌面播放器播放位置不上报导致的进度条与字幕同步停滞。
  `DesktopPlayerAdapter` 恢复 100ms position polling，并通过
  `VideoPlayerController.position` 主动触发 fvp `getPosition()`，避免只读取缓存
  `value.position`。position stream 仅由主动 polling/seek/stop 发布，避免
  `VideoPlayerController` 的 buffering/state listener 用旧缓存 position 覆盖真实位置。
  切换媒体、播放失败与 dispose 会取消旧 timer，seek/stop 后立即发布当前位置；
  增加 generation 校验防止旧播放器异步结果污染新媒体。修复 Store-backed
  Player/Subtitle/Learning controllers 未转发 ChangeNotifier 通知的问题，确保
  `main.dart` 的 `ListenableBuilder` 在 position/cue 更新时重建进度条与字幕层。
  增加 controller 通知回归测试。验证: `flutter analyze` 0 issues,
  `flutter test` 65/65 passed, `flutter build macos --debug` passed。

- 2026-06-25 CST: Phase 2.10 Steps 2-6 — fb-espeak CTC phoneme provider 选型与集成。
  (1) **Step 2 补充 benchmark**: fb-espeak PER=30.5%（Apache 2.0）选定；
  vitouphy PER=19.5% 因 TIMIT 许可阻塞被排除。
  (2) **Step 3 生产管线集成**:
  - `DetectedPhone` 新增 `display_ipa` 字段，UI 以 IPA 为主显示
  - `speech-analysis/phone_recognition.rs`: IPA→ARPAbet 映射 + sidecar 封装
  - `phonetic_fixture.rs`: `build_ctc_phonetic_analysis()` 真实 CTC 推理路径
  - `api-http/phonetic_analysis.rs`: CTC provider 注册 + model seed + 执行分派
  - `scripts/wav2vec2-phoneme-cli.py`: Python sidecar（CTC decode + logit confidence）
  - `scripts/setup-phoneme-model.sh`: 命令行模型下载脚本
  - `scripts/download-phoneme-model.py`: 后台模型下载 sidecar（JSON 进度输出）
  - Flutter `diagnosis_card.dart`: IPA 优先显示
  - Flutter `phonetic_analysis_ui.dart`: 模型下载按钮 + 进度条（App 内一键下载）
  - `install_model` API: 后台 spawn Python 下载进程，带进度回报和状态更新
  - Flutter `api_service.dart`: 新增 `installPhoneticAnalysisModel()` API 调用
  (3) **Step 4 finding 升级**: 隐式完成（现有 alignment + findings 管线已支持真实 confidence）
  (4) **Step 5 端到端验证**: 待下载模型后测试
  (5) **Step 6 回归**: Rust 299 tests + Flutter 64 tests 全部通过
  使用方式: App 设置 → Audio analysis models → 点击下载按钮；或命令行 `./scripts/setup-phoneme-model.sh`。

- 2026-06-25 CST: Phase 2.11 Steps 1-3 完成 + Phase 2.10 研究计划。
  (1) **Step 3 — domain lib.rs 拆分**: 从 1317 行缩减到 194 行。新增 13 个领域模块
  (media / subtitle / pronunciation / word_timing / chunk_timeline / phone_timeline /
  lltimeline / phonetic_analysis / learning / dictionary / transcription / vocabulary /
  diagnosis)，测试下沉到各自模块。
  (2) **Step 1 — 能力矩阵 API**: Phase 2.12 已完成（`_isHan` 替换为 profile 驱动门控，
  `/v1/languages` + `/v1/languages/{code}/profile` 端点已就位）。
  (3) **Step 2 — 学习语言来源**: AppSettings 新增 `learningLanguage` 字段（默认 `auto`），
  优先级链：用户设置 > 字幕轨语言 > `en` fallback。设置对话框顶部新增学习语言下拉框。
  中英双语 localization。
  (4) **Phase 2.10 研究计划**: 编写 `2.10-RESEARCH-PLAN.md`，盘点已有基础设施
  (PhoneTimeline / MFA / ZIPA / 评估 harness)，规划 4 阶段研究流程
  (环境验证 → 候选 benchmark → 选型决策 → 结果记录)。
  (5) **验证**: 294 cargo tests + 64 flutter tests passed, `flutter analyze` 0 issues。

- 2026-06-25 CST: Phase 2.12 — UI State Management Refactoring (Flutter).
  (1) **Store\<T\> 基础设施**: 通用响应式状态容器，支持 `select()` 细粒度字段级
  ValueNotifier 订阅。新增 StoreBuilder/StoreBuilder2 声明式选择器 Widget。
  (2) **Typed domain models**: 新增 `models/types.dart`，提供 WordProfile、WordDetail、
  Diagnosis、PhraseCandidate 等 7 个 typed 类替代 `Map<String, dynamic>`。
  (3) **Controller 迁移**: PlayerController / SubtitleController / LearningController
  内部迁移到 Store，保留 ChangeNotifier 向后兼容。
  (4) **布局提取**: SubtitleOverlay（原 _playerSurface()）和 SidePanel（原 _sidePanel()）
  提取为独立 Widget 文件，减少 main.dart 的构建方法复杂度。
  (5) **验证**: `dart analyze` 0 issues, `flutter test` 64/64 passed。
  分支: `refactor/ui-state-management`。规划文档:
  `.planning/phases/2.12-ui-state-management-refactoring/`

- 2026-06-24 CST: Phase 2.9 closeout + Phase 2.10/2.11 planning.
  (1) **Phase 2.9 收口**: 生产管线多语言解耦完成。2.9-CLOSEOUT.md 记录 Rust 侧
  (AlignerRegistry/语言传播/CJK 分词) + Python 侧 (mlx-whisper/jieba/M:N 对齐)
  全部交付、中文端到端验证结果和设计决策。
  (2) **残留项总览**: 新增 `.planning/DEFERRED-ITEMS.md`，汇总 Phase 2.1–2.9 全部
  残留/延后项，按 P1(英语语流+架构)/P2(小项)/P3(中文/日语) 分级。
  (3) **Phase 2.10 规划**: English Real Speech Analysis — 选出 phone-level provider，
  让英语语流分析从文本预测升级为音频检测。候选 MFA/ZIPA/Wav2IPA/Allosaurus。
  (4) **Phase 2.11 规划**: Architecture Seam Consolidation — 能力矩阵 API、学习语言
  来源、domain 拆分、L1 诊断 seam、听觉锚定准备。Step 1–3 可与 2.10 并行。

- 2026-06-24 CST: Chinese word-level tokenization + mlx-whisper ASR integration.
  (1) **jieba word segmentation**: `tokenize()` in `lltimeline_common.py` now uses
  jieba for Chinese word segmentation instead of character-level splitting. "今天"
  is one token (not "今"+"天"), producing natural word-boundary highlights during
  karaoke playback. Falls back to per-character if jieba unavailable. English
  tokenization unchanged.
  (2) **ASR-to-token alignment**: new `align_asr_words_to_tokens()` handles M:N
  mapping between ASR word boundaries and jieba token boundaries via character-
  position alignment. Merges timing from multiple ASR words when they compose one
  jieba token (e.g. ASR ["上","海"] -> jieba "上海").
  (3) **mlx-whisper integration**: `mlx-whisper-transcribe.py` standalone script
  wrapping `mlx_whisper.transcribe()` with WhisperX-compatible JSON output.
  `production_pipeline.py` gains `--asr` flag (`whisperx`/`mlx-whisper`) and
  `resolve_mlx_whisper_command()`. ~7.5x faster than WhisperX CPU on Apple Silicon.
  (4) Quality comparison on 8-min Chinese audio: mlx-whisper avg_confidence 0.954
  vs WhisperX 0.953, fewer overlaps (2 vs 4), comparable word coverage.

- 2026-06-24 CST: Phase 2.9 — Production multilingual decoupling + pluggable model
  architecture.
  (1) **Pluggable aligner registry**: new `aligners/` package with `AlignerPlugin`
  base class, `MfaAligner` and `MmsFaAligner` plugins extracted from
  `production_pipeline.py`. Registry provides `register()`, `get_aligner()`,
  `available_aligners(language)`, `all_aligners()`. Adding a new aligner (e.g.
  Qwen3-ForcedAligner) requires one plugin file + one `register()` call.
  `production_pipeline.py` dispatch rewritten to use registry — no more if/elif.
  New `list-aligners` subcommand; `doctor` now reports registered aligner status.
  (2) **CJK tokenizer**: `lltimeline_common.py` tokenizer extended to emit each
  CJK character (Chinese, Japanese hiragana/katakana) as an individual word token.
  English tokenization unchanged. 11 new tests for CJK + regression.
  (3) **Language propagation**: `--language` parameter flows through entire
  production chain. `post_aligner_chain()` filters aligners by language: Chinese
  skips MFA (English-only) and uses MMS_FA directly. `apply-mfa-alignment` and
  `apply-mms-fa-alignment` subcommands accept `--language`.
  (4) **CJK chunk partition (Rust)**: `chunk_partition.rs` strong punctuation
  detection extended with CJK sentence-final punctuation (U+3002, U+FF1F, etc.).
  `build_chunk` text joining uses no separator for all-CJK chunks. `is_cjk_char`
  helper covers CJK Unified Ideographs, hiragana, katakana.
  (5) **Rust pipeline language propagation**: `ForcedAlignRequest` gains optional
  `language` field. `refine_transcription_word_timelines()` accepts and propagates
  language from `detected_language` through to the forced-align sidecar.
  (6) **GUI**: post-aligner dropdown dynamically populated from aligner registry.
  Verified: all 24 Python tests pass, all 294+ Rust workspace tests pass, clippy
  clean (no new warnings).

- 2026-06-24 CST: Phase 2.9 planning — Production engine multilingual decoupling.
  Created CONTEXT and PLAN docs identifying 5 English binding points in the
  production pipeline: language propagation, forced alignment language-aware
  degradation, pronunciation analysis provider-ization, text chunk language
  dispatch, and Chinese end-to-end validation. Consumer-side is now
  language-agnostic (Phase 2.6-2.8); this phase targets the production side.
  Updated STATE to reflect Phase 2.8 completion and Phase 2.9 planning.

- 2026-06-24 CST: Phase 2.8 — Token timing alignment + rhythm-aware estimation.
  (1) **Character-level time alignment**: `asr_timing.rs` rewritten to perform
  character-level time interpolation (`align_words_to_tokens`) when whisper BPE
  word count mismatches app tokenizer word count (common for CJK where BPE merges
  characters differently from jieba/lindera). English 1:1 direct path unchanged
  (`extract_direct`). New `TimingSource::AsrAligned` variant for interpolated
  timings. `MergedWord` now carries `text` for alignment computation.
  (2) **Rhythm-aware estimation fallback**: `estimate_word_timings_with_rhythm`
  selects strategy from `LanguageLearningProfile.rhythm_prosody`: `CharWeight`
  for stress-timed (en, clamped char count, `v1`), `SyllableEqual` for
  syllable-timed (zh, equal CJK char weight, `v2-syllable`), `MoraCount` for
  mora-timed (ja, kana/kanji mora counting with small-kana exclusion,
  `v2-mora`). `pronunciation.rs` wired to pass profile rhythm.
  (3) **Public alignment API**: `align_timings_to_tokens` exposed for lltimeline
  import and future re-tokenize scenarios. `word_timing_cache_is_usable` updated
  to accept `v2-*` provider versions.
  (4) **Match arm updates**: `AsrAligned` added to `chunk_partition.rs`
  `acoustic_gap_threshold` (same threshold as `AsrReported`) and
  `application/lib.rs` `timing_priority` (priority 2, same as `AsrReported`).
  Verified: 294 workspace tests pass (7 new: Chinese BPE alignment, English
  direct mapping regression, character time distribution, public alignment API,
  syllable-timed equal weight, mora counting, default rhythm regression),
  clippy clean.

- 2026-06-24 CST: Phase 2.7 — Pronunciation provider dispatch + language-agnostic
  timing/chunk. (1) **PronunciationProvider trait**: new dispatch trait in
  `providers.rs` with `analyze_sentence`, `lookup_word`, `rule_catalog` methods.
  `EnglishPronunciationProvider` wraps `speech_analysis` crate;
  `ChinesePronunciationProvider` produces pinyin from CC-CEDICT with per-character
  fallback. Providers registered in `ApiState::new`, dispatched by
  `sentence_language()` match against `info().languages`. (2) **pronunciation.rs
  rewrite**: `analyze_pronunciation`, `lookup_pronunciation`, `pronunciation_rules`
  all route through registered providers. Cache validation keyed on provider
  id/version. `analyze_pronunciation_track` uses `filter_map(.ok())` to skip
  sentences that fail (e.g. punctuation-only). API routes `/v1/pronunciation/lookup`
  and `/v1/pronunciation/rules` accept `language` query parameter (default "en").
  (3) **Chinese pinyin display**: Chinese subtitles now show tone-marked pinyin
  below the subtitle line via existing `display_ipa` rendering path — no Flutter
  code change needed. (4) **Timing/chunk language-agnostic**: `estimate_word_timings`
  (character-weighted time distribution) and acoustic chunk detection (gap-based)
  confirmed as language-agnostic algorithms. Chinese profile upgraded from
  `Unsupported` to `Supported` for `word_timeline` and `chunk_timeline`. Only
  `detect_text_chunks` (COCA n-gram / PHRASE List) remains English-gated.
  (5) **phonetic_fixture.rs**: non-English skips canonical phone alignment
  (empty canonical list). Verified: 286 workspace tests pass, user confirmed
  Chinese pinyin + word tracking + chunk highlight working, English regression clean.

- 2026-06-23 CST: Phase 2.6 extension — capability matrix API, language selection
  UI, and per-character meaning breakdown. Three user-visible features:
  (1) **Capability matrix API**: `GET /v1/languages` lists supported languages,
  `GET /v1/languages/{code}/profile` returns the full `LanguageLearningProfile`
  (tokenization, dictionary, pronunciation capabilities). Flutter API service
  wired with `listLanguages()` and `lookupLanguageProfile()`.
  (2) **Language selection UI**: `PATCH /v1/subtitles/{track_id}/language` lets
  users override auto-detected language on a subtitle track. Backend follows the
  `set_track_status` pattern (trait → sqlite UPDATE → return updated track).
  `_LanguageChip` widget in the subtitle resource tile shows current language with
  a popup menu; changing language refreshes word/phrase profiles for the active
  track.
  (3) **Per-character meaning**: `DictionaryLookup` extended with
  `character_breakdowns: Vec<CharacterBreakdown>` (character + phonetic + meaning).
  `ChineseDictionaryProvider::resolve()` splits multi-character words and does
  per-char CC-CEDICT/seed lookups to populate meanings. Word learning panel reads
  backend breakdowns first, falls back to client-side syllable splitting. Meaning
  row renders below pinyin in small text. Gate changed from hardcoded
  `profile['language'] == 'zh'` to profile-driven
  `pronunciation == 'zh.pinyin'`. `character_breakdowns` uses
  `skip_serializing_if = "Vec::is_empty"` for backward compatibility with cached
  dictionary entries. Verified: workspace 250 tests, flutter 64, contracts pass,
  no-default-features clean, en/zh/ja regression baseline unchanged.

- 2026-06-23 15:28 CST: Promoted Japanese from a guard fixture to a real language
  (lindera morphological tokenization + JMdict/EDICT2 dictionary), empirically
  validating the dispatch-layer fix from the earlier falsification spike. Added
  `JapaneseTokenizer` with lindera 4.0 + embedded IPADIC behind an opt-in
  `lindera` feature (default off — not vendored offline; offline/default builds
  use character-level fallback). Added `JapaneseDictionaryProvider` reading
  EDICT2 line format with a 15-word seed fallback, registered in the api-http
  dictionary stack. The ja profile now declares `ja.morphological` tokenization,
  `jmdict` dictionary, and `ja.kana` pronunciation — all routed by profile and
  provider with zero edits to dispatch core, `detect_language`, per-char gating,
  or diagnosis. This empirically confirms ROADMAP §14.11: adding a real
  Han-script-sharing language required only profile + provider + registration.
  Surfaced a deferred seam: `core.surface` normalization does not unify Japanese
  inflections (食べる/食べた) because Fix 4 re-derives the normalized key from
  surface text, discarding lindera's base form — base-form unification needs
  the provider-supplied opaque key to flow through `tokenize()`. Updated
  maintenance checklist to require minute-precision changelog timestamps.
  Verified: workspace 286 tests, `--features lindera` morphological proof,
  `--no-default-features` 24 tests, flutter 64, clippy clean, contracts pass;
  en/zh regression baseline unchanged.

- 2026-06-23 09:07:10 CST: Closed out Phase 2.6 (step 7). Consolidated the
  bilingual regression into an explicit set and added a crown-jewel capstone test
  proving English and Chinese vocabularies and their source snapshots stay
  language-isolated (a Chinese word never appears in the English vocabulary and
  vice versa). Wrote `2.6-CLOSEOUT.md` and updated STATE / ROADMAP / REQUIREMENTS
  to mark Phase 2.6 complete for the English + Chinese acceptance set. LANG-001/
  002/003/005/006/007/008/010 are implemented; LANG-004 (auditory-anchored
  observation) and LANG-009 (L1 diagnosis seam) remain reserved seams by design,
  as does non-English audio → listening-unit production (a separate future
  program). English behavior stayed the regression baseline throughout. Verified
  with the full workspace suite (279 tests), flutter analyze/test (63), and
  validate-contracts.

- 2026-06-22 21:49:03 CST: Added the Phase 2.6 Chinese learning panel and
  language-aware diagnosis (step 6). Sentence diagnosis now layers the learning
  language's listening factors onto the recognition barrier as namespaced,
  per-profile *possibilities* (zh: tone_confusion/word_boundary/homophone/
  neutral_tone/tone_sandhi; en: weak_form/linking/...), explicitly framed as
  factors to consider rather than detections from audio — there is no Chinese
  audio analysis yet (deferred per ADR 0012). The decoration lives in the
  application layer (`diagnose_sentence`), keeping `diagnosis-core` language-
  agnostic; a new `reasons` field on `DiagnosisHint` carries them. The word panel
  gained a per-character breakdown for multi-character Han words, aligning each
  character with its pinyin syllable (字 → 拼音/声调) — derived from the dictionary
  phonetic with no extra lookups and gated on script, not language. The diagnosis
  card renders reasons localized with a clean fallback for unknown reasons.
  Verified with new application and widget tests; English diagnosis stays the
  regression baseline.

- 2026-06-22 21:09:21 CST: Integrated CC-CEDICT as the real Chinese dictionary
  source, replacing the 25-word built-in stub with the full ~120k-entry community
  dictionary while keeping the seed as an offline fallback. `ChineseDictionaryProvider`
  now reads an installed CC-CEDICT `.u8` file (cached, mirroring the ECDICT loader),
  parsing `Traditional Simplified [pin1 yin1] /glosses/` and converting tone-numbered
  pinyin to tone marks (handling `u:`→`ü`, neutral tone, capitalized proper nouns, and
  the standard a/e/ou/last-vowel placement); both simplified and traditional headwords
  resolve. Registered CC-CEDICT in the learning-resource catalog with a pinned mirror
  commit and verified SHA-256 (CC-BY-SA 4.0), so it installs like ECDICT/CMUdict.
  Known limitation: words with multiple readings keep the first entry. Verified with
  new parser/tone tests and a throwaway smoke check against the real 118k-entry file.
- 2026-06-22 21:00:00 CST: Fixed two backend `language=en` hardcodes that Step 4
  (client-scoped) missed, so Chinese diagnosis and phrase detection use the sentence's
  actual track language. Added a `sentence_track_language` repository method (joining
  `subtitle_sentences` to `subtitle_tracks`) and a `sentence_language` application
  helper (track language, else `en`); `diagnose_sentence` and `phrase_candidates` now
  resolve through it instead of assuming English. Previously a Chinese sentence's
  diagnosis read English word profiles and ignored the user's Chinese statuses. Added a
  test proving zh diagnosis reads zh profiles and en does not leak.
- 2026-06-22 20:20:02 CST: Added the Phase 2.6 Chinese dictionary and
  pronunciation provider (step 5). Introduced a built-in `ChineseDictionaryProvider`
  in `dictionary-provider` (`supported_languages: ["zh"]`) seeded with common
  words/characters, each carrying tone-marked pinyin (the `zh` profile's
  `zh.pinyin`/`zh.tone`) and a short gloss, and registered it in the api-http
  dictionary stack. The existing `lookup_dictionary` dispatch already routes by
  `supported_languages`, so clicking a Chinese token now shows pinyin + meaning
  while English providers are skipped; unknown words degrade to no result without
  affecting playback or word status. Pinyin is delivered through the dictionary
  phonetics, and the word-learning panel now hides the IPA pronunciation section
  when no variant has real content (Chinese has no IPA provider). Seed data is a
  placeholder for a licensed CC-CEDICT-scale source behind the same interface.
  Verified with new provider, language-routing, and Flutter checks.
- 2026-06-22 17:30:00 CST: Removed the Phase 2.6 `language=en` hardcoding (step 4)
  so the learning language comes from the active subtitle track instead of a
  constant. `subtitle_core::import` now detects the language from the subtitle
  script when the caller does not declare one (Han -> zh, else en) and uses it for
  both tokenization and the stored `track.language`; a declared language still
  wins and English tokenization stays the regression baseline. The Flutter
  `SubtitleTrack` model reads the language the core already serialized, and a
  `_learningLanguage` resolver (active primary track language, `en` fallback)
  threads it through the vocabulary, dictionary, word-profile, source-snapshot and
  phrase paths and `_sourceFor`. The `LocalApi` vocabulary/dictionary/lexical
  methods take a required language; also dropped the dead `normalizeLexical`
  client wrapper. Verified with workspace tests, flutter analyze/test and
  validate-contracts.
- 2026-06-22 16:06:45 CST: Added the Phase 2.6 LexicalUnit model (step 3) in
  `domain` (`lexical_unit.rs`): a language-relative vocabulary learning object
  whose identity is two orthogonal axes — granularity
  (core.char/word/phrase/morpheme) x normalization
  (core.surface/lemma/citation/root) — plus an opaque normalized_key with no
  substring/affix assumption (ADR 0012 R2). Word-granularity identity stays
  `language:normalized_key` so existing English WordProfile ids remain readable;
  non-word granularities namespace the key so Chinese characters never pollute
  Chinese words or English lemmas. English normalizes to a lowercased lemma,
  Chinese keeps the surface form (no lemma assumed), and a
  baseline_normalized_key helper leaves real citation/root normalization to
  per-language providers. Verified with new domain tests and clippy.
- 2026-06-22 16:00:04 CST: Implemented the Phase 2.6 language-aware
  tokenization foundation (steps 1-2 of the multilingual learning phase).
  Added a `LanguageLearningProfile` capability matrix in `domain`
  (`language_profile.rs`) with open namespaced-string `kind` fields (per ADR
  0012 R0), English/Chinese/degraded profiles, and a `profile_for` resolver
  that maps regional variants to their base language and degrades unknown
  languages cleanly; the global `WordStatus` enum is left untouched as the
  language invariant. Replaced the single `tokenize_english` call path in
  `subtitle-core` with a `Tokenizer` trait and a profile-driven
  `tokenize(language, text)` dispatch: English keeps the existing baseline,
  unknown/absent languages degrade to whitespace, and `zh.word_segmentation`
  routes to a Chinese tokenizer. Chinese tokenization uses jieba-rs 0.7.4 word
  segmentation by default (`jieba` feature), with a character-level fallback
  under `--no-default-features`; both preserve original character spans and
  handle mixed CJK/Latin/number runs. Verified with the full workspace test
  suite (255 tests), the no-default-features fallback path, and clippy; the
  English tokenization path is unchanged. jieba-rs is now pinned in Cargo.lock.
- 2026-06-22 11:59:40 CST: Documented the multilingual listening-learning
  product direction across the strategic docs after the Phase 2.5.5 validation,
  following the `.planning/MAINTENANCE.md` rules. Updated PROJECT.md (vision is
  now multilingual and listening-first; new §4.4 principles, §10.9 concepts, and
  §15.5 Milestone 2 multilingual direction). Added REQUIREMENTS.md section 18.4
  with LANG-001..LANG-010 (capability matrix/profile, language-aware
  tokenization, LexicalUnit granularity×normalization, ListeningUnit view plus
  listening-anchored observation, `language=en` removal, Chinese
  dictionary/pinyin provider, Chinese learning panel/diagnosis, comprehension-axis
  invariant with per-profile diagnosis reasons, L1 seam, open kind taxonomy) and
  a release-matrix row; noted TXT-001 is generalized by LANG-002. Added
  ROADMAP.md §14.11 multilingual workstream under Milestone 2. Recorded the
  architecture decision as ADR 0012 and added forward-looking multilingual
  sections to codebase/ARCHITECTURE.md and codebase/DATA-MODEL.md. No code
  changed; English behavior remains the regression baseline.
- 2026-06-22 11:45:56 CST: Added Phase 2.5.5 Language Learning Abstraction
  Validation as a design/validation phase inserted before Phase 2.6
  (Multilingual Learning Foundation), mirroring the earlier 2.3.5-before-2.4
  pattern. Validated the multilingual learning abstraction against real
  second-language-acquisition research rather than engineering aesthetics:
  the meaning-vs-sound diagnosis axis maps to Field's decoding-vs-meaning
  listening model, language-specific listening units to Cutler's
  cross-linguistic segmentation (English stress, French syllable, Japanese
  mora, Mandarin syllable/tone), the LexicalUnit to Nation's word family,
  chunks to Wray's formulaic language, lexical competition to the
  Marslen-Wilson cohort model, and L1 filtering of L2 perception to Best
  (PAM) and Flege (SLM). Locked the comprehension axis as the single language
  invariant: the global vocabulary status enum stays language-agnostic and
  reusable, while diagnosis reason taxonomy becomes per-profile and
  extensible. Added an L1->L2 diagnosis seam (nullable, unused in v1, no
  schema change). Ran a typological falsification with Japanese and Arabic
  that forced three abstraction revisions: R0 `kind` taxonomies must be open
  namespaced strings with clean degradation instead of exhaustive enums
  (Japanese mora, Arabic templatic morphology fall outside the original
  closed sets); R1 listening observations must be able to anchor to a
  `ListeningUnit`, not only a `LexicalUnit`, so tone/pitch minimal-pair
  failures have a home; R2 `normalized_key` must be provider-opaque because
  Arabic non-concatenative roots (k-t-b) are not surface substrings. Scoped
  the architecture to the top-15 learning languages with typological
  clustering and flagged Hindi's abugida as the next writing-system probe.
  Fed the validated foundation back into Phase 2.6 as seven implementation
  constraints and resolved two of its open questions. No production code
  changed; deliverables are design docs (SLA foundation, falsification,
  closeout) plus updates to STATE and the Phase 2.6 plan.
- 2026-06-22 10:30:00 CST: Updated `validate-contracts.sh` MFA strategy
  assertion from `--strategy align-one` to `--strategy align` to match the new
  batch-align default. All 16 Python tests and the full contract validation
  suite now pass with the updated defaults.
- 2026-06-22 09:15:00 CST: Switched the MFA default strategy from `align-one`
  to batch `align`. The `align-one` strategy spawned a separate `mfa
  align_one` process per segment, incurring ~11 s of model-loading overhead
  each time; for 115 segments this meant 210 s total. Batch `align` loads the
  model once and aligns all segments in a single process (58 s, 3.6× faster)
  with identical output. The original reason for `align-one` was an MFA 3.3.9
  SQLite export bug (empty interval CSVs); re-testing confirmed the bug is no
  longer present. `align-one` is kept as `--mfa-strategy align-one` fallback.
- 2026-06-22 09:04:00 CST: Completed Phase 2.5 Sound Pattern /
  PhoneTimeline. PhoneTimeline is now a first-class resource with SQLite schema
  v14, candidate/active/archive lifecycle APIs, LLTimeline import/export
  round-tripping, OpenAPI coverage, and desktop resource management. Completed
  phonetic analyses now bridge to PhoneTimeline candidates; the desktop app can
  show, activate, archive, delete, and consume active PhoneTimeline resources
  for current-phone highlighting and diagnostic sound-pattern display, while
  falling back to legacy phonetic analyses when no active resource exists.
  Added the Phase 2.5 provider benchmark gate and recorded the no-release
  provider decision: research fixtures and candidate models stay out of the
  default product path until benchmark, provenance, and license gates pass.
- 2026-06-21 21:16:48 CST: Completed Phase 2.4 ChunkTimeline generation and
  consumption. Chunk boundaries are now persisted as first-class
  `ChunkTimeline` resources with SQLite schema v13, active/candidate/archive
  lifecycle APIs, LLTimeline import/export round-tripping, and OpenAPI
  coverage. The desktop app now lists ChunkTimeline candidates in Subtitle
  Resources, can generate/activate/archive/delete them, prioritizes the active
  ChunkTimeline for playback, and adds chunk navigation, click-to-seek, loop
  current chunk, and expanded chunk practice controls. Updated Phase 2.4
  closeout docs. Verified with `cargo test --workspace --quiet`,
  `flutter analyze`, `flutter test`, `./scripts/validate-contracts.sh`, and
  `git diff --check`.
- 2026-06-21 10:19:08 CST: Implemented the first Phase 2.3 manual
  WordTimeline review pass in the desktop app. Manual Review now opens a
  sentence-level inspector backed by a full cloned WordTimeline draft, supports
  integer-millisecond start/end editing with ±10ms/±50ms controls, plays the
  current sentence or word using draft boundaries, and saves a full
  `created_by=user` / `status=active` user-adjusted WordTimeline revision.
  Added complete Flutter WordTimeline read/create client methods, millisecond
  payload serialization, draft validation/dirty tracking, and focused tests.
  Verified with `flutter analyze` and `flutter test` (59 tests passed).
- 2026-06-21 10:31:53 CST: Made Phase 2.3 Manual Review discoverable as a
  labeled button in the Timeline Resource Summary instead of an icon-only
  action, and fixed word-click navigation so selecting a subtitle word opens the
  Word Learning side panel rather than the Subtitle Resources panel. Verified
  with `flutter analyze` and `flutter test` (60 tests passed).
- 2026-06-21 10:39:53 CST: Fixed Manual Review playback verification leaking
  its temporary source loop after closing the dialog. The review flow now
  restores the previous source loop state when the inspector exits, so using
  Play sentence / Play word no longer leaves normal playback looping the review
  segment. Verified with `flutter analyze` and `flutter test` (60 tests passed).
- 2026-06-21 10:51:01 CST: Reworked subtitle resource export so the existing
  Export action asks for an output format. Users can now choose SRT or
  LLTimeline JSON from the same export flow; LLTimeline export writes the full
  `.lltimeline.json` document via `GET /v1/subtitles/{track_id}/lltimeline/export`.
  Verified with `flutter analyze` and `flutter test` (60 tests passed).
- 2026-06-21 11:02:30 CST: Added a direct Export LLTimeline JSON action to the
  Timeline Resource Summary so users can export the full resource from the same
  area that shows active/manual WordTimeline versions. The button reuses the
  same track-level `.lltimeline.json` export path and is covered by widget
  tests. Verified with `flutter analyze` and `flutter test` (60 tests passed).
- 2026-06-21 02:55:00 CST: Hardened the timeline-production browser GUI so it
  cancels cleanly and previews without blocking. `cancel()` now signals the
  whole process group (`start_new_session` + `os.killpg` SIGTERM, escalating to
  SIGKILL after a 3s grace) instead of orphaning the whisperx/MFA worker, and
  reports a real exit code (130 on cancel) so the UI no longer sticks on
  "Running..." Command preview no longer synchronously SHA256-hashes multi-GB
  media (instant placeholder for preview; real hash computed only on `/run`);
  previewed commands survive `poll()` until the next run; and `main()` forces
  line-buffered stdout so the server URL appears even under pipe redirection.
  Added `test_production_pipeline_gui_contract.py` (10 tests) covering the
  process-group cancel, fingerprint resolution, placeholder, and stdout
  behavior. Verified end-to-end against the Brooklyn middle-school sample:
  whisperx baseline + `from-whisperx-json` convert and MMS-FA post-alignment
  both produce a valid `llplayer.timeline.v1` `.lltimeline.json`.
- 2026-06-20 21:08:52 CST: Added subtitle-resource consumption capability
  visibility in the standalone Subtitle Resources panel. Each resource now
  reports sentence, word, chunk, and phone timing availability with counts;
  resource refresh probes capabilities independently so partial failures do not
  hide usable subtitles; and opening a new media clears stale resource
  capability state before reloading.
- 2026-06-20 21:08:52 CST: Hardened active subtitle-resource consumption after
  LLTimeline import by loading word timings, chunk partitions, phone analyses,
  and pronunciation independently. Resource-list capability refresh no longer
  triggers full-track chunk partition generation, so importing a large
  `.lltimeline.json` is not blocked by panel capability probing.
- 2026-06-20 21:36:31 CST: Promoted subtitle resources to a top-level desktop
  entry, opening a dedicated management page like the vocabulary book instead
  of relying on the right-side transcript panel. LLTimeline import now refreshes
  visible resources after success, and current-media imports reuse an existing
  same-media/same-subtitle fingerprint track id so repeated or previously
  imported `.lltimeline.json` resources remain visible and consumable.
- 2026-06-20 21:46:04 CST: Fixed the desktop development sidecar selection trap
  where a stale `target/release/api-http` was preferred over the freshly built
  debug sidecar, leaving real user databases at schema v9 without
  `word_timeline_runs`, `lltimeline_resources`, or subtitle lifecycle status.
  Rebuilt the release sidecar, migrated the local database to schema v12, and
  verified the desktop sample MP4 plus `baseline.lltimeline.json` imports as a
  visible subtitle resource with 1,755 word timings.
- 2026-06-20 10:14:20 CST: Added the first full subtitle-resource lifecycle
  management pass. `SubtitleTrack` resources now carry `available|archived`
  status with SQLite migration `0012_subtitle_resource_lifecycle`; the local API
  can archive, restore, delete, export, and list resources; and the Subtitle
  Resources panel exposes archive/restore/delete/export actions while preventing
  archived resources from being activated.
- 2026-06-20 10:05:16 CST: Reworked Phase 2.2 app-side subtitle resource
  handling so subtitles and `.lltimeline.json` files behave as attachable,
  visible resources for the current media. Added current-media LLTimeline
  import with fingerprint mismatch confirmation, remapped imported track /
  sentence / WordTimeline identifiers for exchange-safe attachment, exposed
  media subtitle-resource listing APIs, and moved Timeline Resource Summary out
  of the Transcript panel into a standalone Subtitle Resources side panel that
  can import, list, activate, and refresh subtitle resources.
- 2026-06-20 08:39:01 CST: Hardened the MFA `align-one` sidecar so a single
  segment `mfa align_one` subprocess failure is recorded as a per-segment
  diagnostic/skipped timing instead of crashing the whole run, while still
  failing fast when every segment fails so production fallback can engage.
- 2026-06-20 00:34:23 CST: Created Phase 2.3 manual timeline review UI
  planning docs, defining the sentence-level Word Timing Inspector approach,
  user-adjusted WordTimeline save/activate/export flow, playback verification
  controls, and Phase 2.4 handoff boundary.
- 2026-06-20 00:18:59 CST: Replaced the timeline production Tkinter GUI with a
  local browser-based GUI backed by Python's standard-library HTTP server,
  using macOS `osascript` only for folder/media selection and avoiding Tk file
  dialogs entirely.
- 2026-06-20 00:11:42 CST: Attempted to reduce the timeline production Tk save
  dialog crash on macOS/Python 3.13 by removing the multi-pattern file type
  filter; this was later superseded by replacing the Tk GUI entirely.
- 2026-06-19 23:59:47 CST: Fixed timeline production GUI/CLI WhisperX discovery by
  auto-detecting the default timeline-production venv under
  `~/Library/Caches/LLPlayerNext/research/timeline-production/venv/bin/whisperx`;
  the GUI now pre-fills this path when present.
- 2026-06-19 23:28:09 CST: Added a standalone Tkinter GUI wrapper for the local
  LLTimeline production pipeline at
  `scripts/timeline-production/production_pipeline_gui.py`, covering media
  selection, output paths, SHA256 fingerprinting, WhisperX/post-aligner options,
  dry-run command preview, live logs, cancellation, and output-folder access.
- 2026-06-19 23:18:55 CST: Completed Phase 2.2 app timeline resource UI alignment. Added
  LLTimeline resource metadata/artifact persistence (`lltimeline_resources`),
  import/export artifact round-trip coverage, Flutter LLTimeline client methods,
  timeline resource controller state, and a Transcript-panel Timeline Resource
  Summary UI for import, active/candidate WordTimeline visibility, production
  readiness/artifacts, candidate activation, and a Phase 2.3 manual-review
  entry placeholder. Verified active WordTimeline playback binding remains on
  `trackWordTimings()` with legacy fallback.
- 2026-06-19 16:20:39 CST: Added the Phase 2.2 start handoff document at
  `.planning/handoff/project-handoff-2026-06-19-phase-2.2-start.md`, summarizing
  the completed Phase 2.1 hardening work, verified commands, remaining
  non-blocking architecture debt, and the recommended Phase 2.2 audit-first
  entry path for LLTimeline resource UI alignment.
- 2026-06-19 16:10:34 CST: Completed the Phase 2.1 application orchestration
  debt fix for transcription word timelines. Added
  `AppServices::refine_transcription_word_timelines` with a
  `ForcedAlignSidecar` input and `WordTimelinePipelineResult`, moving
  DTW extraction, MMS_FA sidecar invocation, forced-alignment merge,
  pause-refinement, WordTimeline snapshot creation, activation, and legacy
  fallback storage out of `api-http`. `crates/api-http/src/transcription.rs`
  now only reads the generated Whisper JSON, resolves the optional sidecar, and
  calls application orchestration. Updated Phase 2.1 and CONCERNS docs to mark
  this architecture debt handled while keeping mega-file splitting and
  monotonicity ablation as later standalone work.
- 2026-06-19 16:10:34 CST: Also moved the phonetic research fixture's canonical
  phone alignment and finding construction out of
  `crates/api-http/src/phonetic_analysis.rs` into
  `AppServices::build_research_fixture_phonetic_analysis`, so the HTTP
  coordinator keeps job state, queueing, repository writes, and events while
  application owns the speech-analysis composition.
- 2026-06-19 16:10:34 CST: Removed the remaining direct `speech_analysis`
  references from `crates/api-http/src/lib.rs` by exposing chunk partition
  response types and learned prosodic provider catalog access through the
  application layer.
- 2026-06-19 16:01:48 CST: Closed Phase 2.1 with a documented scope cut after
  completing the current hardening work: P0 word-index placeholders, P1 shared
  tokenizer/evaluation guardrails, production post-aligner fallback, and P3
  evaluation-stat de-duplication. Deferred the application orchestration
  extraction, application/persistence mega-file split, and forced-align
  monotonicity ablation into explicit architecture debt so Phase 2.2 can start
  without a risky broad refactor. Updated `.planning/STATE.md`,
  `.planning/codebase/CONCERNS.md`, and Phase 2.1 docs accordingly.
- 2026-06-19 15:55:21 CST: Marked the timeline-production / aligner-evaluation
  phase as temporarily closed and moved it into long-running research and
  production-script maintenance. Prepared Phase 2.2 planning docs for app-side
  `.lltimeline.json` resource UI alignment, covering resource import visibility,
  WordTimeline candidate summaries, active timeline selection, playback binding,
  and a later manual-review entry point.
- 2026-06-19 15:51:14 CST: Generalized the timeline-production post-alignment
  stage into a selectable degradation strategy. `produce-whisperx` now accepts
  `--post-aligner auto|mfa|mms-fa|none`; `auto` and `mfa` try MFA first, fall
  back to MMS_FA, and preserve the original WhisperX WordTimeline if all
  post-aligners fail, recording `post_alignment_failure` artifacts in the
  reusable `.lltimeline.json` resource. Added `apply-mms-fa-alignment`,
  extended `doctor` with MMS_FA runtime visibility, and updated contract
  dry-runs for the ordered fallback chain.
- 2026-06-19 15:41:28 CST: Paused further aligner benchmark expansion and
  documented deferred Qwen3-ForcedAligner, BFA/easytranscriber/CTC, and MMS_FA
  research directions under the timeline-production research docs. Advanced the
  current production mainline by adding MFA post-alignment orchestration to
  `scripts/timeline-production/production_pipeline.py`: `produce-whisperx` now
  supports `--post-aligner mfa`, appending an MFA `align-one` WordTimeline while
  preserving the WhisperX timeline as a candidate fallback, and
  `apply-mfa-alignment` can append MFA timings to an existing `.lltimeline.json`
  without rerunning WhisperX. Extended contract dry-runs for both production
  MFA entrypoints.
- 2026-06-19 15:19:15 CST: Completed the first MFA English US ARPA
  `align-one` TIMIT TEST 100 evaluation: 881/881 matched words, start MAE
  14.46ms, start P95 48.0ms, end MAE 18.20ms, end P95 53.0ms, tail mean abs
  34.12ms, tail P95 112.05ms, and no text mismatches. Updated Phase 4 docs to
  mark MFA as the strongest observed word-boundary aligner under a high-quality
  transcript/utterance-anchor condition, with WhisperX transcript + MFA as the
  next realistic production-route test.
- 2026-06-19 14:43:16 CST: Installed the local research-only MFA runtime via
  Homebrew `micromamba`, created the isolated MFA 3.3.9 environment under
  `~/Library/Caches/LLPlayerNext/research/mfa/env`, and updated the MFA setup
  and alignment sidecar scripts to force `MFA_ROOT_DIR` into the same research
  cache and prepend the MFA environment's `bin` directory to subprocess `PATH`
  so model files, MFA temporary defaults, and OpenFST/Kaldi binary resolution do
  not spill into `~/Documents/MFA` or the user's shell profile. Added a
  parallel `align-one` MFA sidecar strategy after batch `mfa align` reached
  successful first-pass alignment on TIMIT TEST 100 but failed in MFA's SQLite
  interval collection/export path with empty interval CSVs; `align-one` now
  resolves saved dictionaries and pre-extracted acoustic model directories
  before launching parallel jobs and gives each MFA child process an isolated
  `MFA_ROOT_DIR` to avoid concurrent model-cache extraction and
  command-history YAML writes.
- 2026-06-19 11:44:19 CST: Expanded the TIMIT TEST 100 alignment benchmark
  comparison across MMS_FA + TIMIT transcript, full WhisperX CLI, and
  WhisperX CLI + MMS_FA post-alignment; documented that MMS_FA remains the best
  current upper-bound route with a high-quality transcript, while the WhisperX
  CLI + MMS_FA post-pass improves start timing but regresses end/tail timing.
  Added the research-only MFA sidecar scaffold (`setup-mfa-research.sh`,
  `mfa-align-cli.py`) plus TextGrid parser contract coverage, with MFA
  installation and real runs still pending because this machine does not yet
  have `mfa`, `conda`, `mamba`, or `micromamba` available.
- 2026-06-19 11:00:47 CST: Implemented the M2.1 P1 tokenizer/evaluation
  guardrail: added shared `scripts/lltimeline_common.py`, moved benchmark,
  production, and evaluation tooling onto the same word normalization/token
  helpers, added regression coverage for multi-apostrophe words, and extended
  word timeline comparison reports with normalized text mismatch counts, rates,
  and samples.
- 2026-06-19 10:54:54 CST: Implemented the M2.1 P0 forced-alignment
  `word_index` contract fix: `align-cli.py` now emits `skipped: true`
  placeholders using unfiltered word indexes, `forced_align::merge_alignments`
  treats placeholders as per-word DTW fallback, contract tests cover CJK and
  punctuation skip cases, and ADR 0011 / M2.1 planning docs now match the
  existing top-level `timings[]` sidecar JSON shape.
- 2026-06-18 20:45:41 CST: Fixed the timeline-production research venv setup
  to install with `uv pip`, downloaded and smoke-loaded the WhisperX
  `large-v3` ASR stack plus the English wav2vec2 alignment model, added
  `scripts/timeline-production/whisperx-align-request.py` for known-transcript
  benchmark alignment, and produced the first TIMIT TEST 20 WhisperX alignment
  report: 171/171 matched words, start MAE 65.50ms, start P95 141.5ms, end MAE
  45.02ms, end P95 151ms, and tail lag mean -142.55ms.
- 2026-06-18 20:23:44 CST: Added TIMIT benchmark candidate tooling with
  `prepare-alignment-bundle` and `add-alignment-candidate`, fixed the MMS_FA
  sidecar for torchaudio 2.9 audio loading and tokenizer behavior, and produced
  the first real TIMIT TEST 20 MMS_FA evaluation report: 171/171 matched words,
  start MAE 56.38ms, start P95 128ms, end MAE 33.71ms, and end P95 81.5ms.
- 2026-06-18 20:15:11 CST: Validated local TIMIT full gold intake from
  `/Users/shadow/data/lisa/data/timit/raw`, generating local TEST/TRAIN
  LLTimeline gold resources under the research benchmark cache. Hardened the
  TIMIT converter for overlapping word rows, non-positive-duration rows,
  transcript-unmapped words, and leading/trailing apostrophe tokens, with
  smoke-test and contract validation coverage.
- 2026-06-18 19:47:03 CST: Reordered Phase 4 benchmark work to use existing
  high-quality gold corpora before CNN10/NBC self-built samples, documented the
  TIMIT → Buckeye → LibriSpeech alignments → news gold set sequence, added
  `scripts/benchmark-datasets.py timit-to-lltimeline` for local TIMIT
  `.WRD/.PHN/.TXT` conversion into `LLTimeline JSON v1`, and covered it with a
  synthetic TIMIT-style smoke fixture in contract validation.
- 2026-06-18 19:37:24 CST: Started Phase 4 evaluation work by adding
  document-level `compare-lltimeline` reports for comparing baseline,
  candidate, and gold word timelines inside one `.lltimeline.json`, including
  P95 boundary offsets, sentence-tail lag metrics, a multi-candidate LLTimeline
  fixture, contract validation coverage, and updated `.planning/` evaluation
  docs.
- 2026-06-18 19:30:22 CST: Completed Phase 3 Production Pipeline V1 by adding
  `production-report.json` generation for LLTimeline outputs, automatic report
  emission from `produce-whisperx`, contract validation for production quality
  reports, and `.planning/` status updates that move the project into Phase 4
  evaluation work.
- 2026-06-18 18:00:00 CST: Completed the `.planning/codebase/` documentation system.
  Renamed `CONVENTIONS.md` → `MAINTENANCE.md` (项目维护规则，与代码约定区分).
  Created three new codebase files: `STRUCTURE.md` (物理文件布局 + 新代码放哪),
  `CONCERNS.md` (技术债/已知问题/脆弱区域/测试缺口清单), and `CONVENTIONS.md`
  (项目级代码约定: crate 依赖规则、错误处理、异步、API 设计、Flutter/Python 模式).
  Added dedicated section for the unified test runner (`scripts/test.sh`) in TESTING.md.
  Co-Authored-By: Claude <noreply@anthropic.com>
- 2026-06-18 17:32:00 CST: Restructured the project documentation system by
  introducing the GSD-inspired `.planning/` directory as the project management
  hub. Moved `prd.md` → `.planning/PROJECT.md`, `roadmap.md` → `.planning/ROADMAP.md`,
  `requirements.md` → `.planning/REQUIREMENTS.md`. Created `.planning/STATE.md`
  as living project memory, `.planning/MILESTONES.md` as completed milestone index,
  `.planning/MAINTENANCE.md` as maintenance rules, and `.planning/codebase/` with
  ARCHITECTURE / STACK / DATA-MODEL / TESTING architecture skeleton docs.
  Consolidated `docs/discuss/` → `.planning/discuss/`, `docs/handoff/` →
  `.planning/handoff/`, `docs/timeline-production/` → `.planning/phases/2.0-
  production-engine/timeline-production/` (long-term subsystem). Migrated M2.0
  planning and feature docs from `docs/planning/`, `docs/features/`, and
  `docs/development/` into the 2.0-production-engine phase directory with
  upstream design notes in a dedicated `design-notes/` subdirectory. Frozen
  M1.x documents remain in `docs/` with index links from MILESTONES.md.
  Co-Authored-By: Claude <noreply@anthropic.com>
- 2026-06-18 16:08:50 CST: Added the `produce-whisperx` Phase 3 orchestration
  command to run media preparation, WhisperX execution, and LLTimeline
  conversion as one production pipeline entrypoint, with dry-run validation.
- 2026-06-18 16:06:35 CST: Added `run-whisperx` to the Phase 3 production
  pipeline with default/custom WhisperX command support, dry-run contract
  validation, run reports, and JSON output discovery for downstream LLTimeline
  conversion.
- 2026-06-18 16:02:53 CST: Extended the Phase 3 production pipeline with
  `prepare-media`, preprocessing artifacts, optional external vocal isolation
  command support, and LLTimeline artifact embedding for preprocessing reports.
- 2026-06-18 15:57:18 CST: Started Phase 3 production pipeline work with a
  research-only timeline-production script set, ffmpeg audio preparation,
  WhisperX JSON to `LLTimeline JSON v1` conversion, a sample WhisperX fixture,
  and contract validation coverage for the conversion bridge.
- 2026-06-18 15:53:09 CST: Completed Phase 2 resource lifecycle support for
  word timelines with summary, publish, archive-active, delete, OpenAPI/client
  coverage, and `lltimeline-resource.py` lifecycle commands; transcription job
  lifecycle methods are now represented in the handwritten local API client.
- 2026-06-18 15:36:01 CST: Completed the LLTimeline JSON v1 Phase 1 core by
  adding OpenAPI schemas, handwritten client methods, contract validation, and
  `scripts/lltimeline-resource.py` for validating, importing, and exporting
  `.lltimeline.json` files through the local API.
- 2026-06-18 15:21:41 CST: Added LLTimeline JSON v1 import support with
  `POST /v1/lltimeline/import`, round-trip HTTP coverage, and a minimal
  `.lltimeline.json` contract fixture that deserializes through the domain
  model.
- 2026-06-18 15:11:06 CST: Added the `docs/timeline-production/` documentation
  structure and started Phase 1 of the production-engine route with
  `LLTimeline JSON v1` domain contracts plus an HTTP export endpoint that wraps
  subtitle segments and active/candidate `WordTimeline` resources into a
  resource document.
- 2026-06-18 14:50:26 CST: Reframed the product definition around two
  coordinated tracks: a local heavy production engine for high-precision
  WordTimeline/PhoneTimeline/ChunkTimeline generation, evaluation, correction,
  and `.lltimeline.json` export; and a lightweight LLPlayerNext consumer that
  reads those resources for word highlighting and chunk playback without
  bundling heavy ASR/FA runtimes.
- 2026-06-18 11:40:04 CST: Transcription now preserves staged word timeline
  candidates from a single ASR run: raw Whisper DTW, MMS forced-alignment merge
  when available, and pause-refined final timings. The final stage is activated
  while prior candidates remain exportable for objective comparison without
  rerunning transcription.
- 2026-06-18 11:28:07 CST: Added a developer-facing word timeline evaluator
  that compares exported `WordTimeline` JSON files, reports weak DTW-vs-FA
  drift and anomaly metrics, optionally scores against gold word boundaries,
  and emits JSON/Markdown reports with smoke fixture coverage in contract
  validation.
- 2026-06-18 11:14:42 CST: Started Phase 1 word timeline resources with
  versioned `WordTimeline` domain contracts, SQLite schema v10 persistence,
  activation/archive semantics, active-timeline compatibility sync back to
  legacy `word_timings`, and HTTP management/export endpoints.
- 2026-06-18 11:07:27 CST: Added research-mode acoustic forced alignment for Whisper transcription:
  developers can prepare an isolated torchaudio MMS_FA venv, and transcription
  will auto-detect it, merge validated per-word aligned timings after DTW, and
  silently retain DTW timings when the sidecar is unavailable or fails.
- 2026-06-18 11:07:27 CST: Added transcription job regeneration and archiving
  support so subtitle timing experiments can rerun with current algorithms while
  old completed jobs stay queryable by id but hidden from the active job list
  and reuse lookup.
- Fixed development sidecar discovery: the Flutter desktop app now walks
  up directory ancestors to find the `api-http` binary (preferring
  `target/release` over `target/debug`), and the Rust API sidecar walks up
  from both its own executable path and the current working directory to
  locate `whisper-cli`, `ffmpeg`, and `ffprobe` inside
  `third_party/runtime/macos-arm64`. Together these fixes let the app find
  the full ASR toolchain when launched from anywhere inside the repository
  tree.
- Added `resolve_bundled_tool` and `runtime_candidates_from` to the
  transcription coordinator so the API sidecar discovers the bundled
  `whisper-cli` runtime by walking ancestor directories from both
  `current_exe` and `current_dir`. Flutter's sidecar resolution checks
  `target/release/api-http` before `target/debug/api-http`, so both
  profiles must be rebuilt after upgrading the Rust source.
- Started Milestone 2.0 Phase 0 with a fixed 60-slot real-speech evaluation
  catalog covering news, interview, conversation, speech rate, recording
  quality, and six target connected-speech phenomena.
- Added a provider-neutral phonetic evaluation tool that reports Phone Error
  Rate, detected-phone timeline validity, and subtitle-token association
  coverage, with success and failure smoke fixtures.
- Recorded candidate-provider roles, licensing constraints, a concrete Phase 0
  execution plan, and a proposed ADR that prevents product integration or
  `detected_in_audio` claims before quality and licensing gates pass.
- Added Vosk/Kaldi as a lightweight ASR and forced-alignment research baseline,
  without treating canonical decoder alignment as real detected-phone output.
- Proposed an AGPL/commercial dual-license direction and a permissive,
  versioned out-of-process provider SDK boundary while preserving the current
  no-license-granted repository state until legal and contributor preparation
  is complete.
- Added an isolated candidate-research harness that checks the pinned ZIPA
  dependency/artifact boundary, requires licensed external audio, rejects
  sequence-only output without phone timestamps, and records reproducibility
  and performance metadata.
- Added provider-neutral Milestone 2.0 domain contracts, schema v9 persistence,
  durable analysis jobs, detected-phone timelines, alignment findings, user
  feedback, API/events, and explicit model-management rejection paths.
- Added a deterministic research fixture that is disabled in normal builds,
  cannot be distributed as a model, never upgrades its low-confidence findings
  to `detected_in_audio`, and supports repeatable contract verification.
- Added desktop settings v8, current-sentence experimental analysis triggering,
  SSE progress refresh, detected-phone highlighting, and clearly labeled
  audio-detection results that remain hidden by default.
- Added focused widget coverage for the audio-analysis model/job center and
  distinct current-sentence and whole-track analysis triggers.
- Verified detected-phone highlighting across non-monotonic playback position
  changes and passed the existing packaged macOS build/runtime/signing smoke.
- Added `scripts/verify-m20.sh`, v8-to-v9 migration coverage, fake-provider
  idempotency checks, and low-confidence finding safety tests.
- Passed the complete M2.0 historical headless regression with 150 Rust tests,
  Flutter analysis, and 45 Flutter tests; the latest Flutter suite contains 46
  passing tests after the playback-position coverage increment.
- Passed the packaged macOS release build, bundled-runtime discovery, ad-hoc
  signing verification, extracted-package launch, video/audio smoke, and
  persistence checks.
- Milestone 2.0 remains incomplete: no real provider has passed the licensed
  evaluation, quality, performance, provenance, and distribution gates.
- Added an external evaluation-input manifest validator and preparation guide
  that check catalog membership, immutable audio checksums, explicit license
  decisions, bounded word/phone timelines, and independent human review before
  candidate development runs.
- Separated ZIPA code and model revisions and added a smoke-tested experimental
  CTC argmax frame-span projection, while retaining an explicit real-audio
  calibration gate before treating projected timestamps as stable.
- Added a research-only ZIPA CTC ONNX runner and explicit opt-in environment
  setup with pinned dependencies, separate code/model revisions, and
  checksum-verified external downloads.
- Started C2 acoustic-first partition quality with partitioner V2. Gap scoring
  now uses source-specific thresholds for ASR-reported, forced-aligned, and
  user-adjusted timings, while estimated timings remain excluded from acoustic
  evidence.
- Added moderate-gap evidence that can combine with punctuation support without
  overriding phrase protection on its own. Strong acoustic gaps remain able to
  split inside a text phrase.
- Treat punctuation from known ASR-generated subtitle tracks as inferred model
  output instead of a forced boundary. Inferred punctuation must combine with
  acoustic or product evidence before it changes the display partition.
- Reduced weak-evidence single-word fragments at chunk edges and added
  regression tests for ASR punctuation reliability, timing-source sensitivity,
  phrase protection, and fragment suppression.
- Added structured sentence chunk diagnostics containing selected and rejected
  boundary candidates, raw scores, thresholds, forcing state, primary source,
  and evidence. Product-facing partition responses remain unchanged.
- Added an initial golden calibration baseline covering ordinary short
  sentences, preferred-length splitting, single-word-tail suppression, and
  decisive acoustic gaps.
- Completed C2 acoustic-first partition quality. Readability scoring now
  favors supported boundaries near the preferred chunk length, weak evidence
  cannot create undersized fragments, soft/hard length limits prevent
  protected phrases from producing unreadably long chunks, and stronger
  phrase protection still yields to decisive acoustic gaps.
- Added a version-controlled V2 golden corpus covering fast speech, hesitation,
  moderate pauses, ASR-inferred versus trusted punctuation, fixed expressions,
  and long subtitles. The corpus enforces fragment and overlong-chunk quality
  bounds.
- Added `GET /v1/subtitles/{track_id}/chunk-diagnostics` for inspecting selected
  and rejected candidates using the same source-aware configuration as the
  product-facing track partition.
- Completed C3 rich acoustic evidence with partitioner V3. An independent
  pre-boundary-lengthening provider compares real word duration against a
  robust local baseline and can select meaningful boundaries without a pause.
- Added a conservative filled-pause hesitation provider that lowers boundary
  confidence around ASR-recognized `uh`, `um`, `erm`, `hmm`, and `mm` tokens.
  Ordinary hesitation gaps are suppressed while very large pauses remain
  eligible boundaries.
- Rich evidence is provider/version attributed, includes concrete measurement
  details, appears in existing chunk diagnostics, and is consumed as bounded
  signed score changes. Estimated timings and disabled/missing providers
  exactly degrade to C2 behavior.
- Added a C3 golden corpus covering no-pause lengthening, ordinary word
  durations, hesitation-gap suppression, and decisive pauses that survive the
  hesitation penalty.
- Completed C4 with an optional learned prosodic boundary provider and
  partitioner V4. The bundled project-authored MIT linear model runs locally,
  emits provider/revision/license-attributed evidence, and can assist only
  ambiguous rule-based boundaries.
- Added `GET /v1/chunk/providers` for inspecting learned-provider availability,
  runtime, and distribution metadata. Model or feature failures emit no
  evidence, and disabling the provider exactly preserves the C1-C3 pipeline.
- Added a C4 golden corpus covering learned-model contribution, ordinary
  delivery, decisive rule boundaries, and model-disabled fallback.
- Changed the default chunk presentation to static rounded capsules with clear
  visual spacing while preserving word-level highlighting inside each chunk.
  Current-chunk highlighting is now disabled by default and independently
  configurable as static background, slow scale bounce, or slow glow.
- Added an optional spacing-only chunk presentation and migrated existing v7
  desktop settings to the new static-capsule default.
- Added the Word Timing Accuracy milestone. Whisper DTW v2 now ignores
  punctuation timestamps when deriving lexical word edges and gives lexical
  alignment points a bounded duration so punctuation cannot consume audible
  pauses.
- Added optional local PCM energy pause refinement during Whisper
  transcription. Sustained audible pauses near coarse DTW boundaries restore
  adjacent word gaps as provider-attributed `ForcedAligned` timings, while
  missing or unsupported audio safely retains DTW timings.
- Changed timing precedence so refined forced alignment can replace coarse ASR
  timing while user-adjusted timing remains authoritative. Added
  `GET /v1/subtitles/{track_id}/word-timing-diagnostics` for inspecting final
  gaps and adjacent timing providers.
- Existing ASR tracks remain unchanged and must be re-transcribed to receive
  DTW v2 and audible-pause refinement.

## 0.7.2 - 2026-06-14

- Added the first user-visible chunk listening MVP. Primary subtitle sentences
  are rendered as complete, non-overlapping chunk groups and the active chunk
  follows playback using the existing local word-timing timeline.
- Added the stable `SentenceChunkPartition` display contract and V1
  acoustic-first rule partitioner. Real timing gaps, punctuation, phrase
  protection, and deterministic length fallback are resolved into one complete
  partition while estimated timings are excluded from acoustic evidence.
- Added `GET /v1/subtitles/{track_id}/chunk-partitions`, application-layer
  sentence and track partition methods, OpenAPI coverage, and independent
  fallback so chunk analysis failure never interrupts ordinary subtitles,
  word highlighting, or pronunciation enhancements.
- Added desktop chunk grouping and active-chunk highlighting settings. Chunk
  rendering preserves word clicks, vocabulary styles, and phrase interactions.
- Hardened text and acoustic chunk detection by rejecting invalid external
  phrase ranges, preventing phrase matches across punctuation, preserving
  empty-input sentence identity, and correcting gap-confidence interpolation.
- Added the staged C0-C4 chunk listening implementation plan. C0-C1 deliver the
  product loop; later milestones prioritize acoustic boundary quality and keep
  the display/API contract stable.
- Verified with workspace Rust tests, strict targeted clippy, Flutter analysis,
  Flutter tests, and whitespace checks.

## 0.7.1 - 2026-06-13

- Implemented text-level (lexical) chunk detection in the `speech-analysis` crate
  (`text_chunk_detection` module) as a companion to the existing acoustic
  (gap-based) chunk detection. The text detector partitions entire sentences
  into contiguous chunks where every word token belongs to exactly one chunk.
- Three data sources feed the text detector: (1) COCA n-gram collocations
  (MI ≥ 3.0, ~1K seed entries, compiled into the binary via `include_str!`),
  (2) PHRASE List (Martinez & Schmitt 2012, 505 pedagogically-selected
  functional phrases with category labels), and (3) existing ECDICT/built-in
  phrase candidates forwarded from the application layer.
- Sliding-window longest-match-first greedy overlap resolution ensures
  competing multi-word spans (e.g. "a lot of" vs "a lot") are resolved
  deterministically with longer spans taking priority.
- Cross-reference support between acoustic and text layers: new
  `BoundaryMarker::LexicalPhrase` variant, `CombinedChunkResult` type,
  `combine_chunks()` merging acoustic and text evidence with four-quadrant
  confidence logic (mutual-reinforcement, acoustic-only discount, text-only
  discount, no-signal), and `annotate_acoustic_with_text()` for decorating
  acoustic boundaries with lexical phrase markers.
- Added `AppServices::detect_text_chunks`, `detect_text_chunks_for_track`,
  and `detect_combined_sentence_chunks` methods.
- 18 new unit tests across `text_chunk_detection` covering empty/single-word
  input, COCA collocation matching, PHRASE List detection, external candidate
  forwarding, longest-match resolution, case-insensitive matching, partition
  coverage integrity, boundary count consistency, token order preservation,
  punctuation filtering, MI→confidence mapping, and source counts.

- Enabled whisper.cpp DTW (Dynamic Time Warping) token-level timestamps during
  ASR transcription so generated subtitle tracks produce `asr_reported` word
  timings instead of falling back to the weighted estimator.
- Added `-ojf` (JSON-full) and `-dtw <preset>` flags to the whisper-cli
  invocation. The JSON-full output carries per-token `t_dtw` cross-attention
  alignment timestamps in centiseconds.
- New `asr_timing` module merges whisper subword tokens into lexical words by
  leading-whitespace rules and produces `WordTiming` entries with
  `timing_source = asr_reported`.
- DTW is enabled only for `whisper`-family models; custom models skip the step.
- Every stage degrades safely: unavailable `t_dtw` values, segment count
  mismatches, word count mismatches, boundary violations, and non-monotonic
  timestamps all fall back to the existing deterministic weighted estimator on a
  per-sentence basis.
- The Flutter frontend, database schema, and `timing_priority` logic required
  zero changes — `AsrReported` (priority 3) already overrides `Estimated`
  (priority 1) in the existing word-timing pipeline.
- Established a unified testing workflow (`scripts/test.sh`) that consolidates
  `cargo fmt`, `clippy`, `test`, `flutter analyze`, `flutter test`, and contract
  validation into a single command with structured pass/fail summary output.
  Supports `--quick`/`--rust`/`--flutter`/`--full` modes, `--json` for
  machine-readable CI/AI output, `--verbose` for raw logs, `--debug` for
  internal tracing, and `--strict` to require `Cargo.lock`, deny Rust warnings,
  and make Flutter infos/warnings fatal. Successful-run logs are deleted;
  failed-run logs remain at the reported path while the terminal prints only
  the summary and key error lines.
- Extracted shared test utilities (`scripts/lib-testing.sh`) from the six
  `verify-m*.sh` acceptance scripts: cargo resolution, API lifecycle
  (start/stop/wait), curl helpers, and JSON assertion functions.
- Added the project's first Rust integration test
  (`crates/speech-analysis/tests/asr_timing_integration_test.rs`) with a
  real whisper `-ojf` JSON fixture covering subword merge, `t_dtw=-1` filter,
  special tokens, repeated DTW points, and boundary/segment-count mismatch
  fallback.
- Completed the ASR timing fix against real bundled whisper.cpp output:
  `[_BEG_]` / `[_TT_*]` special tokens and punctuation no longer corrupt the
  final lexical word, merged words are text-validated before mapping, repeated
  DTW points become deterministic non-empty intervals, and zero-duration word
  timings are rejected by the storage contract. Previously stored zero-length
  timing caches are detected as unusable and automatically fall back to the
  deterministic estimator.
- Updated CI to invoke `./scripts/test.sh --rust` and `--flutter` instead of
  individual `cargo`/`flutter` commands, keeping the same check coverage while
  producing more actionable failure logs.
- Migrated all 6 `verify-m*.sh` acceptance scripts to source `lib-testing.sh`,
  eliminating duplicated cargo resolution, API lifecycle, cleanup traps, and
  curl helpers. `setup_test_dir()` now registers cleanup automatically, API
  startup restores signal handling for graceful shutdown, and M1.7/M1.8 use
  the shared environment-aware `start_api()` path. Fixed schema drift (v6→v8)
  in verify-m17 and verify-m18 that accumulated across milestones.
- Added the project's second Rust integration test suite
  (`crates/persistence-sqlite/tests/persistence_integration_test.rs`) covering
  file persistence across reopen, migration backup creation, concurrent access
  safety, subtitle import/export, and media availability lifecycle (6 tests,
  25 total for the crate).
- Added `cargo-llvm-cov` coverage collection to CI (`lcov.info` artifact) for
  tracking coverage trends across PRs.
- Fixed the dictionary-provider parallel-test flake by replacing PID/time-based
  fixture paths with `tempfile::NamedTempFile`; 50 repeated parallel runs pass.
- Added 42 unit tests to the `application` crate (previously zero coverage)
  covering `require_text`, `clean_optional`, `normalize_american_english` (19
  irregular/suffix rules), `normalize_phrase`, `phrase_candidates` (including
  token boundary and non-word-token handling), `lexical_from_word`,
  `lexical_source_from_word`, and `timing_priority`. Total workspace tests
  increased from 58 to 100+.
- Fixed a boundary bug in `phrase_candidates` where sentences shorter than a
  phrase's word count could trigger an out-of-bounds index panic; corrected
  the window count formula.
- Set CI coverage gate at 50% line coverage (`--fail-under-lines 50` in the
  coverage job) to prevent coverage regressions, with a planned increase to
  55%+ as test coverage expands.
- Enhanced `./scripts/test.sh --quick` to include `cargo test --workspace
  --lib` (unit tests only, excluding integration/doc tests) while remaining
  under 30s. Quick mode now runs: fmt → clippy → lib unit tests → analyze.
- Added fuzz testing infrastructure with 3 fuzz targets:
  `crates/subtitle-core/fuzz/` (SRT and WebVTT parsing),
  `crates/speech-analysis/fuzz/` (ASR timing JSON extraction). The manifests
  are independent workspaces with committed lock files, the ASR target matches
  the current API, and CI runs every target for a 10-second nightly-Rust smoke
  test.
- Rewrote `testdata/README.md` as a comprehensive fixture catalog documenting
  every test data file, its purpose, and which tests consume it.
- Created `docs/features/testing-milestone.md` as the tracking document for
  the test system improvement initiative with P0/P1/P2 tiered goals and
  progress tracking.
- Added 16 unit tests to the `diagnosis-core` crate (2 → 18) covering all
  `diagnose` function branches: `MeaningBarrier`, `RecognitionBarrier`,
  `InsufficientInformation`, `OtherFactors`, mixed scenarios, non-word token
  filtering, `None` status handling, duplicate lemma dedup, and edge cases.
- Added `criterion` performance benchmarks for `subtitle-core` (SRT/VTT parse,
  tokenize, normalize) and `speech-analysis` (ASR timing extraction, word
  timing estimation). 10 benchmark cases in total covering small fixtures and
  large synthetic inputs (2k sentences, 500 segments). CI compiles all
  benchmarks with `cargo bench --workspace --no-run --locked`.
- Added `proptest` property-based testing with 10 property tests across
  `speech-analysis` (timing output count, monotonicity, bounds, start≤end)
  and `subtitle-core` (normalize idempotence, tokenize word normalization,
  SRT/VTT no-panic, SRT draft field validity). Total workspace tests: 132.
- Added API surface regression test (`openapi_version_snapshot`)
  in `api-http` that snapshots the OpenAPI 3.1.0 version, 51-path count, 18
  key schema definitions, and /v1/ prefix convention. Full semantic
  breaking-change detection remains future work.
- Added `scripts/test-infrastructure.sh` to test cleanup traps, API process
  teardown, quick/full mode selection, strict flags, JSON output, and retained
  failure logs. CI runs this self-test before desktop checks.
- Added `scripts/test.sh --low-memory` to limit Cargo, Rust-test, Rayon, and
  Flutter-test concurrency, reuse Flutter dependency resolution, and diagnose
  child exit code 137 as `SIGKILL` / external resource enforcement. Human
  output now emits a lightweight progress heartbeat before each check so quiet
  commands remain visible to external executors.
- Added a focused ASR word-timestamp handoff documenting the completed
  real-whisper validation, fallback/storage invariants, verification baseline,
  and the current environment's direct-script `SIGKILL` limitation.
- Prevented quick/full mode duplication: the Rust lib-test subset now runs only
  in `--quick`, while Rust/full modes execute the complete suite once.
- Fixed Rust test pass-through handling so arguments after the runner's `--`
  are forwarded after Cargo's test-harness separator.
- Added `.claude/worktrees/` to `.gitignore` so local product/refactor worktrees
  are not accidentally staged.

## 0.7.0 - 2026-06-13

- Integrated the modular Flutter controller/widget architecture while
  preserving Milestone 1.9 pronunciation and word-sync behavior.
- Fixed nullable controller state so media, subtitle, selection, diagnosis,
  and loop state can be cleared without retaining stale values.
- Provider-neutral pronunciation, phoneme, speech-rule, and word-timing
  contracts with schema v8.
- Pinned CMUdict canonical en-US pronunciation with deterministic fallback,
  lexical stress, ARPAbet, IPA display, variants, and token mapping.
- Deterministic bounded word timings for ordinary subtitles and local
  current-word highlighting that remains correct after seek, loop, and rate
  changes.
- Rule-based weak form, contraction, linking, flapping, deletion, and
  assimilation hints from a fixed 18-rule catalog that explicitly does not
  claim real-audio detection.
- Provider/version-isolated canonical pronunciation caching, explicit cache
  invalidation events, and non-blocking track jobs with cancellation and retry.
- Desktop settings v7, pronunciation diagnostics, API/event contracts, and
  Milestone 1.9 automated verification.
- Fixed current-word timing loading by reading the API contract fields
  `timing_source` and `provider_id`.
- Added background, scale-bounce, and glow current-word styles while keeping
  word-timing provenance in diagnostics instead of the playback overlay.
- Confirmed AV1 playback during collaborative functional acceptance.
- Removed the startup stall caused by re-hashing installed learning resources,
  added an explicit core-starting/error/retry screen, and fixed short-sentence
  ECDICT phrase scanning.
- Completed collaborative functional acceptance. Independent Developer ID
  distribution signing and notarization remain deferred release work.

## 0.6.0 - acceptance candidate

- Unified word and user-confirmed phrase learning assets with schema v7 and
  vocabulary asset bundle v3.
- Versioned lemma normalization, persistent corrections, and phrase candidates.
- Clickable phrase underlines in learning subtitles; confirmed phrases remain
  independent assets with their own status and source ranges.
- Explicit checksum-verified ECDICT and CMUdict resource manager.
- Provider-neutral OpenSubtitles title, filename, and media-hash workflows.
- Provider-supplied pronunciation audio in the unified word learning panel.
- Vocabulary asset v3 import preserves newer local state and independently
  merges learning content, history, and durable source encounters.

## 0.5.0 - 2026-06-10

Milestone 1.7 local ASR learning subtitle release.

- Provider-, runtime-, model-, and profile-neutral transcription contracts.
- Durable single-concurrency whole-media jobs with progress, cancellation,
  retry, restart interruption handling, provenance, and idempotent completion.
- whisper.cpp model catalog, explicit verified downloads, custom model
  registration, model management, and persistent job center.
- Generated subtitles become ordinary interactive learning tracks and support
  SRT export.
- Reproducible macOS arm64 whisper.cpp and LGPL-only FFmpeg runtime build,
  license validation, application bundling, and deterministic fake-runtime
  acceptance test.

## 0.4.1 - 2026-06-10

- Draggable viewport-relative subtitle placement, independent primary/secondary
  font controls, and a stable video viewport when subtitle visibility changes.
- Restored the media-kit video texture layout after the subtitle overlay
  refactor, fixing the black video screen regression.

## 0.4.0 - 2026-06-10

Milestone 1.6 desktop learning experience release.

- Responsive subtitle presets and automatic native-subtitle suppression.
- Simplified Chinese and English desktop localization.
- TXT/CSV existing vocabulary import with conflict-safe status initialization.
- Unified word learning panel with durable user definitions and notes.
- Provider-agnostic aggregated dictionary API and multi-source UI.

## 0.3.0 - 2026-06-10

Milestone 1.5 vocabulary learning asset release.

- Status-driven vocabulary books with user-selected status as the authority.
- Durable status history and source sentence snapshots.
- Missing-media recovery and independent vocabulary asset backup/restore.
- Latest-effective context observations with clear support.
- Schema v4 migration with legacy history and source backfill.

## 0.2.0 - 2026-06-09

Milestone 1 macOS Apple Silicon MVP.

### Added

- Local video/audio playback and complete subtitle-learning loop.
- SRT/WebVTT import, interactive transcript, sentence navigation and loop.
- Word status, dictionary lookup, context observations, and diagnosis.
- Dual text subtitles with independent offsets.
- Drag-and-drop import and configurable subtitle appearance/layout.
- Embedded text-subtitle extraction through optional ffprobe/ffmpeg.
- Online-media URL resolution through optional yt-dlp.
- Versioned local settings, progress recovery, diagnostics, and release package.

### Deferred

- Windows/Linux, OpenSubtitles, bitmap subtitle interaction, mobile, ASR, and
  translation.
