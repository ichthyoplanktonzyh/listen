# LLPlayerNext UI 数据展示层分析

> 本文档基于 apps/desktop/lib/ 下的 Dart 代码提取。
> UI = f(State)。这里列出每个UI组件消费了哪些数据、展示什么信息、触发什么操作。

---

## 1. 主界面布局

**文件**: `main.dart` → `_PlayerScreenState.build()`

### 布局结构（Column 纵向排列）

```
┌─────────────────────────────────────────────────┐
│  PlayerAppBar (AppBar)                          │ ← 菜单/操作入口
├─────────────────────────────────────────────────┤
│  Row (横向)                                      │
│  ┌──────────────────────┬────────────────────┐  │
│  │  PlayerSurface        │  SidePanel        │  │
│  │  (视频/音频 + 字幕叠加) │  (侧边栏)          │  │
│  │                      │  Tab 0: Transcript │  │
│  │                      │  Tab 1: Resources  │  │
│  │                      │  Tab 2: Word       │  │
│  │                      │  Tab 3: Diagnosis  │  │
│  └──────────────────────┴────────────────────┘  │
├─────────────────────────────────────────────────┤
│  DownloadStatusBar (可选)                        │
├─────────────────────────────────────────────────┤
│  PlaybackControls                                │
└─────────────────────────────────────────────────┘
```

---

## 2. PlayerAppBar — 应用菜单栏

**文件**: `widgets/app_bar/player_app_bar.dart`

### 展示的数据（无 — 纯操作入口）

### 提供的操作

| 按钮/菜单 | 操作 |
|-----------|------|
| Subtitle Resources | 打开字幕资源管理页面 |
| Vocabulary | 打开词汇本页面 |
| Open Media | 打开本地媒体文件 |
| Open URL | 打开在线媒体 URL |
| Primary Subtitle ▶ Import | 导入主字幕文件 |
| Primary Subtitle ▶ Generate | ASR 生成主字幕 |
| Primary Subtitle ▶ OpenSubtitles | 搜索在线字幕 |
| Secondary Subtitle ▶ (同上) | 同上，用于副字幕 |
| More ▶ Embedded | 导入内嵌字幕 |
| More ▶ Settings | 打开设置对话框 |
| More ▶ Export Logs | 导出核心日志 |
| More ▶ Export/Import Assets | 导出/导入词汇资产 |
| More ▶ Import Word List | 导入外部词表文件 |
| More ▶ Archive Media | 归档当前媒体 |
| More ▶ Transcription Center | 打开转写任务中心 |
| More ▶ Phonetic Analysis Center | 打开语音分析中心 |
| More ▶ Learning Assets | 打开学习资产管理 |
| More ▶ Learning Resources | 打开学习资源管理 |
| More ▶ Phrase Candidates | 显示当前句短语候选 |
| More ▶ Correct Lemma | 纠正当前词的 lemma |

---

## 3. PlayerSurface — 播放器/字幕叠加层

**文件**: `main.dart` → `_playerSurface()`

### 消费的数据

| 数据源 | 用途 |
|--------|------|
| `adapter.controller` (VideoPlayerController?) | 视频渲染或黑色背景 |
| `subtitleController.visible` | 是否显示主字幕 |
| `subtitleController.currentPrimaryCue` | 当前主字幕文本 |
| `subtitleController.secondaryVisible` / `currentSecondaryCue` | 副字幕 |
| `subtitleController.*FontSize/FontFamily` | 字幕字体样式 |
| `subtitleController.positionX/Y` | 字幕位置 |
| `subtitleController.backgroundOpacity` | 字幕背景透明度 |
| `subtitleController.preset` | 字幕预设（影响背景透明度系数） |
| `subtitleController.statusStylesVisible` | 是否启用词状态颜色 |
| `subtitleController.currentWordToken` | 当前高亮的词 |
| `subtitleController.chunkPartitionsBySentence` | Chunk 分组信息 |
| `subtitleController.currentChunkIndex` | 当前高亮的 chunk |
| `subtitleController.pronunciationBySentence` | 当前句音标文本 |
| `settingsController.primaryColor/secondaryColor` | 字幕颜色 |
| `settingsController.*Chunk*` | Chunk 显示样式 |
| `learningController.wordProfiles` | 每个词的掌握状态（决定颜色） |
| `learningController.phraseCandidates/profiles` | 短语下划线 |
| `playerController.mediaPath` | 是否显示"打开媒体"提示 |

### 展示的信息

1. 视频画面或黑色背景
2. 主字幕行：TokenLine 组件（词级可点击、可着色、chunk 分组显示）
3. 音标行（可选）：当前句的标准发音 IPA
4. 副字幕行（可选）：翻译/参考文本
5. 空状态："打开视频/音频"按钮
6. 拖拽上传文件时显示高亮边框

### 触发的操作

| 用户交互 | 操作 |
|---------|------|
| 点击字幕 | `_seekCue(cue)` — 跳转到该句 |
| 点击词 | `_openWord(token, cue)` — 打开词汇详情面板 |
| 点击 chunk | `_seekChunk(chunk)` — 跳转到 chunk 起始 |
| 点击短语 | `_openPhrase(candidate, cue)` — 打开短语详情 |
| 拖拽字幕位置 | `subtitleController.movePosition()` 调整位置 |
| 打开媒体按钮 | `_openMedia()` — 打开文件选择器 |

---

## 4. PlaybackControls — 播放控制栏

**文件**: `widgets/player/playback_controls.dart`

### 消费的数据

| 数据源 | 用途 |
|--------|------|
| `position` | 当前进度文本 + 滑块位置 |
| `duration` | 总时长文本 + 滑块范围 |
| `playing` | 播放/暂停图标切换 |
| `loopCue` | 循环当前句 toggle 状态 |
| `sourceLoopStart` | 是否显示"停止源循环"按钮 |
| `statusStylesVisible` | 词样式 toggle 状态 |
| `subtitlesVisible` | 主字幕 toggle 状态 |
| `secondarySubtitlesVisible` | 副字幕 toggle 状态 |
| `rate` | 播放速度显示（通过 onRateChanged 间接控制） |
| `volume` / `muted` | 音量/静音状态 |
| `audioTracks` / `selectedAudioId` | 音频轨道选择 |
| `embeddedSubtitleTracks` / `selectedEmbeddedSubtitleId` | 内嵌字幕选择 |
| `primarySubtitleOffset` / `secondarySubtitleOffset` | 字幕偏移调整 |
| `chunkControlsEnabled` | chunk 导航按钮是否可点击 |
| `chunkLoopActive` | chunk 循环 toggle 状态 |
| `status` | 状态栏文本 |

### 展示/操作

| 控件 | 操作 |
|------|------|
| 进度条 | 拖动 seek |
| 前一句/后一句 | 跳转到上/下一个 Cue |
| 回到开头 | seek to zero |
| 播放/暂停 | toggle play |
| 停止 | stop + seek zero |
| 循环当前句 | toggle loopCue |
| 前一个/后一个 Chunk | chunk 跳转 |
| 循环当前 Chunk | chunk 循环 |
| 展开 Chunk | 扩大循环范围 |
| 停止源循环 | 清除 sourceLoop |
| 词样式开关 | toggle statusStylesVisible |
| 主/副字幕开关 | toggle visible |
| 播放速度 | 下拉选择更改 rate |
| 音量/静音 | slider + mute toggle |
| 音频轨道 | 下拉选择 |
| 内嵌字幕 | 下拉选择 |
| 字幕偏移 | ±100ms 调整 |

---

## 5. 侧边栏 (SidePanel)

**文件**: `main.dart` → `_sidePanel()`

### Tab 切换 (SegmentedButton)

| Tab | index | 内容 |
|-----|-------|------|
| 字幕 (Transcript) | 0 | TranscriptPanel |
| 资源 (Resources) | 1 | TimelineResourceSummaryPanel |
| 词汇学习 (Word) | 2 | WordLearningPanel (有条件) |
| 诊断 (Diagnosis) | 3 | DiagnosisCard (有条件) |

---

## 6. TranscriptPanel — 字幕全文面板

**文件**: `widgets/panels/transcript_panel.dart`

### 消费的数据

| 数据源 | 用途 |
|--------|------|
| `track` | 完整的字幕 Cue 列表 |
| `currentCue` | 高亮当前句 |
| `wordProfiles` | 词状态颜色 |
| `showStyles` | 是否显示词状态颜色 |
| `baseColor` | 基础文本颜色 |
| `scrollController` | 自动滚动到当前句 |
| `itemExtent` | 每行高度 |

### 展示的信息

- 按时间顺序排列的所有字幕句
- 每句显示：时间戳 + TokenLine 词级渲染
- 当前句高亮底色

### 触发的操作

| 交互 | 操作 |
|------|------|
| 点击句子 | `onSeekCue(cue)` — 跳转到该句 |
| 点击词 | `onWord(token, cue)` — 打开词汇详情 |

---

## 7. TokenLine — 词级渲染行

**文件**: `widgets/subtitle/token_line.dart`

这是最核心的UI组件，负责将一个 Cue（字幕句）渲染为可交互的词序列。

### 消费的数据

| 数据源 | 用途 |
|--------|------|
| `cue.tokens` | 词、标点、空格的 token 序列 |
| `profiles` | 每个词的掌握状态（决定颜色） |
| `showStyles` | 启用/禁用颜色样式 |
| `currentTokenIndex` | 当前高亮的词 |
| `chunkPartition` | 当前句的 chunk 分组 |
| `currentChunkIndex` | 当前高亮的 chunk |
| `phraseCandidates` | 短语候选（下划线标记） |
| `phraseProfiles` | 短语掌握状态 |
| `fontSize` / `fontFamily` / `baseColor` | 字体样式 |
| `chunkDisplayStyle` | 'capsule' 胶囊样式或其他 |
| `chunkHighlightStyle` | 'background'/'bounce'/'glow' |
| `currentWordStyle` / `currentWordIntensity` | 当前词动画 |

### 渲染策略

1. **有 Chunk 分区**: 按 chunk 分组 → 每个 chunk 渲染为一个 WidgetSpan（胶囊/背景样式），内部是 Token span
2. **无 Chunk 分区**: 直接渲染所有 token 的 InlineSpan
3. **短语识别**: 优先检测短语 → 用 PhraseUnderlineSpan 包裹匹配的 token 序列

### Token 颜色映射

每个 token（词）的颜色由其 `normalized` 在 `profiles` 中的 `status` 决定：
- `'unknown_meaning'` → 红色/警告色
- `'known_not_recognized'` → 橙色/强调色
- `'known_recognized'` → 绿色/成功色
- null/未定义 → 默认文本色

### 触发的操作

| 交互 | 操作 |
|------|------|
| 点击词 | `onWord(token, cue)` |
| 点击 chunk | `onChunk(chunk)` |
| 点击短语 | `onPhrase(candidate, cue)` |

---

## 8. WordLearningPanel — 词汇学习面板

**文件**: `widgets/panels/word_learning_panel.dart`

### 消费的数据

| 数据源 | 用途 |
|--------|------|
| `details.profile` | 词条信息（显示形式、状态、ID） |
| `details.history` | 状态变更历史 |
| `details.occurrences` | 来源句快照列表 |
| `dictionary` | 词典查询结果（定义、音标） |
| `pronunciation` | 发音查询结果（IPA 变体） |
| `languageProfile` | 语言 profile（如 zh.pinyin 触发汉字拆解） |

### 展示的信息

1. 词头 (headlineMedium)
2. 当前状态文本
3. 状态选择器 (ChoiceChip × 4: 未设置/不认识/听不出/认识)
4. 分隔线
5. 汉字拆解（中文特有）：逐字拼音 + 释义
6. 词典结果：多个来源的定义
7. 音标变体：IPA 显示
8. 来源句列表
9. 状态历史
10. 用户自定义释义和笔记输入框

### 触发的操作

| 交互 | 操作 |
|------|------|
| 选择状态 | `onStatus(status)` → API 更新 → reload |
| 保存释义/笔记 | `onSave(definition, note)` |
| 点击来源句 | `onSource(occurrence)` → 跳转到来源媒体 |
| 听懂了 | `onHeard()` → 创建 observation (heard=true) |
| 没听懂 | `onNotHeard()` → 创建 observation (heard=false) |

---

## 9. DiagnosisCard — 听诊卡片

**文件**: `widgets/panels/diagnosis_card.dart`

### 消费的数据

| 数据源 | 用途 |
|--------|------|
| `diagnosis` | 诊断结果（hints 列表） |
| `pronunciation` | 标准发音缓存状态 |
| `ruleHintsLevel` | 口语规则提示级别: 'off'/'likely'/'all' |
| `pronunciationProviders` | 发音提供者状态 |
| `timingQuality` | 词时间轴质量描述 |
| `phoneticAnalysis` | 实验性语音分析结果 |
| `currentDetectedPhone` | 当前检测到的音素 |

### 展示的信息

1. 发音提供者状态（名称/版本/降级状态）
2. 时间轴来源质量
3. 标准发音缓存状态
4. 实验性语音分析：
   - 检测到的音素列表（置信度百分比）
   - 当前音素标识
   - 发现的模式/问题列表
5. 诊断提示列表（每个 hint 含 kind + reasons）
6. 口语规则预测

### 触发的操作

| 交互 | 操作 |
|------|------|
| 分析真实发音 | `onAnalyzePhonetics` |
| 分析完整轨道 | `onAnalyzeTrackPhonetics` |
| 点击音素 | `onLoopDetectedPhone` — 循环播放该音素 |
| 点击发现 | `onLoopFinding` — 循环播放发现区间 |
| 反馈 | `onFindingFeedback` — 保存反馈 |

---

## 10. TimelineResourceSummaryPanel — 时间轴资源摘要

**文件**: `widgets/panels/timeline_resource_summary_panel.dart`

### 消费的数据

| 数据源 | 用途 |
|--------|------|
| `wordTimelineSummaries` | 词时间轴版本列表 |
| `phoneTimelineSummaries` | 音素时间轴版本列表 |
| `chunkTimelineSummaries` | 语块时间轴版本列表 |
| `document` | LLTimeline 文档 |
| `error` | 错误信息 |

### 展示的信息

1. 活跃 WordTimeline 信息（算法、版本、词数、区间、置信度）
2. 候选 WordTimeline 列表（可激活）
3. 活跃 PhoneTimeline 信息
4. 活跃 ChunkTimeline 信息
5. 人工审阅状态
6. 生产端 artifacts 列表

### 触发的操作

| 操作 | 功能 |
|------|------|
| 导入 LLTimeline | `onImport` |
| 刷新 | `onRefresh` |
| 激活/归档/删除 | 各时间轴的管理操作 |
| 手动校时 | `onManualReview` |
| 生成 ChunkTimeline | `onGenerateChunkTimeline` |
| 导出 LLTimeline | `onExportLLTimeline` |

---

## 11. SubtitleResourceManagerPanel — 字幕资源管理

**文件**: `widgets/panels/subtitle_resource_manager_panel.dart`

### 消费的数据

| 数据源 | 用途 |
|--------|------|
| `resources` | 当前媒体的所有字幕轨道列表 |
| `capabilities` | 每个资源的能力描述 |
| `activeTrack` | 当前激活的主字幕 |
| 各类 summaries | 时间轴摘要 |
| `timelineDocument` | LLTimeline 文档 |
| `timelineResourceError` | 错误信息 |

### 展示的信息

1. 每个字幕轨道的：语言、来源、状态、能力标签
2. 活跃轨道标记
3. 已归档/已删除轨道列表

### 触发的操作

| 操作 | 功能 |
|------|------|
| 导入字幕 | 文件选择器 |
| 导入 LLTimeline | 文件选择器 |
| 刷新 | 重新加载 |
| 激活/归档/恢复/删除 | 轨道生命周期管理 |
| 导出 SRT/LLTimeline | 文件导出 |
| 更改语言 | 更新轨道学习语言 |

---

## 12. 独立页面 (Full Screens)

### 12.1 VocabularyScreen — 词汇本页面

**文件**: `screens/vocabulary_screen.dart`

**消费数据**: API 返回的 `listVocabulary(status, language, search)`

**UI 元素**:
- 状态筛选 (ChoiceChip × 3): unknown_meaning / known_not_recognized / known_recognized
- 搜索框
- 词汇列表 (VocabularyBookView)
- 导出/导入按钮

**操作**: 点击词 → 打开详情对话框 (WordLearningPanel)

### 12.2 SubtitleResourcesScreen — 字幕资源管理页面

**文件**: `screens/subtitle_resources_screen.dart`

**消费数据**: `PlayerController` + `SubtitleController` 的完整状态

**UI 元素**: 包装 SubtitleResourceManagerPanel

### 12.3 LearningAssetsScreen — 学习资产管理页面

**文件**: `m18_ui.dart`

**消费数据**: API 返回的 `lexicalEntries(language, kind, status, search)`

**UI 元素**:
- 类型切换: Word / Phrase
- 搜索框
- 状态筛选
- 条目列表 (LearningAssetTile)
- 编辑对话框（状态、释义、笔记、来源句）

### 12.4 TranscriptionCenter — 转写任务中心

**文件**: `transcription_ui.dart`

**消费数据**: API 返回的转写模型列表 + 任务列表

**UI 元素**:
- 模型选择
- 语言选择
- 翻译开关
- 任务状态跟踪

### 12.5 PhoneticAnalysisCenter — 语音分析中心

**文件**: `phonetic_analysis_ui.dart`

**消费数据**: API 返回的 providers + models + jobs

**UI 元素**:
- Tab: Models / Jobs
- 提供者/模型列表
- 任务状态轮询

### 12.6 SettingsDialog — 设置对话框

**文件**: `widgets/settings/settings_dialog.dart`

**消费数据**: 全部 AppSettings 字段

**UI 元素**:
- 多个分类 Tab 或分段
- 所有设置项的输入控件
- 保存回调

---

## 13. ManualTimelineReviewDialog — 手动校时对话框

**文件**: `widgets/panels/manual_timeline_review_dialog.dart`

### 消费的数据

| 数据源 | 用途 |
|--------|------|
| `draft.currentCue` | 当前编辑的句子 |
| `draft.currentSentenceWords` | 当前句所有词的时间轴 |
| `draft.dirtyWords` | 已修改的标记 |
| `dirty` | 是否有未保存修改 |
| `validateCurrentSentence()` | 边界校验结果 |

### 展示的信息

1. 句子导航（上/下句）
2. 播放控制（播放句子/播放词）
3. 编辑计数
4. 校验结果（错误/通过）
5. 每个词的：文本、start/end 时间、是否已编辑
6. 时间边界微调按钮（±10ms/±100ms）

### 触发的操作

- 导航句子 → `draft.selectCue(cue)`
- 选择词 → 显示该词时间详情
- 调整边界 → `draft.updateWordBoundary()` / `draft.stepWordBoundary()`
- 重置 → `draft.resetCurrentSentence()`
- 保存 → `onSave(draft)` → API `createTrackWordTimeline()`
- 播放范围 → `onPlayRange(start, end)`
