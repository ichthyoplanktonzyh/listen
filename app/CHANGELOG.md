# Changelog

All notable changes to the LLPlayerNext desktop app.

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
