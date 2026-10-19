# LLPlayerNext 前端状态机分析

> 本文档基于 apps/desktop/lib/ 下的 Dart 代码提取。
> 核心原则：UI 是状态的投影。所有状态通过 Controller → State (immutable value object) → ChangeNotifier 模式管理。

---

## 1. PlayerState — 播放器状态机

**文件**: `controllers/player_controller.dart`
**核心类**: `PlayerState` (immutable) + `PlayerController` (ChangeNotifier)

### 状态字段

| 字段 | 类型 | 含义 | 初始值 |
|------|------|------|--------|
| `mediaId` | `String?` | 后端注册的媒体 ID | null |
| `mediaPath` | `String?` | 本地/网络媒体路径 | null |
| `mediaTitle` | `String?` | 媒体标题 | null |
| `mediaFingerprint` | `String?` | 媒体文件 SHA256 指纹 | null |
| `status` | `String` | 播放器状态文本（用于状态栏显示） | `'Starting local core...'` |
| `position` | `Duration` | 当前播放位置 | zero |
| `duration` | `Duration` | 媒体总时长 | zero |
| `playing` | `bool` | 是否正在播放 | false |
| `muted` | `bool` | 是否静音 | false |
| `rate` | `double` | 播放速度 (0.25–4.0) | 1.0 |
| `volume` | `double` | 音量 (0–100) | 100 |
| `audioTracks` | `List<PlayerTrack>` | 可用音频轨道列表 | [] |
| `selectedAudioId` | `String?` | 当前选中音频轨道 ID | null |
| `embeddedSubtitleTracks` | `List<PlayerTrack>` | 内嵌字幕轨道列表 | [] |
| `selectedEmbeddedSubtitleId` | `String?` | 当前选中内嵌字幕轨道 ID | null |
| `downloadProgress` | `double` | 在线媒体下载进度 (0.0–1.0) | 0.0 |
| `downloadedMediaPath` | `String?` | 下载后的本地路径 | null |
| `sourceLoopStart` | `Duration?` | 源循环起始位置（用于诊断/词汇跳转） | null |
| `sourceLoopEnd` | `Duration?` | 源循环结束位置 | null |

### 派生状态

| 表达式 | 含义 |
|--------|------|
| `positionFraction` | `position/duration`，0.0–1.0 的播放进度 |

### 状态转换（通过方法触发）

```
null (初始)
  ↓ setMedia()
Media Loaded (mediaId, mediaPath, mediaTitle, fingerprint 已设置)
  ↓ setPosition/setDuration/setPlaying (每帧更新)
Playing (position实时更新, playing=true)
  ↓ setPlaying(false)
Paused (playing=false, position保留)
  ↓ clearMedia()
Cleared (所有字段回初始)
```

辅助状态：
- `setDownloadProgress(0.0–1.0)`：下载中 → 下载完成自动归零
- `setSourceLoop(start, end)`：设置循环区间（用于词汇来源句循环播放）
- `setMuted`/`setRate`/`setVolume`：独立设置，无状态机约束

---

## 2. SubtitleState — 字幕状态机

**文件**: `controllers/subtitle_controller.dart`
**核心类**: `SubtitleState` (immutable) + `SubtitleController` (ChangeNotifier)

### 轨道与当前Cue

| 字段 | 类型 | 含义 |
|------|------|------|
| `primaryTrack` | `SubtitleTrack?` | 主字幕轨道（用于学习交互） |
| `secondaryTrack` | `SubtitleTrack?` | 副字幕轨道（仅文本显示） |
| `currentPrimaryCue` | `Cue?` | 当前播放位置对应的主字幕句 |
| `currentSecondaryCue` | `Cue?` | 当前播放位置对应的副字幕句 |
| `selectedCue` | `Cue?` | 用户手动选中的字幕句 |

### 时间偏移与循环

| 字段 | 类型 | 含义 |
|------|------|------|
| `primarySubtitleOffset` | `Duration` | 主字幕时间偏移 |
| `secondarySubtitleOffset` | `Duration` | 副字幕时间偏移 |
| `loopCue` | `bool` | 是否循环播放当前句 |

### 显示设置

| 字段 | 类型 | 含义 |
|------|------|------|
| `visible` | `bool` | 主字幕是否可见 |
| `secondaryVisible` | `bool` | 副字幕是否可见 |
| `statusStylesVisible` | `bool` | 是否显示词汇状态颜色样式 |
| `preset` | `String` | 字幕预设: `'learning'`, `'watching'`, `'compact'` |
| `primaryFontSize` | `double` | 主字幕字号缩放 (0.5–2.0) |
| `secondaryFontSize` | `double` | 副字幕字号缩放 |
| `primaryFontFamily` | `String` | 主字幕字体: `'system'`, `'serif'`, `'monospace'` |
| `secondaryFontFamily` | `String` | 副字幕字体 |
| `positionX` | `double` | 字幕水平位置 (0.0–1.0) |
| `positionY` | `double` | 字幕垂直位置 (0.0–1.0) |
| `backgroundOpacity` | `double` | 字幕背景透明度 (0.0–1.0) |

### 发音与词级同步

| 字段 | 类型 | 含义 |
|------|------|------|
| `pronunciationBySentence` | `Map<String, Map>` | 每句的标准发音（IPA/音标） |
| `timingsBySentence` | `Map<String, List<WordTiming>>` | 每句的词级时间轴 |
| `chunkPartitionsBySentence` | `Map<String, SentenceChunkPartition>` | 每句的语块（chunk）分区 |
| `pronunciationProviders` | `List<Map>` | 可用的发音提供者列表 |
| `currentWordToken` | `int?` | 当前播放位置对应的词 token 索引 |
| `currentChunkIndex` | `int?` | 当前播放位置对应的 chunk 索引 |
| `phoneticAnalysisBySentence` | `Map<String, Map>` | 每句的实验性语音分析结果 |
| `currentDetectedPhone` | `DetectedPhone?` | 当前播放位置检测到的音素 |

### Timeline 资源管理

| 字段 | 类型 | 含义 |
|------|------|------|
| `subtitleResources` | `List<SubtitleTrack>` | 当前媒体的所有字幕资源列表 |
| `subtitleResourceCapabilities` | `Map<String, SubtitleResourceCapabilities>` | 每个资源的能力描述 |
| `wordTimelineSummaries` | `List<WordTimelineSummary>` | 词级时间轴摘要列表 |
| `phoneTimelineSummaries` | `List<PhoneTimelineSummary>` | 音素级时间轴摘要列表 |
| `chunkTimelineSummaries` | `List<ChunkTimelineSummary>` | 语块时间轴摘要列表 |
| `llTimelineDocument` | `LLTimelineDocument?` | 导入的 LLTimeline JSON 文档 |
| `timelineResourceError` | `String?` | 时间轴资源加载错误信息 |

### 核心状态转换

```
无字幕 (primaryTrack=null, currentPrimaryCue=null)
  ↓ setPrimaryTrack(track) — 导入/生成/激活字幕
有轨道 (primaryTrack已设置)
  ↓ updatePosition(mediaPosition) — 每帧由播放位置驱动
找到当前Cue (currentPrimaryCue=new Cue)
  ↓ 切换轨道/清除
清除 (clearSpeechEnhancements — 清除所有增强数据)
```

### TimelineCursor 算法

```
TimelineCursor(cues, offset) — 二分查找，根据 mediaPosition - offset
  定位当前 Cue。支持 previous()/next()/mediaStart()/mediaEnd() 导航。
```

---

## 3. LearningState — 学习状态机

**文件**: `controllers/learning_controller.dart`
**核心类**: `LearningState` (immutable) + `LearningController` (ChangeNotifier)

### 词汇状态

| 字段 | 类型 | 含义 |
|------|------|------|
| `wordProfiles` | `Map<String, Map>` | 所有已知词的全局状态（lemma → profile） |
| `phraseProfiles` | `Map<String, Map>` | 所有短语的状态（canonical → details） |
| `selectedToken` | `SubtitleToken?` | 当前选中的词 token |
| `selectedCue` | `Cue?` | 当前选中的词所在的句子 |

### 查词与词典

| 字段 | 类型 | 含义 |
|------|------|------|
| `selectedWordDetails` | `Map?` | 选中词的详细信息（含 profile, history, occurrences） |
| `selectedDictionary` | `Map?` | 词典查询结果 |
| `selectedPronunciation` | `Map?` | 发音查询结果 |

### 短语与诊断

| 字段 | 类型 | 含义 |
|------|------|------|
| `phraseCandidates` | `List<Map>` | 当前句子的候选短语列表 |
| `diagnosis` | `Map?` | 当前句的听力诊断结果 |

### 侧边面板

| 字段 | 类型 | 含义 |
|------|------|------|
| `sidePanel` | `int` | 当前侧边栏 Tab: 0=字幕, 1=资源, 2=词汇学习, 3=诊断 |

### 语言

| 字段 | 类型 | 含义 |
|------|------|------|
| `availableLanguages` | `[en, zh, ja]` | 后端支持的语言列表 |
| `_languageProfiles` | `Map<String, Map>` | 缓存的语言 profile |
| `currentLanguageProfile` | `Map?` | 当前学习语言的 profile |

### 词汇状态枚举

一个词的听力掌握状态有三种：
```
null                 → 未标记（默认）
'unknown_meaning'    → 不知道意思
'known_not_recognized' → 认识但听不出来
'known_recognized'   → 认识且能听出来
```

### 状态转换

```
初始 (wordProfiles={}, selectedWordDetails=null, sidePanel=0)
  ↓ setWordProfiles() — 加载字幕时批量读取
词汇已加载
  ↓ onWord(token, cue) → selectWord(details)
词汇详情侧边栏打开 (sidePanel=2)
  ↓ setSelectedWordStatus → API 更新 → reload profiles
状态更新
  ↓ clearSelection
关闭详情
```

---

## 4. SettingsState — 设置状态机

**文件**: `settings.dart` → `AppSettings` + `controllers/settings_controller.dart`

### 设置分组

**播放**
| 字段 | 范围 | 默认 |
|------|------|------|
| `rate` | 0.25–4.0 | 1.0 |
| `volume` | 0–100 | 100 |

**字幕**
| 字段 | 范围 | 默认 |
|------|------|------|
| `subtitlesVisible` | bool | true |
| `secondarySubtitlesVisible` | bool | true |
| `statusStylesVisible` | bool | true |
| `primaryFontSize` | 0.5–2.0 | 1.0 |
| `secondaryFontSize` | 0.5–2.0 | 1.0 |
| `primaryFontFamily` | system/serif/monospace | system |
| `secondaryFontFamily` | system/serif/monospace | system |
| `subtitlePreset` | learning/watching/compact | learning |
| `subtitlePositionX` | 0.0–1.0 | 0.5 |
| `subtitlePositionY` | 0.0–1.0 | 0.82 |
| `subtitleBackgroundOpacity` | 0.0–1.0 | 0.72 |
| `primarySubtitleOffsetMs` | int ms | 0 |
| `secondarySubtitleOffsetMs` | int ms | 0 |

**颜色**
| 字段 | 默认 |
|------|------|
| `primaryColor` | 0xffffffff (白) |
| `secondaryColor` | 0xffb8d8ff (浅蓝) |

**布局**
| 字段 | 范围 | 默认 |
|------|------|------|
| `transcriptWidth` | 260–900 | 430 |

**发音与同步**
| 字段 | 默认 |
|------|------|
| `pronunciationVisible` | true |
| `wordSyncVisible` | true |
| `phonemeDisplay` | 'ipa' |
| `wordHighlightStyle` | 'background' |
| `wordAnimationIntensity` | 0.35 |
| `phonemeHighlightVisible` | true |

**Chunk 显示**
| 字段 | 默认 |
|------|------|
| `showChunkGrouping` | true |
| `chunkDisplayStyle` | 'capsule' |
| `highlightCurrentChunk` | false |
| `chunkHighlightStyle` | 'background' |
| `ruleHintsLevel` | 'likely' |

**语音分析**
| 字段 | 默认 |
|------|------|
| `phoneticAnalysisPreference` | 'on_demand' |
| `showExperimentalPhoneticResults` | false |
| `phoneticCachePolicy` | 'keep_completed' |
| `precomputePronunciation` | true |

**转写**
| 字段 | 默认 |
|------|------|
| `transcriptionQuality` | 'balanced' |
| `transcriptionLanguage` | 'auto' |
| `transcriptionDestination` | 'primary' |

**外部工具路径**
| 字段 | 默认 |
|------|------|
| `ffmpegPath` | '' |
| `ffprobePath` | '' |
| `ytDlpPath` | '' |
| `openSubtitlesApiKey` | '' |

**应用**
| 字段 | 默认 |
|------|------|
| `language` | 'system' |

---

## 5. ManualReviewDraft — 手动校时状态机

**文件**: `controllers/manual_review_controller.dart`

非 ChangeNotifier，是一个纯数据 draft 对象。

### 状态字段

| 字段 | 类型 | 含义 |
|------|------|------|
| `track` | `SubtitleTrack` | 关联的字幕轨道 |
| `sourceTimeline` | `WordTimeline` | 基准词时间轴 |
| `_words` | `List<WordTiming>` | 可编辑的词时间轴列表 |
| `currentCue` | `Cue` | 当前正在编辑的句子 |
| `dirtyWords` | `Set<WordKey>` | 已修改的词集合 (sentenceId + tokenIndex) |

### 派生状态

| 表达式 | 含义 |
|--------|------|
| `currentSentenceWords` | 当前句子的词时间轴（按 tokenIndex 排序） |
| `dirty` | 是否有未保存的修改 |
| `validateCurrentSentence()` | 当前句子边界校验结果列表 |
| `validateAll()` | 全部句子边界校验 |

### 操作

```
selectCue(cue)        → 切换到另一句
updateWordBoundary()  → 修改某个词的 start/end
stepWordBoundary()    → 步进式微调 (±deltaMs)
resetCurrentSentence() → 放弃当前句所有修改
createPayload()       → 生成保存用的 JSON payload
```
