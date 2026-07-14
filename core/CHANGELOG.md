# Changelog

## Unreleased

- 2026-07-14 09:05 CST: main.dart 拆分 S7b —— 字幕资源类对话框/导航流程迁往
  `widgets/flows/subtitle_resource_flows.dart`（沿用 `media_import_flows.dart` 顶层
  flow 函数既有模式，非 coordinator）：`deleteSubtitleResourceFlow`/
  `exportSubtitleResourceFlow`/`generateSubtitlesFlow`/`openTranscriptionCenterFlow`/
  `openPhoneticAnalysisCenterFlow`/`openSubtitleResourcesFlow`/`openColdStartMarkingFlow`。
  宿主保留同名薄 wrapper 转调（R3：最小化 build 改动面）；`_generateSubtitles` 的
  setState 任务登记改注入 `recordTaskStatus` 回调（刻意不复用 `_setTaskStatus`，
  后者会额外覆盖 player status 文本，保持逐字语义）。新增
  `test/subtitle_resource_flows_test.dart`（4 例 widget test：删除取消/确认发
  DELETE、导出 null-api 不弹窗、导出双格式渲染与 dismissal）。main.dart
  1842 → 1737 行。`flutter analyze` 零问题、`flutter test` 334 全通过（330 + 4）。

- 2026-07-14 08:52 CST: main.dart 拆分 S7a —— 抽出 `SubtitleSourcesCoordinator`（仅上下文
  无关子集）：`ensureCurrentPronunciation`/`analyzePhonetics`/`handleDrop`/`isMediaPath`/
  `isSubtitlePath` 逐字搬到 `lib/controllers/subtitle_sources_coordinator.dart`，注入
  `getApi`/`isMounted`/`showSnackBar`/`setTaskStatus`/`openMediaPath`/`openSubtitlePath`。
  对话框驱动的来源流程（delete/export/generate/import word list/cold-start 等）按 S5 既定
  裁决留在宿主，后续 S7b 评估迁往 `widgets/flows/` 既有模式。逻辑/字符串不变。新增
  `test/subtitle_sources_coordinator_test.dart`（9 例：扩展名分类、drop 路由/前置守卫/
  不支持类型、发音缓存与去重、phonetics 无轨守卫/成功派发/失败上报）。main.dart
  1937 → 1842 行。`flutter analyze` 零问题、`flutter test` 330 全通过（321 + 9）。

- 2026-07-14 08:47 CST: main.dart 拆分 S6 —— 抽出 `MediaLibraryCoordinator`。首页媒体库/
  triage 动作 9 个方法（`recordRecentMedia`/`prefetchHomeSummary`/`loadMediaLibrary`/
  `openLibraryEntry`/`startExtensiveFromLibrary`/`startIntensiveFromLibrary`/
  `setLibraryTriageIntent`/`toggleFamiliarSupply`/`continueRecentMedia`）逐字搬到
  `lib/controllers/media_library_coordinator.dart`；coordinator 自持 `savedVocabulary`/
  `mediaLibrary` 两个首页汇总事实（原 State 字段），`setState` 改注入 `requestRebuild`；
  media-session 操作按 PLAN R5 走注入回调（`openMediaPath`/`openMedia`）而非直接持有
  coordinator。逻辑/字符串不变。新增 `test/media_library_coordinator_test.dart`（11 例：
  加载成功/失败保留旧值/null API no-op、缺失文件守卫、triage 就地替换与失败上报、continue
  回退拣选器/重开近期路径、recordRecentMedia 无媒体 no-op）。main.dart 2051 → 1937 行。
  `flutter analyze` 零问题、`flutter test` 321 全通过（310 + 11）。

- 2026-07-14 01:15 CST: main.dart 拆分 S5 —— 抽出 `VocabularyActionsCoordinator`（仅上下文无关
  数据方法）。vocabulary 入口大量 BuildContext 耦合（`showDialog`/`Navigator.push`/
  `MaterialPageRoute`），按代码库约定「coordinator 无 context、对话框留宿主」，这些导航/对话框
  方法保留在 State；可抽子集为 10 个纯数据方法：`loadWordEntries`/`loadPhraseEntries`/
  `loadPhraseCandidates`/`openWord`/`setSelectedWordStatus`/`setCapabilityOverride`/
  `saveSelectedLearningContent`/`recordCurrentSource`/`markFirstWord`/`observeSelected`，连同
  私有 `_sourceFor`（仅被这些方法使用，随之内化）逐字搬到
  `lib/controllers/vocabulary_actions_coordinator.dart`，注入 `getApi`/`isMounted`/`text`/
  `refreshDiagnosis`，其余用归位后的 `settings.resolveLearningLanguage`。逻辑/字符串不变。新增
  `test/vocabulary_actions_coordinator_test.dart`（markFirstWord 必刷 diagnosis、无选择的
  observeSelected 静默 no-op）。main.dart 2206 → 2051 行。`flutter analyze` 零问题、`flutter test`
  310 全通过（308 + 2）。

- 2026-07-14 00:50 CST: main.dart 拆分 S3+S4（合并）—— 抽出 `PracticeActionsCoordinator`。
  精听练习与 shadowing 深度交织（`_navigatePracticeSentence` 同时派发 cloze 与 shadowing、
  `_replayPracticeWindow`/`_setShadowingStep` 共享），故合为单个 coordinator 避免跨 coordinator
  循环依赖。19 个方法（四种练习启动、练习窗循环、提交、录音/回放/ABA、rate/step、external/
  slice-window shadowing、复习保存、句子导航、teardown）逐字搬到
  `lib/controllers/practice_actions_coordinator.dart`；注入 `getApi`/`isMounted`/`refreshDiagnosis`/
  `seekCue`，`tools` 由持有的 settings 内部派生，其余全用 S2.5 归位后的 `playbackActions.*` 与
  `settings.resolveLearningLanguage`。逻辑/字符串不变；~24 处调用点改走 coordinator。新增
  `test/practice_actions_coordinator_test.dart`（4 例：无 draft replay no-op、submit 必刷 diagnosis
  回调、无目标句不 seek、无 attempt 不改状态）。main.dart 2469 → 2206 行。`flutter analyze`
  零问题、`flutter test` 308 全通过（304 + 4）。

- 2026-07-14 00:25 CST: main.dart 拆分 S2.5 —— 把跨领域共享 glue helper 归位到自然属主，
  为后续 coordinator 抽取降低注入面。`_mediaTimeMs` 与 `_currentPracticeChunk(s)` 迁入
  `PlaybackActionsCoordinator`（已持 `mediaTime`/`currentChunkRef`/subtitle）；`_learningLanguage`
  改为 `SettingsController.resolveLearningLanguage(trackLanguage)`，main.dart 16 处调用点改为
  `settingsController.resolveLearningLanguage(subtitleController.primaryTrack?.language)`。
  `ListeningInboxCoordinator` 随之去掉 `mediaTimeMs` 注入，直接用 `playbackActions.mediaTimeMs`。
  `_sourceFor`（仅 vocab 使用）留待 vocab slice。逻辑逐字不变；新增 3 例测试（coordinators_test
  的 mediaTimeMs/practice-chunk 空态、settings_test 的 resolveLearningLanguage 优先级）。
  `flutter analyze` 零问题、`flutter test` 304 全通过（301 + 3）。

- 2026-07-14 00:05 CST: main.dart 拆分 S2 —— 抽出 `ListeningInboxCoordinator`。把
  `_captureListeningInbox` / `_refreshListeningInbox` / `_replayListeningInboxItem` /
  `_processListeningInboxItem` 四个方法逐字搬到 `lib/controllers/listening_inbox_coordinator.dart`
  （注入 `getApi`/`isMounted`/`mediaTimeMs` + 复用既有 `playbackActions`），逻辑/字符串不变。
  `_hardInterruptListening` 与 `_toggleExtensiveListening`（含 `showDialog` 与跨 slice
  `_refreshDiagnosis` 依赖）暂留 State，待其依赖抽出后处理；两个 `loopRange` 方法后续归入
  `PlaybackActionsCoordinator`。新增 `test/listening_inbox_coordinator_test.dart`（3 例：process
  review-item 分支、null-range replay 守卫、null-api no-op）。main.dart 2527 → 2476 行。
  `flutter analyze` 零问题、`flutter test` 301 全通过（298 + 3）。

- 2026-07-13 23:40 CST: main.dart 拆分 S1 —— 抽出 `HuntingActionsCoordinator`。把
  `_toggleHuntingMode` / `_reindexHuntingCorpus` / `_answerHuntingCheck` 三个方法逐字搬到
  `lib/controllers/hunting_actions_coordinator.dart`，仅做 seam 改写（`api`→`getApi()`、
  `mounted`→`isMounted()`、`l.text`→注入 `text()`、controller 接收者按现有 coordinator 短命名）；
  逻辑/分支/字符串不变。`_PlayerScreenState` 新增 `huntingActions` 字段 + `initState` bind，
  3 处调用点改走 coordinator。新增 `test/hunting_actions_coordinator_test.dart`（5 例：toggle
  启/停、reindex 成功/失败、null-api no-op），复用既有 `LocalApi.withTransport` fake。main.dart
  2578 → 2527 行。`flutter analyze` 零问题、`flutter test` 298 全通过（293 + 5）。

- 2026-07-13 23:20 CST: 立 `main.dart` Coordinator 抽取治理 mini-phase 的可执行 PLAN
  （`.planning/phases/main-dart-coordinator-extraction/PLAN.md`）。核实 `_PlayerScreenState`
  从 2.23 的 1457 行回涨至 2578 行，且无任何测试 mount `PlayerScreen`、State 无 DI，故整屏
  widget 测试不可行；测试网改建在代码库既有的 Coordinator 隔离单测层。PLAN 按现有
  `media_session_coordinator` 模板，分 Slice 0（fakes + 前置）+ S1–S7（Hunting / Inbox /
  Shadowing / Practice / Vocabulary / MediaLibrary / SubtitleSources），逐 Slice test-first、
  逐字搬移、analyze+test+对拍验证；`initState`/`dispose`/`build`/视图组合与高频 `_onPosition`
  保留在 State。属语义重构（非机械搬移），与本次 lexical/timeline 两个纯机械拆分区分。

- 2026-07-13 23:05 CST: 机械拆分 `apps/desktop/lib/models/timeline.dart`（2837 → 10 行 library +
  6 个 part 文件，最大 `rhythm.dart` 965 行，均低于 AGENT.md 1500 行阈值）。采用 Dart
  `part`/`part of`：原文件零 import、完全自包含，故 43 处 `import 'models/timeline.dart'` 全部
  保持不变。按子领域切分：`timeline/subtitle.dart`（token/cue/track/capabilities）、`word_chunk.dart`
  （Word/Chunk timeline + evidence + SenseGroup）、`sound.dart`（PhoneTimeline + sound 原语）、
  `rhythm.dart`（RhythmFrame 模型全族）、`document.dart`（LLTimeline document/metadata/artifact/
  DetectedPhone）、`display.dart`（DisplayChunk/partition/cursor）。逐字搬移，脚本验证 2618 非空行
  与原文完全一致（仅 dart format 空行规整）。`flutter analyze` 零问题、`flutter test` 293 全通过、
  未违反 ADR 0014（手写解析不变，仅分文件）。

- 2026-07-13 22:47 CST: 机械拆分 `persistence-sqlite/src/lexical.rs`（1801 → 948 行，低于
  AGENT.md 1500 行阈值）。按子领域抽出三个子模块：`lexical/import_export.rs`（bulk
  import/export + capability-state 持久化的两个 inherent impl 块 + `merge_imported_entry`）、
  `lexical/capability.rs`（capability profile/state 读写 helper）、`lexical/rows.rs`（row 反序列化
  + sense-folder/observation reader）。`LearningAssetRepository` trait impl 因 Rust 不允许 trait
  impl 跨文件拆分，保留在 `lexical.rs`。纯搬移不改逻辑；`export_lexical_assets`/
  `import_lexical_assets` 升为 `pub(crate)` 以保持 tests 可见。`cargo test -p persistence-sqlite`
  110+5+6 全绿，workspace build 通过，clippy 告警数 19 与拆分前完全一致（零回归）。

- 2026-07-13 19:30 CST: Phase 3.9.2 Syntax Provider Product Activation 收口。corrected v2
  holdout、逐 query qualification、spaCy opt-in lifecycle、单 batch/逐句共享编排、真实媒体与
  missing/corrupt/invalid/timeout 降级全部通过；contracts、句法相关 crates 与 Rust workspace
  全绿。最终裁决为 spaCy artifact + B `going_to`/`used_to`/`have_to` + SenseGroup + matcher
  qualified，B `want_to` fallback-only；base bundle +0B，C/ChunkTimeline/Construction identity
  边界冻结。PLAN/STATE/CLOSEOUT 已更新，phase 转 COMPLETED。

- 2026-07-13 19:22 CST: Phase 3.9.2 激活可选 spaCy 共享句法产品 capability。application
  新增单次 probe/batch、逐句 finalise 的 consumer orchestrator；同一 artifact ID 供已资格
  B（`going_to` / `used_to` / `have_to`）、syntax-aware SenseGroup 与 dependency candidate
  matcher 共用，`want_to` 继续精确 text fallback。新增 HTTP/OpenAPI composition、未配置/timeout/
  坏树逐句隔离测试；base 路径不启动 Python。fresh opt-in 安装以 fully pinned spaCy 3.8.13 +
  `en_core_web_sm` 3.8.0 实测通过 probe 与 development v2，clean install 162,250,752 bytes，
  base bundle +0B；runtime/model/training-data 许可与安装/刷新/停用/卸载分别审计。模型 identity
  排除非内容 `__pycache__/*.pyc` 后在 research/fresh venv 稳定一致；真实媒体 244 cues 中唯一
  双 root 句单独 fallback，不影响其余句，句法仍不进入 C、不替代 ChunkTimeline、不铸造
  Construction identity。

- 2026-07-13 18:57 CST: Phase 3.9.2 Slice 0 建立 corrected syntax qualification v2。冻结旧 v1
  历史，新增 development/validation v2、独立 digest 与 scorer，把 attachment gold、产品歧义
  policy 和 artifact validity 分层，并改为逐 consumer query 授权。spaCy 开发/锁定验证均达到
  100% lexical/exact mapping、零 silent/tree issue；`going_to`、`used_to`、`have_to` 各自 100%
  qualified。basic dependency 无法稳定区分 want-to wh subject/object，且锁定歧义例 raw allow，
  因而 `want_to` 明确为 `fallback_only`，不能再整体否决 artifact，也不能整体放行 provider。

- 2026-07-13 18:45 CST: 新建 Phase 3.9.2 Syntax Provider Qualification Correction and Product
  Activation。纠正 3.9.1 将 `Which team do you want to win?` 的保守 block policy 当作唯一
  parser attachment gold 的评估错误；冻结旧报告，另建 v2 subject/object 清晰最小对照和
  ambiguous-abstain gate。首选 spaCy 作单一产品候选；若修正版资格通过，则在不让 Python/model
  成为基础产品硬依赖的前提下，让 B、syntax-aware SenseGroup 与 Construction candidate matcher
  共享同一 validated artifact，并保留 C/ChunkTimeline/Construction identity 边界和无模型 fallback。

- 2026-07-13 16:53 CST: Phase 3.9.1 Shared Syntactic Analysis Provider 收口。完整 contracts 与
  Rust workspace 测试通过；PLAN/STATE/CLOSEOUT 记录负向资格结论：Stanza/spaCy 共享中立契约、
  token mapping、sidecar failure taxonomy、B/SenseGroup consumer 与 Construction candidate
  matcher 均已验证，但两个候选都因锁定 wh-extraction 高风险假阳性不得激活。模型、runtime、
  treebank/training provenance 分层审计完成；无模型产品路径保持原 B 与 rule SenseGroup，句法
  不进入 C、不替代 ChunkTimeline、不铸造 Construction identity。

- 2026-07-13 16:48 CST: Phase 3.9.1 Slice 6 建立 Construction dependency matcher seam 与真实
  媒体 QA。matcher 只在 qualified + activatable artifact 上输出带 source artifact、subtitle
  token span 与 bindings 的可重建候选，类型和序列化守卫证明不会铸造 Construction canonical/
  occurrence identity 或 capability。以 owner 本地 244 cue / 1773 word 新闻字幕运行 Stanza/
  spaCy：两者 lexical mapping 100%、exact span 98.76%、零静默错位且刷新确定；Stanza 零树错误，
  spaCy 在一个口语残句产生双 root 并被 validator 闭合拒绝。生产 SenseGroup 对真实 Stanza
  输出保持教学粒度和 `New York City` 多词短语完整性；missing/corrupt/invalid sidecar 均不生成
  draft。报告不复制字幕正文，未资格候选仍不接入产品，B/SenseGroup 保留原 fallback，C 与
  ChunkTimeline 未改动。

- 2026-07-13 16:36 CST: Phase 3.9.1 Slice 5 新增独立 syntax-aware SenseGroup Provider。
  新增 `syntax-aware-sense-group/v1` / `dependency_teaching_partition_v1`，与既有
  `rule-based-sense-group/v1` 分开 fingerprint、持久化和 candidate/active/archive 生命周期；
  metrics 引用 syntactic artifact/descriptor 并显式记录 `chunk_timeline_dependency=false`。
  dependency clause/conj/subordinator/PP subtree 只提出 boundary/head/NP-PP-clause label，强标点、
  phrase candidate 完整性、min 2/hard max 8 与典型 3–5 组教学粒度仍作最终裁决；错误 snapshot
  或低 coverage 精确返回原 rule partition。新增 4 项 syntax partition fixture 和 rule/syntax
  双 run 持久化回归；未资格 Provider 在 application gate 被拒绝，现有 HTTP 默认生成路径保持
  rule Provider，ChunkTimeline 代码与生命周期均未改动。

- 2026-07-13 16:27 CST: Phase 3.9.1 Slice 4 建立 Reference B 句法 consumer seam。
  `ConnectedSpeechContext` 将 validator activatable 与外部 provider qualification 设为两个独立
  gate；未资格/缺失 artifact 与原 `predict_default_connected` 输出逐项相同。本阶段只把锁定
  验证通过的 future/motion `going to`、habitual/state（含 `get used to`）和 `have to do with`
  idiom 用中立 UPOS/lemma/features 映射作保守门控；失败的 `want to` wh-extraction 仍固定走
  现有 text heuristic。B evidence 区分 `prediction_provenance:syntax_model`（带 artifact ID）
  与 `text_heuristic`，但 status 仍为 `PossibleByRule`，不冒充 C/audio evidence。新增 5 项
  syntax consumer/fallback 回归；speech-analysis 175 单元 + 12 集成测试全通过。

- 2026-07-13 16:22 CST: Phase 3.9.1 Slice 3 完成冻结评估与负资格判定。
  开发集仅用于 neutral query/mapping 调整；随后按预登记 digest 对验证集每个候选只运行一次。
  Stanza 1.13.0/en_ewt 与 spaCy 3.8.13/en_core_web_sm 3.8.0 均达到 100% lexical/exact
  mapping、零静默错位/树错误，并在 future/motion `going to`、habitual/state `used to`、
  obligation/idiom `have to` 对上满分；但两者都在 multi-token wh-extraction
  `Which team ... want to win` 产生一项高风险 `wanna` 假阳性，依锁定零容忍 gate 判为
  `not_qualified`，未添加 validation-specific 特例。资源 gate 均通过（Stanza/spaCy cold p95
  2.63/1.21s、warm p95 106.4/4.1ms、RSS 0.86/0.32GB、产品包 +0B）；runtime/model/
  treebank 分层许可证、精确 installed-tree checksum/size 和 raw case reports 已审计，Stanza
  传递训练数据 provenance 不完整仍独立保持 research-only。

- 2026-07-13 16:10 CST: Phase 3.9.1 Slice 2 新增隔离式 Python 句法研究 Provider。
  新建 `syntactic-provider` Rust crate 与版本化 JSONL sidecar，Stanza/spaCy 均只输出同一
  provider-neutral draft；进程边界保持 stdout 纯协议、stderr 诊断，lazy runtime/model
  探测和 runtime missing/model missing/corrupt/unsupported language/invalid output/timeout
  闭合失败不会生成 artifact。token 映射覆盖 Unicode scalar offset、缩约 N:1、缩写 1:N、
  normalized overlap 与显式 unaligned；Stanza/spaCy 原生标签在适配器内归一化，产品包不
  链接 Python/model。新增 opt-in 隔离 venv、研究资产分层许可证 manifest、8 项 Python
  sidecar contract 与 4 项 Rust process contract，并纳入全局 contract validator。

- 2026-07-13 15:56 CST: Phase 3.9.1 Slice 1 建立 provider-neutral Rust 契约。
  domain 新增版本化 `SyntacticAnalysis`、完整 provider/runtime/model/checksum provenance、
  Unicode scalar char span 多对多映射、UD 字段、source/config/model 隔离 fingerprint，以及
  span/coverage/HEAD/单 root/无环/sentence ownership validator；application 新增 draft-only
  `SyntacticAnalysisProvider`、capability 与 closed error taxonomy，并由 server-side finalizer
  铸造 artifact identity、拒绝 invalid provider 输出。fake provider、缩约 N:1、低 coverage
  abstain、坏 span/head/cycle 和模型升级重算测试通过；本 slice 不增加持久化或 parser runtime。

- 2026-07-13 14:21 CST: Phase 3.9.1 Slice 0 建立共享句法 Provider 的可执行研究边界。
  新增 ADR 0023，锁定 provider-neutral、可重建 artifact、Unicode scalar half-open char span
  1:N/N:1 token 映射、closed validation/abstain 降级、隔离 provider/runtime/model/config 的缓存
  身份，以及不得填充 C、替代 ChunkTimeline 或铸造 Construction identity 的边界。新增 24 条
  开发/锁定验证歧义 fixture（含真实 CNN10 字幕短摘录与受控最小对照）、4 条 mapping contract
  fixture 和无 parser 依赖的 validator；预登记 alignment/关键歧义/失败/延迟/内存/体积 gate，
  并分别审计 Stanza/spaCy runtime、model weights 与 UD/treebank 许可，未知项保持 research-only。

- 2026-07-13 13:59 CST: 新建 Phase 3.9.1 Shared Syntactic Analysis Provider。确定以
  UD/CoNLL-U 语义建立共享、可重建的 token-aligned 句法 artifact，通过现有 Python sidecar
  模式先评估 Stanza/spaCy，供 Reference B、SenseGroup 与 Construction 共用；明确模型缺席
  时保留现有保守 B 与标点/长度 SenseGroup，句法结果不得填充 C、替代 ChunkTimeline 或铸造
  Construction canonical identity。新增 CAP-011/012，锁定 char-span 1:N/N:1 token 映射、
  开发/验证集分离、真实字幕歧义评估及代码/runtime/model/treebank 分层许可证审计。

- 2026-07-13 13:25 CST: Phase 3.9 英语语流规则第二批。Reference B 规则源升级为 v3；Phrase
  rule 新增上下文门控，不再把字面相邻词无条件缩约：`going to` 只接受动词补语候选并阻断
  专名/限定词/常见地点歧义，`want to` 对 wh-extraction 歧义保守缺席，`used to` 区分
  habitual 与 `be used to + NP/gerund`。新增 `gotta`、`hafta/hasta`、`had to`、habitual
  `used to`、`supposed to/ought to`、安全层 `trying to`，以及
  `lemme/gimme/kinda/sorta/outta/lotta/lotsa/dunno` 的完整 A→B 音素结构；weak form 补标点、话语
  起始 `/h/`、`the + vowel` 阻断。新增正例、motion/NP/疑问抽取/形容词 used-to 等反例和
  UI 结构断言；speech-analysis 170 项测试全通过。规则与来源同步登记到 3.9 catalog。
  `connected_speech_rules.rs` 达到规模线后，将构式/弱读阻断提取到 `context.rs`（主文件回落
  到 1403 行），为下一批音节规则保留清晰模块边界。

- 2026-07-13 12:17 CST: Phase 3.9 第 4 项启动：新增 General American 英语语流完整规则目录，
  按 `B-safe` / `B-context` / `C-only` / `dialect` 记录音素环境、阻断条件、口音范围、来源和
  实现状态，明确“全部纳入目录”不等于把声学渐变现象伪造成 B。首批 B 扩展：硬编码
  `did you` 改为通用 `/t,d,s,z/ + /j/` coalescence，并修正输出为 `/dɪdʒu/`；新增 `/n/`
  在双唇/软腭音前的部位同化、V#V `[j]/[w]` 连接、跨词弱功能词前的美式 flap；词内 flap
  加入“重读元音后、非重读元音前”条件，`/t,d/` 删除收紧为词尾辅音簇 + 辅音环境。新增
  标点/强边界阻断，避免跨逗号等标点触发 linking/assimilation/deletion；新增规则环境与
  反例测试，speech-analysis 全部 165 项回归通过。

- 2026-07-13 10:57 CST: 修复长句 A/B/C 结构带后半句不可见。新增三视图共用的跟随式
  sentence viewport：紧凑模式按当前 token/播放节点自动横向定位，左右渐隐提示仍有内容；
  展开按钮切换为可换行、可纵向滚动的完整句结构。A 跟随单词，B 同时跟随规则跨度与普通
  文本跨度，C 跟随当前音频节点；切换视图不再只能看到句首。新增长句第 11 节点定位和完整
  展开回归测试，中英 tooltip 同步补齐。

- 2026-07-13 10:47 CST: 修正 Rhythm C 证据门控。播放器不再把 text/WordTimeline 派生的
  RhythmFrame 作为“预测 C”显示；C 现在同时要求当前句已加载音素，且 frame 自身
  `phone_evidence_coverage > 0`。无音素证据时只提供当前句/全轨音频分析入口，A/B 仍可正常
  使用。新增四象限回归测试锁定“有 frame 无 phones”“有 phones 无 frame phone evidence”
  均不得显示 C。

- 2026-07-13 10:30 CST: 修复导入过 LLTimeline 后刷新听感结构仍显示不可用。Flutter 资源
  加载不再用带 artifacts 的旧文档整体覆盖后端新导出文档；现在保留新导出的 WordTimeline
  派生 RhythmFrame，仅把旧 artifacts 合并回来。新增回归测试覆盖“旧文档无 rhythm frames、
  新导出有 rhythm frames”的真实 QA 场景。

- 2026-07-13 10:12 CST: 将 Phase 3.9 A/B/C audible-structure 两批实现合入已完成
  Phase 3.12 的 main；保留 3.12 收口事实，并将 3.9 状态切换为主工作区真实媒体 QA 与
  增量修正。后续工作从 main 新建专用阶段分支，不在 main 直接开发。

- 2026-07-13 09:24 CST: Phase 3.12 Vendor-neutral LLM Provider 收口，CODE COMPLETE。
  创建 `3.12-CLOSEOUT.md`（五切片 0/1/2/2b/3 交付清单、七项 Key Decisions、四条 exit signal
  逐条核验通过、验证记录、QA 归属、Deferred 清单）；PLAN 置 CODE COMPLETE；STATE.md 主线
  切换至 Phase 3.13 Reading Studio / 3.12.1 Judge Qualification 并登记已完成 phase 索引。
  Exit signals 全部核验通过：两异构 adapter 同契约套件证中立、切 provider 领域 JSON 不变 +
  provenance 保留、删/禁 key 诚实降级、密钥不落普通存储 + 错误不回显凭证。剩余为 owner 真实
  provider 端到端产品 QA（人工门）与增量协议 Slice 4（owner 按需）；judge 质量资格属 3.12.1。

- 2026-07-13 09:24 CST: Phase 3.12 Slice 3：Flutter 最小设置 UI（AI providers）。
  新增 `apps/desktop/lib/models/llm_provider.dart` 手写 DTO（`LlmProviderProfileView`
  /`LlmProviderCapability`/`LlmCapabilityClaim`/`LlmProbeResult`，ADR 0014）+
  `test/contract/llm_provider_contract_test.dart` fixture 契约测试（4 项，pin 到
  OpenAPI v1.yaml）；`LocalApi` 增 listLlmProviders/registerLlmProvider/deleteLlmProvider/
  probeLlmProvider（secret 只写、DELETE 204→null）；自包含 `LlmProviderSettings` widget
  （provider 列表 + 添加表单 + 连通/能力 probe 测试 + 删除；协议下拉 OpenAI/Anthropic、
  用途勾选、密钥 obscured 提交后即清空、数据去向警告、"未获显示资格 仅供诊断"提示、
  has_credential 徽标不显示 secret）；SettingsDialog 加第 7 个导航类目"AI providers"
  与 section（新增可空 `api` 参数，缺 sidecar 时降级提示），settings_flow 传入既有 `api`；
  localization en+zh 补 24 键。判定默认不获显示资格（属 3.12.1），UI 明示。
  验证：flutter analyze 全项目零问题；flutter test 288 全通过（含新增 4 契约）。
  Rust 侧本切片未改动。至此 3.12 功能面完成，剩余：增量协议（Slice 4，owner 按需）、CLOSEOUT。

- 2026-07-13 08:57 CST: Phase 3.12 Slice 2b：provider 工厂 + 真实 OS-keychain + HTTP 路由。
  llm-provider 新增 `BuiltSemanticProvider`（按 profile.adapter_kind 建 OpenAI/Anthropic
  adapter，暴露 as_judge/as_rubric/probe；新协议= 新 match 臂，契约不变）+ 工厂契约测试
  （两 profile 建对应 adapter、probe 实测能力）。api-http：`crates/api-http/src/routes/llm.rs`
  四路由 `GET/POST /v1/llm/providers`、`GET/DELETE /v1/llm/providers/{id}`、
  `POST .../{id}/probe`（连通+能力实测）、`POST .../{id}/judge`（provider-backed 判定→
  记为 heuristic_proxy，不进 surface）；响应用 `ProviderProfileView`（只暴露 has_credential，
  **不含 auth_ref/secret**）；`secret` 请求字段 write-only 入 keychain。`KeychainSecretStore`
  （`secret_store_keychain.rs`，security-framework generic password，cfg-gated macOS + 非
  macOS 显式 unsupported，auth_ref=随机 account id）；`ApiState` 加 `secret_store`（默认
  in-memory，`with_secret_store` 注入 keychain）；main.rs 接 profile repo + keychain。
  OpenAPI v1.yaml 补 4 路由 + `LlmProviderProfileView`/`RegisterLlmProvider`/`CapabilityClaim`/
  `ProviderCapability`/`LlmAdapterKind`/`LlmUse`/`DataRetentionPreference`/`CostBudget` schema。
  api-http 集成测试（默认 in-memory store + 本地 fake endpoint）：注册不回显 secret、列表无
  secret、probe 实测 supported、删除移除、未知 provider judge→404。
  **修 bug**：`LlmAdapterKind` serde snake_case 会产出 `open_ai_chat_completions` 与 `as_str()`
  的 `openai_chat_completions` 分叉（DB 列 vs JSON blob），显式 `#[serde(rename)]` 对齐。
  验证：domain 74 / application 53+ / llm-provider 12 / persistence 109 / api-http 44+12 全通过；
  新文件 clippy 零告警；validate-contracts OK（OpenAPI route-drift 门通过）。剩余：最小设置
  UI（Slice 3）、增量协议 OpenAI Responses/Gemini（Slice 4）、CLOSEOUT。

- 2026-07-13 08:22 CST: Phase 3.12 Vendor-neutral LLM Provider 后端优先切片落地
  （Slice 0/1/2a/2b，设置 UI 与真实 keychain 实现后置）。**中立性证明（核心 exit
  signal）成立**：新增 `crates/llm-provider/`，用 `reqwest` 手写两个异构协议 adapter
  （OpenAI Chat Completions-compatible = Bearer/扁平 messages/native response_format；
  Anthropic Messages = x-api-key+version/顶层 system/content block/tool_use 结构化输出），
  由泛型 `LlmSemanticProvider<A>` 组合 prompt/schema/parse 一次写成；本地 axum fake-server
  契约套件驱动**两个 adapter 过同一场景**（成功/拒绝/schema-invalid/截断/限流/超时/probe），
  核心断言 `drafts[0]==drafts[1]`（异构 wire→相同领域输出）通过（10 契约测试）。
  domain 新增 `llm_provider.rs`（`LlmAdapterKind`、`LlmProviderProfile`、opaque
  `LlmAuthRef`、`ProviderCapability`/`CapabilityClaim`=Declared/Probed/Unknown、`LlmUse`、
  `DataRetentionPreference`、标准化 secret-free `LlmProviderError` 分类学）；application
  新增两层 seam（`LlmChatAdapter` wire seam + `SemanticRubricProvider`/`SemanticJudgeProvider`
  application seam + `RubricDraft`/`JudgmentDraft` 仅内容草稿）。**draft-not-domain-type
  边界**：provider 只返内容草稿，身份 fingerprint/版本/快照 hash/3.11 validator 全部
  服务端持有（`record_llm_judgment` + `judge_semantic_attempt`）——四层分离经 LLM 路径
  仍成立，5 种失败模式一律不写 judgment（诚实降级）。**密钥安全**：`SecretStore` trait +
  in-memory 实现；`0036_llm_provider_profiles.sql`（只存 auth_ref，无密钥列）+
  `LlmProviderProfileRepository` SQLite 实现 + register/delete-with-secret use case；
  守卫测试证明**注册后 raw key 不出现在任何 DB 列或 JSON blob**、删除 provider 同删密钥、
  密钥被外部删除时降级为 None 不报错。api-http 补 `Provider`/`SecretStore` 错误 → HTTP 映射
  （secret-free，auth 无 payload）。新增 ADR 0022（provider 中立/draft 边界/keychain+auth_ref/
  能力 probe/诚实降级/无显示资格）。远端对照证伪写入 PLAN v3：架构照 rust-genai 中立-类型派、
  拒绝 LiteLLM 归一 OpenAI wire、能力描述符借 LiteLLM 分类学但对本地 endpoint 必须 probe、
  密钥严于 genai(env)/aichat(明文)。修正 `MIGRATION_VERSION` 35→36。验证：domain 74 /
  application 41 / llm-provider 10 契约 / persistence 109（含 4 profile + 4 LLM judgment）/
  api-http 53 全通过；新文件 clippy 零告警；validate-contracts OK；git diff --check 通过。
  本 phase 判定默认**不获任何显示资格**（资格评估属 3.12.1）；剩余：真实 OS-keychain
  SecretStore 实现、provider-backed HTTP 路由与工厂、最小设置 UI、closeout。
- 2026-07-13 08:40 CST: 扩展 Phase 3.9 B 预测可听结构到 weak form、contraction、
  assimilation、deletion 与 flapping。Deletion 由空预测改为在完整跨词结构中移除词尾
  `/t|d/`（如 `last call`：`/læst | kɔl/ → /læs.kɔl/`）；flapping 不再只
  输出孤立 `DX`，而是在完整词内把元音间 `/t|d/` 替换为 `/ɾ/`。其余三类使用完整规则
  音素生成可听结构；新增测试确保所有类别都有 A/B 且纯文本规则不生成 C。

- 2026-07-13 08:28 CST: 恢复 Phase 3.9 的 A/B/C audible-structure 算法与 UI 重构并完成
  linking 首条竖切片。`RhythmConnectedSpeechRef` 新增向后兼容的 A citation、B predicted、
  C actual 可听结构（音组、IPA、学习者 cue、书写 token 来源映射）；`pick up` 的文本规则现
  输出 `/pɪk | ʌp/ → /pɪ.kʌp/` 与 `pɪ-kʌp`，不再只显示 linking 类别。C 仅在存在
  observed phone evidence 时生成，timing/prosody 只作边界与分组证据。Flutter B ribbon
  直接呈现书写结构到可听结构的变化，C ribbon 展示 phone-segmental 支持的实际音组；OpenAPI、
  Dart model、Rust/Flutter/contract 回归同步扩展。Phase 3.12 继续在独立 worktree 并行推进。

- 2026-07-12 19:20 CST: 清除 speech-analysis 既有 deny 级 clippy error。
  `sense_group_partition.rs` 测试里的恒真断言 `assert!(any_span_covers || true, ...)`
  （Phase 3.4.2 引入，触发 `overly_complex_bool_expr`）改为实义断言
  `assert!(any_span_covers, ...)`：探查确认含中间标点的句子里逗号 token 确实被相邻
  sense group span 吸收，断言现在真正锚定该行为并匹配测试名，注释同步纠正。
  speech-analysis 155 项测试通过；workspace-wide `cargo clippy --all-targets` error 归零。

- 2026-07-12 18:55 CST: Phase 3.11 Slice 4 收口，Semantic Task Evidence Foundation
  CODE COMPLETE。新增 ADR 0021（semantic attempt/judgment/observation/capability 四层分离、
  独立任务族 spike 裁决、rubric 身份含 purpose、abstain 一等、adjudication 非 override、
  v35 append-only、portable/export 不进 VocabularyAssetBundle、§3.7 过渡规则由本 ADR 取代）；
  evidence matrix 标记 FINALIZED；创建 `3.11-CLOSEOUT.md`；PLAN 置为 CODE COMPLETE；
  STATE.md 主线切换至 Phase 3.12 并登记已完成 phase 索引。修复 api-http 测试
  needless_range_loop 告警。exit signals 全部核验通过；本 phase 无独立 UI，真实内容
  端到端 QA 归属首个消费它的 Studio（3.13）。

- 2026-07-12 18:40 CST: Phase 3.11 Slice 3 落地：最小 HTTP API + OpenAPI 契约。新增
  `crates/api-http/src/routes/semantic.rs`：`/v1/semantic/rubrics`(+`/{id}`、
  `/{id}/attempts`)、`/v1/semantic/attempts`(+`/{id}`、`/{id}/judgments`)、
  `/v1/semantic/judgments`(+`/{id}/adjudications`)、`/v1/semantic/adjudications`
  九条只写读面（无 update/delete，append-only；id 服务端按 fingerprint 生成）；
  `contracts/openapi/v1.yaml` 补齐九路径与 19 个 schema（Semantic* / Rubric* /
  AttemptResponse / PointJudgment / JudgmentAbstain 等）；domain 新增
  `semantic_task_attempt_id` fingerprint 助手。api-http 契约测试引用 Slice 1 gold
  fixture 走完整 HTTP 链路（好/差/abstain 三判定 + adjudication 往返、abstain 逐点为空、
  矩阵违规与篡改哈希返回 400、未知 rubric 版本 404）。本 phase 不交 Dart DTO（推迟
  3.13 首个真实 consumer）。api-http 53 项、workspace 25 套件、validate-contracts
  全部通过。

- 2026-07-12 18:05 CST: Phase 3.11 Slice 2 落地：schema v35 + repository + use case。
  新增 `0035_semantic_tasks.sql`（semantic_rubrics/semantic_task_attempts/
  semantic_judgments/judgment_adjudications 四表，UPDATE/DELETE 全部触发器禁止，
  刻意不建任何指向 media 的外键）；`SemanticTaskRepository` trait + SQLite 实现
  （queryable 列 + 全量 JSON 文档，无更新/删除方法）；AppServices 语义任务 use case
  （rubric 版本续接校验、attempt/judgment/adjudication 全链路 domain validator 前置、
  重复冲突与篡改哈希拒绝）；`ApplicationError::Invalid` 动态校验错误 → HTTP 400
  `invalid_input`。负向测试：语义全流程零 lexical observation/capability 变更、
  adjudication 后 judgment 行逐字节不变、删除媒体后全链路仍可读、四表 append-only
  触发器生效、3.8 shadowing 完成路径延伸断言不产生任何 semantic 事实。dictogloss
  in-progress 草稿持久化显式推迟到首个 Studio consumer（迁移文件注释记录 additive
  路径）。workspace 测试全绿；clippy 唯一 error 为 speech-analysis 既有基线。

- 2026-07-12 17:48 CST: Phase 3.11 Slice 1 落地：domain 语义任务契约层。新增
  `crates/domain/src/semantic_task.rs`：`SemanticTaskKind` 封闭枚举（七类任务）、
  `SemanticRubric`（自足来源快照 + 版本 + 修订注记 + generator provenance）、
  `SemanticTaskAttempt`（clip 级事实，仅 completed/abandoned，无对错层）、
  `SemanticJudgment`（逐点 covered/partial/missing/uncertain + 回答内精确 char span +
  双侧快照哈希 + abstain 一等）、`JudgmentAdjudication`（确认/纠正，不回写 judgment）；
  validator 落实矩阵裁决（隐藏原句、L1 触发原因、dictogloss 独占多稿、ASR 可靠性、
  span 越界/verdict-span 契约、rubric 版本一致性）与可比较性谓词。新增
  `testdata/semantic-task/gold-fixture-v1.json`（同一 rubric 好/差/abstain 三判定 +
  一次 adjudication）。domain 70 项、workspace 25 套件全部通过；semantic_task 无
  clippy warning。无网络、无模型即可完整验证。

- 2026-07-12 17:25 CST: Phase 3.11 Slice 0 完成并通过 owner 复核门。`3.11-PLAN.md` 按
  上游现状修订为 v2（固定 v34/ADR 0021 基线、五切片可执行粒度、Dart DTO 推迟到 3.13）；
  新增 `3.11-EVIDENCE-MATRIX.md`：七类语义任务 + 五条负向裁决的 evidence matrix（真实
  CNN10 片段示例、Lee 1986 / Wajnryb 1990 文献核实）、typed contract spike 裁决为方案 C
  （新封闭枚举 `SemanticTaskKind` + 独立 attempt 表族，复用 PracticeTarget/Anchor，
  `PracticeKind` 不动、不改开放 string）；确立"3.11 不新增任何 LearningObservation
  writer"。执行分支 `codex/3.11-semantic-task-evidence-foundation`。

- 2026-07-12  CST: Phase 3.10 Coach Dashboard 收口。owner 产品 QA 通过所有 QA-A ~ QA-E
  项目：入口语义、数字来源事实可下钻、建议可执行无副作用、材料轨迹与毕业确认正确、历史不足
  降级干净。创建 `3.10-CLOSEOUT.md`，更新 `STATE.md` 将主线切换至 Phase 3.11。

- 2026-07-12 15:05 CST: Phase 3.10 自动化与代码范围完成，转 owner 产品 QA。Dashboard 新增
  指标来源明细 API/弹窗（实际 session/attempt/event/history ID、结果与时间）、同一材料多次
  `ListeningCompleted` 理解度轨迹、基于重复自报与练习正确率的毕业候选、确认式
  `graduated` triage intent，以及“不清楚→转精听 / 听懂大意→保留泛听”的确认式 content-fit
  建议；所有动作只整理内容库，不静默修改能力。新增 10,000 事件有界性能测试与材料轨迹/
  毕业回归，建立 `3.10-MANUAL-QA.md`，PASS 前阶段不收口。最终验证中 Flutter analyze、
  Flutter 284 项与 contracts 通过；Phase 3.10 focused Rust 测试全部通过。workspace 全量仍被
  两项既有基线阻断：Clippy 的 `sense_group_partition.rs` deny 级恒真布尔表达式，以及
  Phase 3.8 shadowing event 测试期望 `not_scored`、实际 payload 为 null；均与 Dashboard 改动无关。

- 2026-07-12 14:44 CST: Phase 3.10 Coach Dashboard 首条完整竖切片落地。新增只读
  `CoachDashboardRepository` 与 SQLite 周期聚合、`GET /v1/coach/dashboard` channel-ready
  envelope、可追溯规则建议和无历史 starter checklist；reading/speaking/writing 缺少主动
  验证时明确返回 unassessed。Flutter 新增 typed DTO、Store/controller、双语 Dashboard 页面
  和工作台入口，展示泛听、练习、复习、listening capability history 与 L1 规则命中事实，
  并可直达复习、猎词或返回真实输入。新增 application、SQLite、HTTP、transport/controller
  回归与 OpenAPI 契约。Flutter 284 项、analyze、contracts 通过；workspace test 首轮仅因新增
  路由尚未写入 OpenAPI 而失败，契约已补齐待复跑；strict clippy 仍被既有
  `construction.rs` Rust 1.94 `collapsible_if` 阻断。

- 2026-07-12 11:52 CST: Owner 将 Phase 3.9 L1-aware Diagnosis v1 明确延期，暂不收口、
  不创建 CLOSEOUT，亦不把当前真实媒体 QA 记为通过。已合入的实现与自动化验证保留；延期原因
  是当前 UX 依赖词汇状态/历史 observation、基础诊断和 RhythmFrame 规则命中的多重前置，尚未
  形成“本句没听懂 → 定位 → 回听 → 同类短练习”的自然学习闭环，且规则时间段可能来自 text
  prior / 估算 timing。主线切换至 Phase 3.10 Coach Dashboard；3.9 数据不作为其硬依赖。

- 2026-07-12 09:07 CST: Owner 明确确认 Phase 3.8 Shadowing & Recording Comparison
  真实媒体、真实麦克风及跨媒体入口 QA 全部通过。`3.8-MANUAL-QA.md` 记录首轮发现的
  跨媒体主字幕导航泄漏、修复与复验 PASS；新增 `3.8-CLOSEOUT.md`，计划状态转为 COMPLETE，
  `STATE.md` 当前第一优先切换至 Phase 3.9。Phase 3.8 冻结后仍保持非评分 completion、
  录音资产 outlive media 与客观比较不作发音评价的边界。

- 2026-07-12 09:02 CST: 修复 Phase 3.8 跨媒体 shadowing 播放器 UX 泄漏。从复习卡或词典
  内联片段进入“跟一下”时，练习窗现在固定为当前来源片段，隐藏主字幕上一句/下一句与句数
  进度；播放/暂停按钮和空格键改为控制独立切片播放器，导航函数同时拒绝跨媒体调用，避免
  任何快捷键误播主播放器。新增 widget 回归测试；`flutter analyze` 与相关测试通过。

- 2026-07-12 08:33 CST: Phase 3.8 Shadowing & Recording Comparison 自动化实现完成并进入
  owner 真实媒体 QA。macOS 端新增 `AVAudioRecorder` 权限与 mono PCM16 WAV 采集，Flutter
  练习浮窗点亮“跟一下”第四题型，支持 chunk → 1+2 → 整句、0.75/0.9/1.0x、跨媒体入口、
  原音/录音/A-B-A 独占播放、双波形及客观时长/停顿比较；媒体/比较失败保留录音和 snapshot，
  权限拒绝可引导系统设置。新增 Rust DSP、HTTP/OpenAPI/Flutter typed seam 与回归测试；
  `cargo test --workspace`、Flutter 278 项、`flutter analyze`、契约校验、包含 sidecar/runtime 的
  macOS Release 打包及
  `git diff --check` 通过。严格 clippy 仅被既有 `construction.rs` `collapsible_if` 阻断。
  同时修复正式打包二次签名丢失 Runner entitlements，产物现保留麦克风输入权限键。新增
  `3.8-MANUAL-QA.md`，Phase 保持 ACTIVE，等待 owner 裁决后再收口。

- 2026-07-11 20:36 CST: Phase 3.8 首条后端竖切片落地。新增 schema v33
  `recording_assets`、SQLite `RecordingRepository` 与 recording create/get/delete API；
  `RecordingAsset` 保存语言、容器/codec、采样率、声道、sample format、byte length、SHA-256、
  recorder version 和来源片段 snapshot，为 3.14 录音转录保留诚实输入。新增
  `PracticeResult::Completed` 与 shadowing completion API，非评分录音完成明确不写 speaking
  observation、不生成 review、不计入 content-fit，并以 persistence/HTTP/contract 回归锁定。

- 2026-07-12 10:40 CST: Phase 3.9 L1-aware Diagnosis v1 全量落地（Mandarin → English）。
  （1）LearnerProfile L1 持久化：schema v34 `learner_profiles`（v33 按 later-lander-renumbers
  规则保留给 3.8 in-flight 的 `recording_assets`），实现既有 `LearnerProfileRepository` trait、
  统一读取面 `LearnerProfileView`（L1 权威 / UI 语言快照 / L2 保留位，三轴分离）、
  GET/PUT `/v1/learner/profile`，设置对话框“学习”类新增母语（L1）下拉，未设置时全链路无感。
  （2）L1L2 难点 profile provider：diagnosis-core 新增 `l1l2_difficulty_rules`（zh→en 九类难点，
  weak function words / schwa / final consonants / clusters / t-d deletion / flapping / linking /
  stress-timed rhythm / compressed forms），每类含 family 识别规则（rhythm_frames weak
  groups/compression spans + 2.16 connected-speech 六 family，evidence class 一律
  heuristic_proxy）与 possibilities 语气解释；无检测器的两类（final consonants/clusters）
  声明空 family 永不虚假触发；研究依据逐条记录于 `3.9-L1-PROFILE-EVIDENCE.md`。
  （3）诊断集成：`SentenceDiagnosis` 附加 `l1_hints`（带可复听 span，无 span 不出提示）与
  `l1_context`（unsupported_pair 显示语言中立提示），降级阶梯为无 L1→字节不变基础诊断、
  组合不支持→仅 context、无 sound-side 失败/无 rhythm frame→仅 context；命中写幂等
  `l1_difficulty_hit` LearningEvent（(sentence, kind) 指纹去重，供 3.10 难点分布）。
  （4）corpus family 标注投影：reindex 在 v28 投影上追加 kind=connected_speech、
  normalized_key=family 的可重建行（word timeline 生命周期、转写管线、lltimeline 导入均补齐
  reindex 触发点）；`/v1/learner/l1-specialty` 按难点聚合全库同类片段（跨媒体 round-robin），
  corpus 缺席降级为当前 track 内存聚合（indexed=false）；Flutter 诊断卡新增母语听觉视角区
  （复听 chip 走循环播放、同类片段对话框：试听走 3.5.7 切片窗、当前 track 条目可一键进
  3.5.6 句听写练习）。验证：cargo test --workspace 全绿（含新增 diagnosis-core 8 项、
  persistence L1 链路 6 项）、flutter analyze 0 issue、flutter test 278 项、
  validate-contracts（OpenAPI/event/player）通过；clippy 仅存量告警。

- 2026-07-11 20:07 CST: Owner 明确确认 Phase 3.7 Hunting List 真实媒体功能验收通过。
  `3.7-MANUAL-QA.md` 记录 PASS，新增 `3.7-CLOSEOUT.md`，计划状态转为 COMPLETE 并冻结；
  `STATE.md` 当前第一优先切换至 Phase 3.8。此次收口不改变 Gate Q 中 Q3（复习）与 Q4
  （content-fit）主动延期的 QA 债归属。

- 2026-07-11 19:50 CST: Phase 3.7 Slice 5a completion 统计落地。泛听理解度自报对话在狩猎
  模式启用时显示“命中 N 次 / 听出 M 次”；typed completion request 新增可选 hunting summary，
  application 校验总提示 ≤5 且回答数不超过提示数，并把 prompted/recognized/not-recognized/
  not-noticed 四类计数写入 `listening_completed` event payload，不进入 content-fit。新增 Rust
  持久化与 Flutter HTTP seam 回归，Rust API/SQLite 145 项、Flutter 274 项、analyze、OpenAPI/
  event/player contract 与 diff check 均通过。真实媒体连续感 QA 由 owner 按新增
  `3.7-MANUAL-QA.md` 执行，Phase 保持 ACTIVE，未提前收口。

- 2026-07-11 15:31 CST: Phase 3.7 Slice 3/4 落地。后端新增当前 media/track 的猎词目标出现点
  查询：word 复用 lemma-normalized corpus key，phrase 复用 FTS 句子匹配，所有提示要求稳定
  sentence 关联，并以 `indexed=false` 区分未建索引与零命中。Flutter 新增会话级
  `HuntingSessionController`，从真实播放器 position stream 驱动显式狩猎开关、前置 priming、
  句后 check、总预算 5/每目标 2；不自动暂停或重播，切媒体/结束泛听即清零。三态作答中
  “是/否”走 ADR 0017/0019 observation/evidence 链路，“没注意”只写
  `hunting_check_answered` LearningEvent。新增 reindex 提示、播放菜单/浮层 UI、中英本地化及
  Rust HTTP/application/persistence、Flutter controller/widget/contract 回归；Rust 相关全量、
  Flutter 274 项、OpenAPI/event/player contract 均通过。

- 2026-07-11 15:03 CST: Phase 3.7 Slice 2 Flutter 猎词单管理 UI 落地。新增
  `HuntingController + Store<HuntingState>` 与 typed target/candidate API seam；听力词典工具栏
  增加带 active 数量徽标的猎词单入口，词条详情可手动加入，管理面板支持查看/归档目标、
  确认复习失败候选并跳回词条。补齐中英本地化、controller/widget/contract 测试；
  `flutter analyze`、新增 6 项聚焦测试与 Flutter 全量 271 项测试通过。

- 2026-07-11 14:51 CST: Phase 3.7 首个后端竖切片落地：新增 schema v32
  `hunting_targets`，将复习失败候选与用户确认的猎词目标分离；支持 manual、review candidate
  与 Listening Inbox 来源校验，实施最多 5 个 active 目标的硬上限、归档/重启用身份，并新增
  候选读取及目标创建/列表/归档 API、OpenAPI/TypeScript contract 与 Rust 回归测试。确认
  review candidate 后将候选转为 `consumed`，不自动扩容猎词单；同时修复契约校验脚本仍只
  接受词汇资产 v5、与当前 OpenAPI v5/v6/v7 权威范围漂移的问题。

- 2026-07-11 14:44 CST: Gate Q owner 裁决落地：Q1（3.3 泛听）与 Q2（3.35 工作台）明确
  通过；Q3（3.4 复习）与 Q4（3.5 内容分档）因后续仍需调整 UX/功能而明确延期，残余 QA
  债保留在原 phase，不转嫁给 3.7。Gate Q 据此通过，Phase 3.7 Hunting List 转为 ACTIVE。

- 2026-07-11 12:56 CST: 四通道规划落地后的评审修订。3.12 判定为超载 phase：judge 资格
  评估（fixture + 人工 gold + 留出集 + 三级资格裁决）拆出为新 Phase 3.12.1（新建
  `3.12.1-PLAN.md`），3.12 修订 v2 收窄为两个异构协议 adapter（OpenAI-compatible +
  Anthropic Messages）先证厂商中立、OpenAI Responses/Gemini native 降为增量 slice。
  统一 judge 三级资格口径（未经留出集校验不进学习 surface / 仅可显示可纠正 feedback /
  supporting evidence），修复共享上下文 §3.5 与 final 稿 §9 的矛盾。共享上下文新增
  §3.6 seam 预留裁决标准（解释 3.7 拒绝 FocusTarget 与 3.10 接受 channel-ready
  envelope 的一致依据）、§3.7 过渡期证据权威与计划保鲜纪律（3.11–3.18 为方向承诺，
  开工前须按现状修订）。final 讨论稿补修订记录（FINAL 稿改动今后走修订记录）。同步
  PHASE-BREAKDOWN（序列表/依赖图/执行顺序/全局规则 13）、ROADMAP、REQUIREMENTS
  （LOOP-013/014）、3.10/3.13/3.14/3.17 计划引用。STATE.md 已完成 3.x phase 条目
  压缩入索引表（396 → 307 行，恢复 ≤400 余量）。

- 2026-07-11 12:15 CST: 对照四通道最终讨论与现有 3.7–3.10 计划完成路线重排。四份计划
  升级 v3：3.7 保持 listening-only 且新增 3.3/3.35/3.4/3.5 真实 QA Gate Q；3.8 明确为
  shadowing 模仿层，非评分 completion 不得用 `Correct` 伪造 speaking success，并为后续
  录音转录保留诚实 seam；3.9 不提前接 LLM/两层复述；3.10 建 channel-ready envelope，
  无数据通道显示未评估而非 0。新建 3.11–3.18 八个 PLAN 与共享上下文，依次覆盖 semantic
  task/evidence、厂商中立 LLM provider 与 judge 校验、Reading/Speaking/Writing Studio、
  Personal Expression、四通道 projection/review、Cross-modal Coach closeout。同步 Phase
  Breakdown、PROJECT、REQUIREMENTS、ROADMAP、STATE 与最终讨论稿；未修改任何已冻结 phase。

- 2026-07-11 12:04 CST: 四通道产品方向形成最终讨论版，并将长期定位从“听力理解播放器”
  更新为“以真实内容为共同语境、听力先行的四通道语言学习工作台”；当前 Phase 3.7–3.10
  听力执行顺序不变，后续逐个验证 Reading/Speaking/Writing Studio。最终稿收敛两层复述、
  clip-level attempt 与 lexical capability 的粒度边界、SemanticRubric/SemanticJudgment、
  用户 adjudication 与 capability override 分离、LLM judge 校验门禁。新增厂商中立 LLM
  provider 裁决：领域 trait 不依赖单一 wire format，初始协议适配覆盖 OpenAI Responses /
  Chat Completions-compatible、Anthropic Messages、Gemini native API 与本地兼容服务；同步
  PROJECT、REQUIREMENTS、ROADMAP 与 STATE，不修改冻结 phase 文档。

- 2026-07-11 11:55 CST: 新增四技能扩展讨论稿的评审结论文档
  （`.planning/discuss/four-skills-expansion-review-and-llm-boundary.zh.md`）：
  记录对原稿的批判性评审（P0 隐藏语义评判依赖、范围过大、缺前置 spike、引用待核实）；
  owner 裁决正面引入 LLM API 作为语义能力 provider，并定五条架构边界（application 层
  provider trait + ADR、判定为 heuristic_proxy 级证据带模型/prompt 快照、用户可 override、
  结构化断言不给综合分、spike 校验后才获写证据资格）；确立"说"通道两层复述设计
  （L1 意义复述 → L2 表达复述）及其证据归属（第一层写 listening 不写 speaking、
  第一层为诊断工具非固定前置）。本文不改变现有 phase 排期与冻结边界。

- 2026-07-11 11:25 CST: 新增四通道产品讨论稿，调研 Phase 3.7–3.10 听力主线之外的
  speaking / reading / writing 功能；提出片段复述、角色接话、媒体伴生阅读、读听差异诊断、
  dictogloss 重构、个人表达模板与分层写作反馈，并给出四通道 evidence matrix、优先级及
  对 3.7–3.10 的演进建议。本文仅作后续产品输入，不改变现有 phase 排期与冻结边界。

- 2026-07-11 09:58 CST: 3.7–3.10 计划修订为 v2（四份 v1 计划写于 3.4.1/3.5.x/3.6 落地前）。
  共性：状态语言换四通道 capability 口径、证据链路对齐 ADR 0017/0019、播放对齐 3.5.7
  双实例架构。个性：3.7 目标定位优先复用 corpus 投影（lemma 归一）+"没注意"不写观察
  证据 + 狩猎小结挂 extensive-only completion + 标注 3.3 未收口前置；3.8 入口宿主改为
  3.5.6 练习浮窗第四题型 + shadowing 锁定韵律层 chunk（ADR 0016）+ attempt 排除出
  content-fit 折算；3.9 corpus connected-speech family 检索明确为新增可重建投影工程量 +
  LearnerProfile 收窄为补 L1；3.10 删除悬案区回访/卡点解决率（3.5.6 已撤机制）+ 精听不
  虚构 session 时长 + durable 事实清单对齐 v19–v31 schema + 建议引擎补猎词单联动。
  STATE.md 同步记录决策。

- 2026-07-11 09:32 CST: 3.6.1 收口后审计修复。SQLite schema v31 为
  `lexical_sense_folder_occurrences` 补 `BEFORE UPDATE` 父词条一致性触发器（0030 只防
  INSERT，assign 的 upsert UPDATE 路径此前仅靠应用层 SQL 守卫）；词典资产导入的义项边
  改为显式词条一致性谓词——原实现依赖触发器 `RAISE(ABORT)` 兜底，而 `OR IGNORE` 不降级
  ABORT，脏边会令整个导入失败而非按注释所称被跳过（已用 sqlite 实验证实）。新增测试：
  切片跨文件夹移动语义、UPDATE 触发器拒绝跨词条改写、脏边导入被跳过、v30→v31 迁移。
  顺手清理 lexical.rs 既有 needless_borrow clippy 警告。验证：persistence 83 +
  application 50 + api-http 35/12 全绿，clippy persistence-sqlite 零警告。

- 2026-07-11 08:48 CST: 重排底部 compact 迷你播放器为三段式布局：媒体信息改为圆形媒体标识、
  标题与时间双行展示，上一句/播放暂停/下一句居中且强化主播放按钮，倍速、静音和工作台展开
  收至右侧；进度条贴合播放器顶边，并为窄窗口保留自适应收缩。新增 compact widget 布局回归测试。

- 2026-07-11 08:37 CST: Phase 3.6.2 Dictionary Inline Clip UX 收口。词典详情移除根层
  `SlicePlaybackWindow` overlay，保留同一第二解码核心并改为默认视频的内嵌切片卡；未归类
  重复竖向卡片改为 PageView 横向轨道，支持触控/鼠标滑动、左右箭头/左右键切片与空格播放暂停。
  迁移 3 个旧竖向卡片测试并新增无 `Positioned` 内嵌 renderer 覆盖；Flutter 定向测试 24 passed。

- 2026-07-10 23:30 CST: 启动 Phase 3.6.2 Dictionary Inline Clip UX。owner 反馈 3.6 词典页
  错把 3.5.7 的浮窗 renderer 复用为根层 overlay；本阶段将保留第二解码核心，改为词条详情内嵌
  当前切片卡与水平切片浏览轨道，不改冻结的 3.6 / 3.6.1 文档或后端契约。

- 2026-07-10 23:25 CST: Phase 3.6.1 Sense Folders 收口。Owner 已接受真实媒体桌面 QA；
  CLOSEOUT、STATE 与冻结计划已同步。下一步建议为独立的 SceneLex 消费契约 spike，只定义
  已发布外部义项/资源的版本与发布状态，以及与本地文件夹 `external_ref` 的对齐，不实现
  下载、生成或自动消歧。

- 2026-07-10 23:25 CST: 开始 Phase 3.6.1 Sense Folders。新增本地义项文件夹的领域模型、
  schema v30、词典详情 API 与桌面端手动归类界面：文件夹是用户身份权威，外部 semantic
  reference 仅为可选不透明对齐字段；切片归类不写入学习证据、不改变词条级四通道画像，
  未归类切片仍完整显示。词典资产导出升级至 v7 并保留 v5/v6 导入。SceneLex/API/自动消歧
  均未接入。自动验证：Rust application 50、persistence 81、api-http 35 + HTTP integration 12
  全绿；Flutter analyze 与 widget test 全绿。真实桌面 owner QA 待执行。

- 2026-07-10 21:05 CST: Phase 3.6 债务清偿并收口。SQLite schema v29 新增
  `corpus_occurrences_fts` FTS5 伴生索引（rowid 镜像、触发器维护、迁移回填），多词 corpus
  查询从 `LIKE '%…%'` 全表扫描升级为分词短语匹配；`delete_track` 在 FK cascade 前显式清理
  FTS 行，连贯性不依赖 cascade 触发器。词 token 索引键与自由文本单词查询双向经
  `normalize_lexical_form`（用户纠正 → provider lemma → 基线）归一——"run" 能找到
  "running" 的语境；v29 前的存量索引需手动"重建媒体库语料索引"一次以获得 lemma 匹配。
  新增 lemma 归一与删轨连贯性测试；同步 DATA-MODEL（v28/v29 投影记录）与 OpenAPI 搜索
  语义描述。验证：Rust 三 crate 全绿（persistence 79 passed）、`validate-contracts.sh`
  通过、clippy 零新增警告、`git diff --check` 通过。真实媒体手工 QA 按 owner 决定豁免，
  `3.6-CLOSEOUT.md` 已写，phase 冻结；STATE 与 3.6-PLAN Progress 同步。

- 2026-07-10 20:19 CST: Phase 3.6 收口批次二（除真实媒体 QA 外全部剩余项）。后端：corpus
  搜索改为按 media 轮转采样（窗口函数交错排序），大词条截断页跨来源多样化，补采样测试。
  Flutter 词典详情：切片 wpm 估算标注与"默认顺序/按语速"排序（UI 状态改按 occurrence 身份
  键控，排序不串已揭示/已标记状态）；每切片"加入复习"出口（ReviewItem 带 sentence anchor
  时间窗，复习队列按 3.4 卡型派生；范围裁决：不内嵌 3.1 practice 会话 UI，词典动作出口收敛
  到复习队列）；回补词典化时移除的四通道 override 就地编辑、释义/笔记编辑与升级建议确认/
  拒绝 banner；外链兜底（零切片/零结果态 YouGlish 外链 + 词典发音按钮，明示仅供参考不作
  练习素材）；命中 limit 显示"已跨媒体采样"提示。新增语速估算单测与 5 个 widget 测试。
  验证：`cargo test -p persistence-sqlite`、`flutter analyze` 零问题、`flutter test`
  265 passed、`git diff --check` 通过。已知债挂账：phrase LIKE 全扫（FTS5 备选）、自由文本
  lemma 归一。

- 2026-07-10 19:58 CST: Phase 3.6 Slice 3 收尾接线 + Slice 1 体验修正。后端：corpus 索引纳入
  active chunk timeline 的 chunk 行（含空格查询同时命中句子与 chunk），chunk timeline
  activate/archive/delete 与激活式生成触发该轨重建；新增 `rebuild_corpus_index` 全库回填
  use case 与 `POST /v1/corpus/reindex` 契约（存量媒体库的主动重建入口）。Flutter：词典页
  从弹窗改为 master-detail 页内详情并自持第二解码切片窗——播放例句不再退出词典、不触碰主
  播放器（入路由时暂停）；深链改为按 entry id 直取详情；词条详情新增"在我的媒体库中搜索"
  （corpus 命中经切片窗试听、一键收为该词条来源切片，去重已保存句子）；词汇本零结果时降级
  为 corpus 纯查询；词典页工具栏新增重建索引入口；"加入复习"回补到词典详情；新增
  `CorpusOccurrence` 手写 DTO + fixture 契约测试与 library-section widget 测试。
  回归修复（3.5/3.5.6 接缝）：精听 session 在 extensive-only completion 后永不完成，练习
  准确率校准失去触发点——改为 attempt 提交时增量折算（`record_practice_accuracy_feedback`），
  completion 仅折算理解度自报。验证：`cargo test -p application -p persistence-sqlite
  -p api-http` 全绿、`validate-contracts.sh` 通过、`flutter analyze` 零问题、`flutter test`
  259 passed、`git diff --check` 通过。

- 2026-07-10 16:26 CST: Phase 3.6 Slice 3 后端索引基础。新增 SQLite schema v28 的
  `corpus_occurrences` 可重建本地投影、`CorpusIndexRepository` 实现与
  `GET /v1/corpus/search` OpenAPI 契约；字幕导入和轨道语言修改会替换该轨道的索引。首批
  索引精确 lexical token 与句级 phrase occurrence：单词精确命中不与句级行重复，含空格短语
  查询只返回句级上下文。chunk / connected-speech index 与 Flutter 搜索/收例句交互仍在 Slice 3
  后续接线范围内。

- 2026-07-10 16:10 CST: Phase 3.6 Slice 2 接线。词典每个带稳定 sentence ID 的来源切片在
  “先听 → 显示文本”后可单键标记“这次听出/没听出”；复用既有 lexical-observation API，
  因而保持 sentence-level diagnosis 兼容记录，并自动追加 ADR 0017 的 listening
  context-marking evidence、既有识别证据/建议与 projection 链路。旧切片若无稳定句子链接，
  明确仅可试听、不伪造证据。

- 2026-07-10 15:56 CST: 启动 Phase 3.6 Listening Dictionary MVP 第一刀（Flutter-only，零新
  后端表/字段/契约）：词汇本详情演进为“学习对象 → 来源切片”的听力词典视图，显示四通道
  画像与诚实的本地切片覆盖度；每条切片默认隐藏句子文本、可手动揭示目标词高亮，并复用
  3.5.7 独立切片播放器（含未关联来源的既有指纹恢复路径）。词汇学习面板与诊断 lexical
  barrier 可直达指定词条；新增中英文文案和 widget tests。corpus index/搜索、逐例听出标记、
  义项文件夹与复习/练习出口仍按 3.6 后续 slices 推进。

- 2026-07-10 15:46 CST: Phase 3.5.7 Slice Playback Window 收口。Flutter-only：以独立
  fvp/video_player 第二实例取代词汇来源句的主播放器劫持；新增可注入
  `OccurrenceMediaResolver`（关联媒体/文件定位/指纹验证/注册）、默认音频优先且可展开视频的
  `SlicePlaybackWindow`、音频焦点互斥与中英文文案。所有 A 组来源句入口迁移，删除
  `playOccurrence`/`loopOccurrence`；B 组当前媒体 `loopRange` 未迁移。真实 macOS 双实例
  spike 通过，`flutter analyze`、`flutter test`（252 passed）与 `git diff --check` 通过；owner
  确认收口，冻结 phase，3.6 复用该播放端承接多切片卡片浏览。

- 2026-07-10 15:20 CST: Phase 3.5.6 Intensive Practice Floating Window 收口。新增
  `3.5.6-CLOSEOUT.md`，将执行 PLAN 标为完成并冻结；STATE 从 owner 声明收尾更新为正式收口。
  真实媒体手工 QA 按 owner 决定豁免；此 phase 不闭合 milestone，`MILESTONES.md` 不变。

- 2026-07-10 14:58 CST: 规划：切片播放器与听力词典 v2（纯文档，无代码）。基于
  `.planning/discuss/personal-listening-dictionary-and-slice-player.zh.md` 的评审结论（新增 §9，
  状态改 REVIEWED）：新增 Phase 3.5.7 Slice Playback Window 计划（独立第二解码实例浮窗取代
  `playOccurrence` 主播放器劫持，Slice 0 为双实例可行性 spike，B 组 loopRange 不迁移）；
  3.6 听力词典 PLAN 修订为 v2（第一刀零新后端"学习对象 → 切片"资产词典页，corpus index/搜索
  降为第二刀，义项为 3.6.x 独立 phase 且 sense spike 从"3.6 前"改排到义项切片前，图谱视图
  推迟，`LexicalEntry` 不改名）。STATE 记录 3.5.6 owner 收口（CLOSEOUT 待补）、新决策与
  下一步工作。

- 2026-07-10 14:19 CST: Phase 3.5.6 清理 3.2 的失效内部聚合。物理删除 application 的卡点
  writer、`PracticeSessionSummary` read-side aggregation、`StuckPoint*` DTO/helpers 及相应
  persistence 历史测试；既有 SQLite `learning_events`、practice attempts 与 review 数据不删，
  但不再派生“悬案/本次总结”。泛听结束 use case 改名为 extensive-only
  `complete_listening_session`，不再写旧的 open/unexplained/familiar-material 字段，理解度自报与
  content-fit calibration 仍保留。同步 ARCHITECTURE / DATA-MODEL / STATE；验证 Rust
  persistence/application/api-http、Flutter 全量测试和 contracts 均通过。

- 2026-07-10 10:15 CST: Phase 3.5.6 自动化收尾补强。新增
  `intensive_practice_window_test.dart` 覆盖浮窗 mini-player 收起/恢复、相邻句导航和关闭回调；
  测试暴露并修复了 `IntensivePracticeWindow` 将 `Positioned` 包在 `LayoutBuilder` 下导致的
  `StackParentData` 运行时断言——现改为以 viewport 尺寸计算浮窗位置，使 `Positioned` 保持为
  workbench Stack 的直接子项。`flutter analyze` 与新 widget test 通过。

- 2026-07-10 10:00 CST: Phase 3.5.6 Slice 0–3 首轮落地。精听从右侧 `PracticePanel` 移至新建、
  可拖动的 `IntensivePracticeWindow`：姿态栏“测一下”直接打开，支持迷你播放控制收起/展开、
  复听、相邻句连续换题、结果 diff、retry 与加入复习队列；关闭会清理 `loopPractice` 与 transient
  practice state。移除右侧 Practice tab、精听 mark/skip/悬案/session summary/精听完毕 UI，
  `PracticeController` 不再加载 summary 或写卡点/diagnosis-viewed 事件。公开契约移除 summary/
  stuck-point/diagnosis-viewed/通用 practice complete routes 和 DTO；泛听结束收敛为
  `POST /v1/listening/sessions/{id}/complete`，应用层只允许 `extensive` session，保留理解度自报
  与 `ListeningCompleted` 写入。同步 OpenAPI、generated client、Flutter DTO/测试和契约 gate。
  定向 `flutter analyze`、Flutter practice tests、`cargo test -p application -p api-http`、
  `validate-contracts.sh` 已通过；浮窗 widget 交互与真实媒体 QA 待 Slice 4。

- 2026-07-10 09:44 CST: 启动 Phase 3.5.6 Intensive Practice Floating Window，新增
  `3.5.6-PLAN.md`，将浮窗、迷你播放器、相邻句导航、精听卡点/session 机制撤回及测试顺序
  拆成独立 slices。计划明确关键边界：`completePracticeSession` 也服务 Phase 3.3 泛听的
  comprehension report / `ListeningCompleted`，因此精听 UI 不再调用它，但不能无差别删除；
  卡点专属契约可移除，泛听结束语义须保留或迁为专名 API。同步更新 `STATE.md` 当前阶段与时间戳。

- 2026-07-10 09:27 CST: Phase 3.5.5 Intensive Listening UX Fix 收口。撰写
  `3.5.5-CLOSEOUT.md`（如实记录 delivered 8 组 + carved-out 1 组 + deferred 6 项）;9 组走查
  问题交付 8 组（回退首页、循环标注、内容匹配度入口、词汇来源竞态、听懂了吗含 C 视图第 4 项、
  溢出菜单、词汇本升级 A+B、意群/chunk 表达统一），全程守住 ADR 0016 数据双层分离。最大的
  一块独立功能"精听浮动练习小窗"（含 P0）切出到新 Phase 3.5.6（建 `3.5.6-intensive-practice-window/
  3.5.6-CONTEXT.md`，引用上游设计文档，PLAN 待独立会话撰写）。`STATE.md` 新增 3.5.5 完成条目
  与 3.5.6 下一步、更新头部时间戳与最近决策。MILESTONES 不动（3.5.5 非里程碑）。

- 2026-07-10 09:22 CST: Phase 3.4.3 Construction Modeling Spike 收口（纯 domain，未建设
  SQLite/API/Flutter/LLTimeline schema）。新增 `construction` domain seam 和可执行 en/zh/ja
  manual gold fixture：区分 `SentenceExemplar`（来源快照素材）、人工 canonical
  `Construction`（`language + key + schema_version`）、可重建的
  `ConstructionOccurrence`（token span + slots + construction-owned variant policy）及
  `UserSentencePattern`（独立用户资产、可选 system link）。fixture 覆盖时态/语态/否定/疑问、
  一句多构式/嵌套、recognition/production + read/listen/speak/write modality，以及从没有任何
  system occurrence 的任意日语句子提炼个人模板。结论：证据足以锁定边界，但不足以冻结
  canonical library、自动 provider、迁移与消费工作流，故不建生产表；下一步先验证“收藏句 →
  个人模板”产品切片。`cargo test -p domain construction --lib` 4 passed。

- 2026-07-10 09:14 CST: 字幕「分组」显示统一（Flutter-only，UX 收敛）。将原先两个
  相互独立、可叠加显示的可见性开关 `showChunkGrouping`/`showSenseGrouping` 合并为
  单一模式枚举 `groupingMode`（`off`/`prosodic`/`semantic`/`compare`，字符串持久化，
  默认 `off`）。**渲染**（`token_line.dart`）：`prosodic` 复用既有语流语块胶囊（实线
  边框）;`semantic` 用同样胶囊几何但**虚线 + 琥珀 accent 描边 + 临时标记 tooltip**，
  明确标注其为启发式「标记」而非声学证据;`compare` 以语流胶囊为底，在每一处「语义
  边界与语流边界不重合」的分歧点（token 间）叠加 `ListenColors.accent` 小箭标 + 虚线
  刻度 + 「语义与语流在此不一致」tooltip——这些分歧点即听力热点。两套数据仍各自独立
  流入 `TokenLine`（`chunkPartition` + `senseGroups`），由控件按模式择一绘制。
  **设置**：`AppSettings` 去掉两个旧 bool、新增 `groupingMode` + 加载期迁移
  （`show_sense_grouping==true`→`semantic`;否则 `show_chunk_grouping`(缺省视为 true)
  →`prosodic`;否则 `off`），保持 v8 向后兼容;新增 `chunkHighlightActive` 派生
  （仅 `prosodic`/`compare` 且开启当前分组高亮时，当前语块高亮才随播放走）。设置弹窗与
  flow 用单个 4 选项下拉替换两个开关，子控件（分组显示方式/当前分组高亮/高亮样式）改按
  `groupingMode != off` 联动。**改名/本地化**：面向用户不再暴露 Chunk/SenseGroup/意群，
  统一「分组 / Grouping」;新增 en+zh 键 `groupingMode*`、`groupingSemanticProvisional`、
  `groupingDivergenceHint`，改写 `chunkDisplayStyle`/`highlightCurrentChunk`/
  `chunkHighlightStyle` 文案为「分组」措辞。`player_stage`/`side_panel`/`transcript_panel`
  改为透传 `groupingMode` + 两套数据，转写列表与视频字幕同源同模式。
  **数据模型保持分离**（不改后端/`crates/**`、不改 SenseGroup/ChunkTimeline 领域/持久化/
  API），符合 ADR 0016：语义与语流本就会分歧，该分歧正是最有教学价值的信号。
  **本轮延后**（follow-up）：播放循环/导航仍绑定语流语块、不随模式切换;意群算法
  （NLP/置信度）不改，`semantic` 本轮刻意保持粗糙的「标记」。新增/更新测试：4 种模式
  渲染（语流胶囊、语义虚线临时标记、compare 在分歧处出标记而在重合处不出、off 平铺）
  + 6 项 `groupingMode` 迁移/派生用例。`flutter analyze` 零问题、`flutter test` 247 passed。
- 2026-07-09 23:43 CST: Phase 3.5.5 词汇本升级 Slice 2-4 完成（能力过滤为主 + 四通道
  摘要 + 纳入 Phrase）。**Slice 2 后端 API**：application `list_vocabulary` 暴露
  `kind`/`status`/`capability_filter`（去掉 `Some(Word)` 硬编码，`kind=None` 返回词+短语）;
  路由 `VocabularyQuery` status 改可选、新增 `kind`/`capability`/`assessment`（后两者同时
  present 才构成 `CapabilityFilter`）;OpenAPI 加性更新（status 去 required + 4 个新 param）;
  2 处测试调用适配。**Slice 3 Flutter 数据**：`api_service.listVocabulary` 改命名可选参数
  （status 可选 + capability/assessment/kind），2 处调用方（`savedVocabularyCount` 等）适配。
  **Slice 4 词汇本 UI**：`VocabularyBookView` 列表项渲染四通道能力摘要（复用
  `effectiveAssessment`，acquired=绿/not_acquired=琥珀/unassessed=灰，带 tooltip）+ word/phrase
  徽标 + 来源快照;`VocabularyScreen` 过滤器从旧三态换为能力维度选择（reading/listening/
  speaking/writing）+ 状态过滤（全部/已掌握/未掌握/未评估），legacy status 后端保留;详情弹窗
  查词典/发音对 Phrase 做 null 容错。共享配色 helper `capabilityAssessmentColor` 统一列表与
  过滤器。新增 l10n 键 vocabFilterAll/vocabFilterCapabilityHint;新增 widget 测试验证四通道
  图标 + phrase 徽标渲染。契约工件 `local-api-v1.ts` 同步更新。`flutter analyze` 零问题、
  `flutter test` 236 passed、`cargo test -p persistence-sqlite/-p api-http` 全绿、
  `validate-contracts.sh` 通过。留待独立 phase：问题 3（统一学习对象抽象、句子/构式/搭配
  作为资产）、旧状态 ChoiceChips 移除。

- 2026-07-09 23:05 CST: Phase 3.5.5 词汇本升级 Slice 1（后端能力过滤持久化，A+B 计划）。
  `LearningAssetRepository::list_lexical_entries` 新增 `Option<CapabilityFilter>` 参数
  （domain 新增 `CapabilityFilter{capability, assessment}`）。SQLite impl 分两分支：无过滤
  走原查询;有过滤时 `LEFT JOIN lexical_capability_states`(sense_id='' 条目级)并按有效结论
  过滤——`COALESCE(json_extract(override_json,'$.conclusion'), json_extract(projection_json,
  '$.conclusion'))`,`unassessed` 匹配无状态行(override 优先于 projection,缺失=未评估)。
  三处调用方传 `None`(application 通用 wrapper 与 vocabulary 暂不暴露,slice 2 再接);两处
  持久化测试补 `None`。新增测试 `list_lexical_entries_filters_by_effective_capability_assessment`
  验证 acquired/not_acquired/unassessed 三态过滤 + override 覆盖 projection + per-capability
  语义。`cargo test -p persistence-sqlite` 74+5+6 全绿。后续 slice：application/route/OpenAPI
  加性暴露过滤 → Flutter 数据层 → 词汇本 UI（四通道摘要 + 能力过滤器 + Phrase + ListenTheme）。

- 2026-07-09 22:38 CST: Phase 3.5.5 收尾（既有失败测试 + 溢出菜单阈值）。①修复
  `content_fit_card_test.dart > renders both dimension bands...` 的既有失败：de4bc2e7
  把 `contentFit` 文案从 'Content fit' 改成 'Difficulty'（'难度适配'）时漏更新测试，
  第 53 行仍断言旧文案 'Content fit'；改为当前 'Difficulty'（测试陈旧，非代码 bug）。
  ②底部工具栏溢出菜单阈值 `roomy` 从 1080 降到 900（方案建议 840~900）：平铺功能按钮
  （泛听/Chunk/字幕菜单）撑到 900px 才收进 `more_horiz` 溢出菜单，功能区约 800px 仍舒适。
  `flutter analyze` 零问题，全量 `flutter test` 235 passed（此前唯一的既有失败已消除）。

- 2026-07-09 22:33 CST: Phase 3.5.5 —"听懂了吗"方案第 4 项落地（C 视图按需加载 +
  移除技术分析按钮）。此前只做了文案改名，方案核心结构未动。本次：DiagnosisCard 移除
  "分析真实发音 / 分析整条字幕"两个技术按钮及 `onAnalyzePhonetics`/`onAnalyzeTrackPhonetics`
  参数（那是"作用范围"这一纯技术决策塞给用户）；改为在 C·本次音频听感参照位置
  (`player_stage.dart` mode=='actual' 且无 rhythmFrame) 原位显示加载提示
  `_SoundReferenceLoadPrompt`，提供[加载当前句][加载全部字幕]两个力度选项，语义从技术
  动作转为"看这一句 / 一次分析整轨后切句免等"。`PlayerStage` 新增 `onLoadSoundReference`
  回调，`main.dart` 接 `_analyzePhonetics`（preference=='off' 时为 null 退回旧不可用
  提示）。清理传递链：移除 `SidePanel.onAnalyzePhonetics` 参数/字段/本地包装。新增
  en/zh 键 soundReferenceNoData/loadCurrentSentence/loadWholeTrack/soundReferenceLoadHint，
  删除废弃键 analyzeRealPronunciation/analyzeSubtitleTrack。`diagnosis_card_test.dart`
  移除测两个已删按钮的用例（其余 4 用例仍绿）。`flutter analyze` 零问题，全量
  `flutter test` 除 1 个先前既有失败（`content_fit_card_test.dart` 的 golden-target
  用例，在 clean HEAD 上同样失败、与本次改动无关）外全部通过。

- 2026-07-09 22:07 CST: Phase 3.5.5 UX 修复（词汇来源记录竞态）。fc70949d 的自动来源
  记录走 `unawaited` 发 occurrence 写入后紧接着 reload/fetch details，两个 HTTP 请求
  无序，reload 可能先于写入返回，导致"刚遇到的来源句在面板上不立即出现"（需重开词汇
  才显示），且写入错误被吞。`LearningWorkflowController.openWord`（已存在词分支）与
  `setCapabilityOverride`（`not_acquired` 时）均改为 `await` occurrence 写入并 try/catch
  兜底，保证 details 重载能看到新记录、且写入失败不影响能力覆盖结果；手动"记录当前句"
  按钮原本就是 awaited，无需改。移除不再使用的 `dart:async` 导入。`flutter analyze`
  零问题，`learning_workflow_controller_test.dart` 11 passed。注：fc70949d 的"听懂了吗"
  方案仅落地文案改名，方案第 4 项（把"分析真实发音/分析整条字幕"移出 DiagnosisCard、
  改 C 视图按需加载）尚未实现，待定。

- 2026-07-09 22:00 CST: Phase 3.5.5 UX 修复（循环标注 + 内容匹配度入口）。
  **循环标注 bug**：`PlaybackActionsCoordinator.loopRange` 此前把 chip 标签硬编码为
  `'loopRange'`，调用方传入的场景描述只进了瞬时状态文本，导致收件箱/卡点/复查/
  声音线证据/音素/热点/节奏/练习等所有 range 循环在循环 chip 上全部显示同一个
  "范围循环"，提交声称的"区分场景"未生效。改为新增 `loopRange(..., {String labelKey})`
  命名参数，chip 用 `labelKey`、状态文本仍用 `label`；9 个调用点（main.dart×6、
  side_panel.dart×3）各传对应场景 key。新增 en/zh 本地化键 loopPractice/loopInbox/
  loopStuckPoint/loopRhythm/loopPhone/loopHotspot（loopEvidence 复用已有键）。
  **内容匹配度入口**：de4bc2e7 在侧栏姿态区加的 `_contentFitSummary` 只是完整
  `ContentFitCard` 的有损单行复制（仅两个 fit chip + 弹窗），而带冷启动补标注按钮、
  精听目标提示、校准状态的完整卡片仍埋在"字幕资源"技术 tab 里，空词汇画像新用户
  最需要的冷启动入口在默认转写 tab 不可达。改为在转写 tab（浏览/决策主面）直接渲染
  完整 `ContentFitCard`（透传 `onStartColdStart`），移除有损的 `_contentFitSummary`，
  不再在词汇/诊断/练习深度 tab 上重复堆叠。命名语义（内容匹配度/理解/听辨）与意群一样
  留待单独的语义重设计，本次不碰。`flutter analyze` 零问题，`flutter test
  coordinators_test.dart` 7 passed。

- 2026-07-08 18:20 CST: Phase 3.5 Slice 8 — Cold-start quick-marking flow。后端：
  `cold_start_word_candidates` 从 track transcript 抽样高频未评估词（共享
  `normalize_lexical_form` 归一化路径，按频次降序、同频字典序，clamp 50）。
  API `GET /v1/subtitles/{track_id}/cold-start-words?limit=20` + OpenAPI spec +
  `ColdStartWordCandidate` schema。端点测试验证排序、标注后候选消失。Flutter：
  `ColdStartWordCandidate` DTO + `coldStartWords` API method。
  `ColdStartMarkingSheet` 弹窗逐词三选一标注（KnownRecognized/KnownNotRecognized/
  UnknownMeaning/Skip），写入复用现有 `upsertWordLexicalEntry`，关闭后回调
  `loadContentFit` 刷新 fit 卡。`ContentFitCard` 降级态显示"快速标注"入口，
  回调经 `SubtitleResourceManagerPanel` → `SubtitleResourcesScreen` / `SidePanel` →
  `main.dart` 传递。en/zh 双份本地化（coldStart* 键）。契约测试 + widget 测试覆盖。
  `cargo test --workspace` 全绿，`flutter analyze` 零问题，`flutter test` 236 passed。

- 2026-07-08 12:35 CST: Phase 3.4.2 Slice 6 — Closeout。创建 `3.4.2-CLOSEOUT.md`（exit
  signals 逐条验证、alignment 推迟理由、ChunkTimeline 改名评估结论"继续推迟"、
  累积文件变更清单）。`3.4.2-PLAN.md` 全部 checkbox 标记完成、状态 COMPLETED。
  `STATE.md` 更新 Phase 3.4.2 完成记录。Phase 3.4.2（Semantic / Prosodic Group
  Separation）全部 7 个 Slice 交付完毕。

- 2026-07-08 12:15 CST: Phase 3.4.2 Slice 5 — Flutter 集成。Dart 模型三类（SenseGroup/
  SenseGroupAnalysis/SenseGroupAnalysisSummary，手写 fromJson/toJson，ADR 0014 纪律）。
  ApiService 6 方法（list/summaries/generate/activate/archive/delete）。SubtitleController
  + SubtitleState 新增 `senseGroupsBySentence: Map<String, List<SenseGroup>>` 缓存 +
  copyWith + 清除 + 便捷访问器。SpeechEnhancementWorkflowController 加载 active analysis
  并按 sentence_id 分桶。MediaSessionCoordinator 透传。Settings 新增 `showSenseGrouping`
  布尔（默认 off）+ 持久化 + en/zh 本地化。契约测试 7 用例
  （SenseGroup 最小/完整/round-trip、SenseGroupAnalysis 含组/active、Summary 解析）。
  flutter analyze 零问题，flutter test 233 passed。

- 2026-07-08 11:45 CST: Phase 3.4.2 Slice 4 — Application use cases + API routes + LLTimeline 集成。
  新增 `crates/application/src/sense_groups.rs`（generate/list/summarize/get/activate/archive/delete，
  generate 无 word timeline 硬依赖，纯文本 partition → SenseGroup 组装含 char-span text 切片）。
  API 7 个 handler（`timelines.rs`）+ 6 条路由注册（`lib.rs`）覆盖 GET/POST/DELETE/activate/archive。
  LLTimeline 导出填充 `sense_group_analyses` + `active_sense_group_analysis_id`，导入镜像
  chunk_timelines 保存+激活流程。`remap_lltimeline_identity` 扩展 5 处（media/track remap、
  sentence_id remap、parent_word_timeline_id remap、analysis id remap + group id remap、
  active id remap）。OpenAPI spec 新增 5 paths + 5 component schemas（SenseGroupAnalysis/
  SenseGroupAnalysisSummary/SenseGroup/SenseGroupSource/GenerateSenseGroupAnalysis）。

- 2026-07-08 11:15 CST: Phase 3.4.2 Slice 3 — SenseGroupAnalysis 持久化层落地。新增
  `migrations/0025_sense_group_analyses.sql`（`sense_group_analysis_runs` 表，4 索引含
  active 唯一约束，镜像 chunk_timeline_runs 模式），在 `migrations.rs` 注册 v25 slot。
  `repositories.rs` 三处扩展（SubtitleRepository trait / TimelineResourceRepository trait /
  blanket impl）各 7 方法（save/list/get/active/activate/archive/delete）。`subtitles.rs`
  SQLite 实现全部 7 方法，activate 自动降级先前 active 为 Candidate。测试：lifecycle
  全链路（candidate→active→archived、第二个 activate 顶替第一个）、active 唯一约束、
  JSON round-trip（多组含 label/sources 字段）、迁移恢复测试验证 v25 表存在。

- 2026-07-08 10:30 CST: Phase 3.4.2 Slice 2 — 规则回退 partition provider 落地。新增
  `crates/speech-analysis/src/sense_group_partition.rs`（`partition_sentence` 纯文本分组，
  标点+长度+短语保护规则），在 `lib.rs` 注册模块。14 个单元测试覆盖英文 ≥5 句、中文 ≥3 句、
  边界情况及不变量断言（组不重叠、连续覆盖全部 Word token、每组 ≥1 Word）。合入
  `codex/3.4.2-sense-group-separation` 获取 Slice 1 domain contract。

- 2026-07-08 08:15 CST: Phase 3.5 Slice 7 反馈回流 → 个人 sound fit 校准项。
  校准项 = 独立持久表 `content_fit_calibrations`(迁移 v27)中的反馈计数记录
  (理解度自报三档计数 + 计分练习尝试/正确计数),是学习者证据不是缓存:
  与 fit 缓存分离、在任何 fit 重算后存活;原始材料信号永不改写。写路径:
  complete practice session 尾部把本 session 的理解度自报(3.3 泛听)与计分
  练习表现(跳过不计)累加进对应媒体的校准记录(无 media 或无反馈不写;
  已结束 session 重复 complete 不重复计数;best-effort——fit 是装饰,校准存储
  不可用不能挡 session 完成)。读路径:fit 计算末尾以纯函数从计数导出修正
  (`sound_fit_calibration_outcome`,domain 单点定义,全部 heuristic_proxy:
  自报 ≥2 条按多数方向 ±1 档、平票取谨慎向 harder;练习 ≥5 次尝试正确率
  ≥0.85 → 易一档 / ≤0.5 → 难一档;双通道相加 clamp 到 ±1 档),只平移 sound
  档位并追加两个可解释校准信号(comprehension_report_unclear_ratio /
  practice_correct_rate,decisive 标记);任一通道证据足够即
  `evidence_grade → usage_calibrated`(零修正也算校准:使用验证了档位)。
  算法版本 content-fit-v1 → v2(管线加入校准输入;分档常量未动),
  fingerprint 纳入校准水位(新反馈自动失效缓存)。openapi FitSignal kind
  枚举 + Dart 本地化(en/zh)+ contract fixture 校准态测试同步;UI 无需改动
  (usage_calibrated 文案与信号渲染 Slice 4 已就位)。测试:domain 校准
  真值表 5 项(最小证据/多数与平票/正确率端点/双通道合成与 clamp/应用后
  材料信号不动 + 饱和);persistence 集成 3 项(自报两次 unclear → 难一档 +
  usage_calibrated + 换词汇强制重算后校准存活;无 media/无反馈不写;
  精听 1/6 正确 → 难一档 + decisive 信号)。验证:cargo test --workspace
  440 passed / 0 failed,flutter analyze 干净,flutter test 227 passed,
  clippy 四 crate 零新增(20 处告警全在既有文件),validate-contracts 仅
  本机既有 4 个 CJK jieba 失败。

- 2026-07-08 07:55 CST: Phase 3.5 Slice 5 三队列分拣 + 首页媒体库列表。后端:
  `GET /v1/media` 媒体库读模型(每个媒体 + primary 语言轨的缓存 fit +
  用户分拣意图 + 3.2 熟料标记;逐媒体 fit 失败静默降级为无徽标不掉行)、
  `PUT /v1/media/{media_id}/triage-intent` 持久化 pin 泛听 / pin 精听 / 暂缓
  (null 清除);迁移 v26 `media_triage_intents`(v25 槽位留给 3.4.2,
  "后落地方顺延"规则记录在迁移文件与 migrations.rs 注释);
  `MediaRepository` 增 list/意图三方法,`LearningEventRepository` 增
  `list_event_subject_ids`(熟料媒体查询);openapi 同步
  (MediaLibraryEntry/SetTriageIntentRequest)。队列本身保持派生视图
  (ADR 0018 决策 6):派生规则放客户端展示层(与 isIntensiveListeningTarget
  同先例),服务端只存意图、只供事实。Flutter:首页"开始听"下方新增媒体库列表
  (`media_library_section.dart`),按 精听靶单 / 泛听队列 / 暂缓区 / 未分级 分组,
  黄金靶置顶并挂"精听靶"徽标,行内双维 fit mini chips 复用 fit_* 档位语汇;
  派生阶梯:用户意图 > 熟料回听供给(设置可关,`familiar_material_suggestions`,
  默认开、徽标克制)> 黄金靶 → 精听 > 任一维 too_hard → 暂缓 > 其余泛听,无事实
  不建议;行点击 = 普通打开(红线:完全无视分拣行为不变),一键泛听(打开 + 起
  extensive session)/ 一键精听(打开 + 落 practice 面板)。测试:persistence 4 项
  (意图 roundtrip/列表事实/熟料回流/校验+返回)、api-http 端点 1 项(列表含 fit +
  意图存取清除)、Dart contract fixture 7 项(wire shape/容错/round-trip/队列派生
  真值表)+ widget 5 项(分组排序/意图覆盖/熟料开关迁移/回调/空态)。验证:
  cargo test --workspace 432 passed / 0 failed,flutter analyze 干净,flutter test
  226 passed,clippy 四 crate 零新增,validate-contracts 仅本机既有 4 个 CJK
  jieba 失败。

- 2026-07-08 02:00 CST: Phase 3.5 剩余工作编排(owner 决策)。Slice 8 冷启动快速标注流
  交接:新增 `3.5-SLICE8-COLDSTART-GUIDE.md`(自包含实施指南——抽样端点镜像 content_fit
  的归一化统计、标注复用现有词条路径零新写入面、fit 卡降级态挂入口、五个坑位:归一化
  同路 / 未评估≠不认识 / 零新写入面 / 不阻塞红线 / jieba 本机既有失败),由独立实现者
  执行,可与 Slice 5/7 并行。Slice 5 UI 方向确定:不做独立页面,首页"开始听"下方加
  媒体库列表(新 list-media 端点),按队列分组、黄金靶置顶。推进顺序:Slice 5 → 7
  (新 session);3.5-PLAN 与 STATE 同步。

- 2026-07-08 01:40 CST: Phase 3.5 Slice 6 listening-projection-v1(ADR 0019)。首个证据
  投影算法,确认门控的保守规则:acquired 只由升级确认事件从证据流导出(裸任务成功与
  上下文标记只作辅助,护住 3.4 "5 语境→建议→确认"管线);无辅助任务失败降档,已确认
  词有单次 lapse 保护(SRS lapse 惯例),任务成功可重固确认词并打断失败连击;
  confidence(0.85 task 级 / 0.40 弱化)与 evidence_as_of_ms 填充 3.4.x 预留 seam。
  触发:append_channelized_observation 内同步重算(限读最新 200 条)+ recency guard
  (更新的兼容/导入写入压过更旧的证据结论)。写入者阶梯:override(读时)> task 级
  证据 > 兼容/导入 > 弱化证据——兼容同步不得以 acquired 覆盖 task 级证据结论(A 方案:
  自报"认识"不能翻任务失败的盘),降档与清除始终放行(无失败棘轮);兼容同步尾部统一
  从画像重导 status 列,堵住 create/import 直写 entry.status 的绕行。升级确认对
  listening 的投影直写移除(ADR 0017 决策 4 兑现),非 listening 通道保留过渡直写。
  两个刻意的行为变化(记录于 ADR 0019 决策 4):仅标记/导入支撑的词单次听写/复习
  失败即翻为 KnownNotRecognized;任务失败后经 status 面板重标"认识"不再翻回。共享
  上下文 §14、3.5-PLAN、STATE 同步。测试:domain 规则真值表 6 项;集成 2 项(五语境
  确认后投影出处为 listening-projection-v1 + conf 0.85;任务失败翻档 + 阶梯拦截自报
  升级 + reading 通道不受影响);既有升级/复习/资产测试全数保持通过。验证:workspace
  427 passed / 0 failed,clippy 15 告警与基线持平零新增。

- 2026-07-07 22:00 CST: Phase 3.5 Slice 4 API + 当前媒体 fit 展示。后端:
  `GET /v1/subtitles/{track_id}/content-fit`(track-scoped,走 Slice 3 缓存读路径)+
  openapi path/schema(FitSignal/DifficultyDimension/ContentDifficultyProfile);
  api-http 端点测试(未标注词汇时诚实报 too_hard + assessed 0 + unassessed decisive,
  二次读命中缓存返回一致)。Flutter:手写 DTO(ADR 0014)+ contract fixture 测试 5 项
  (wire shape、黄金靶派生 meaning 易 × sound 难、诚实阈值镜像后端 0.5、round-trip、
  缺 signals 容错);`ContentFitCard` 落字幕资源面板(当前媒体摘要面):双维档位
  chips(轻松/合适/有挑战/需要辅助——预期管理文案守 guardrail)+ 黄金靶提示 +
  详情弹窗(信号→文案,decisive 标记,不见公式)+ 词汇画像不足的诚实降级提示
  (档位不隐藏只重新框定);fit 拉取挂 timeline 资源加载,失败静默清卡不阻塞;
  widget 测试 5 项。媒体库列表徽标推迟到 Slice 5(队列 UI 才有媒体列表)。验证:
  workspace 420 passed / 0 failed;flutter analyze 无 issue;flutter test 214 全过;
  api-http clippy 无新增告警。

- 2026-07-07 21:10 CST: Phase 3.5 Slice 3 persistence 难度缓存。schema v24:
  `0024_content_difficulty_profiles.sql`(每 subject 一行的可重算缓存,无 FK,
  靠 fingerprint 自失效);`DifficultyRepository` sqlite 实现(JSON 快照 + 投影查询列
  整体重写)。缓存读路径 `content_fit_for_track`:廉价指纹校验(track 指纹 + active
  word/chunk timeline 身份 + 语言级词汇水位,不做归一化不组装文档),命中返回缓存,
  失效重算并回存;指纹组装收敛为单一定义点,compute 路径共用(词汇水位从"匹配条目
  max"改为语言级 `lexical_vocabulary_watermark`(count, max_learning_updated_at)新
  仓储方法——语言内任何标记使该语言全部缓存失效,粗粒度但绝不陈旧)。AppServices 增
  `difficulty` 仓储(Disabled 默认 + `with_difficulty_repository`,api-http main 已接线)。
  **迁移编号协调**:3.5 先落地取 v24,worktree 中未动工的 3.4.2 顺延 v25(其 PLAN/
  实施指南/CHANGELOG 已在 worktree 分支同步改号,commit 271e87c1)。测试:缓存命中
  (篡改行回读证明)、词汇变更失效重算并回存、迁移恢复测试断言 content_difficulty_profiles
  表与 MIGRATION_VERSION。验证:workspace 419 passed / 0 failed,clippy 前后 15 告警
  零新增。

- 2026-07-07 20:20 CST: Phase 3.5 Slice 2 application fit 计算服务。新增
  `crates/application/src/content_fit.rs`:`compute_content_fit_for_track` 从
  `export_lltimeline_document` 单点组装输入,词义知识经 `LexicalEntry::status`
  (= `legacy_status_view` 保守折叠视图,override 已折入)读取;transcript word token
  经 `normalize_lexical_form` 归一(空归一 token 排除出分子分母)后批量查询;信号:
  unknown/unassessed/KNR 密度、语速(仅句内 speech time,排除句间静默)、弱读/压缩
  密度(rhythm frames 派生自 active word timeline,缺失则省略)、平均 chunk 长度;
  `input_fingerprint` = 算法版本 + track 指纹 + active word/chunk timeline 身份 +
  词汇水位(条目数 + max learning_updated_at)的 SHA-256(domain 新增
  `content_fit_fingerprint` 助手)。测试:语速排除句间空隙/零时长单测 2 项;sqlite
  集成 4 项(双维密度与档位、快语速升档且 rhythm 信号在场、指纹稳定性与词汇变更
  失效、语言缺失/无 word token 校验错误)。验证:workspace 418 passed / 0 failed,
  touched crates clippy 无新增告警。

- 2026-07-07 19:40 CST: Phase 3.5 Slice 1 domain 双维难度契约。新增
  `crates/domain/src/content_fit.rs`:`ContentDifficultyProfile` v2(meaning/sound 双
  `DifficultyDimension` + 结构化 `FitSignal`(kind/value/decisive)+
  `assessed_token_ratio` + `evidence_grade` + `algorithm_version`)、banding 纯函数
  (`meaning_fit` 覆盖率分档、`sound_fit` KNR 基档 + 语速/弱读单向升档饱和于 too_hard)、
  全部阈值常量单点定义(heuristic_proxy,注研究锚点);诚实降级判定
  `has_sufficient_vocabulary_profile`(MIN_ASSESSED_TOKEN_RATIO=0.5)。旧单维
  `ContentDifficultyProfile`/`InputFit` 壳从 learning_loop.rs 移除(零外部引用,原地
  重塑无兼容负担);`InputFit` 迁入新模块,glob re-export 路径不变。测试 7 项:阈值
  端点、unassessed 保守折算与 decisive 标记、KNR 基档、升档与饱和、慢速交付信号仅
  informational、缺失可选信号省略、画像充分性阈值。验证:workspace 412 passed / 0
  failed,domain clippy 零告警。ADR 0018 FitSignal 形状同步为 decisive 标记。

- 2026-07-07 19:00 CST: Phase 3.5 Difficulty & Content Triage 立项（Slice 0）。新增
  ADR 0018 双维 fit 定义：meaning/sound 双维 `ContentDifficultyProfile` v2 形状、
  信号集 v1（unknown/unassessed/known_not_recognized 密度、语速、弱读/压缩密度、
  chunk 长度）、研究锚点（听力 95% 词汇覆盖 van Zeeland & Schmitt 2013、阅读 98%
  Hu & Nation 2000、语速 Tauroza & Allison 1990 / Griffiths 1992、弱读瓶颈
  Field 2008）与映射告诫、分档规则（阈值全部 heuristic_proxy，常量单点定义，改常量
  必须升 algorithm_version）、诚实降级（assessed_token_ratio + evidence_grade）、
  三队列为派生视图、listening-projection-v1 随本 phase 落地并移除升级确认投影直写
  （ADR 0017 决策 4 到期义务）。3.5-PLAN.md 重写为 9-slice 版（句级画像裁剪出 v1，
  subject_kind 留 seam）；STATE.md 更新阻塞项与下一步；迁移编号协调：3.4.2 预留
  v24，3.5 名义 v25，后落地方顺延。

- 2026-07-07 17:30 CST: Phase 3.4.4 Learning Evidence Channelization 收口（Slice 4）。
  新增 3.4.4-CLOSEOUT.md（交付清单、outcome 入身份指纹的关键修正记录、Non-Goals 兑现、
  Exit Signals 核验）；PLAN 标 COMPLETED；共享上下文 §14 标记证据层完成；STATE.md 更新
  当前位置与下一步（3.5 可启动，首个证据投影算法随 fit 定义实现）。

- 2026-07-07 17:00 CST: Phase 3.4.4 Slice 3 写入路径接线与便携资产。四条路径全部产出
  通道化 observation：上下文标记（双写，legacy 最新覆盖行为不变但通道化流保留每次判断）、
  练习提交（成功与失败均记录，修复失败偏置；无句子锚点也可记录）、复习提交（按 rating
  映射，source 与 anchors 去重）、升级确认（ADR 0017 决策 4 过渡条款，确认本身入证据流）。
  `VocabularyAssetBundle` 追加 optional `learning_observations`（版本仍 6，旧包缺字段
  兼容），导出全量、导入按 id 幂等追加并跳过本地不存在的 entry。修复身份设计缺陷：
  outcome 纳入 id 指纹（context marking 的 source_ref 按 (entry, sentence) 恒定，同毫秒
  不同判断必须是两行）。测试：练习成功/失败通道化断言、复习失败通道化断言、标记双写
  与资产包 round-trip（3 条 observation 幂等导入）、升级确认入流断言。
  验证：`cargo test --workspace` 405 passed、0 failed；clippy 无新增警告。

- 2026-07-07 16:00 CST: Phase 3.4.4 Slice 2 持久化 schema v23。新增
  `0023_learning_observations.sql`（追加式表，entry 级联删除，
  entry+capability+occurred_at 索引）；迁移回填：未清除的 legacy LexicalObservation
  逐行转为 listening/context_marking observation（origin=legacy_backfill、
  source_ref=旧 id、surface_form=original_form），已清除的标记视为撤回不回填，
  回填幂等（INSERT OR IGNORE）。LearningAssetRepository 新增
  append_learning_observation / list_learning_observations（按通道过滤、时间倒序分页）。
  测试：v23 回填断言（含 cleared 排除与幂等）、追加语义（同 (entry, sentence) 两行共存、
  重复追加幂等）；migration_recovery_test 种子补 lexical_observations 表并断言 v23。
  验证：`cargo test -p persistence-sqlite` 67 tests 全过。

- 2026-07-07 15:35 CST: Phase 3.4.4 Slice 1 domain 契约。新增
  `crates/domain/src/learning_observation.rs`：`LearningObservation`（追加式身份 =
  entry + task + source_ref + occurred_at 指纹）、ObservationTaskType / ObservationOutcome /
  AssistanceLevel / ObservationOrigin 枚举、ADR 0017 任务→通道映射 v1 的单点定义
  （observation_spec_for_marking / _practice / _review，Skipped 不产证据）。
  5 个单元测试（身份不可覆盖、映射表、snake_case 契约与 round-trip）。

- 2026-07-07 15:20 CST: 启动 Phase 3.4.4 Learning Evidence Channelization（Slice 0）。
  新增 ADR 0017：通道化追加式 LearningObservation（capability/task_type/assistance/
  surface_form/origin，禁止 latest-wins 身份）；任务→通道映射 v1 表；投影写入者互斥
  （upgrade 确认声明为过渡直写）；legacy LexicalObservation 以 legacy_backfill 来源回填；
  资产包 additive 携带 observation。新增 3.4.4-PLAN（Slice 0-4，明确 Non-Goals：不做
  投影算法、不迁移 diagnosis、不加 API/UI）。占用 schema v23,3.4.2 迁移号协调至 v24。
  STATE.md 同步。

- 2026-07-07 13:10 CST: `CapabilityProjection` 预留分级能力 seam 字段（精化评审 §4.1）：
  `confidence: Option<f32>`（0.0..=1.0 结论强度）与 `evidence_as_of_ms: Option<u64>`
  （投影所依据证据窗口截止时间），serde default + None 不序列化，旧 JSON/DB 行/资产包
  完全兼容；真证据投影算法上线前保持 None。受 f32 影响，capability 结构链
  （CapabilityProjection/DimensionState/Profile/History、VocabularyAssetBundle、
  LexicalEntryDetails）从 Eq 降为 PartialEq。OpenAPI CapabilityProjection schema 增加
  两个 optional 属性。Flutter 不改：字段为 None 时线上 JSON 形状不变，Dart fromJson
  对未知键安全。新增 serde 兼容性测试。验证：`cargo test --workspace` 全部通过、
  `cargo clippy` 无新增警告；`./scripts/validate-contracts.sh` 的 4 个 CJK 分词失败为
  本机缺 jieba 的既有环境问题，与本变更无关（已在无改动树上复现确认）。

- 2026-07-07 12:40 CST: 修复 capability projection 来源标注失真（精化评审 §5.1）。
  `sync_capability_from_legacy_status` 增加 source 参数：外部词表导入
  （`import_external_vocabulary`）写 `Import`，legacy status 写路径的实时兼容同步写
  `LegacyLearningStatusMigration`（与 v22 一次性回填共享来源语义，以 algorithm_version
  `legacy-status-compat-v1` 区分）；`EvidenceProjection` 保留给真证据路径（升级确认）。
  新增两个来源断言测试。历史已写入的旧标签不回溯迁移。
  验证：`cargo test -p application -p persistence-sqlite` 全部通过。

- 2026-07-07 12:10 CST: Learning Domain Model v2 第二轮精化评审裁决落档。新增
  `.planning/discuss/learning-domain-model-v2-refinement-review.zh.md`（八项优化空间、
  复杂度分层原则、字段裁决标准、砍掉项与排期）；共享上下文新增不变量 16-18（listening
  acquired 条件语义、投影写入者互斥、精细度不泄漏交互层）、§5.3 evidence shape 增补
  `surface_form`、新增 §14 Refinement Addendum；STATE.md 记录决策并更新下一步
  （证据层 slice 为 3.5 前置、sense 身份 spike 为 3.6 前置）。

- 2026-07-07 21:00 CST: 迁移号第二次协调：v24（0024_content_difficulty_profiles）由
  main 上先落地的 Phase 3.5 Slice 3 占用，本阶段 sense_group_analyses 迁移顺延为
  v25/0025；PLAN 与实施指南同步改号（顺延规则不变）。

- 2026-07-07 15:00 CST: 迁移号协调：schema v23（0023_learning_observations）由 main 上的
  Phase 3.4.4 证据层占用，本阶段 Slice 3 的 sense_group_analyses 迁移改用 v24/0024；
  PLAN 与实施指南同步更新，并注明合并时编号再冲突的顺延规则。

- 2026-07-07 14:00 CST: 新增 3.4.2-IMPLEMENTATION-GUIDE.md（Slice 2-6 交接实施指南）。

- 2026-07-07 12:20 CST: ADR 0016 增补决策 9（2026-07-07 修正案）：用户意群修正是独立
  per-sentence overlay 层。

- 2026-07-07 CST: 启动 Phase 3.4.2 Semantic / Prosodic Group Separation（Slice 0-1）。

- 2026-07-06 CST: 完成 Phase 3.4.1 Slice 6 authority switch and closeout。capability profile
  成为唯一权威决策来源：diagnosis-core `classify_entry()` 移除 legacy `LearningStatus` 回退
  分支，只使用 capability profile 进行 meaning/recognition barrier 分类；upgrade suggestion
  `confirm_upgrade_suggestion()` 统一为 capability-first 路径（旧无 `capability` 字段的
  suggestion 默认走 listening projection），移除 legacy status 双写路径；external vocabulary
  import 补齐 capability profile sync（修复导入后 profile 缺失导致诊断降级为 insufficient
  的 bug）。`LearningStatus` enum 和 `LexicalEntry.status` 字段标记 deprecated，保留用于
  schema 兼容和 legacy API 消费者。Phase 3.4.1 全部 6 个 slice 完成，PLAN 标记 COMPLETED。
  验证：`cargo test --workspace` 395 passed、`flutter test` 204 passed。

- 2026-07-06 CST: 修复 persistence-sqlite 关键死锁：`lexical_details()` 持有
  `self.connection.lock()` 后调用 `self.lexical_capability_profile()` 导致 Mutex 不可重入死锁，
  改为直接调用 `read_capability_profile(&conn, ...)` 复用已持有的连接。全量 Rust 测试通过
  （395 tests，含 persistence-sqlite 64 + api-http 43）。

- 2026-07-06 CST: 完成 Phase 3.4.1 Slice 5 API, events and Flutter。OpenAPI additive capability
  profile GET/PUT contract（`/v1/lexical-entries/{id}/capability-profile` 和
  `/v1/lexical-entries/{id}/capability/{capability}`）。SSE 新增 `lexical-capability-changed` event，
  `LexicalCapabilityChangedPayload` 含 entry ID、capability 和 effective assessment。Dart 手写
  DTO：`CapabilityProjection`、`CapabilityOverride`、`CapabilityDimensionState`（effectiveAssessment
  getter：override > projection > unassessed）、`LexicalCapabilityProfile`；`LexicalEntryDetails`
  新增可选 `capabilityProfile` 字段。`LearningState` 新增 `capabilityProfiles` map，
  `LearningController.updateCapabilityProfile` 维护；`BackendEventCoordinator` 处理
  `LexicalEntryChangedEvent` 时提取 profile，`LearningWorkflowController.openWord` 加载时存储；
  新增 `setCapabilityOverride` 方法通过 API 设置/清除单通道 override。词汇面板四通道显示
  （reading/listening/speaking/writing），每通道 acquired/not_acquired ChoiceChip + unassessed 独立
  italic 表达 + override 标识；字幕 `TokenLine` 从 `capabilityProfiles` 派生 display status
  （reading not_acquired → unknown_meaning、reading acquired + listening not_acquired →
  known_not_recognized、both acquired → known_recognized）。复习结束页/词汇详情 suggestion
  按钮改用 localization keys（`confirmListeningAcquired`/`deferUpgrade`/`listeningUpgradeSuggestion`）。
  新增 `capability_profile_contract_test.dart`（6 tests）和 `backend_event_contract_test.dart` 扩展
  （2 tests）。验证：`flutter analyze` 0 issues、`flutter test` 204 passed、`cargo check --workspace`
  clean、api-events schema parity 3 passed、event contract examples regenerated。

- 2026-07-06 13:30 CST: 完成 Phase 3.4.1 Slice 4 diagnosis and review suggestion migration。
  diagnosis-core 新增 `diagnose_with_profiles()`，meaning barrier 改用 reading effective
  assessment、recognition barrier 改用 listening effective assessment + sentence observation，
  unassessed 维度严格不触发 barrier 只产生 InsufficientInformation（含 entry IDs）。旧
  `diagnose_with_phrases()` 退化为从 legacy status 创建 profiles 后委托新实现。Application
  层 `diagnose_sentence()` 批量读取 capability profiles 传给 diagnosis-core。UpgradeSuggestion
  新增可选字段 capability/previous_assessment/suggested_assessment（serde(default) additive），
  `evaluate_upgrade_suggestion()` 改为检查 listening.effective_assessment == NotAcquired，
  生成的 suggestion 标记 capability=Listening。`confirm_upgrade_suggestion()` 对 capability-aware
  suggestion 直接更新 listening projection + sync legacy，旧 suggestion 走 legacy 路径。
  新增 6 个 diagnosis-core 测试（profile 驱动 meaning/recognition barrier、unassessed
  insufficient、context observation override、both acquired → other factors）和 4 个集成测试
  （capability override 影响诊断、unassessed insufficient、capability-aware 确认更新 listening
  projection、legacy suggestion 旧路径确认）。验证：cargo test --workspace（395+ passed）、
  clippy 无新增警告。

- 2026-07-06 12:15 CST: 完成 Phase 3.4.1 Slice 3 application and portable assets。新增 application
  层 capability profile 读取、用户 per-channel override 设置/清除及双向 compatibility adapter：
  legacy status 变更同步到 capability projection（不覆盖已有 user override），capability override
  变更同步回 legacy status view。VocabularyAssetBundle 升级到 v6，携带完整 capability_profiles；
  v5 旧 bundle 导入时通过 legacy mapping 自动生成 migration projection；v6 导入按 per-dimension
  时间戳合并，imported projection 不能覆盖本地较新 user override。新增
  `LearningChangeSource::CapabilityOverrideSync`。新增 5 个测试：创建词条时 capability 同步、
  override 设置/清除影响 legacy status、v6 export/import round-trip、v5 bundle legacy mapping 导入、
  imported projection 不覆盖 local override。验证：`cargo test --workspace`（386 passed）、
  `cargo clippy --workspace --all-targets` 无新增警告、contract validation 无新增失败。

- 2026-07-06 11:14 CST: 完成 Phase 3.4.1 Slice 2 persistence foundation。SQLite schema
  v22 新增 `lexical_capability_states` 与 `lexical_capability_history`，按 entry + optional sense +
  capability 保存 system projection 和 user override；v21 legacy status 在同一迁移事务中按
  ADR 0015 回填为带 `legacy_learning_status_migration` provenance 的 projection，原
  `lexical_entries.status` 保留不删。扩展 LearningAssetRepository，支持 profile 读取、projection
  更新、override 设置/清除和 before/after history；effective 读取保持 override 优先，清除后恢复
  projection。新增 v21 精确回填、旧列保留、迁移前文件备份、重复打开、失败恢复和 repository
  round-trip 回归。验证：`cargo test -p persistence-sqlite`（44 unit + 5 migration recovery +
  6 integration passed）、`cargo clippy -p persistence-sqlite --all-targets --no-deps -- -D warnings`、
  `cargo test -p application`（48 passed）、`cargo fmt --all`、`git diff --check` 通过；跨依赖
  strict clippy 仍被既有 speech-analysis lint 阻断。

- 2026-07-06 11:07 CST: 完成 Phase 3.4.1 Slice 1 domain contract。新增 reading/listening/
  speaking/writing `LexicalCapability`、三值 `CapabilityAssessment`、不可持久化 unassessed 的
  concrete conclusion、带 provenance 的 system projection、user override 与 effective profile
  优先级；新增可选 `LexicalSenseId` seam。实现 ADR 0015 固定的 legacy status 回填和保守反向
  view，覆盖四种旧状态、productive channel 保持 unassessed、override 不删除 projection、
  无法表达组合不强制降级及 snake_case 序列化。当前切片不修改 SQLite/API/运行行为。验证：
  `cargo test -p domain`（25 passed）、`cargo clippy -p domain --all-targets -- -D warnings`、
  `cargo fmt --all`、`git diff --check` 通过。

- 2026-07-06 11:00 CST: 启动 Phase 3.4.x Learning Domain Model v2。Phase 3.4 与
  3.35 暂停最终真实媒体/owner QA，保留已完成代码与自动化结果；建立
  `baseline/learning-model-v1` 迁移基线。新增 3.4.1~3.4.3 共享上下文和分阶段 PLAN，
  锁定四通道词汇能力画像、`unassessed / not_acquired / acquired`、evidence/system
  projection/user override 分层、SenseGroup 与声音/韵律组双层模型及 Construction identity
  spike。ADR 0015 取代 ADR 0012 的单值 `LearningStatus` 长期权威决定，并固定 schema v21
  legacy 映射、v22 additive migration 与 conservative legacy view；同步更新 ROADMAP、
  REQUIREMENTS、STATE、phase breakdown、AGENT 和 codebase 架构/数据模型事实源。

- 2026-07-06 10:17 CST: Phase 3.4 升级建议引擎 v1 落地。SQLite schema v21 新增
  `recognition_evidence` 与 `upgrade_suggestions`；practice 正确、review `good/easy` 和逐例
  `RecognizedInContext` 证据按 lexical entry + sentence（无 sentence 时按 media）去重，累计
  5 个不同语境后生成 `heuristic_proxy` 建议。建议只在用户确认后执行
  `known_not_recognized -> known_recognized`，并写入 `lexical_status_history` 与
  `StatusChanged` event；拒绝保持原状态并冷却 30 天。新增 pending/history/confirm/reject API、
  OpenAPI/TypeScript/Dart 契约，复习结束页与词汇详情提供非打断式确认/拒绝入口；补齐阈值、
  状态护栏、冷却、持久化、HTTP 和 Flutter 回归测试。验证：`cargo test -p application -p
  persistence-sqlite -p api-http`、`flutter analyze`、`flutter test`（194 passed）、
  `validate-contracts`、目标文件格式检查与 `git diff --check` 通过；clippy 仅报告既有跨 crate
  warnings。

- 2026-07-05 21:59 CST: Phase 3.4 复习失败证据与猎词候选池落地。SQLite schema v20 新增
  `hunting_candidates`，按 lexical entry + review item 聚合失败次数并保留媒体、字幕轨、
  句子、目标词和 prompt snapshot；`again` 评分在词条与句子仍有效时追加
  `NotRecognizedInContext` `LexicalObservation`，来源丢失时只保留 snapshot 候选，不伪造
  observation，也不修改 `LearningStatus`。`ReviewSubmission` 返回生成的 observation/candidate
  IDs，`ReviewCompleted` 事件同步记录证据引用。为遵守单文件 1500 行护栏，将复习调度与卡型
  派生机械拆到 `practice/review.rs`。验证：`cargo test -p application -p
  persistence-sqlite -p api-http`、`flutter analyze`、`flutter test`（193 passed）、
  `validate-contracts`、`cargo clippy -p application -p persistence-sqlite -p api-http
  --all-targets`、`git diff --check` 通过；clippy 仅报告既有跨 crate warnings。

- 2026-07-05 21:51 CST: Phase 3.4 四类 audio-first 卡型差异化落地。到期队列新增
  application-owned `ReviewCard` 读模型，基于 `ReviewItem` 来源和锚点稳定派生听音识词、
  chunk cloze、phrase 出现判断、原句回听四类卡；卡型不写入 SQLite，历史复习项无需迁移。
  Flutter 队列分别提供翻词、文本填空、二选一判断和原句对照交互，完成后继续复用三档自评
  与既有调度器。同步 OpenAPI、TypeScript/Dart DTO、契约校验与架构/数据模型文档，并新增
  Rust 派生规则测试、API 断言和四类 Flutter widget 回归测试。验证：`cargo test -p
  application -p api-http`、`flutter analyze`、`flutter test`（193 passed）、
  `validate-contracts`、`git diff --check` 全部通过。

- 2026-07-05 21:33 CST: 启动 Phase 3.4 Audio-first Review Queue。新增 SQLite schema v19
  `review_schedules` 并为历史复习项回填立即到期计划；补齐到期队列与三档评分 API，评分写入
  `ReviewAttempt`、推进 heuristic_proxy 调度并追加 `ReviewCompleted` 事件。Flutter 新增
  ReviewController/Store、首页及学习工具入口、声音优先翻面卡和 snapshot 降级；复习音频仅在
  来源 media 与当前 media 匹配时播放，避免错播。词汇本详情新增手动加入复习，使队列无需
  精听/泛听前置也可独立使用。同步 OpenAPI、TypeScript/Dart DTO、架构与数据模型文档及
  Rust/Flutter 回归测试。验证：相关 Rust tests 全通过，`flutter analyze` 与 `flutter test`
  （189 passed）、`validate-contracts`、`git diff --check` 通过；strict clippy 被当前工具链新报的
  存量 `speech-analysis` / `application` lint 阻断，本阶段改动未引入对应告警。

- 2026-07-05 21:11 CST: Phase 3.35 收尾复审修复与 UX 优化。修复三处走查遗留实质问题：
  (1) 首页“继续学习”原本是死代码（媒体信息与 mediaPath 同生同灭），改为持久化最近媒体
  路径/标题/进度/字幕数到 settings，“继续播放”真正重开并按后端进度恢复位置；(2) 首页
  readiness 冷启动全为 0，改为连接后预取全局听力收件箱与词汇量（客户端聚合，capped 显示
  “N+”），字幕就绪改用最近媒体的字幕数并在无最近媒体时显示占位；(3) 播放设置弹窗倍速
  下拉改用本地状态，选后即时刷新。附带修复分栏拖动逐帧写盘（新增 `saveSoon` 防抖）与
  首页 Inbox 标签硬编码英文。UX 优化：文稿自动跟随在用户拖动/滚轮时暂停并显示“回到当前句”
  悬浮按钮（程序化滚动不触发）；窄窗口上下布局的媒体区改为可纵向拖动并支持压缩/复位；
  姿态动作栏仅在文稿/词汇/诊断/练习 tab 上下文显示，资源与收件箱 tab 隐藏；Test 姿态由
  文字胶囊改为与相邻 OutlinedButton 一致的描边下拉触发器；文稿空态补齐标题+原因+导入动作；
  无媒体播放条移除四个无意义禁用图标。新增文稿跟随暂停/恢复与首页继续播放回归测试。
  验证：`flutter analyze` 通过、`flutter test` 188 passed、`git diff --check` 通过。

- 2026-07-05 20:17 CST: 补齐 Phase 3.35 收尾材料：新增每日英语听力参考取舍矩阵、
  三种目标窗口尺寸与真实媒体手工 QA 清单，以及 `AWAITING_OWNER_QA` closeout 草稿；
  同步 PLAN 和 STATE，将当前阶段准确记录为“代码与自动化完成，等待 owner 截图/手工验收”，
  未提前标记 COMPLETED。

- 2026-07-05 20:13 CST: Phase 3.35 UX 走查 P2 收口。在线 URL 入口改为“添加来源”
  流程，输入时校验地址并识别 YouTube/普通网页，使用分段控件明确选择在线播放或下载到
  本机，同时展示访问授权提示；沿用现有 yt-dlp 解析、后台下载和下载状态条，不新增虚假的
  在线资源库或 provider。新增媒体 overlay、听觉参考、音素类别和学习状态语义色 token，
  字幕、音素与节奏组件不再直接持有产品色值。新增 URL 来源 widget 回归测试。

- 2026-07-05 20:07 CST: Phase 3.35 UX 走查 P1 收口。字幕与时间轴资源页首层改为
  学习能力和可用状态，provider、generator、precision、候选时间线及 artifact 收入技术详情；
  句子诊断移除 190px 高度限制，拆为常显摘要和可展开证据分析；词汇详情按学习状态、
  释义与发音、来源原句、折叠历史重排，并以媒体位置和本地日期替代原始毫秒值；设置页新增
  通用、字幕、学习、资源、外部工具、实验功能六类侧边导航。同步更新 P1 widget 回归测试。

- 2026-07-05 12:05 CST: Phase 3.35 UX 走查 P0 收口。新增
  `3.35-UX-REVIEW-CHECKLIST.md`，记录首页状态、顶部工具栏、播放工作台、播放条、
  右侧面板、资源/诊断/词汇/设置、在线来源和颜色 token 的 P0/P1/P2 问题清单。
  首页新增“继续学习”和资源状态摘要；顶部工具栏按内容、字幕、学习、更多分组；媒体/文稿
  分栏比例写入设置并新增压缩/复位控制；播放条把泛听、Inbox、语块和字幕样式收进模式菜单；
  右侧面板 tab 在宽度允许时显示文字，并补足词汇/诊断空态说明。验证：
  `flutter analyze`、`flutter test`（185 passed）通过。

- 2026-07-05 08:55 CST: 修复播放界面右侧文稿未稳定跟随当前句的问题。
  `TranscriptPanel` 改为按当前 cue 对应的真实列表行执行 `Scrollable.ensureVisible`，
  不再依赖旧的固定 `cue.index * 76` 行高估算；目标行尚未构建时先按列表比例预定位，
  下一帧再用真实行位置校准，适配长字幕可变行高。新增 widget 回归测试覆盖可变高度文稿
  从后段 cue 切换到前段 cue 时仍能把当前句滚入视口。验证：`flutter analyze`、
  `flutter test`（184 passed）通过。

- 2026-07-05 08:47 CST: 修复 Phase 3.35 字幕资源页与右侧资源 tab 的布局挤压。
  字幕资源列表和时间轴资源详情改为同一高度池内的可拖动上下分栏，时间轴详情移除固定
  `maxHeight: 430`，改为在分配到的区域内独立滚动；独立“字幕资源”页面和媒体工作台右侧
  tab 共享该行为，避免矮窗口下资源详情顶穿底部播放区。新增 widget 回归测试覆盖分隔线
  拖动和紧凑高度无 overflow。验证：`flutter analyze`、`flutter test`（183 passed）通过。

- 2026-07-04 23:25 CST: Phase 3.35 首轮 UI 与产品配色落地。新增来源中立首页、浅色工具栏、
  独立播放条和可拖动媒体/字幕分栏工作台；窄窗口自动上下布局，右侧导航改为等宽图标 tab，
  文稿支持可变行高，播放控制不再依赖横向拖动。新增集中式 `ListenTheme`，采用冷杉绿、
  雾灰、暖金与近黑媒体画布，并统一按钮、输入、弹窗、菜单、滑杆、选中/禁用状态；字幕
  资源、timeline、练习、诊断、人工校对、任务和下载状态已从旧深色硬编码迁移。新增主题、
  首页与工作台 widget 测试。验证：`flutter analyze`、`flutter test`（182 passed）、
  `git diff --check` 通过；等待 owner 截图反馈与真实媒体手工 QA 后继续 Phase 3.35 收口。

- 2026-07-04 22:34 CST: 新增 Phase 3.35 Listening Workbench UI Redesign 规划。
  在 Phase 3.3 与 3.4 之间插入独立 UI 重构阶段，参考每日英语听力的内容层级、同步字幕与
  播放学习一体化组织，计划统一 app shell、来源中立内容入口、播放器工作台、字幕、学习
  上下文面板、design tokens 与响应式状态；明确不做像素复刻、不复制品牌，也不在本 phase
  实现 YouTube provider。同步修正产品定位：local-first 不等于 local-only，未来 YouTube 等
  在线来源将与本地内容进入统一学习工作台，学习资产和高频路径仍默认本地。更新 PROJECT、
  REQUIREMENTS（UI-016/UI-017）、ROADMAP、STATE 与 Phase 3.0 breakdown。documentation-only。

- 2026-07-04 21:53 CST: Phase 3.3 泛听 Listening Inbox MVP 落地。
  后端新增 `ListeningInboxItem` domain model、`ListeningInboxRepository`、SQLite schema v18
  `listening_inbox_items` 表、Inbox capture/list/process API，以及
  `listening_inbox_captured` / `listening_inbox_processed` 事件；`completePracticeSession`
  支持可选理解度自报，session 创建写入 `listening_started`。桌面端新增
  `ExtensiveListeningController`、Listening Inbox typed DTO/API、右侧 Inbox 整理面板、
  播放条泛听 toggle/软打断/硬打断按钮和应用内快捷键（`I`、`Shift+I`、`Shift+P`）。
  Inbox 项可回听、存入 `ReviewItem`、升格微精听练习项、收藏片段或归档；未处理项按
  默认 7 天过期降级归档。OpenAPI 与 handwritten TypeScript contract 已同步。
  新增 `3.3-MANUAL-QA.md`，将真实 30 分钟泛听、软/硬打断、Inbox 整理、重启持久化、
  过期归档和零打扰检查拆成可执行手工 QA 清单。
  验证：`cargo test -p application -p persistence-sqlite -p api-http -- --nocapture`、
  `cargo clippy -p application -p persistence-sqlite -p api-http --all-targets`（保留既有
  clippy warnings）、`flutter analyze`、`flutter test`、`./scripts/validate-contracts.sh`、
  `git diff --check` 通过。系统级全局热键、独立收藏浏览容器与 30 分钟真实媒体手工 QA
  仍留作 3.3 closeout 前事项。

- 2026-07-04 21:15 CST: 修复精听听写输入与播放器字幕快捷键冲突。
  新增 `PlayerGlobalShortcuts`，当焦点位于 `EditableText` 文本输入控件时临时让播放器级快捷键让路，
  避免真实听写中输入 `h` 被全局 `H` 隐藏字幕快捷键截获；无文本输入焦点时原播放器快捷键行为保持不变。
  新增 widget 回归测试覆盖 `H` 在输入态与非输入态的分发差异。

- 2026-07-04 16:38 CST: Phase 3.2 卡点与 session summary 切片落地。
  后端新增卡点/诊断查看/完成 session 事件流与 session summary API，卡点状态由
  `learning_events`、practice attempts、review items 派生，不引入新的持久化状态表；
  OpenAPI 与 TypeScript contract 同步更新。桌面端新增精听卡点标记/跳过、悬案区 v0、
  复习归因、诊断查看记录、完成精听 session 与熟料标记入口。新增 Rust persistence/API
  集成测试、Flutter controller/contract 测试，并更新 planning closeout、架构、数据模型与
  测试索引。验证：`cargo test -p application -p persistence-sqlite -p api-http`、
  `cargo clippy -p application -p persistence-sqlite -p api-http --all-targets`、
  `flutter analyze`、`flutter test`（170 passed）、`./scripts/validate-contracts.sh`、
  `git diff --check` 全部通过；真实媒体 GUI 手工 QA 尚待 owner 最终确认。

- 2026-07-04 16:06 CST: 桌面 app 品牌名与图标切换到 `listen`。
  根据 `docs/brand/listen/` 品牌材料，将 macOS app 产品名、Bundle ID、窗口标题、
  打包脚本产物名和用户可见导出文件名从 LLPlayerNext 切到 `listen`；使用推荐的
  `listen-icon-concept-b-1024.png` 重新生成 AppIcon iconset。用户数据路径采用兼容策略：
  新安装写入 `~/Library/Application Support/listen`，若旧 `LLPlayerNext` 数据库存在则继续读取旧库；
  设置文件读取新路径并回退旧路径，保存时写入新路径。

- 2026-07-04 15:50 CST: Phase 3.1 精听练习切片落地。
  桌面端新增 Test posture 的首个竖切片：三姿态入口、cloze / chunk dictation /
  sentence dictation 练习面板、练习 session/item/attempt/review 的 typed Dart DTO 与
  LocalApi 客户端封装、失败项一键进入 review；练习面板支持听后作答、结果 diff、重试、
  重放当前证据窗口和打开诊断。诊断侧完成 C-1 phrase-aware diagnosis：当前句命中的
  Phrase lexical entries 会参与 meaning / recognition barrier 判断；C-2 rhythm hotspots
  可从诊断卡直接 loop 对应 evidence range。新增 Flutter controller/contract/widget 测试与
  diagnosis-core phrase 回归测试。验证：`flutter analyze`、`flutter test`（168 passed）、
  `cargo test -p diagnosis-core`、`cargo test -p application`、`cargo test -p api-http`、
  `./scripts/validate-contracts.sh`、`git diff --check` 全部通过。

- 2026-07-04 12:46 CST: Phase 3.x 产品形态与执行序列全部落地（documentation-only）。
  新增 `.planning/discuss/listen-learning-activity-path.zh.md`：完整用户学习活动路径
  （冷启动 -> 材料供给 -> 泛听 -> 精听 -> 整理 -> 回访 -> 教练）与一级产品原则 P1-P6
  （精听/泛听一级心智、功能按场景分不按设备分且生产端唯一 PC-only、可组合不强制流程、
  泛听默认零打扰、不课程化不游戏化、硬件北极星约束），并定义核心概念（三姿态、双维
  难度、卡点、悬案区、Listening Inbox、微精听、片段收藏、熟料回听、猎词单、理解度
  自报、升级建议等）。新增 `3.0-PHASE-BREAKDOWN.md` 确立 Phase 3.1 ~ 3.10 执行序列、
  全局设计规则（可组合性、capability gating、guardrails 继承、evidence class、先派生
  后建模）与依赖图；新增十个 phase 目录及 PLAN：3.1 练习切片（含 C-1/C-2 进诊断）、
  3.2 卡点与 session summary、3.3 泛听 Inbox、3.4 audio-first 复习与升级建议、
  3.5 双维难度分拣、3.6 听力词典 MVP、3.7 猎词单、3.8 shadowing、3.9 L1-aware 诊断、
  3.10 教练 dashboard。同步更新 PROJECT.md（2026-07-04 产品定义更新 + §15.6 原则）、
  ROADMAP.md（头部路线注记 + §14.12 执行序列）、STATE.md（Phase 3.0 执行序列、
  最近决策、下一步改为 Phase 3.1 开工）、3.0-PLAN.md（breakdown 指针）。
  无产品代码变更。

- 2026-07-03 21:20 CST: 恢复误删的 listen brand 与用户旅程资源。
  最新一次 cleanup 提交误删了 `docs/brand/listen/` 品牌说明和 6 张视觉概念资产，
  以及 `.planning/discuss/listen-user-journeys-current-and-planned.md` / `.zh.md` 两份用户旅程文档；
  本提交在最新 main 顶部以 revert-style 恢复这些文档和资产。documentation-only，无产品代码变更。

- 2026-07-03 21:15 CST: 合入 listen brand 视觉概念与用户旅程文档。
  恢复并保留 `docs/brand/listen/` 品牌说明和 6 张视觉概念资产，同时将
  `.planning/discuss/listen-user-journeys-current-and-planned.md` 与中文版本
  `.planning/discuss/listen-user-journeys-current-and-planned.zh.md` 纳入 main；两份旅程文档覆盖
  当前已可达功能和 Phase 3.x 规划功能的用户路径。documentation-only，无产品代码变更。

- 2026-07-03 21:08 CST: Phase 2.23 正式收口 + ADR 0014。
  真实媒体手工 smoke 通过（owner 确认）后新增 `2.23-CLOSEOUT.md`：全部硬指标达成
  （main.dart 1457 行 / setState 10、sound_analysis 14 模块、schema v17、STATE 瘦身、
  cargo 358 / flutter 164 passed），A-1..A-7 + Step 3 + T1-T9 全部完成，C 类归 3.x、
  D 类明确 defer，phase 文件夹冻结。T7 决策落定为 **ADR 0014**：Dart 模型解析保持手写，
  fixture 契约测试为防漂移标准机制；存量 `timeline.dart` 不做 codegen 迁移，3.x 新 DTO
  默认手写 + 契约测试，新模型家族体量显著增长时再做仅新代码试点（新 ADR）。
  STATE.md 按维护规则把 2.23 压缩为已完成索引行（152 行），主线全面转入 Phase 3.x。
  仅规划/决策文档，无代码变更。

- 2026-07-03 16:07 CST: Phase 2.23 Step 3 完成 — main.dart 收缩为 composition root + UI 状态单轨化。
  硬指标达成：main.dart 3601 → **1457 行**（gate ≤1500）、setState 107 → **10**（gate ≤30，
  剩余均为局部 UI 状态）。六刀切法：(1) status 单源化——删除与 `PlayerController.status`
  重复的宿主字段（含一处双写），~95 处 setState 迁到 controller；(2) 新增
  `ResourceActionsCoordinator`（资源动作，8 个重复 timeline 方法收敛为共享骨架）；
  (3) 新增 `MediaSessionCoordinator`（媒体/字幕/LLTimeline 导入、生成轨、speech enhancements）；
  (4) 新增 `PlaybackActionsCoordinator`（chunk 导航/循环/occurrence 回放，顺带去除
  `_openVocabulary`/`_playOccurrence` 重复源解析块）；(5) Widget 提取 `PlayerStage`（491 行
  stage+overlay，phone-evidence 展开态内化）、`SidePanel`、`PlaybackBar`；(6) Flow 函数提取
  settings/online/embedded/OpenSubtitles/manual review（pristine 标志降级为流内局部变量）。
  coordinator 均 context-free，宿主经 `bind()` 注入运行时钩子；对话框留在宿主薄包装。
  controller + Store 定调为唯一 UI 状态模式并写入 `ARCHITECTURE.md` Flutter 节；
  `SubtitleController` 新增 `activeWordTimingCount` 派生 getter。新增
  `test/coordinators_test.dart`（6 测试）。验证：`flutter analyze` 无问题、`flutter test`
  **162 passed**（基线 156）、每刀独立全绿。待办（归用户）：按 `2.22-FRONTEND-E2E-QA.md`
  P0 路径跑真实媒体手工 smoke。
- 2026-07-02 23:52 CST: Phase 2.23 handoff T5 — 机械拆分巨型 Rust
  测试文件。`crates/persistence-sqlite/src/tests.rs` 拆为 `tests/`
  模块目录（migrations/timelines/lexical/subtitles_dictionary/vocabulary/
  phonetic_analysis/learning_loop + shared `mod.rs`），最大文件 507 行；
  `crates/api-http/src/tests.rs` 拆为 route-group 模块目录
  （general/media_subtitles/timelines/phonetic_analysis/speech_language/practice/
  openapi + shared `mod.rs`），OpenAPI parity 单独成文件，最大文件 902 行。
  仅调整测试模块相对 `include_*` 路径与模块开头 test attribute 边界，断言不改。
  验证：`cargo test -p persistence-sqlite --quiet` 46 passed、
  `cargo test -p api-http --quiet` 40 passed、`cargo test --workspace --quiet`
  358 passed、`./scripts/validate-contracts.sh` 通过。

- 2026-07-02 23:46 CST: Phase 2.23 handoff T4 — `sound_analysis.rs`
  机械拆分为 `crates/speech-analysis/src/sound_analysis/` 模块目录。
  `mod.rs` 仅保留 module declarations 与 public re-export，对外
  `speech_analysis::sound_analysis::*` 路径不变；实现切为 build/config/phones/
  connected/tokens/anchors/nuclei/grouping/boundaries/references/hotspots/quality/
  helpers/constants/tests，最大文件为 `tests.rs` 901 行，所有实现文件低于
  1500 行。字符串字面量 multiset 对比旧单文件保持 534/534 完全一致，
  provenance / signal-source / evidence 文案未改值；`AGENT.md` 新增
  >1500 行或多子域文件先拆模块的触发规则。验证：`cargo test -p speech-analysis
  --quiet` 152 passed、`cargo test --workspace --quiet` 358 passed、
  `./scripts/validate-contracts.sh` 通过。

- 2026-07-02 23:38 CST: Phase 2.23 handoff T3 — 建立基线快照
  `.planning/phases/2.23-architecture-debt-paydown/2.23-BASELINE.md`。
  记录 main.dart 3601 行 / 107 个 `setState`、`sound_analysis.rs` 3383 行、
  `timeline.dart` 2596 行、persistence/api-http 巨型测试文件 2603/2024 行、
  各 Rust crate 测试计数合计 358、Flutter 测试 158 passed。T3 预检先发现
  既有 `cargo fmt` drift，本批先用 workspace `cargo fmt` 修复 4 个 Rust 文件的
  formatter-only 差异，再完成基线记录。验证：
  `./scripts/test.sh --quick --low-memory` 4/7 passed（3 skipped，lib tests
  325 passed）、`cargo test --workspace --quiet` 358 passed、
  `./scripts/validate-contracts.sh` 通过、`flutter analyze` 无问题、
  `flutter test` 158 passed。

- 2026-07-02 23:14 CST: Phase 2.23 handoff T7 — 新增 Dart LLTimeline contract
  解析安全网与 codegen 调研。`apps/desktop/test/contract/lltimeline_parse_test.dart`
  直接读取 2 个 committed rhythm LLTimeline fixtures，覆盖 segments、WordTimeline、
  document-level `rhythm_frames`、`PhoneTimeline.sound_analysis.rhythm_frame` fallback
  与 audible-structure references/provenance/quality 关键字段。负向实验确认改坏
  `rhythm_frames` 字段会让测试变红。新增
  `design-notes/timeline-dart-codegen-research.md`，评估 json_serializable/freezed
  收益、成本和对现有手写容错语义的影响；本批不做迁移、不写 ADR。
  验证：`flutter analyze` 无问题、`flutter test` 158 passed。

- 2026-07-02 23:06 CST: Phase 2.23 handoff T6 — 完成剩余 SSE event payload
  typed 化。新增/扩展 `event_payloads.rs` 中 lexical-observation-cleared、
  vocabulary-assets-imported、pronunciation provider diagnostic、
  pronunciation-analysis-completed 与 route/job 共用 progress/completed payload；
  迁移 m18、pronunciation、timeline word-timing route、vocabulary import 和
  speech batch emit sites，生产发射点不再用 ad-hoc `json!` map 构造 event payload。
  验证：`cargo test -p api-http --quiet` 通过；专门 grep 仅剩 contract test 的
  `service-started` 示例。

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
