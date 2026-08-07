# 工作台重构 · 会话交接材料

> 给「继续推进工作台重构」的新会话。**先读这份，再读**
> [`workbench-ia-gap-analysis.md`](workbench-ia-gap-analysis.md)（差距对照 + 优先级 + 已确认决定），
> 然后读 [`../../AGENT.md`](../../AGENT.md)（硬约束 / 验证命令 / 开发文化）。
> 本文只记「状态 + 下一步 + 别再重新踩的坑」，规则以 AGENT.md 和测试为准。

## 1. 现在在哪

- 分支：**`feat/daily-english-workbench-rebuild`**（从 `feat/ia-restructure` 切出；PR base 是 `feat/ia-restructure`，不是 `main`）。
- 已提交 `723bf12`：**P0-a 文稿排版重做**完成。
- **工作树有未提交改动**：**P0-b 顶栏 + P0-c 盲听/选词** 都已完成、三闸全绿，但 **owner 尚未要求提交**（仅在 owner 要求时提交）。新会话开工前先 `git status` 看一眼这批改动，别当成脏工作树清掉。涉及文件见 §3 各条。
- 任务性质：**不是从零重建**。`feat/ia-restructure` 已实现工作台大半功能，本轮是**按差距对照补齐 + 提质**，逐条从「用户能看到什么」出发。别整体重写已跑通且有测试的壳层。
- **⚠️ 复刻参考功能前，先看真图**：`~/Desktop/每日英语听力UI/` 下 15 张真截图（文件名即功能名）。gap-analysis / 本文都是二手转述，会漂移；**冲突时以真图为准**。P0-c 就是照文字臆测把盲听/选词做错、被 owner 打回后照真图重做的。

## 2. 已确认的执行决定（不要再问，除非要推翻）

| 项 | 决定 |
| --- | --- |
| 返回当前句 | 底部条 → **浮动 FAB**（右下角；仅滚离后出现；避让当前句；tooltip+语义标签；窄窗可用） |
| 学习模式菜单 | **单个下拉、内部分两组**：阅读态（阅读/盲听/选词）+ 精听态（单句精听/填空/听写/跟读）；口语/写作「任务」移出该菜单 |
| 句子解析 | 复刻参考「解析面板」+ 顶部 `文字层面 / 语音层面` 切换。语音层面复用现有 `DiagnosisCard`；**文字层面待做 → 诚实占位**（缺 AI 契约，不伪造成功） |
| 精听态形态 | **可拖拽浮动小窗**（非全覆盖！真图 `单句精听.png` 复核，早先「全覆盖」写错），逻辑全复用；窗内外壳＝顶部 `N/总` + `倍速/次数/间隔`、中间提示区、底部键盘提示条 |
| 诚实占位（本轮不做真功能，只做 UI 态 + 记后端缺口） | `次数/间隔`、听写「先选句」队列。~~选词「干扰项/答案」数据~~ **← 已推翻：真图证明候选词就是挖掉的词打乱，题目自带、无需后端，P0-c 已实装真功能** |
| 截图 | 由 **owner 手动提供**，agent 不操控电脑 |
| 提交 | **仅在 owner 要求时提交**；每步 owner 提供实机截图做「现状 vs 参考」回归 |
| 顺序 | **P0 → P1 → P2** |

## 3. 路线图与状态

**P0（决定「像不像每日英语听力」）**
- [x] **P0-a 文稿排版**：去逐行时间码 · 当前句「蓝字 + 左 2.5px 强调线」（弃填充块）· 段落化 · 左对齐 · 紧凑行高。已提交 `723bf12`。
- [x] **P0-b 顶栏重做**：左侧 `媒体库 / <标题>` 面包屑（不伪造频道名）· 右侧有 tooltip 工具带（听力会话 · **跟读**(接当前句,无句禁用) · 翻译 · 学习模式 · 字幕 · **导出/打印**(禁用占位) · **分享**(禁用占位) · 设置）。**未提交**（owner 未要求）。改 `media_workbench.dart:_SessionHeader`+`_Breadcrumb`、`main.dart:2590` 接线；新增 `test/workbench_header_test.dart`（5 例）；新建 `docs/product/workbench-backend-gaps.md`。三闸全绿。
- [x] **P0-c typed `WorkbenchStudyMode` + 盲听 + 选词**：新增 `lib/models/workbench_study_mode.dart`（`normal/blindListening/wordSelection`——精听态 P1 再并入）。学习菜单「整篇」组把 listening 表达成三个显示（通读/盲听/选词，单选，移除独立「听」项，`读/说/写` 频道不变）。**盲听/选词按真图（`每日英语听力UI/盲听模式.png`、`选词模式.png`）实装为单句聚焦视图**替换文稿列表：盲听=当前句词级挖空（下划线，保留部分词作骨架）+ 顶部 `盲听模式` 条 + `N/总` 进度；选词=当前句挖空 + `请选择下列单词进行填空` + 候选词 chip（**就是被挖掉的词打乱，题目自带在 token 里，无需后端**），点 chip 填入首个空、点已填词清除。状态存 `main.dart:_studyMode`。**未提交**。改 `study_menu.dart`/`transcript_panel.dart`/`side_panel.dart`/`main.dart`；测试更新 `side_panel_shape_test`、`content_channel_switching_test`、`transcript_panel_test`（+3 例）。三闸全绿。
  - ⚠️ **教训**：先前照 gap-analysis 文字把盲听做成整篇灰条、选词做成「缺数据占位」，全错。**做参考功能前先看 `~/Desktop/每日英语听力UI/` 里的真图**，别照文字臆测。
- [x] **P0-d 返回当前句改浮动 FAB**：按真图 `每日英语听力UI/浮动重新定位.png` 把 `_BackToCurrentBar` 底部横条换成右下角浮动 FAB `_BackToCurrentFab`——`_readThroughList` 由 `Column` 改 `Stack`（`Column` 底层 + `Positioned(right/bottom: gap16)` 的 FAB），仅 `!_following && currentCue != null` 时出现（即当前句已滚离，天然不盖当前句）；形态=浅灰圆角方块（`surfaceContainerHighest` + `outlineVariant` 描边 + `elevation 2`，`ListenRadii.surfaceBorder`）+ 双下箭头 `keyboard_double_arrow_down`（`chrome` 尺寸 / `onSurfaceVariant`），图标 40×52，`Tooltip` + `Semantics(button,label)`，窄窗可用。**未提交**。改 `transcript_panel.dart`；`transcript_panel_test.dart` 两个测试改：文字 finder → `Key('transcript-back-to-current')`；第三个测试重写为 `back-to-current floats over the list without shrinking it`（钉浮动不缩表 + 落在右下象限）。三闸全绿。

**P1**（进行中）：
- [x] **精听浮动窗外壳对齐真图**——⚠️**前提更正**：早先 gap-analysis/本文写「浮动窗→**全覆盖**专注壳」是**错的**（owner 当场纠正 + 真图复核）。`单句精听.png` 里精听练习是**可拖拽的圆角+投影浮动小窗**（四角圆、不贴边、下方文稿透出、视频右下角 PiP），**不是全覆盖**。故**保持** `intensive_practice_window.dart` 的可拖拽浮动 `Positioned`（≤860×560、标题栏拖动），只把**窗内外壳**换成真图那套：`_titleBar`(标题+×，拖动手柄，去掉旧 mini-player 开关) · `_metaRow`(左 `N/总` 进度药丸 + 右 `倍速｜次数｜间隔` **诚实占位**药丸) · `Expanded(_body)`(复用 `_practiceContent` 跟读/答题/结果渲染器，居中限宽 `ListenBreakpoints.contentColumnMax`) · `_keyboardHintBar`(`<`·`⌘P 播放/暂停`·`⌘R 重听本句`·`>`，均可点 + `CallbackShortcuts` 绑 ⌘P/⌘R)。**移除 mini-player**（真图无，播放走键盘条）。`次数/间隔` + `⌘L 返回前2秒` 诚实占位记台账 §5/§6。**未提交**。改 `intensive_practice_window.dart`、`localization.dart`(+4键)；测试改 2 例（去 mini-player 断言、play/pause 改点键盘条）。三闸全绿。**教训**：又一次照文字文档臆测（这次是「全覆盖」）被真图/owner 打回——`intensive_practice_window` 是**浮动窗**，别改形态。
- [ ] 解析面板 `文字/语音` 切换（`side_panel.dart` `_diagnosisCard()`；文字层面诚实占位）。
- [ ] 底栏三段式 + 媒体缩略图/标题 + 倍速药丸。
- [ ] 导出/打印（纯前端可做部分）+ 分享入口。

**P2**：播放列表（queue model，后端缺口）· 桌面浮层字幕 · 词典气泡丰富度 · 全屏 · 设置分区（桌面字幕 tab）。

**后端缺口台账**：`docs/product/workbench-backend-gaps.md`（P0-b 已建）——已记：媒体来源层级/双语标题（§1）、导出/打印/离线（§2）、分享（§3）、跟读评分绑定 cue（§4）、精听「次数/间隔」自动重复（§5）、精听「返回前2秒」seek-back（§6）；待记：听写先选句、文字层面 AI 解析契约、解析按 cue 缓存、播放列表 queue。（选词数据**不是缺口**，见台账 §3 后的修正注。）逐条随 P1 消账。

## 4. 代码地图（已探明，省得重查）

- 工作台壳 / 顶栏：`lib/widgets/layout/media_workbench.dart` — `_SessionHeader`(~227, P0-b 重做：面包屑+工具带+跟读/导出/分享)、`_Breadcrumb`(~352)、分栏 `_MediaWorkbenchState`(~83)、`_MediaPane`(~458)。
- 工作台实例化 + 菜单接线：`lib/main.dart` `MediaWorkbench(...)`(~2608)；菜单 `_studyMenu()`(~2203)/`_translationMenu()/_listeningMenu()/_sessionSubtitleMenu()`；学习模式选择 `_selectStudyMode()`(~2235)；`_studyMode` 字段是盲听/选词的本地 UI 态。
- 文稿：`lib/widgets/panels/transcript_panel.dart`（P0-a 已改 `_TranscriptCueRow`；P0-c 加 study-mode 分支）。`build` 按 `studyMode` 分派：normal→`_readThroughList()`(~164 滚动列表)、blind→`_BlindView`(~518)、word→`_WordSelectView`(~579)。挖空逻辑 `_blankSentence()`(~817，按 `cue.id` 确定性种子)。行高经 `TokenLine.lineHeight`（默认 null 不影响视频字幕，文稿传 1.35）。
- 右侧宿主 + tabs：`side_panel.dart`、`side_panel_tabs.dart`（`原文/笔记` 两 tab —— **参考也有，保留**，别按老指令删）。
- 学习菜单：`lib/widgets/layout/study_menu.dart`（单下拉三组：整篇=通读/盲听/选词/读 · 单句=跟读/挖空/语块听写/整句听写 · 产出=说/写）。listening 频道被表达成「整篇」里的通读/盲听/选词三个单选项（无独立「听」项）；接 `selectedMode/onModeSelected`。
- 解析：`side_panel.dart` `_diagnosisCard()`（=语音层面）+ 文稿内联展开。
- 精听逻辑（**好资产，全复用**）：`controllers/practice_controller.dart`、`controllers/practice_actions_coordinator.dart`、`widgets/panels/intensive_practice_window.dart`（**可拖拽浮动窗** `Positioned` in Stack ≤860×560，标题栏拖动——**就是对的形态，别改成全覆盖**；P1 已把窗内外壳对齐真图＝`_titleBar`/`_metaRow`(进度+设置药丸)/`_body`/`_keyboardHintBar`）。
- 底栏：`widgets/player/playback_controls.dart` `_fullControlRow`(~644)，现为两行扁平（进度行 + 一条工具行），无三段/播放列表/媒体缩略图。
- 词典气泡：`widgets/panels/word_bubble.dart`（锚定、点外/Esc 关闭、加载/失败态齐 —— 已达标）。
- typed 模式：`models/workbench_study_mode.dart`（P0-c 已建，`normal/blindListening/wordSelection` 阅读态；精听态 P1 并入）。`models/content_channel.dart` 仍是频道枚举——阅读态是 listening 频道的显示变体，不是替换频道；两者在 `StudyMenu` 里合成「一个单选」呈现。

## 5. 下一步 —— 入口（P1 剩余）

P0 四条 + P1「精听浮动窗外壳对齐真图」已完成。下一步在 P1 剩余里挑（见 §3 P1 行）。**动手任何一条前先看 `~/Desktop/每日英语听力UI/` 真图**（`文本高亮以及解析.png` / `双击解析唤醒词典气泡.png` / `底栏…` / `离线:导出:打印.png` / `右下角字幕.png`）。建议顺序：
- **解析面板 `文字/语音` 切换**（推荐下一步）：`side_panel.dart` `_diagnosisCard()`（=语音层面）加「文字/语音」切换，文字层面诚实占位（AI 解析契约/按 cue 缓存记台账「待记」）。
- 底栏三段式 + 媒体缩略图/标题 + 倍速药丸；导出/打印（纯前端部分）+ 分享入口。

（P0-a/b/c/d + 精听窗 的落地要点见 §3 各条；回看实现改动见其列出的文件。）

## 6. 别再踩的坑

- **P0-d 已完成**：FAB 现为 `_BackToCurrentFab`（浮动，不再让出等高一条）。测试已改：`manual scroll pauses following…` 用 `Key('transcript-back-to-current')`（图标 FAB 无文字，别再 `find.text('回到当前句')`）；`back-to-current floats over the list without shrinking it` 钉「浮动不缩表 + 落右下象限」。`圆角必须用 `ListenRadii`（radius_discipline_test 会拦 `circular()` 字面量）——FAB 用 `surfaceBorder`。
- **精听窗已完成**：`IntensivePracticeWindow` **仍是可拖拽浮动 `Positioned`**（≤860×560，标题栏拖动）——**别再改成全覆盖**（早先照文字文档「全覆盖」臆测被真图/owner 打回）。窗内去掉 mini-player / `_showMiniPlayer`，改成进度+设置药丸 + 底部键盘条。`intensive_practice_window_test.dart` 里旧的 `Hide/Show player`、`Current sentence`、`play_circle_outline` illustration、`fact_check_outlined`、`play_arrow`(mini-player) 断言都已删/改；播放/暂停现在点 `find.text('Play / pause')`（底部键盘条），导航在 `chevron_left/right`（tooltip 仍 `Previous/Next sentence`）。**两个纪律闸**：限宽用 `ListenBreakpoints.contentColumnMax`（`column_width_discipline_test` 拦 `maxWidth:` 字面量）、圆角用 `ListenRadii`。
- **`transcript_panel_test.dart` 结构（P0-c 后）**：`main()` 调 `_analysisGroup()` + `_studyModeGroup()`（盲听/选词/无当前句）；`_Harness.currentCue` 已改为 **可空**（`Cue?`）。改文稿相关测试先摸清这两组。
- `TokenLine.textAlign` 默认 `center`（给视频字幕），文稿必须传 `TextAlign.start`；`lineHeight` 默认 null，文稿传紧凑值。已做，别回退。
- 查词锚点测试点击点：左对齐后要点在行首词（`transcript_panel_test.dart` 已改为 `row.left+40, row.top+22`）。
- 响应式：`TranscriptPanel`/`MediaWorkbench` 分栏已验证会随宽度重排（临时探针 narrow204→wide104、workbench small144→big84）。别再怀疑这块。

## 7. 验证（每步必跑，无 CI 兜底）

```bash
flutter analyze --fatal-infos --fatal-warnings
flutter test
python3 -m unittest tool/test_backend_artifacts.py
```
硬约束：不改 `backend.lock.json` / listen-core / `.listenpkg` schema；`lib/` 不写死界面语言字面量（用 `AppLocalizations` + `lib/localization.dart` 同补 en/zh）；不在 `main` 开发、不 force-push、不自行 merge PR。
