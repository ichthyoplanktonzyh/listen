# Changelog

All notable changes to the LLPlayerNext desktop app.

## [Refactor Phase 5] — Controller Wiring

### Summary

Wired Phase 2's 4 `ChangeNotifier` controllers into `main.dart`. The `build()` method now reads all state from controllers via `ListenableBuilder`, while widgets continue using constructor-based dependency injection.

### Architecture

```
adapter.streams → _PlayerScreenState → controller.setXxx()
                                         ↓
                                   build() reads controller getters
                                         ↓
                                   Widget(data, callbacks)
```

### Changes

| Step | Commit | Description |
|---|---|---|
| Step 1 | `310f39d` | Add 17 new getters/setters to PlayerController |
| Step 2 | `c5c5522` | Add 6 getters + 4 setters to SubtitleController |
| Step 3 | `e8981e5` | Wire controllers in main.dart, bridge adapter streams |
| Step 4 | `5717ef7` | Refactor _loadSettings/_saveSettings via SettingsController |
| Step 5 | `9e613b5` | Refactor build() to read from controllers (ListenableBuilder) |
| Steps 6-8 | `8c91df2` | Mark shadow state, update dispose(), wrap AppControllers |

### What's Done
- `build()` reads all widget data from controllers, not state fields
- Adapter streams (position/duration/playing/errors/tracks) bridge to PlayerController
- `_loadSettings` uses `settingsController.load()`, syncs to subtitle/player controllers
- `_saveSettings` uses `settingsController.update()` for atomic persist
- `AppControllers` InheritedWidget wraps the widget tree (available for future use)
- Widgets still receive data via constructor — no direct controller access

### What Remains (Future Phase)
- ~55 shadow state fields still present for business method backward compat
- Business methods (_openMediaPath, _onEvent, _loadWordProfiles, etc.) still write to old fields
- Need to migrate business methods to use controllers, then remove shadow fields

### Test Results
```
29/29 tests passed — 0 failures
flutter analyze — No issues found!
flutter build macos --debug — ✓ Built successfully
```

---

## [Refactor Phase 3] — Widget Extraction

### Summary

Extracted 13 widget/screen files from the monolithic `main.dart`, reducing it from **3254 → 1877 lines** (42% reduction). All widgets follow constructor-based dependency injection — each receives only the data and callbacks it needs, with no direct controller dependency.

### Architecture Principle

```
main.dart (state owner) → constructor(data, callbacks) → Widget (render only)
```

- Widgets never import or depend on controllers directly
- i18n strings fetched internally via `AppLocalizations.of(context)`
- SettingsDialog uses `StatefulBuilder` + internal state shadows for instant UI feedback

### New Files (13)

| File | Lines | Description |
|---|---|---|
| `lib/screens/vocabulary_screen.dart` | 155 | Full vocabulary management screen |
| `lib/widgets/app_bar/player_app_bar.dart` | 213 | AppBar with 3 text buttons + 3 popup menus (22 callbacks) |
| `lib/widgets/panels/diagnosis_card.dart` | 34 | Hint list from diagnosis data |
| `lib/widgets/panels/transcript_panel.dart` | 71 | Scrollable transcript ListView |
| `lib/widgets/panels/word_learning_panel.dart` | 208 | Word detail editing panel |
| `lib/widgets/player/download_status_bar.dart` | 66 | Download progress + actions bar |
| `lib/widgets/player/playback_controls.dart` | 310 | Full playback control bar (~30 params) |
| `lib/widgets/settings/settings_dialog.dart` | 487 | Complete settings dialog (18 settings) |
| `lib/widgets/subtitle/token_line.dart` | 210 | Style-aware clickable subtitle tokens |
| `lib/widgets/vocabulary/pronunciation_button.dart` | 62 | Audio playback button |
| `lib/widgets/vocabulary/vocabulary_book_view.dart` | 45 | Vocabulary list with play/unlink actions |
| `lib/widgets/vocabulary/vocabulary_details_view.dart` | 62 | Word status + occurrence list + history |
| `lib/widgets/vocabulary/vocabulary_transfer_actions.dart` | 30 | Export/Import IconButtons |

### Modified Files (3)

| File | Change |
|---|---|
| `lib/main.dart` | Removed 10 classes, 6 methods, 170 lines of AppBar actions (−42%) |
| `test/m18_ui_test.dart` | Updated imports for moved classes |
| `test/vocabulary_book_test.dart` | Updated imports for moved classes |

### Test Results

```
29/29 tests passed — 0 failures
flutter analyze — No issues found!
```

### Previous Phases (already committed)

| Phase | Commit | Description |
|---|---|---|
| Phase 1 | `ffd3114` | Extract models, services, utilities |
| Phase 2 | `a1e01fc` | Create ChangeNotifier controller layer |
| Phase 4 | `f25b2e5` | Replace Timer.periodic with event-driven position tracking |
