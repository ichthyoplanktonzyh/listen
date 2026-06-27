# 基于 Statecharts 的改进建议

本文总结前四篇分析中识别的所有问题，并给出基于 Statecharts 理论的具体改进方案。

## 改进优先级矩阵

| 编号 | 改进项 | 影响面 | 实现难度 | 优先级 |
|------|--------|--------|---------|--------|
| R1 | 引入 `sealed class` 状态枚举 | 所有 Store | 中 | P0 |
| R2 | 新增跨区域事件总线 | Orchestrator | 中 | P0 |
| R3 | 请求序列号防竞态 | Orchestrator | 低 | P1 |
| R4 | 拆分臃肿的 Orchestrator | main.dart | 高 | P1 |
| R5 | SpeechEnhancements 错误细粒度化 | SubtitleMachine | 中 | P1 |
| R6 | 次级字幕独立状态机 | SubtitleMachine | 高 | P2 |
| R7 | 显式 PlayMode 枚举 | PlayerMachine | 低 | P1 |
| R8 | 代码级 Statechart 文档 | 全局 | 低 | P2 |

---

## R1：引入 `sealed class` 状态枚举

### 问题

当前 `PlayerState`、`SubtitleState`、`LearningState` 使用大量 `nullable` 字段编码状态，导致非法组合在类型系统中无法被禁止。

### 方案

将每个状态机的最外层生命周期建模为 **sealed class**（在 Dart 3 中为 `sealed class`，在旧版本中用自由联合类型）。

```dart
// PlayerMachine 的核心状态
sealed class PlayerState {
  const PlayerState();
}

class PlayerIdle extends PlayerState {
  const PlayerIdle();
}

class PlayerOpening extends PlayerState {
  const PlayerOpening(this.path);
  final String path;
}

class PlayerReady extends PlayerState {
  const PlayerReady({
    required this.mediaId,
    required this.mediaPath,
    required this.mediaTitle,
    required this.playback,
    this.audioTracks = const [],
    this.selectedAudioId,
  });

  final String mediaId;
  final String mediaPath;
  final String mediaTitle;
  final PlaybackState playback;  // Playing | Paused
  final List<PlayerTrack> audioTracks;
  final String? selectedAudioId;
}

class PlayerError extends PlayerState {
  const PlayerError(this.message);
  final String message;
}

sealed class PlaybackState {
  const PlaybackState();
}

class Playing extends PlaybackState {
  const Playing({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.rate = 1.0,
    this.mode = const NormalMode(),
  });
  
  final Duration position;
  final Duration duration;
  final double rate;
  final PlayMode mode;  // NormalMode | LoopCueMode | LoopRangeMode
}

class Paused extends PlaybackState {
  const Paused({this.position = Duration.zero});
  final Duration position;
}
```

### 收益

- **编译期安全**：非法状态组合无法通过编译
- **模式匹配**：`switch(state) { PlayerIdle(): ... }` 可穷举
- **自文档化**：状态结构一目了然

---

## R2：跨区域事件总线

### 问题

当前跨状态机通信通过 `_PlayerScreenState` 的 `_onPosition` 内联方法隐式完成，区域之间的同步逻辑分散在 Orchestrator 层。

### 方案

引入轻量级事件总线，使正交区域之间通过命名事件通信：

```dart
class EventBus {
  final Map<Type, List<void Function(Object)>> _handlers = {};

  void on<T>(void Function(T) handler) {
    _handlers.putIfAbsent(T, () => []).add((e) => handler(e as T));
  }

  void emit<T>(T event) {
    for (final handler in _handlers[T] ?? []) {
      handler(event);
    }
  }
}

// 定义跨区域事件
class PositionChanged {
  const PositionChanged(this.position, this.cue);
  final Duration position;
  final Cue? cue;
}

class CueSelected {
  const CueSelected(this.cue);
  final Cue cue;
}

class WordTimelineActivated {
  const WordTimelineActivated(this.id);
  final String id;
}
```

```dart
// 在 SubtitleMachine 中订阅
bus.on<PositionChanged>((event) {
  if (state is Active) {
    updateCue(event.position);
  }
});

// 在 LearningMachine 中订阅
bus.on<CueSelected>((event) {
  refreshDiagnosis(event.cue.id);
});
```

### 收益

- **解耦**：Controller 之间不再需要 Orchestrator 中转
- **可测试**：事件可录制回放
- **可扩展**：新功能只需订阅现有事件

---

## R3：请求序列号防竞态

### 问题

异步 API 请求（diagnosis、phrase candidates 等）返回时可能已过时。

### 方案

```dart
class AsyncGuard {
  int _seq = 0;

  int get next => ++_seq;

  Future<T> guard<T>(Future<T> Function() request) async {
    final captured = next;
    final result = await request();
    if (captured == _seq) return result;
    throw AbortedException();
  }
}

// 使用
final guard = AsyncGuard();
Future<void> _refreshDiagnosis(Cue cue) async {
  try {
    final result = await guard.guard(() => api.diagnose(cue.id));
    learningController.setDiagnosis(result);
  } on AbortedException {
    // 忽略过时结果
  }
}
```

---

## R4：拆分臃肿的 Orchestrator

### 问题

`_PlayerScreenState` 承担了以下所有职责：
1. API 连接生命周期管理
2. 媒体加载/打开
3. 字幕资源管理（加载、切换、归档、删除）
4. 时间线资源管理（word/phone/chunk）
5. 词汇导入导出
6. 设置对话框
7. 在线下载
8. 事件路由

### 方案

```dart
// 拆分为独立协调器
class ApiCoordinator { /* API 连接/重连 */ }
class MediaCoordinator { /* 媒体打开/关闭/进度保存 */ }
class SubtitleCoordinator { /* 字幕加载/切换/归档 */ }
class TimelineCoordinator { /* 时间线资源管理 */ }
class VocabularyCoordinator { /* 词汇导入导出 */ }

// 最终在 main.dart 中组合
class _PlayerScreenState extends State<PlayerScreen> {
  late final ApiCoordinator api;
  late final MediaCoordinator media;
  late final SubtitleCoordinator subtitle;
  // ...
}
```

---

## R5：SpeechEnhancements 错误细粒度化

### 问题

当前 `timelineResourceError: String?` 聚合了 4 个子区域的错误，丢失精度。

### 方案

```dart
class SpeechEnhancementsState {
  const SpeechEnhancementsState({
    this.wordTimings = const WordTimingsNotLoaded(),
    this.pronunciation = const PronunciationNotLoaded(),
    this.chunk = const ChunkPartitionsNotLoaded(),
    this.phonetic = const PhoneticAnalysisNotLoaded(),
  });

  final WordTimingsState wordTimings;
  final PronunciationState pronunciation;
  final ChunkState chunk;
  final PhoneticAnalysisState phonetic;
}

sealed class WordTimingsState {}
class WordTimingsNotLoaded extends WordTimingsState {}
class WordTimingsLoading extends WordTimingsState {}
class WordTimingsReady extends WordTimingsState {
  final Map<String, List<WordTiming>> data;
}
class WordTimingsFailed extends WordTimingsState {
  final String error;
}
```

---

## R6：次级字幕独立状态机

### 问题

次级字幕 (`secondaryTrack`) 共享 PrimaryTrack 的 `Store<SubtitleState>` 但缺少独立生命周期。

### 方案

```dart
class SubtitleDualState {
  const SubtitleDualState({
    this.primary = const NoTrack(),
    this.secondary = const NoSecondaryTrack(),
    this.display = const DisplayConfig(),
  });

  final TrackState primary;   // NoTrack | Loading | Active | Error
  final SecondaryTrackState secondary;  // NoSecondaryTrack | SecondaryActive
  final DisplayConfig display;
}

sealed class SecondaryTrackState {}
class NoSecondaryTrack extends SecondaryTrackState {}
class SecondaryActive extends SecondaryTrackState {
  final SubtitleTrack track;
  final Cue? currentCue;
}
```

---

## R7：显式 PlayMode 枚举

### 问题

播放循环模式通过 `loopCue` (bool) 和 `sourceLoopStart/End` (Duration?) 两个分散字段编码，可产生非法组合。

### 方案

```dart
sealed class PlayMode {
  const PlayMode();
}

class NormalMode extends PlayMode {
  const NormalMode();
}

class LoopCueMode extends PlayMode {
  const LoopCueMode();
}

class LoopRangeMode extends PlayMode {
  const LoopRangeMode(this.start, this.end);
  final Duration start;
  final Duration end;
}
```

---

## R8：代码级 Statechart 文档

### 建议

在关键状态机边界处用注释标明 Statecharts 语义：

```dart
/// SubtitleController 管理字幕显示、时序和语音增强数据。
///
/// Statechart 概览（SCXML 风格）：
/// ┌─────────────────────────────────────────┐
/// │ SubtitleMachine                         │
/// │ ├── TrackLifecycle                      │
/// │ │   ├── NoTrack                         │
/// │ │   ├── Loading ──→ Active             │
/// │ │   └── Active ──→ NoTrack             │
/// │ ├── SecondaryTrack              [OR]   │
/// │ └── DisplayConfig               [OR]   │
/// └─────────────────────────────────────────┘
class SubtitleController extends ChangeNotifier {
```

---

## 总结

本项目的 Store 模式实际上是 **Statecharts 的轻量级实现**——它提供了：

- ✅ **正交区域**：通过多个 `Store` 并行运行
- ✅ **细粒度选择器**：`Store.select()` 实现了精确的状态变更通知
- ✅ **不可变快照**：`copyWith` 模式确保状态不变性

但缺少的是：

- ❌ **显式状态枚举**：用 `sealed class` 替代 `nullable` 字段
- ❌ **事件通道**：跨区域通信依赖 Orchestrator 中转
- ❌ **层次化状态**：状态扁平存储而非嵌套

通过实施上述改进，LLPlayerNext 的 UI 状态管理将更接近完整的 Statecharts 形式化模型，从而获得更好的类型安全、可测试性和可维护性。
