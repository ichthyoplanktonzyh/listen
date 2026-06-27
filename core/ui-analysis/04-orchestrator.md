# AppOrchestrator — 编排层状态图分析

**文件**: `lib/main.dart`（`_PlayerScreenState`）
**角色**: 四个正交状态机的协调者与事件路由中心

## 概述

Orchestrator 是 Statecharts 理论中"全局事件总线"的体现。它不持有独立的 Store，而是：

1. 监听各 Controller 的变更 (`ListenableBuilder`)
2. 监听从 Rust 核心发来的后端事件 (`_onEvent`)
3. 监听播放器适配器的位置/状态流 (`adapter.position`)
4. 协调跨状态机的复杂时序操作

## 状态图

```
AppOrchestrator (_PlayerScreenState)
├── ApiLifecycle                        ← 与 Rust 后端的连接生命周期
│   ├── Connecting                      ← 启动时
│   │   ├── InitialConnect              ← 首次连接
│   │   └── Reconnect                   ← 失败后重试
│   ├── Connected                       ← API 连接就绪
│   │   ├── Idle                        ← 无媒体加载
│   │   ├── MediaActive                 ← 有媒体加载
│   │   │   ├── SubtitleLoaded          ← 字幕已加载
│   │   │   └── SubtitleLoading         ← 字幕加载中
│   │   └── EventProcessing             ← 处理后端推送事件
│   └── Disconnected                    ← 连接断开
├── JobLifecycle                        ← 异步作业状态（正交区域）
│   ├── Transcription
│   │   ├── NoJob
│   │   ├── Running(progress)
│   │   └── Completed(result)
│   ├── PhoneticAnalysis
│   │   ├── NoJob
│   │   ├── Running(progress)
│   │   └── Completed(result)
│   └── ManualReview
│       ├── NotOpen
│       ├── Reviewing
│       └── Saving
└── UiState                             ← 局部 UI 状态
    ├── StatusDisplay                    ← 底部状态栏文字
    ├── DragDrop                         ← 拖放文件状态
    │   ├── Inactive
    │   └── Dragging
    └── ActiveDownload                   ← 在线下载进度
        ├── NoDownload
        └── Downloading
```

## 核心数据流分析

### 1. Position Update Pipeline（关键数据流）

Orchestrator 中最重要的数据流是从播放器位置到字幕同步的**因果链**：

```
adapter.position (Stream, 每 100ms)
  │
  ▼
_onPosition(position)
  │
  ├──→ SubtitleMachine.updatePosition(position)
  │       └──→ updateCurrentPrimaryCue / updateCurrentSecondaryCue
  │
  ├──→ SubtitleMachine.updateCurrentWord(position, enabled)
  │       └──→ currentWordToken = findWordAtPosition()
  │       └──→ currentChunkIndex = findChunkAtPosition()
  │
  ├──→ SubtitleMachine.updateCurrentDetectedPhone(position, enabled)
  │       └──→ currentDetectedPhone = findPhoneAtPosition()
  │
  ├──→ [if cue switched]
  │       ├──→ _refreshDiagnosis()
  │       ├──→ _loadPhraseCandidates()
  │       └──→ _ensureCurrentPronunciation()
  │       └──→ _keepCurrentVisible()  // 滚动 transcript
  │
  ├──→ [if loopCue enabled]
  │       └──→ adapter.seek(cue.start)  // 循环
  │
  ├──→ [if sourceLoop enabled]
  │       └──→ adapter.seek(loopStart)  // 循环
  │
  └──→ PlayerMachine.setPosition(position)
```

在 Statecharts 术语中，这是一个 **多目标事件广播**——单个 `POSITION_UPDATE` 事件被发送到多个正交区域。

### 2. Backend Event Routing

Rust 后端通过 HTTP 事件流推送事件，Orchestrator 的 `_onEvent` 充当事件路由器：

```
后端事件流 (_onEvent)
  │
  ├── "service-started"
  │     → _loadWordProfiles()
  │     → _loadTimelineResource(trackId)
  │
  ├── "transcription-job-changed"
  │     └── status="completed"
  │           → _loadGeneratedTrack(trackId, secondary)
  │     └── status≠"completed"
  │           → status='ASR ${job.status}...'
  │
  ├── "phonetic-analysis-job-changed"
  │     └── status="completed"
  │           → _loadSpeechEnhancements(trackId)
  │     └── status≠"completed"
  │           → status='Audio analysis ...'
  │
  ├── "word-profile-changed"
  │     → updateSingleWordProfile()
  │
  └── (其他事件)
```

## 跨区域同步场景

### 场景 1：打开媒体文件

```
用户动作: 选择文件 / 拖放文件
  │
  ▼
Orchestrator._openMediaPath(path)
  │
  ├──→ PlayerMachine: Idle → Opening
  │     → setStatus('Opening...')
  │     → clearMedia() / clearSubtitles()
  │     → adapter.open(path)
  │
  ├──→ [成功后] PlayerMachine: Opening → Ready
  │     → setMedia(id, path, title, fingerprint)
  │     → api.registerMedia() / api.readProgress()
  │
  ├──→ SubtitleMachine: NoTrack → Loading
  │     → _loadSubtitleResources()
  │     → [如果有保存的track] _usePrimarySubtitleTrack()
  │
  └──→ LearningMachine: 
       → _loadWordProfiles()
       → _loadPhraseProfiles()
```

### 场景 2：语音分析完成

```
后端事件: "phonetic-analysis-job-changed" (completed)
  │
  ▼
Orchestrator._onEvent()
  │
  ├──→ SubtitleMachine.SpeechEnhancements.PhoneticAnalysis:
  │     NotLoaded → Loaded
  │     → _loadSpeechEnhancements(trackId)
  │     → timingsBySentence / chunkPartitions / pronunciation / phoneticAnalysis
  │
  ├──→ SubtitleMachine.CueTracking:
  │     → updateCurrentWord() (刷新高亮)
  │     → updateCurrentDetectedPhone() (刷新音素)
  │
  └──→ ui-state: status='Audio analysis completed'
```

## 当前实现的问题（Statecharts视角）

### 问题 1：Orchestrator 过于臃肿

`_PlayerScreenState` 的 build 方法返回一个巨大的 Widget 树，且约 30+ 个回调方法定义在此类中。这违反了 Statecharts 的**关注点分离**原则——Orchestrator 应只负责路由，而不应包含所有回调逻辑。

```dart
// main.dart 中 ~2000+ 行代码
class _PlayerScreenState extends State<PlayerScreen> {
  // ~50 个字段
  // ~50 个方法
  // build() 返回 ~300 行 Widget 树
}
```

### 问题 2：隐式状态枚举不足

`status` 字段使用自由字符串编码，而非显式状态枚举。这使得保证某状态下的字段合法性变得困难。

```dart
// 当前
String status = 'Starting local core...';

// Statecharts 推荐
enum AppStatus { starting, connected, disconnected, error, ... }
```

### 问题 3：回调深度传递

`AppControllers`（InheritedWidget）提供了访问子控制器的能力，但 Orchestrator 的方法（如 `_onWord`、`_onSeekCue` 等）通过 `SidePanel` 和 `SubtitleOverlay` 等 widget 的构造函数参数层层传递。这在 Statecharts 模型中应表达为**事件通道（event channel）**。

### 问题 4：异步竞态

许多 `_onPosition` 触发的 API 调用（diagnosis、phrase candidates 等）没有请求取消机制。如果播放位置快速移动，可能导致：

1. 请求 A 发出（cue 1）
2. 请求 B 发出（cue 2）
3. 请求 B 返回 → 正确更新 UI
4. 请求 A 返回 → **错误覆盖** UI 为 cue 1 的数据

当前的 `cue.id` 检查减轻了此问题，但不能完全消除。

## 改进建议

```dart
// 1. 将 Orchestrator 拆分为多个专注的协调器
class PositionCoordinator {
  // 只负责 position → subtitle / learning 的同步
}

class MediaLifecycleCoordinator {
  // 只负责 open / close / switch media
}

class BackendEventCoordinator {
  // 只负责 _onEvent 路由
}

// 2. 使用请求序列号解决竞态
int _diagnosisRequestSeq = 0;

Future<void> _refreshDiagnosis() async {
  final seq = ++_diagnosisRequestSeq;
  final result = await api.diagnose(cue.id);
  if (seq == _diagnosisRequestSeq) {
    learningController.setDiagnosis(result);
  }
}

// 3. 用显式状态枚举替代 status 字符串
enum AppConnectionState { connecting, connected, disconnected }
enum MediaState { noMedia, opening, playing, error }
```
