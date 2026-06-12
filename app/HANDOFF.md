# Handoff — LLPlayerNext Flutter Desktop 重构 (Phases 1–6)

## M1.9 Integration Status

The refactor branch was merged into the Milestone 1.9 acceptance branch on
2026-06-12.

- M1.9 pronunciation, sentence IPA, rule hints, settings, canonical word
  pronunciation, and local current-word highlighting now use the extracted
  controllers and widgets.
- `SubtitleController` owns sentence pronunciation, word timings, and current
  word state.
- `LearningController` owns selected canonical pronunciation.
- `SettingsController` exposes all settings-v7 pronunciation controls.
- Nullable controller state uses explicit nullable copy semantics, fixing
  stale media, subtitle, loop, selection, and diagnosis state.
- `main.dart` is 2101 lines after integration, down from the pre-refactor
  M1.9 file's 3613 lines.
- `flutter analyze`, 35 Flutter tests, Rust clippy/fmt, contracts, and the full
  M1.9 historical regression suite pass.
- The macOS release archive builds successfully. Independent launch on the
  current machine is blocked by macOS AMFI because Developer Mode is disabled
  and no code-signing identity is installed; system logs report error `-423`
  for the ad-hoc-signed executable.

**日期**: 2026-06-12
**分支**: `worktree-refactor+flutter-frontend`
**工作树**: `.claude/worktrees/refactor+flutter-frontend/apps/desktop/`

## 背景：为什么要重构

`apps/desktop/lib/main.dart` 原本是一个 **3254 行**的单体文件，`_PlayerScreenState` 类包含：
- ~95 个状态字段
- 50+ 个方法（媒体加载、字幕管理、词汇学习、设置持久化、导航）
- 10 个内联 widget 类
- ~170 行 AppBar 内联代码

每次 `setState` 都重建整棵 widget 树。添加功能需要在 3200 行中找到正确位置。代码可以运行但不可测试、不可审查、不可扩展。

## 目标架构

```
PlayerAdapter (物理层)
    ↓ stream events
Controllers (ChangeNotifier 状态管理)
    ↓ notifyListeners
_PlayerScreenState.build() 读取 controller getter
    ↓ 构造函数传参
Widget (纯渲染，不依赖 controller)
```

## 已完成：6 个 Phase

### Phase 1 — 提取数据/服务/工具
- `lib/models/timeline.dart` — Cue, SubtitleTrack, TimelineCursor
- `lib/services/api_service.dart` — LocalApi 后端连接
- `lib/services/external_tools.dart` — ffmpeg/yt-dlp 封装
- `lib/utils/` — format_duration, subtitle_position, subtitle_style, word_list_parser

### Phase 2 — 创建 Controller 层
- `PlayerController` — PlayerState (19 字段)
- `SubtitleController` — SubtitleState (20 字段)
- `LearningController` — LearningState (10 字段)
- `SettingsController` — 包装 AppSettings
- `AppControllers` — InheritedWidget (updateShouldNotify: false)

### Phase 3 — 提取 13 个 Widget
- `lib/screens/vocabulary_screen.dart` (155 行)
- `lib/widgets/app_bar/player_app_bar.dart` (213 行, 22 回调)
- `lib/widgets/panels/diagnosis_card.dart` (34 行)
- `lib/widgets/panels/transcript_panel.dart` (71 行)
- `lib/widgets/panels/word_learning_panel.dart` (208 行)
- `lib/widgets/player/download_status_bar.dart` (66 行)
- `lib/widgets/player/playback_controls.dart` (310 行, ~30 参数)
- `lib/widgets/settings/settings_dialog.dart` (487 行, 18 设置项)
- `lib/widgets/subtitle/token_line.dart` (210 行)
- `lib/widgets/vocabulary/pronunciation_button.dart` (62 行)
- `lib/widgets/vocabulary/vocabulary_book_view.dart` (45 行)
- `lib/widgets/vocabulary/vocabulary_details_view.dart` (62 行)
- `lib/widgets/vocabulary/vocabulary_transfer_actions.dart` (30 行)
- main.dart: 3254 → 1877 行 (−42%)

### Phase 4 — 事件驱动位置跟踪
- `player_adapter.dart`: Timer.periodic → VideoPlayerController.addListener
- 广播 streams: position, duration, playing, errors, tracks

### Phase 5 — Controller 接入
- `PlayerController`: 补充 17 个 getter/setter
- `SubtitleController`: 补充 10 个 getter/setter
- `initState`: adapter streams → controller 桥接
- `_loadSettings/_saveSettings`: 改用 SettingsController
- `build()`: ListenableBuilder 包裹 → 所有 widget 数据从 controller 读取
- `AppControllers`: 包裹整棵 widget 树

### Phase 6 — 消灭 Shadow State ✨ (本次)

将 ~55 个 shadow state 字段从 `_PlayerScreenState` 迁移到 4 个 controller。

**改动**:
- `lib/settings.dart` — 添加 `AppSettings.copyWith()` (27 字段)
- `lib/controllers/settings_controller.dart` — 添加 `primaryColor`/`secondaryColor` Color getter
- `lib/controllers/subtitle_controller.dart` — cursor 修复 offset、添加 `setPositionX/Y()`
- `lib/controllers/learning_controller.dart` — 添加 `selectedToken`/`selectedCue` 到 `LearningState`、`updateSingleWordProfile()`、`updateSinglePhraseProfile()`
- `lib/controllers/player_controller.dart` — 添加 `setMediaPath()`
- `lib/main.dart` — **1987 → 1891 行** (−96)

**main.dart 字段数**: ~55 shadow + 4 controller → 12 total（5 service handles + 3 UI local + 4 controllers）

**保留的本地字段**（非 shadow）:
| 字段 | 原因 |
|---|---|
| `adapter` | DesktopPlayerAdapter 硬件适配器 |
| `transcriptController` | ScrollController — widget 层 |
| `subscriptions` | StreamSubscription 生命周期管理 |
| `progressTimer` | Timer 基础设施 |
| `api` | LocalApi service handle |
| `status` | UI 状态栏消息（setState 本地管理） |
| `activeDownload` | OnlineMediaDownload service handle |
| `dragging` | 拖拽 UI 瞬态状态 |

## Widget 模式（关键规则）

```dart
class MyWidget extends StatelessWidget {
  const MyWidget({required this.data, required this.onAction, super.key});
  final SomeData data;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);  // i18n 内部获取
    // ... 纯渲染
  }
}
```

- ❌ 禁止 widget 导入 controller 文件
- ❌ 禁止 `AppControllers.of(context)` 在 widget 中使用
- ✅ 数据通过构造函数传入
- ✅ 操作通过回调传出
- ✅ i18n 通过 `AppLocalizations.of(context)` 内部获取

## 未完成：下一步工作

### 优先级 1：验证测试 ⚠️

Phase 6 代码改动较大（6 文件，403 insertions / 384 deletions）。**Flutter SDK 在当前 CLI 沙箱中不可用，尚未运行测试。** 需要立即手动验证：

```bash
cd /Users/shadow/LLPlayerNext/.claude/worktrees/refactor+flutter-frontend/apps/desktop
flutter analyze        # 预期: No issues found
flutter test           # 预期: 29/29 passed
flutter build macos --debug  # 预期: Build successful
```

### 优先级 2：Widget 单元测试

提取出的 13 个 widget 现在可以独立测试（因为不再依赖 controller），但尚未编写 widget 测试。

### 优先级 3：PlayerController adapter 集成

当前 `PlayerController` 不持有 adapter 引用。`togglePlayPause()` 等方法只是翻转状态位，实际的 `adapter.playOrPause()` 由 main.dart 的回调执行。可以考虑让 controller 持有 adapter 引用以封装完整的 action 逻辑。

### 优先级 4：main.dart 进一步瘦身

当前 1891 行，目标 ~1500 行。进一步的瘦身方向：
- 提取更多独立方法到 mixin 或 helper
- `_openSettings` 18 个 callback 可通过统一 dispatcher 简化
- `_searchOpenSubtitles` 等大型方法可提取到独立文件

## 验证命令

```bash
cd /Users/shadow/LLPlayerNext/.claude/worktrees/refactor+flutter-frontend/apps/desktop
flutter analyze        # ⚠️ 未执行
flutter test           # ⚠️ 未执行
flutter build macos --debug  # ⚠️ 未执行
```

## 合并说明

```bash
# 原始仓库有未提交的 M1.9 工作（另一个 AI 做的），先提交或 stash
cd /Users/shadow/LLPlayerNext
git checkout main
git merge worktree-refactor+flutter-frontend
```

## 完整提交历史

```
(Phase 6 — 待提交)
4df95ea Phase 5 Step 9: Update CHANGELOG.md and HANDOFF.md
8c91df2 Phase 5 Steps 6-8: Mark shadow state, update dispose, wrap AppControllers
9e613b5 Phase 5 Step 5: Refactor build() to read from controllers
5717ef7 Phase 5 Step 4: Refactor _loadSettings/_saveSettings via SettingsController
e8981e5 Phase 5 Step 3: Wire controllers into main.dart (adapter bridges)
c5c5522 Phase 5 Step 2: Add getters/setters to SubtitleController
310f39d Phase 5 Step 1: Add getters/setters to PlayerController
a60e311 Phase 3: Extract 13 widgets
f25b2e5 Phase 4: Event-driven position tracking
a1e01fc Phase 2: Create ChangeNotifier controllers
ffd3114 Phase 1: Extract models, services, utils
```
