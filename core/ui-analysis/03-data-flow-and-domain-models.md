# LLPlayerNext 数据流与领域模型分析

> 本文档描述前端各 Controller 之间的数据流、核心领域模型的结构、以及 API 契约。

---

## 1. 全局数据流架构

```
                         ┌──────────────────┐
                         │  LocalApi (HTTP)  │ ← Rust 后端 (api-http)
                         └────────┬─────────┘
                                  │ events stream (SSE)
                                  ▼
                     ┌────────────────────────┐
                     │   _PlayerScreenState   │ ← 主页面 StatefulWidget
                     │   (编排层 Orchestrator) │
                     └──┬──────┬──────┬──────┘
                        │      │      │
              ┌─────────┘      │      └──────────┐
              ▼                ▼                  ▼
     ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
     │PlayerCtrl    │  │SubtitleCtrl  │  │LearningCtrl  │
     │(ChangeNotif.)│  │(ChangeNotif.)│  │(ChangeNotif.)│
     └──────┬───────┘  └──────┬───────┘  └──────┬───────┘
            │                 │                  │
            ▼                 ▼                  ▼
     ┌───────────┐    ┌───────────┐     ┌───────────┐
     │PlayerState│    │SubtitleSt.│     │LearningSt.│
     │(immutable)│    │(immutable)│     │(immutable)│
     └───────────┘    └───────────┘     └───────────┘
            │                 │                  │
            └─────────────────┼──────────────────┘
                              │
                              ▼
                     ┌────────────────┐
                     │  AppControllers │ ← InheritedWidget
                     │  (DI Container)  │
                     └────────────────┘
                              │
                              ▼
                    ┌────────────────────┐
                    │   Widget Tree      │
                    │  (ListenableBuilder│
                    │   + ValueListenable)│
                    └────────────────────┘
```

### 核心原则

1. **单向数据流**: API/Events → Orchestrator → Controller → State → Widget
2. **Immutable State**: 每个 Controller 持有不可变 State 对象，通过 `copyWith` 产生新状态
3. **ChangeNotifier**: 状态变更时 `notifyListeners()`，Widget 通过 `ListenableBuilder` 重建
4. **Orchestrator 在 `_PlayerScreenState`**: 所有 API 调用、事件处理、跨 Controller 协调都在这里

### 事件驱动的数据流 (SSE)

```
后端事件 → LocalApi.events() stream → _onEvent() 分发:
  'service-started'          → _loadWordProfiles() + _loadTimelineResource()
  'transcription-job-changed' → 更新状态 / 加载生成的字幕轨道
  'phonetic-analysis-job-changed' → 更新状态 / 加载语音分析结果
  'word-profile-changed'     → learningController.updateSingleWordProfile()
```

### 时钟驱动的数据流 (Timer + Position)

```
adapter.position stream (每帧，事件驱动)
  → _onPosition(position)
    → subtitleController.updatePosition(position) — 更新 currentCue
    → subtitleController.updateCurrentWord(position) — 更新 currentWordToken
    → subtitleController.updateCurrentDetectedPhone(position) — 更新音素
    → loopCue 检测（到达句尾循环）
    → sourceLoop 检测（到达源循环区间尾）
    → Cue 切换时触发:
      - _refreshDiagnosis()
      - _loadPhraseCandidates()
      - _ensureCurrentPronunciation()
    → playerController.setPosition(position)

progressTimer (每5秒 Timer)
  → api.saveProgress(mediaId, position) — 持久化播放进度
```

---

## 2. 核心领域模型

**文件**: `models/timeline.dart`

### 2.1 SubtitleToken — 字幕词元

```
SubtitleToken
  ├── index: int          ← 在句子中的位置索引
  ├── kind: String        ← 'word' | 'punctuation' | 'space'
  ├── text: String        ← 原始文本
  └── normalized: String? ← 归一化/lemma（用于词汇状态查询）
```

### 2.2 Cue — 字幕句

```
Cue
  ├── id: String            ← 唯一标识
  ├── index: int            ← 在轨道中的序号
  ├── start: Duration       ← 开始时间
  ├── end: Duration         ← 结束时间
  ├── text: String          ← 显示文本
  └── tokens: List<SubtitleToken> ← 分词结果
```

### 2.3 SubtitleTrack — 字幕轨道

```
SubtitleTrack
  ├── id: String
  ├── mediaId: String?
  ├── fingerprint: String?
  ├── language: String?     ← 学习语言 (en/zh/ja)
  ├── source: String        ← 'subtitle' | 'lltimeline-json-v1' | 'generated'
  ├── status: String        ← 'available' | 'archived'
  └── cues: List<Cue>       ← 所有字幕句
```

### 2.4 WordTiming — 词级时间

```
WordTiming
  ├── sentenceId: String    ← 所属句子 ID
  ├── tokenIndex: int       ← 词在句子中的索引
  ├── text: String          ← 词文本
  ├── start: Duration       ← 词开始时间
  ├── end: Duration         ← 词结束时间
  ├── confidence: double?   ← 置信度
  ├── source: String        ← 'whisperx' | 'mfa' | 'mms_fa' | 'user_adjusted'
  ├── provider: String      ← 提供者标识
  └── providerVersion: String
```

### 2.5 WordTimeline — 词时间轴资源

```
WordTimeline
  ├── id: String
  ├── trackId: String       ← 关联字幕轨道
  ├── status: String        ← 'active' | 'candidate' | 'archived'
  ├── algorithmId/Version   ← 生成算法
  ├── createdBy: String     ← 'system' | 'user'
  ├── parentTimelineId: String? ← 编辑链（人工编辑指向源 timeline）
  ├── metricsJson: Map       ← 质量指标
  ├── words: List<WordTiming> ← 所有词时间
  └── createdAt/updatedAt
```

### 2.6 WordTimelineSummary — 词时间轴摘要

```
WordTimelineSummary
  ├── lifecycleStage: String ← 'system_generated' | 'user_adjusted'
  ├── wordCount: int
  ├── providerIds: List<String>
  ├── timingSources: List<String>
  ├── averageConfidence: double?
  ├── canActivate/Archive/Delete: bool
  └── isActive: bool (status == 'active')
```

### 2.7 ChunkTimeline — 语块时间轴

```
ChunkTimelineChunk
  ├── sentenceId: String
  ├── chunkIndex: int
  ├── startWordIndex/endWordIndex: int
  ├── start/end: Duration
  ├── text: String
  ├── boundarySources: List<String>
  ├── confidence: double
  ├── warnings: List<String>
  └── evidenceJson: Map

ChunkTimeline
  ├── providerId/Version
  ├── algorithm: String
  ├── precision: String      ← 'word' | 'phone'
  ├── chunks: List<ChunkTimelineChunk>
  └── parentWordTimelineId: String?
```

### 2.8 PhoneTimeline — 音素时间轴

```
DetectedPhone
  ├── symbol: String
  ├── phoneSet: String       ← 'ipa' | 'xsampa' | 'arpa'
  ├── start/end: Duration
  ├── confidence: double?
  ├── tokenIndex: int?
  ├── provider: String
  └── modelRevision: String

PhoneTimeline / PhoneTimelineSummary
  ├── phoneSet
  ├── phones: List<DetectedPhone>
  ├── alignments: List<Map>
  ├── findings: List<Map>
  └── precision: String
```

### 2.9 LLTimelineDocument — 交换文档

```
LLTimelineDocument
  ├── schema: String           ← 'llplayer.timeline.v1'
  ├── metadata (generator, media, language, humanReviewed)
  ├── activeWordTimelineId: String?
  ├── activePhoneTimelineId: String?
  ├── activeChunkTimelineId: String?
  └── artifacts: List<LLTimelineArtifact>
```

### 2.10 辅助模型

```
TimelineCursor(List<Cue>, offset: Duration)
  → current(mediaPosition) → Cue?  (二分查找)
  → previous(cue) → Cue?
  → next(cue) → Cue?

SentenceChunkPartition
  → sentenceId + chunks: List<DisplayChunk>

DisplayChunk(index, tokenStart, tokenEnd, text, start, end)

SubtitleResourceCapabilities
  → sentenceTiming / wordTiming / chunkTiming / phoneTiming: bool
  → 对应的 counts
```

---

## 3. 词汇状态模型

词汇系统经 API 与后端交互，前端维护缓存。

### WordProfile (API 返回)

```
{
  'id': String,
  'normalized_lemma': String,
  'display_form': String,
  'status': String | null,     ← 三种状态之一
  'user_definition': String?,
  'personal_note': String?,
  'language': String,
}
```

### WordDetails (API 返回)

```
{
  'profile': { WordProfile },
  'history': [                ← 状态变更历史
    {
      'status': String,
      'source': Map,
      'changed_at': int,
    }
  ],
  'occurrences': [            ← 来源句快照
    {
      'media_title_snapshot': String,
      'media_fingerprint_snapshot': String,
      'sentence_text_snapshot': String,
      'start_ms_snapshot': int,
      'end_ms_snapshot': int,
      'encounter_count': int,
    }
  ],
}
```

### Observation (上下文观察)

一次"是否听出来"的记录，不修改全局状态。

```
{
  'word_profile_id': String,
  'sentence_id': String,
  'original_form': String,
  'heard': bool,              ← 听出来了/没听出来
  'source': { media info },
}
```

---

## 4. AppSettings 模型

**文件**: `settings.dart` → `AppSettings`

持久化到 `~/Library/Application Support/LLPlayerNext/settings-v8.json`

包含约 40+ 个字段，按功能分组：
- 播放（rate, volume）
- 字幕显示（样式、位置、字体、颜色）
- 字幕预设（learning/watching/compact）
- 布局（transcriptWidth）
- 发音与同步（pronunciationVisible, wordSyncVisible, phonemeDisplay 等）
- Chunk 显示（showChunkGrouping, chunkDisplayStyle 等）
- 语音分析（phoneticAnalysisPreference, phoneticCachePolicy 等）
- 外部工具路径（ffmpeg, ffprobe, yt-dlp）
- OpenSubtitles API Key
- 转写参数（quality, language, destination）
- 主题色

---

## 5. UI 状态汇总矩阵

| 状态领域 | 状态机 | 状态字段数 | 核心 Controller |
|---------|--------|-----------|----------------|
| 播放器 | PlayerState | ~15 字段 | PlayerController |
| 字幕 | SubtitleState | ~30 字段 | SubtitleController |
| 学习词汇 | LearningState | ~12 字段 | LearningController |
| 设置 | AppSettings | ~40+ 字段 | SettingsController |
| 手动校时 | ManualReviewDraft | ~5 字段 | ManualReviewDraft (非 Controller) |

### 总字段数: ~100+ (不含 API 返回的临时数据)
### 核心状态类型: 5 个 (4 个 ChangeNotifier + 1 个 Plain Object)

---

## 6. 关键数据流路径

### 路径 1: 打开媒体 + 字幕

```
用户选择文件
  → _openMediaPath(path)
    → adapter.open(path)    — 启动播放器
    → api.registerMedia()   — 后端注册媒体
    → api.readProgress()    — 恢复播放进度
    → _loadSubtitleResources() — 加载已有字幕
    → adapter.play()        — 开始播放

用户导入字幕
  → _openSubtitlePath(path)
    → api.importSubtitle()  — 后端导入+分词
    → _usePrimarySubtitleTrack()
      → subtitleController.setPrimaryTrack()
      → _loadWordProfiles() — 批量读取词状态
      → _loadSpeechEnhancements() — 加载时间轴/发音/chunk
```

### 路径 2: 播放驱动字幕

```
adapter.position stream (每帧)
  → _onPosition(position)
    → subtitleController.updatePosition(position)
      → 通过 TimelineCursor 二分查找定位 currentPrimaryCue
    → Cue 切换时触发: diagnosis / phrase candidates / pronunciation
    → playerController.setPosition(position)
```

### 路径 3: 点击词 → 学习详情

```
用户点击词 token
  → _openWord(token, cue)
    → api.wordDetails()      — 获取词详情+历史+来源
    → api.lookupDictionary() — 词典查询
    → api.lookupPronunciation() — 发音查询
    → learningController.selectWord(details) — 设置到状态
    → 侧边栏自动切换到 Tab 2 (WordLearningPanel)

修改状态
  → _setSelectedWordStatus(status)
    → api.updateWordProfile()
    → learningController.updateSingleWordProfile()
    → _refreshDiagnosis()
```

### 路径 4: 时间轴资源导入与激活

```
导入 .lltimeline.json
  → _openLLTimelineResource()
    → api.importLLTimelineForMedia()
    → _usePrimarySubtitleTrack()
    → subtitleController.setTimelineResource()
    → _loadSpeechEnhancements()

激活 WordTimeline
  → _activateWordTimeline(timelineId)
    → api.activateWordTimeline()
    → _loadSpeechEnhancements() — 重新加载词时间
```

### 路径 5: 设置持久化

```
设置变更
  → settingsController.update(newSettings)
    → _settings = newSettings
    → notifyListeners()
    → _settings.save()       ← 写 JSON 到磁盘

初始化加载
  → settingsController.load()
    → AppSettings.load()      ← 读 JSON 文件
    → 同步到 subtitleController 和 playerController
```
