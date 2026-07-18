# Changelog

All notable changes to the listen desktop app.

## 2026-07-16 — Phase 3.15.8 Semantic Search (Code Complete)

- Added an opt-in local semantic model lifecycle and “Search by meaning” dialog with rebuild, status,
  model fingerprint, top-K source provenance, disable/enable, and removal controls.
- Production-gap review can show model-versioned “near something you used” clues below existing ranked
  targets. These clues do not change ranking and are explicitly not synonym or capability claims.
- Uninstalled, disabled, stale, and failed semantic capability leaves exact corpus search and the original
  production-gap review available.

---

## Refactoring Initiative — Phases 1–6

### Why This Happened

The Flutter desktop app (`apps/desktop/`) had a single `main.dart` file of **3254 lines** containing a monolithic `_PlayerScreenState` class. This class held:

- **~95 state fields** (playback, subtitle, learning, settings, UI, download)
- **50+ methods** (media loading, subtitle management, vocabulary, settings persistence, navigation)
- **10 inline widget classes** (TokenLine, WordLearningPanel, PlaybackControls, etc.)
- **~170 lines of AppBar action buttons** inlined in the build method

The code worked but was untestable, unreviewable, and impossible to extend. Each `setState` call rebuilt the entire widget tree. Adding a feature meant navigating 3200 lines to find the right spot.

### End Goal

A thin `_PlayerScreenState` that:
1. Holds controllers (not raw state fields)
2. Delegates business logic to controllers and services
3. Composes widgets by passing controller-derived data via constructors
4. Each widget is independently testable

---

## Phase 1 — Extract Models, Services, Utilities

**Commit**: `ffd3114`

Moved pure data structures and I/O code out of `main.dart`:

| New File | Contents |
|---|---|
| `lib/models/timeline.dart` | `Cue`, `SubtitleTrack`, `TimelineCursor`, `SubtitleToken` |
| `lib/services/api_service.dart` | `LocalApi` — backend connection and API calls |
| `lib/services/external_tools.dart` | `OnlineMediaDownload`, `ExternalTools` — ffmpeg/yt-dlp wrappers |
| `lib/utils/format_duration.dart` | Duration → "MM:SS" formatting |
| `lib/utils/subtitle_position.dart` | Viewport coordinate math for draggable subtitles |
| `lib/utils/subtitle_style.dart` | Responsive font sizing for subtitle presets |
| `lib/utils/word_list_parser.dart` | TXT/CSV word list import parsing |

---

## Phase 2 — Create ChangeNotifier Controller Layer

**Commit**: `a1e01fc`

Created 4 `ChangeNotifier` controllers with immutable state snapshots. Each controller holds a `_state` value object, exposes getters, and calls `notifyListeners()` on mutation via a private `_update()` helper.

| Controller | State Object | Field Count |
|---|---|---|
| `PlayerController` | `PlayerState` | 19 (media metadata, playback, audio tracks, download) |
| `SubtitleController` | `SubtitleState` | 20 (tracks, cues, fonts, visibility, offsets, position) |
| `LearningController` | `LearningState` | 8 (word profiles, phrases, diagnosis, selection) |
| `SettingsController` | wraps `AppSettings` | 20+ (language, fonts, paths, API keys) |

Also created `AppControllers` — an `InheritedWidget` with `updateShouldNotify: false` that holds all 4 controllers + the API service. Descendants access via `AppControllers.of(context)`.

**At this point**: Controllers existed but were completely unused. `main.dart` still held all state directly.

---

## Phase 3 — Extract 13 Widgets from main.dart

**Commit**: `a60e311`

Extracted all widget classes and UI construction methods into independent files. Each widget follows **constructor-based dependency injection** — it receives data and callbacks via constructor parameters, with no direct controller dependency.

| File | Lines | What It Replaces |
|---|---|---|
| `lib/screens/vocabulary_screen.dart` | 155 | Full vocabulary management screen (was inline class) |
| `lib/widgets/app_bar/player_app_bar.dart` | 213 | AppBar with 22 callback parameters |
| `lib/widgets/panels/diagnosis_card.dart` | 34 | Hint list from diagnosis data |
| `lib/widgets/panels/transcript_panel.dart` | 71 | Scrollable transcript ListView |
| `lib/widgets/panels/word_learning_panel.dart` | 208 | Word detail editing panel (was inline class) |
| `lib/widgets/player/download_status_bar.dart` | 66 | Download progress bar |
| `lib/widgets/player/playback_controls.dart` | 310 | Full playback control bar (~30 constructor params) |
| `lib/widgets/settings/settings_dialog.dart` | 487 | Complete settings dialog (18 settings, StatefulBuilder) |
| `lib/widgets/subtitle/token_line.dart` | 210 | Subtitle token rendering with phrase underlines |
| `lib/widgets/vocabulary/pronunciation_button.dart` | 62 | Audio pronunciation playback button |
| `lib/widgets/vocabulary/vocabulary_book_view.dart` | 45 | Vocabulary list |
| `lib/widgets/vocabulary/vocabulary_details_view.dart` | 62 | Word status + occurrence list |
| `lib/widgets/vocabulary/vocabulary_transfer_actions.dart` | 30 | Export/Import buttons |

**Result**: `main.dart` reduced from 3254 → 1877 lines (−42%). Static analysis and all 29 tests passed.

---

## Phase 4 — Event-Driven Position Tracking

**Commit**: `f25b2e5`

Replaced `Timer.periodic` polling with `VideoPlayerController.addListener(_notify)`. The adapter now emits `position`, `duration`, `playing`, `errors`, and `tracks` via broadcast streams, pushed on every video frame by the native player callback. No more 16ms timer overhead.

---

## Phase 5 — Wire Controllers into main.dart

**Commits**: `310f39d` through `4df95ea` (6 commits)

### What Changed

1. **Enhanced controllers** — Added missing getters and setters to `PlayerController` (17 new) and `SubtitleController` (10 new)
2. **Bridged adapter streams** — `initState` now routes `adapter.*` streams to `playerController.setXxx()` and `subtitleController.updatePosition()`
3. **Refactored settings I/O** — `_loadSettings` uses `settingsController.load()` and syncs values to subtitle/player controllers; `_saveSettings` uses `settingsController.update()` for atomic persist
4. **Rewired `build()`** — Wrapped in `ListenableBuilder(listenable: Listenable.merge([all 4 controllers]))`. All widget construction methods (`_playerSurface`, `_controls`, `_sidePanel`, `_transcript`, `_diagnosisCard`, `_downloadStatusBar`) now read data from controller getters instead of state fields
5. **Wrapped with `AppControllers`** — The `InheritedWidget` now wraps the entire widget tree, available for future direct-widget-controller access
6. **Updated keyboard shortcuts** — `CallbackShortcuts` bindings use controller calls instead of `setState`

### Architecture After Phase 5

```
DesktopPlayerAdapter (physical layer)
    │  broadcasts position/duration/playing/errors/tracks
    ▼
_PlayerScreenState.initState() bridges streams → controllers
    │
    ├── playerController.setPosition/setPlaying/setDuration/...
    ├── subtitleController.updatePosition()
    │
    ▼
ListenableBuilder(listenable: [all 4 controllers])
    │  rebuilds when any controller notifies
    ▼
build() reads controller getters → passes data to widgets
    │
    ├── PlaybackControls(position: playerController.position, ...)
    ├── TranscriptPanel(track: subtitleController.primaryTrack, ...)
    ├── WordLearningPanel(details: learningController.selectedWordDetails, ...)
    └── ... (all 13 widgets)
    │
    ▼
AppControllers(player, subtitle, learning, settings, api)
    │  Available via AppControllers.of(context) for future use
    ▼
Widget(data, callbacks) — no controller imports, pure constructor DI
```

---

## Phase 6 — Eliminate Shadow State Fields

**Date**: 2026-06-12

### What Changed

Migrated ~55 "shadow state" fields from `_PlayerScreenState` into the 4 controllers. These fields were the last remaining direct state in main.dart — business methods still wrote to them via `setState` while `build()` already read from controllers.

### Changes by File

| File | Type | Detail |
|---|---|---|
| `lib/settings.dart` | Feature | Added `AppSettings.copyWith()` (27-field copyWith for incremental settings updates) |
| `lib/controllers/settings_controller.dart` | Feature | Added `primaryColor` / `secondaryColor` as `Color` getters |
| `lib/controllers/subtitle_controller.dart` | Fix | `primaryCursor` / `secondaryCursor` now include offset (matching main.dart behavior); added `setPositionX()` / `setPositionY()` |
| `lib/controllers/learning_controller.dart` | Feature | Added `selectedToken` / `selectedCue` to `LearningState`; added `setSelectedToken()`, `setSelectedCue()`, `updateSingleWordProfile()`, `updateSinglePhraseProfile()` |
| `lib/controllers/player_controller.dart` | Feature | Added `setMediaPath()` for partial media metadata updates |
| `lib/main.dart` | Refactor | **1987 → 1891 lines** (−96). All 55 shadow fields replaced by controller reads/writes |

### main.dart Before / After

| Metric | Before | After |
|---|---|---|
| State fields | ~55 shadow + 4 controllers | 12 total (5 service handles + 3 UI local + 4 controllers) |
| `setState` calls | ~50 (mixed shadow + controller) | ~15 (status messages + UI-only like `dragging`, `activeDownload`) |
| State source of truth | Split (shadow + controllers) | Controllers only |
| `_loadSettings` setState block | 30 lines | Removed |
| `_saveSettings` reads | Shadow fields | Controllers |
| `_onPosition` | Computed cursors from shadows + setState | Controller cursors + `_lastPrimaryCueId` tracking |
| `_openSettings` callbacks | setState + `_saveSettings()` | Controller setters + `settingsController.update(copyWith(...))` |
| `tools` getter | Read shadow `ffmpegPath` etc. | Read `settingsController.*` |
| `primaryCursor` / `secondaryCursor` getters | Shadow getters (deleted) | `subtitleController.primaryCursor` (offset-aware) |

### Retained Local Fields

These 8 fields are NOT shadow state — they're service handles or pure UI-local state:

| Field | Why Kept |
|---|---|
| `adapter` | Hardware adapter (DesktopPlayerAdapter) |
| `transcriptController` | ScrollController — widget layer concern |
| `subscriptions` | StreamSubscription list — lifecycle management |
| `progressTimer` | Timer — infrastructure |
| `api` | LocalApi service handle |
| `status` | UI status bar messages (setState'd locally) |
| `activeDownload` | OnlineMediaDownload service handle (has .cancel() method) |
| `dragging` | Transient drag-and-drop UI state |

### Migration Pattern

Every business method followed the same migration:

```dart
// Before (Phase 5):
setState(() {
  primaryTrack = imported;
  currentPrimaryCue = primaryCursor.current(position);
});
// controller NOT updated for these fields

// After (Phase 6):
subtitleController.setPrimaryTrack(imported);
subtitleController.setCurrentPrimaryCue(
  subtitleController.primaryCursor.current(playerController.position),
);
// setState removed — controller.setXxx triggers ListenableBuilder rebuild
```

### Verification Status

⚠️ **Tests not yet run after Phase 6 changes.** Flutter SDK not available in the CI sandbox. Run manually:

```bash
cd apps/desktop
flutter analyze        # Expected: No issues found
flutter test           # Expected: 29/29 passed
flutter build macos --debug  # Expected: Build successful
```

---

## Phase 5 — Wire Controllers into main.dart

*(see above)*

---

## Full Commit History

```
(Phase 6 — pending commit)
a60e311 Phase 3: Extract 13 widgets
f25b2e5 Phase 4: Event-driven position tracking
a1e01fc Phase 2: Create ChangeNotifier controllers
ffd3114 Phase 1: Extract models, services, utils
```
