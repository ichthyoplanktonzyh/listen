# PLAN — main.dart Coordinator Extraction (治理 mini-phase)

> 类型：架构债治理（同 Phase 2.23 / 2.3.5 性质），非产品行为变更。
> 起因：`apps/desktop/lib/main.dart` 的 `_PlayerScreenState` 从 2.23 收缩的 1457 行
> 回涨到 **2578 行**，违反 AGENT.md「单文件 > ~1500 行或多子领域应拆分」。3.x 的
> practice / hunting / listening-inbox / vocabulary 方法被直接堆进 State，而非按
> 代码库既定模式抽 Coordinator。
> 前置事实（已核实）：**无任何测试 mount `PlayerScreen` / import `main.dart`**；
> `_PlayerScreenState` 在字段初始化器里直接 `new` 出所有 controller/adapter/api，无 DI，
> 整屏 widget 测试不可行。因此测试网建在 **Coordinator 隔离单测**层（代码库既有 14 个
> `*_controller_test.dart` / `coordinators_test.dart` 已是此模式），test-first / test-alongside。

## 目标与非目标

- 目标：把 `_PlayerScreenState` 的 ~80 个动作方法按子领域抽到 `lib/controllers/` 下的新
  Coordinator，`_PlayerScreenState` 退回薄 composition root（字段 + `initState` /
  `dispose` / `build` + build 辅助 widget 方法）。目标行数 ≤ ~1500，理想 ≤ 1200。
- 目标：每个新 Coordinator 有隔离单测，逐字搬移不改产品行为。
- 非目标：不改任何 UI/学习语义、不改 API 契约、不改 schema、不动 build 的视图组合逻辑、
  不引入 mixin/extension-on-State 这种代码库此前刻意未用的新约定。

## 既定模式（照抄，勿发明）

参考 `lib/controllers/media_session_coordinator.dart`：
- 构造函数 `required this.<controller>` 注入 controller/adapter 依赖（长期持有）。
- `late <Fn> Function() <name>;` 字段 + `bind({ required ... })` 注入 UI 耦合操作：
  `getApi`、`isMounted`、`text`（本地化）、对话框/确认回调、`setState`-触发型回调
  （如 `onMediaSwitched`）、`reloadLearningEntries` 等。
- 方法体内用 `player.xxx` / `getApi()` / `onXxx()`，不直接触 `State`。
- `_PlayerScreenState.initState` 里 `xxxCoordinator.bind(getApi: () => api, isMounted:
  () => mounted, ...)`，与现有三个 coordinator 的 bind 调用并列。
- setState 交互：方法内需要重建时，通过注入的回调（如 `requestRebuild: () =>
  setState((){})` 或复用 controller 的 `ChangeNotifier`）触发，Coordinator 不持有 State。

测试模式参考 `test/practice_controller_test.dart` / `test/slice_player_controller_test.dart`
（已有 fake `LocalApi` / adapter）与 `test/coordinators_test.dart`。

## Slice 0 —— 测试安全网前置（必须先做）

在抽任何方法前，为「即将被搬走的行为」建最小回归网，避免无网重构：
1. 抽出可复用的测试替身：把 `practice_controller_test` / `slice_player_controller_test`
   里内联的 fake `LocalApi` / fake adapter 提升为 `test/support/fakes.dart`（若已足够则
   直接复用，勿过度设计）。
2. 为「纯逻辑、无 UI」的候选方法先写 characterization test（当前行为快照），特别是:
   `_currentPracticeChunks`、`_mediaTimeMs`、`_timingQuality`、`_taskStatusText`、
   `_capabilityStatusSegment`、`_generatedPrimarySubtitleStatus`、`_isMediaPath`、
   `_isSubtitlePath`。这些搬走后必须行为不变。
3. 验证：`flutter test`（当前 293 全绿基线）+ 新增用例全绿。
- 交付即基线：此后每个 Slice 结束都跑全量 `flutter test` + `flutter analyze`。

## 抽取分组（每组 = 一个 Slice，按依赖从叶到根排序）

排序原则：先抽跨方法引用最少、依赖最独立的子领域，逐步收敛。每刀独立提交 + 更新
CHANGELOG + `flutter analyze` + `flutter test` 全绿 + 逐字 body 对拍（见「验证」）。

- **S1 HuntingActionsCoordinator**（最独立，3 方法）：`_toggleHuntingMode`、
  `_reindexHuntingCorpus`、`_answerHuntingCheck`。依赖 `huntingController`、
  `huntingSessionController`、`getApi`、`isMounted`、`requestRebuild`、`text`。
- **S2 ListeningInboxCoordinator**：`_toggleExtensiveListening`、`_captureListeningInbox`、
  `_hardInterruptListening`、`_refreshListeningInbox`、`_replayListeningInboxItem`、
  `_processListeningInboxItem`、`_loopSoundRibbonFinding`、`_loopRhythmCue`。依赖
  `extensiveListeningController`、`playerController`、`slicePlayerController`、`getApi`…
- **S3 ShadowingActionsCoordinator**：`_startShadowingPractice`、`_beginShadowingRecording`、
  `_stopShadowingRecording`、`_playShadowingReferenceOnce`、`_playShadowingRecording`、
  `_playShadowingAba`、`_setShadowingRate`、`_setShadowingStep`、`_startExternalShadowing`、
  `_startSliceWindowShadowing`、`_startReviewShadowing`。依赖 `recordingAdapter`、
  `practiceController`、`slicePlayerController`…
- **S4 PracticeActionsCoordinator**：`_startClozePractice`、`_startChunkDictationPractice`、
  `_startSentenceDictationPractice`、`_replayPracticeWindow`、`_submitPractice`、
  `_togglePracticePlayback`、`_savePracticeReview`、`_navigatePracticeSentence`、
  `_closePracticeWindow`、`_currentPracticeChunks`。依赖 `practiceController`、
  `playerController`、`adapter`…（`practice_controller` 已有测试，扩展它）。
- **S5 VocabularyActionsCoordinator**：`_loadWordEntries`、`_loadPhraseEntries`、`_openWord`、
  `_setSelectedWordStatus`、`_setCapabilityOverride`、`_saveSelectedLearningContent`、
  `_observeSelected`、`_markFirstWord`、`_correctCurrentLemma`、`_showCurrentPhraseCandidates`、
  `_loadPhraseCandidates`、`_openPhrase`、`_openVocabulary`、`_showVocabulary`、
  `_openListeningDictionaryEntry`、`_openReviewQueue`、`_openLearningAssets`、
  `_openLearningResources`、`_openCoachDashboard`、`_openDiagnosisView`、`_refreshDiagnosis`、
  `_openSlicePlayback`、`_closeSlicePlayback`。（较大，可再拆 vocab / review-dashboard 两刀）
- **S6 MediaLibraryCoordinator**：`_loadMediaLibrary`、`_openLibraryEntry`、
  `_startExtensiveFromLibrary`、`_startIntensiveFromLibrary`、`_setLibraryTriageIntent`、
  `_toggleFamiliarSupply`、`_continueRecentMedia`、`_recordRecentMedia`、`_prefetchHomeSummary`。
- **S7 SubtitleSourcesCoordinator**：`_deleteSubtitleResource`、`_exportSubtitleResource`、
  `_generateSubtitles`、`_openTranscriptionCenter`、`_openPhoneticAnalysisCenter`、
  `_analyzePhonetics`、`_ensureCurrentPronunciation`、`_importEmbeddedSubtitle`、
  `_searchOpenSubtitles`、`_openOnline`、`_openManualReviewTimeline`、`_handleDrop`、
  `_isMediaPath`、`_isSubtitlePath`、`_openSubtitleResources`、`_importWordList`、
  `_openColdStartMarking`。
- **保留在 State**（不抽）：`initState` / `dispose` / `build` / `_playerStage` / `_sidePanel`
  / `_controls` / `_downloadStatusBar`（视图组合）；`_showSnackBar`（需要 context/ScaffoldMessenger）；
  `_onPosition` / `_onEvent`（高频/事件分发，`_onEvent` 可评估并入既有
  `BackendEventCoordinator`）；`_setTaskStatus` / `_confirmLLTimelineMismatch` 等薄 glue 视
  引用情况决定，倾向留在 State 作为注入回调的实现。
- 逐 Slice 收敛后复核 `_setWorkbench*` / `_expand/collapseWorkbench` / `_loadSettings` /
  `_saveSettings` / `_connectApi` / `_runSmokeIfConfigured` / `_exportLogs` 是否值得抽
  `BootstrapCoordinator`，或作为 composition-root 职责保留。

## 每 Slice 执行步骤（codex 可直接照做）

1. 新建 `lib/controllers/<name>_coordinator.dart`，照 `media_session_coordinator.dart`
   模板：构造注入 controller 依赖 + `bind({...})` 注入 UI 回调。
2. **逐字**把方法体从 `main.dart` 剪切进 coordinator；把对 `setState` / `context` /
   `l.text` / `api` 的直接引用改为注入的回调（`requestRebuild()` / `text()` / `getApi()`）。
   不重写逻辑、不改分支、不改字符串。
3. `main.dart`：删除已搬方法；`initState` 增加 `xxxCoordinator.bind(...)`；build 及其他
   调用点改为 `xxxCoordinator.method()`（或保留同名薄 wrapper 转调，减少 build 改动面）。
4. 新建 `test/<name>_coordinator_test.dart`，复用 `test/support/fakes.dart`，覆盖该
   coordinator 的每个公开方法的关键路径（成功 + 至少一条降级/边界），镜像
   `practice_controller_test.dart` 断言风格。
5. 验证（全绿才提交）：
   - `flutter analyze`（零问题）
   - `flutter test`（≥293 + 新增，全绿）
   - **逐字对拍**：`git show` 该 coordinator 的方法体 vs `main.dart` 原始 body，确认仅
     `setState/context/api` 引用改写、其余逐字一致。
6. 提交：`refactor(desktop): extract <Name>Coordinator from main.dart` + CHANGELOG 时间戳条目。

## 风险登记

- R1 回调线程化出错（把 `setState` 改成 `requestRebuild` 时漏掉某处重建）→ 缓解：逐字对拍 +
  coordinator 单测覆盖「方法调用后状态可观察变化」。
- R2 `_onPosition` 高频路径：**不抽**，避免每帧多一层间接。
- R3 build 调用点改动面：优先在 State 保留同名薄 wrapper 转调 coordinator，把 build diff
  降到最小；收敛后再评估是否内联。
- R4 无整屏 widget 测试：接受，以 coordinator 隔离单测 + analyzer + 逐字对拍为网；
  每刀后由 owner 做一次真实 app 冒烟（打开媒体→精听练习→猎词→泛听 inbox→词汇）。
- R5 循环依赖（coordinator 之间互调，如 practice↔shadowing）→ 缓解：共享操作走注入回调
  或 controller，不让 coordinator 直接持有彼此；必要时合并为一刀。

## 分支与流程

- 独立分支（勿在已收口 phase 分支上做）；机械/治理性质，参照 2.23 收口方式：完成后
  `STATE.md` 记一行 + CHANGELOG 汇总；是否登记 MILESTONES 由 owner 定。
- 逐 Slice 提交，保持每个提交范围纯净（勿让 `flutter format` / `cargo fmt` 牵连无关文件——
  本次 lexical 拆分曾误纳 fmt 改动，已回退，引以为戒）。

## 验证命令

```sh
cd apps/desktop && flutter analyze
cd apps/desktop && flutter test
```
