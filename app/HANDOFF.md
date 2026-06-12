# Handoff — LLPlayerNext Flutter Desktop 重构 (Phases 1–5)

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

## 已完成：5 个 Phase

### Phase 1 — 提取数据/服务/工具
- `lib/models/timeline.dart` — Cue, SubtitleTrack, TimelineCursor
- `lib/services/api_service.dart` — LocalApi 后端连接
- `lib/services/external_tools.dart` — ffmpeg/yt-dlp 封装
- `lib/utils/` — format_duration, subtitle_position, subtitle_style, word_list_parser

### Phase 2 — 创建 Controller 层
- `PlayerController` — PlayerState (19 字段)
- `SubtitleController` — SubtitleState (20 字段)
- `LearningController` — LearningState (8 字段)
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

### 优先级 1：迁移商业方法到 Controller
`build()` 已从 controller 读取数据，但 ~55 个 "shadow state" 字段仍存在因为商业方法（`_openMediaPath`、`_onEvent`、`_loadWordProfiles` 等）还在写旧字段 + 调 `setState`。

需要：
1. 逐个方法将 `setState(() => field = value)` 替换为 `controller.setXxx(value)`
2. 方法完成后删除对应的 shadow 字段
3. 目标：main.dart ~1500 行，shadow 字段清零

### 优先级 2：Widget 单元测试
提取出的 13 个 widget 现在可以独立测试（因为不再依赖 controller），但尚未编写 widget 测试。

### 优先级 3：PlayerController adapter 集成
当前 `PlayerController` 不持有 adapter 引用。`togglePlayPause()` 等方法只是翻转状态位，实际的 `adapter.playOrPause()` 由 main.dart 的回调执行。可以考虑让 controller 持有 adapter 引用以封装完整的 action 逻辑。

## 验证命令

```bash
cd /Users/shadow/LLPlayerNext/.claude/worktrees/refactor+flutter-frontend/apps/desktop
flutter analyze        # No issues found!
flutter test           # 29/29 passed
flutter build macos --debug  # ✓ Built successfully
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
