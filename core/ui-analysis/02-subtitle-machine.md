# SubtitleMachine — 字幕状态图

**文件**: `lib/controllers/subtitle_controller.dart`
**Store 类型**: `Store<SubtitleState>`（约 30 个字段）

## 概述

SubtitleMachine 是项目中最复杂的状态机，它管理字幕加载、显示、同步以及多层次的时序资源（WordTimeline / PhoneTimeline / ChunkTimeline）。

## 层次化状态图

```
SubtitleMachine
├── TrackLifecycle                    ← 主字幕轨生命周期
│   ├── NoTrack                       ← 无字幕轨
│   ├── Loading                       ← 正在加载
│   ├── Active                        ← 字幕轨就绪
│   │   ├── CueTracking              ← 当前字幕条跟踪
│   │   └── SpeechEnhancements       ← 语音增强数据（正交区域）
│   │       ├── WordTimings
│   │       ├── Pronunciation
│   │       ├── ChunkPartitions
│   │       └── PhoneticAnalysis
│   └── Error                         ← 加载失败
├── SecondaryTrack                    ← 辅助字幕轨（简化版）
└── DisplayConfig                     ← 显示配置（正交区域）
    ├── Visibility
    ├── Position
    ├── Appearance (Font, Size, Opacity)
    └── Preset
```

## 状态组详细分析

### 1. TrackLifecycle 区域

```
状态 NoTrack {
  entry: primaryTrack=null, currentPrimaryCue=null
  
  on LOAD_TRACK(track):
    Loading / _usePrimarySubtitleTrack(track)
  on LOAD_LLTIMELINE(document):
    Loading / importLLTimeline()
}

状态 Loading {
  entry: status='Loading ...'
  
  on LOAD_SUCCEEDED:
    Active / _loadWordProfiles(), _loadPhraseProfiles(), 
            _loadSpeechEnhancements(track.id)
  on LOAD_FAILED(error):
    Error / status='Subtitle import failed: $error'
}

状态 Active {
  on UNLOAD_TRACK:
    NoTrack / clearSpeechEnhancements()
  on SWITCH_TRACK(newTrack):
    Loading / _usePrimarySubtitleTrack(newTrack)
  on ARCHIVE:
    NoTrack (如果 primaryTrack 被归档)
}
```

### 2. CueTracking — 当前字幕条跟踪

这是 SubtitleMachine 中对 **PlayerMachine.POSITION_UPDATE** 事件最敏感的机制。

```
CueTracking {
  entry: currentPrimaryCue 由 position 决定
  
  on POSITION_UPDATE(position) [当 primaryTrack != null]:
    currentPrimaryCue = primaryCursor.current(position)
    [if currentCue changed]: 
      → _refreshDiagnosis()
      → _loadPhraseCandidates()
      → _ensureCurrentPronunciation()
      → _keepCurrentVisible()  // 滚动 transcript
  
  on SELECT_CUE(cue):
    currentPrimaryCue = cue
    → adapter.seek(mediaStart(cue))
    → _refreshDiagnosis()
}
```

关键观察：`CueTracking` 本质上是**一个由 position 驱动的 Mealy 机**——输出（当前 cue）是输入（position）和状态（track）的函数。

### 3. SpeechEnhancements — 四维正交区域

```
SpeechEnhancements {
  // 四个并发子区域，各自独立加载
  
  区域 WordTimings {
    状态 NotLoaded
    状态 Loading { entry: fetch timings }
    状态 Loaded(timingsBySentence)
    状态 Failed(error)
    
    on ACTIVATE_WORD_TIMELINE(id):
      Loading → Loaded
  }
  
  区域 Pronunciation {
    状态 NotLoaded
    状态 Loading { entry: fetch pronunciation }
    状态 Loaded(pronunciationBySentence)
    状态 Failed
  }
  
  区域 ChunkPartitions {
    状态 NotLoaded
    状态 Loading { entry: fetch chunk partitions }
    状态 Loaded(chunkPartitionsBySentence)
    状态 Failed
  }
  
  区域 PhoneticAnalysis {
    状态 NotLoaded
    状态 Analyzing { entry: createPhoneticAnalysisJob() }
    状态 Analyzed(phoneticAnalysisBySentence)
    状态 Failed
    
    on ANALYSIS_JOB_COMPLETED: Analyzing → Analyzed / load analyses
    on ACTIVATE_PHONE_TIMELINE(id): NotLoaded → Loaded
  }
}
```

### 4. DisplayConfig 正交区域

```
DisplayConfig {
  区域 Visibility {
    状态 Visible  { entry: visible=true }
    状态 Hidden   { entry: visible=false }
    
    on TOGGLE: Visible ⇄ Hidden
  }
  
  区域 Position {
    状态 Default  (0.5, 0.82)
    状态 Adjusted (userModified)
    
    on DRAG(dx, dy): Adjusted / movePosition()
    on RESET: Default / (0.5, 0.82)
  }
  
  区域 Appearance {
    状态 PresetLearning   { entry: preset='learning' }
    状态 PresetWatching   { entry: preset='watching' }
    状态 PresetCompact    { entry: preset='compact' }
    
    on SET_PRESET(p): → 对应 Preset 状态
    on FONT_SIZE_CHANGE: → / setFontSize()
  }
  
  区域 SecondaryVisibility {
    状态 SecondaryVisible { entry: secondaryVisible=true }
    状态 SecondaryHidden  { entry: secondaryVisible=false }
  }
}
```

## 当前实现中的状态图问题

### 问题 1：State 字段膨胀

`SubtitleState` 包含约 30 个字段，其中许多字段仅在特定状态下有意义：

```dart
// 当前：即使 NoTrack 状态，仍保有 timingsBySentence/chunkPartitions 等字段
// 状态图中应在不同状态下有不同字段集
```

**Statecharts 推荐**：使用区分联合类型（discriminated union）或代码中的 sealed class。

### 问题 2：次级字幕轨缺少生命周期

`secondaryTrack` 的加载/卸载没有独立的状态跟踪——它与 primaryTrack 共用同一个 Store，通过字段区分。Statecharts 中应建模为独立的**正交区域**或独立的微型状态机。

### 问题 3：SpeechEnhancements 错误处理

四个子区域的错误被聚合成一个字符串 `timelineResourceError`，丢失了精确的错误来源。Statecharts 应为每个子区域分配独立的错误状态。

### 问题 4：同步时序

`currentDetectedPhone` 和 `currentChunkIndex` 依赖 `updateCurrentWord()` 和 `updateCurrentDetectedPhone()` 两个方法被 `_onPosition` 调用。这种时序同步本质上是**跨区域同步**，但当前以内联代码实现。Statecharts 的广播机制可以简化此逻辑。

## 改进建议

```dart
// 将 SubtitleState 拆分为层次化结构
sealed class SubtitleStatus {}
class NoTrack extends SubtitleStatus {}
class Loading extends SubtitleStatus {}
class Active extends SubtitleStatus {
  final SubtitleTrack track;
  final CueTracking cueTracking;
  final SpeechEnhancements speech;
}

sealed class CueTracking {
  Cue? get currentCue;
}

sealed class SpeechEnhancements {
  // 每个维度独立 sealed class
  WordTimingsStatus get wordTimings;
  PronunciationStatus get pronunciation;
  ChunkStatus get chunk;
  PhoneStatus get phone;
}
```
