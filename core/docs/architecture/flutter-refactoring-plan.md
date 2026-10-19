# Flutter 前端重构方案

> 基于对 asbplayer、Memento 两个参考项目的架构分析，以及当前 LLPlayerNext 前端代码的审查。

## 一、参考项目及其可借鉴之处

### 1. asbplayer（TypeScript/React）

**架构模式：** monorepo workspace — `common/`（共享逻辑）+ `client/`（Web 播放器）+ `extension/`（浏览器扩展）

**可借鉴的：**
- `common/components/` 有 40+ 个独立组件，每个职责单一
- `common/hooks/` 11 个自定义 hooks，将状态逻辑从 UI 中分离
- `extension/controllers/` 12 个控制器类——subtitle-controller、anki-ui-controller、bulk-export-controller 等，一个领域一个 controller
- `global-state/` 使用简单的 `get/set` 接口管理全局状态，没有重型状态库
- 模块导出通过 `index.ts` barrel export，对外接口清晰

### 2. Memento（C++/Qt/QML）

**架构模式：** Context 依赖注入 + Manager 领域分层 + QML 声明式 UI

**可借鉴的：**
- `Context` 类是一个轻量的服务定位器，持有所有共享服务（播放器、字幕列表、词典、Anki、音频播放器）——对标我们的 `AppControllers`
- `manager/` 目录：`PlayerManager`、`SubtitleListManager`、`MainManager`——每个 Manager 负责一个领域，有明确的接口
- `qml/controls/`：24 个 QML 文件，按播放器(Player.qml, PlayerControls.qml)、字幕(SubtitleList.qml)、词典(DefinitionPopup.qml)、设置(OptionsWindow.qml) 分组
- `qml/definition/`：词典 UI 组件独立目录（DefinitionPage.qml、TermEntry.qml、KanjiEntry.qml 等）
- UI 组件树：`Main.qml → Player（视频区域）+ toolSplitView（搜索/字幕侧栏）+ searchWindow（独立窗口）`

### 3. 两个项目的共同模式

| 维度 | asbplayer | Memento | 适用 LLPlayerNext |
|---|---|---|---|
| 状态分层 | React hooks + Context Provider | Context 类 + QObject 属性绑定 | ChangeNotifier + ListenableBuilder |
| 组件拆分粒度 | 每个 UI 功能一个文件 | 每个控件一个 .qml 文件 | 每个 Widget 一个 .dart 文件 |
| 业务逻辑位置 | controllers/ + services/ | manager/ | controllers/ |
| 共享状态传递 | Inherited Context | Context 指针注入 | InheritedWidget |
| 设置管理 | SettingsProvider（浏览器存储） | Settings（QObject 子类） | SettingsController（ChangeNotifier） |

## 二、当前问题

### 主文件规模

```
main.dart: 3331 行
  _PlayerScreenState: ~70 个可变字段
  方法: ~60 个 (_openMedia, _openWord, _setSelectedWordStatus, ...)
  Widget build(): ~1000 行
```

### 核心问题

1. **单体 setState**：所有状态变更走 `setState()`，整个 widget tree rebuild
2. **无法独立测试**：Widget、业务逻辑全部耦合在一个类里
3. **无法复用**：TokenLine、SidePanel 等无法在其他页面使用
4. **修改风险高**：改一处可能影响完全不相关的功能

## 三、目标架构

```
lib/
├── main.dart                          # ~30 行，入口 + fvp 初始化
├── app.dart                           # ~50 行，MaterialApp + theme + 顶层 provider
│
├── models/                            # 纯数据类，零 Flutter 依赖
│   ├── player_state.dart
│   ├── subtitle_state.dart
│   ├── learning_state.dart
│   ├── settings_state.dart
│   └── timeline.dart                  # ← 从 lib/ 移入
│
├── controllers/                       # ChangeNotifier — 业务逻辑 + 状态
│   ├── player_controller.dart         # 包装 DesktopPlayerAdapter
│   ├── subtitle_controller.dart       # 字幕加载、时间线跟踪
│   ├── learning_controller.dart       # 词状态、诊断、短语候选
│   ├── settings_controller.dart       # JSON 文件读写
│   └── app_controller.dart            # 跨 controller 协调、API 初始化
│
├── services/                          # 无状态服务
│   ├── api_service.dart               # ← local_api.dart 重命名
│   └── external_tools.dart            # ← 移入，ffmpeg/ffprobe/yt-dlp
│
├── screens/                           # 完整页面（可 push 到 Navigator）
│   ├── player_screen.dart             # 主播放器页面（~200 行 Scaffold）
│   ├── vocabulary_screen.dart         # ← 从 main.dart 提取
│   ├── transcription_screen.dart      # ← 从 transcription_ui.dart
│   ├── learning_assets_screen.dart    # ← 从 m18_ui.dart
│   └── learning_resources_screen.dart # ← 从 m18_ui.dart
│
├── widgets/                           # 可复用组件
│   ├── player/
│   │   ├── video_surface.dart         # 视频渲染区 + 字幕叠加层
│   │   └── playback_controls.dart     # 进度条 + 播放/暂停 + 倍速
│   │
│   ├── subtitle/
│   │   ├── subtitle_overlay.dart      # 视频上的字幕位置控制
│   │   ├── token_line.dart            # 单词级渲染 + 颜色标记 + 点击
│   │   └── subtitle_style.dart        # 字号/颜色计算辅助
│   │
│   ├── panels/
│   │   ├── side_panel.dart            # 侧边栏容器 + 3 tab 切换
│   │   ├── transcript_panel.dart      # 完整逐句转录列表
│   │   ├── word_learning_panel.dart   # 单词详情 + 词典查询
│   │   └── diagnosis_card.dart        # 句子诊断提示
│   │
│   ├── app_bar/
│   │   └── player_app_bar.dart        # 顶部工具栏 + 所有下拉菜单
│   │
│   └── common/
│       ├── drop_target.dart           # 拖拽区域包装
│       └── responsive_text.dart       # 响应式字号
│
├── localization/
│   ├── app_localizations.dart         # 接口
│   ├── l10n_en.dart                   # 英文
│   └── l10n_zh.dart                   # 中文
│
└── utils/
    ├── subtitle_position.dart         # moveSubtitlePosition()
    ├── word_list_parser.dart          # parseExternalWordList()
    └── format_duration.dart           # _format()
```

### 文件行数目标

| 文件 | 当前 | 目标 |
|---|---|---|
| `main.dart` | 3331 | ~30 |
| `player_screen.dart` | — | ~250 |
| `player_controller.dart` | — | ~200 |
| `subtitle_controller.dart` | — | ~200 |
| `learning_controller.dart` | — | ~250 |
| `settings_controller.dart` | — | ~150 |
| `token_line.dart` | — | ~200 |
| `playback_controls.dart` | — | ~150 |
| `side_panel.dart` | — | ~80 |
| `transcript_panel.dart` | — | ~150 |
| `word_learning_panel.dart` | — | ~300 |
| 其他 widget | — | ~50–150 各 |

**总计拆分后单文件均 ≤ 300 行。**

## 四、状态管理设计 — ChangeNotifier

### 选择理由

- Flutter 内置，零额外依赖
- `ListenableBuilder` 实现精准 rebuild——只有依赖某个 controller 的 widget 才会 rebuild
- 和 Memento 的 QObject 属性绑定、asbplayer 的 React Context 是同构的模式
- 不需要 Riverpod/Bloc 的学习成本和 boilerplate

### PlayerController

```dart
class PlayerController extends ChangeNotifier {
  final DesktopPlayerAdapter _adapter;

  // ── 状态 ──
  String? mediaId, mediaPath, mediaTitle, mediaFingerprint;
  bool playing = false, muted = false, loopCue = false;
  double rate = 1.0, volume = 100.0;
  Duration position = Duration.zero, duration = Duration.zero;
  List<PlayerTrack> audioTracks = [];
  String? selectedAudioId;
  List<PlayerTrack> embeddedSubtitleTracks = [];
  String? selectedEmbeddedSubtitleId;

  // ── 计算属性 ──
  double get positionFraction =>
      duration == Duration.zero ? 0 : position.inMilliseconds / duration.inMilliseconds;

  // ── Stream（供外部监听）──
  Stream<Duration> get positionStream => _adapter.positionStream;
  Stream<Duration> get durationStream => _adapter.durationStream;
  Stream<bool> get playingStream => _adapter.playingStream;

  // ── 动作 ──
  Future<void> openFile(String path) async { ... }
  Future<void> openUrl(String url) async { ... }
  void playOrPause() { ... }
  void seek(Duration pos) { ... }
  void setRate(double rate) { ... }
  void setVolume(double volume) { ... }
  void setAudioTrack(String? id) { ... }
  void dispose() { ... }
}
```

### SubtitleController

```dart
class SubtitleController extends ChangeNotifier {
  // ── 状态 ──
  SubtitleTrack? primaryTrack, secondaryTrack;
  TimelineCursor? primaryCursor, secondaryCursor;
  Cue? currentPrimaryCue, currentSecondaryCue;
  bool visible = true, secondaryVisible = true, statusStylesVisible = true;
  double fontSize = 1.0, secondaryFontSize = 1.0;
  String fontFamily = 'system', secondaryFontFamily = 'system';
  String preset = 'learning';
  double positionX = 0.5, positionY = 0.82, backgroundOpacity = 0.72;

  // ── 计算属性 ──
  Cue? get currentCue => currentPrimaryCue;
  SubtitleTrack? get activeTrack => primaryTrack;
  int? get currentWordToken => ...;

  // ── 动作 ──
  Future<void> openFile(String path, {bool secondary = false});
  Future<void> loadTrack(SubtitleTrack track, {bool secondary = false});
  Future<void> generateSubtitles({bool secondary = false});
  Future<void> importEmbedded();
  void updatePosition(Duration position);  // 驱动时间线
  void movePosition(Offset delta, Size viewport);
  void setPreset(String preset);
  void setFontSize(double scale, {bool secondary = false});
}
```

### LearningController

```dart
class LearningController extends ChangeNotifier {
  // ── 状态 ──
  Map<String, Map<String, dynamic>> wordProfiles = {};
  Map<String, Map<String, dynamic>> phraseProfiles = {};
  Map<String, dynamic>? selectedWordDetails;
  Map<String, dynamic>? selectedDictionary;
  Map<String, dynamic>? selectedPronunciation;
  List<Map<String, dynamic>> phraseCandidates = [];
  Map<String, dynamic>? diagnosis;
  int sidePanel = 0;  // 0=transcript, 1=word-learning, 2=diagnosis

  // ── 动作 ──
  Future<void> openWord(SubtitleToken token, Cue cue);
  Future<void> setWordStatus(String lemma, String? status);
  Future<void> observeWord(String lemma, String sentenceId, bool heard);
  Future<void> refreshDiagnosis(String sentenceId);
  Future<void> loadPhraseCandidates(String sentenceId);
  Future<void> exportVocabulary();
  Future<void> importVocabulary();
  Future<void> importWordList(String content, {bool csv = false});
  void selectSidePanel(int index);
}
```

### SettingsController

```dart
class SettingsController extends ChangeNotifier {
  AppSettings _settings = AppSettings.defaults();

  // 便捷访问（保持和当前代码兼容）
  String get language => _settings.language;
  String get ffmpegPath => _settings.ffmpegPath;
  String get subtitlePreset => _settings.subtitlePreset;
  // ... 所有设置字段

  Future<void> load();
  Future<void> save();

  /// 批量修改设置
  void update(AppSettings Function(AppSettings) fn) {
    _settings = fn(_settings);
    notifyListeners();
    unawaited(save());
  }
}
```

### Controller 提供方式 — InheritedWidget

```dart
class AppControllers extends InheritedWidget {
  final PlayerController player;
  final SubtitleController subtitle;
  final LearningController learning;
  final SettingsController settings;
  final ApiService api;

  const AppControllers({
    required this.player,
    required this.subtitle,
    required this.learning,
    required this.settings,
    required this.api,
    required super.child,
    super.key,
  });

  static AppControllers of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppControllers>()!;

  @override
  bool updateShouldNotify(AppControllers old) => false; // controllers 自身 notify
}
```

### 使用示例

```dart
// player_screen.dart
class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = AppControllers.of(context);
    return Scaffold(
      appBar: PlayerAppBar(),
      body: DropTarget(
        onDragDone: (details) => ctrl.subtitle.openFile(details.paths.first),
        child: Row(
          children: [
            Expanded(
              child: Stack(
                children: [
                  const VideoSurface(),
                  ListenableBuilder(
                    listenable: ctrl.subtitle,
                    builder: (_, __) => SubtitleOverlay(
                      cue: ctrl.subtitle.currentPrimaryCue,
                      visible: ctrl.subtitle.visible,
                      position: Offset(ctrl.subtitle.positionX, ctrl.subtitle.positionY),
                    ),
                  ),
                ],
              ),
            ),
            const SidePanel(),
          ],
        ),
      ),
    );
  }
}
```

```dart
// token_line.dart — 只接收需要的数据，不依赖 controller
class TokenLine extends StatelessWidget {
  final Cue cue;
  final Map<String, Map<String, dynamic>> wordProfiles;
  final Map<String, String> phraseColors;
  final bool statusStylesVisible;
  final void Function(SubtitleToken token, Cue cue)? onWordTap;
  final double fontSize;

  // ... build 方法
}
```

## 五、迁移路径（每个阶段都可独立工作、可测试）

### Phase 1：提取纯数据和纯服务（0 风险）

**操作：**
- 创建 `lib/models/` 目录，把 `timeline.dart` 移入
- 把 `local_api.dart` → `lib/services/api_service.dart`（重命名，不改逻辑）
- 把 `external_tools.dart` → `lib/services/external_tools.dart`
- 把 `parseExternalWordList()` 移到 `lib/utils/word_list_parser.dart`
- 把 `moveSubtitlePosition()` 移到 `lib/utils/subtitle_position.dart`
- 把 `responsiveSubtitleSize()` 移到 `lib/widgets/subtitle/subtitle_style.dart`
- `main.dart` 只改 import 路径

**验证：** `flutter build macos --release` 通过。所有功能不变。

### Phase 2：创建 Controller 层

**操作：**
- 创建 `PlayerController`，从 `_PlayerScreenState` 中迁移：
  - 字段：`mediaId`, `mediaPath`, `mediaTitle`, `playing`, `muted`, `rate`, `volume`, `position`, `duration`, `audioTracks`, `embeddedSubtitleTracks`
  - 方法：`_openMedia`, `_openMediaPath`, `_openOnline`, `_downloadOnline`, `playOrPause`, `seek`, `setRate`, 等

- 创建 `SubtitleController`，迁移：
  - 字段：`primaryTrack`, `secondaryTrack`, `primaryCursor`, `secondaryCursor`, `currentPrimaryCue`, `visible`, `fontSize`, `preset`, `positionX`, `positionY` 等
  - 方法：`_openSubtitle`, `_openSubtitlePath`, `_loadGeneratedTrack`, `_importEmbeddedSubtitle`, `_onPosition` (cue 更新逻辑)

- 创建 `LearningController`，迁移：
  - 字段：`wordProfiles`, `phraseProfiles`, `selectedWordDetails`, `selectedDictionary`, `diagnosis`, `phraseCandidates`, `sidePanel`
  - 方法：`_openWord`, `_setSelectedWordStatus`, `_observeSelected`, `_refreshDiagnosis`, `_loadPhraseCandidates`, `_exportVocabulary`, `_importVocabulary`

- 创建 `SettingsController`，迁移：
  - `_loadSettings`, `_saveSettings`, 所有 settings 字段

- `_PlayerScreenState` 改成持有 4 个 controller，`build()` 用 `ListenableBuilder` 替代 `setState`

**验证：** 功能对等，手动测试所有核心路径。

### Phase 3：Widget 提取

**操作：** 把 `build()` 中的大块 Widget 提取为独立文件。

| Widget | 来源（main.dart 行号区域） | 新文件 |
|---|---|---|
| `PlayerAppBar` | 1980–2151 | `widgets/app_bar/player_app_bar.dart` |
| `VideoSurface` | 2153–2300 | `widgets/player/video_surface.dart` |
| `SubtitleOverlay` | 2300–2400 | `widgets/subtitle/subtitle_overlay.dart` |
| `TokenLine` | 2600–2823 | `widgets/subtitle/token_line.dart` |
| `PlaybackControls` | 2400–2498 | `widgets/player/playback_controls.dart` |
| `SidePanel` | side panel 三段 | `widgets/panels/side_panel.dart` |
| `TranscriptPanel` | side panel [0] | `widgets/panels/transcript_panel.dart` |
| `WordLearningPanel` | side panel [1] | `widgets/panels/word_learning_panel.dart` |
| `DiagnosisCard` | side panel [2] | `widgets/panels/diagnosis_card.dart` |
| `DropTarget wrapper` | 2153–2158 | `widgets/common/drop_target.dart` |
| `SettingsDialog` | 864–1231 | `widgets/settings_dialog.dart` |

**原则：** 每个 widget 只通过构造函数接收它需要的数据和回调，不直接依赖 controller。

**验证：** 功能对等 + 对核心 widget 添加 widget test。

### Phase 4：Screen 提取 + 路由

**操作：**
- `VocabularyScreen` — 已在 main.dart 底部，移到 `screens/vocabulary_screen.dart`
- `TranscriptionCenter` — 从 `transcription_ui.dart` 移到 `screens/transcription_screen.dart`
- `LearningAssetsScreen` / `LearningResourceScreen` — 从 `m18_ui.dart` 移到 `screens/`
- 用 `Navigator.push(MaterialPageRoute(...))` 保持不变，暂不引入 go_router（等路由多了再考虑）

**验证：** 功能对等。

## 六、PlayerAdapter 优化

当前用 `Timer.periodic(100ms)` 轮询 position。改为事件驱动：

```dart
// player_adapter.dart — 修改
class DesktopPlayerAdapter {
  // ...
  void _onControllerUpdate() {
    final value = _controller!.value;
    _positionController.add(value.position);
    _durationController.add(value.duration);
    _playingController.add(value.isPlaying);
    _errorController.add(value.errorDescription);
  }

  // 用 addListener 替代 Timer.periodic
  void _startPolling() {
    _controller!.addListener(_onControllerUpdate);
  }

  void _stopPolling() {
    _controller!.removeListener(_onControllerUpdate);
  }
}
```

## 七、文件变更汇总

```
新增 25 个文件：
  lib/models/          4 个
  lib/controllers/     5 个
  lib/widgets/        12 个
  lib/screens/         2 个（vocabulary_screen, transcription_screen）
  lib/utils/           2 个

修改 1 个文件：
  lib/main.dart        3331 → ~30 行
  lib/player_adapter.dart  轮询 → 事件驱动

移动/重命名 4 个文件：
  lib/local_api.dart → lib/services/api_service.dart
  lib/external_tools.dart → lib/services/external_tools.dart
  lib/timeline.dart → lib/models/timeline.dart

  lib/transcription_ui.dart → lib/screens/transcription_screen.dart
  lib/m18_ui.dart → lib/screens/learning_assets_screen.dart (拆分)
```

## 八、不做的事

| 不做 | 原因 |
|---|---|
| 引入 Riverpod / Bloc | 当前规模不需要。ChangeNotifier 够用，未来如果真的需要再迁移，成本可控 |
| 引入 go_router | 只有 4 个独立页面，Navigator.push 够用。等页面超过 10 个再考虑 |
| 引入 code generation（freezed, json_serializable） | 增加构建复杂度。model 类用 hand-written immutable class 即可 |
| 使用 ARB 文件替代硬编码 i18n | 当前只有 en/zh 两种语言，硬编码 Map 够用。等语言超过 5 种再迁移 |
| 创建单独的 `common/` 共享包 | 当前只有 Flutter 一个客户端。asbplayer 有 web+extension 两个才需要 monorepo |

## 九、参考项目关键源码位置

| 参考点 | 文件路径 |
|---|---|
| asbplayer 控制器拆分 | `/tmp/asbplayer/extension/src/controllers/` (12 个 controller) |
| asbplayer 共享状态接口 | `/tmp/asbplayer/common/global-state/index.ts` |
| asbplayer 设置 Provider 模式 | `/tmp/asbplayer/common/settings/settings-provider.ts` |
| Memento Context 依赖注入 | `/tmp/Memento/src/state/context.h` |
| Memento QML 组件拆分 | `/tmp/Memento/src/qml/controls/` (24 个 .qml 文件) |
| Memento 主窗口组件树 | `/tmp/Memento/src/qml/Main.qml` |
