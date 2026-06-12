# Handoff — Refactor Phases 1–4 Complete

**Date**: 2026-06-12
**Branch**: `worktree-refactor+flutter-frontend`
**Worktree**: `.claude/worktrees/refactor+flutter-frontend/`

## What Was Done

A 4-phase refactoring of the Flutter desktop app (`apps/desktop/`):

1. **Phase 1** — Extract pure data (`models/`), services (`services/`), and utilities (`utils/`)
2. **Phase 2** — Create `ChangeNotifier` controller layer (`controllers/`) — NOT yet wired into UI
3. **Phase 3** — Extract 13 widget files from the 3254-line `main.dart` (→ 1877 lines)
4. **Phase 4** — Replace `Timer.periodic` position polling with event-driven tracking in `player_adapter.dart`

## Current State

```
lib/
├── main.dart ........................ 1877 lines (state owner)
├── models/ .......................... Phase 1
│   └── timeline.dart
├── services/ ........................ Phase 1
│   ├── api_service.dart
│   └── external_tools.dart
├── utils/ ........................... Phase 1
│   ├── format_duration.dart
│   ├── subtitle_position.dart
│   ├── subtitle_style.dart
│   └── word_list_parser.dart
├── controllers/ ..................... Phase 2 (NOT WIRED)
│   ├── app_controllers.dart (InheritedWidget)
│   ├── player_controller.dart
│   ├── subtitle_controller.dart
│   ├── learning_controller.dart
│   └── settings_controller.dart
├── screens/ ......................... Phase 3
│   └── vocabulary_screen.dart
└── widgets/ ......................... Phase 3
    ├── app_bar/player_app_bar.dart
    ├── panels/{diagnosis_card, transcript_panel, word_learning_panel}.dart
    ├── player/{download_status_bar, playback_controls}.dart
    ├── settings/settings_dialog.dart
    ├── subtitle/token_line.dart
    └── vocabulary/{pronunciation_button, vocabulary_book_view, vocabulary_details_view, vocabulary_transfer_actions}.dart
```

## Widget Pattern (CRITICAL — follow this)

Every extracted widget follows this pattern:

```dart
class MyWidget extends StatelessWidget {
  const MyWidget({
    super.key,
    required this.data,       // data via constructor
    required this.onAction,   // callbacks via constructor
  });

  final SomeData data;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);  // i18n internally
    // ... render
  }
}
```

**Rules**:
- NO direct controller access (`context.read<FooController>()`) inside widgets
- NO importing controller files into widget files
- All data flows in via constructor parameters
- All actions flow out via callbacks
- i18n via `AppLocalizations.of(context)` internally

## What's NOT Done (Future Work)

1. **Controller wiring** — The Phase 2 controllers exist but are NOT connected to the UI. `main.dart` still holds all state directly (95+ fields in `_PlayerScreenState`). A future phase should:
   - Move state into controllers
   - Wrap the widget tree with `AppControllers` (InheritedWidget)
   - Have `_PlayerScreenState` listen to controllers instead of holding state

2. **Further main.dart reduction** — Even at 1877 lines, `main.dart` still has ~95 state fields and all business logic. The goal should be a thin `build()` method that composes widgets, not a state monolith.

3. **Widget unit tests** — Extracted widgets can now be tested in isolation with `WidgetTester`, but no widget tests exist yet.

## Merge Instructions

This branch (`worktree-refactor+flutter-frontend`) needs to be merged back to the original repo:

```bash
# In the original repo:
cd /Users/shadow/LLPlayerNext
git checkout main
git pull  # if there's M1.9 work to integrate first
git merge worktree-refactor+flutter-frontend
```

**⚠️ Warning**: The original repo at `/Users/shadow/LLPlayerNext` has uncommitted M1.9 work from another AI. Commit or stash that before merging.

## Verification

```bash
cd apps/desktop
flutter analyze        # Should show "No issues found!"
flutter test           # Should pass all 29 tests
```
