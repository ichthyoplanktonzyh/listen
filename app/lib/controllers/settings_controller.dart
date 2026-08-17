import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../services/media_import_file_service.dart';
import '../settings.dart';
import '../utils/transcript_translation.dart';

/// Wraps [AppSettings] persistence with [ChangeNotifier] for reactive UI.
class SettingsController extends ChangeNotifier {
  /// The media library folder is picked with the same directory chooser the
  /// import path already uses, so there is one platform channel, not two.
  SettingsController({this.files = const LocalMediaImportFileService()});

  final MediaImportFileService files;

  AppSettings _settings = const AppSettings();

  AppSettings get settings => _settings;

  // ── Convenience accessors ──

  String get language => _settings.language;
  String get themeMode => _settings.themeMode;
  String get subtitlePreset => _settings.subtitlePreset;
  String get primaryFontFamily => _settings.primaryFontFamily;
  String get secondaryFontFamily => _settings.secondaryFontFamily;
  double get primaryFontSize => _settings.primaryFontSize;
  double get secondaryFontSize => _settings.secondaryFontSize;
  double get subtitlePositionX => _settings.subtitlePositionX;
  double get subtitlePositionY => _settings.subtitlePositionY;
  double get subtitleBackgroundOpacity => _settings.subtitleBackgroundOpacity;
  double get transcriptWidth => _settings.transcriptWidth;
  double get workbenchMediaFraction => _settings.workbenchMediaFraction;
  String get lastMediaPath => _settings.lastMediaPath;
  String get lastMediaTitle => _settings.lastMediaTitle;
  int get lastMediaPositionMs => _settings.lastMediaPositionMs;
  int get lastMediaDurationMs => _settings.lastMediaDurationMs;
  int get lastMediaSubtitleCount => _settings.lastMediaSubtitleCount;
  double get volume => _settings.volume;
  double get rate => _settings.rate;
  bool get subtitlesVisible => _settings.subtitlesVisible;
  bool get secondarySubtitlesVisible => _settings.secondarySubtitlesVisible;
  bool get statusStylesVisible => _settings.statusStylesVisible;
  String get ffmpegPath => _settings.ffmpegPath;
  String get ffprobePath => _settings.ffprobePath;
  String get ytDlpPath => _settings.ytDlpPath;
  String get openSubtitlesApiKey => _settings.openSubtitlesApiKey;
  bool get wordSyncVisible => _settings.wordSyncVisible;
  String get groupingMode => _settings.groupingMode;

  /// How the transcript pairs the two subtitle tracks. It is a habit that
  /// changes several times inside one session — check the translation, hide
  /// it again, test yourself — so it persists like the other display choices
  /// rather than resetting per media.
  TranscriptTranslation get transcriptTranslation =>
      TranscriptTranslation.fromStorage(_settings.transcriptTranslation);

  Future<void> setTranscriptTranslation(TranscriptTranslation value) {
    if (transcriptTranslation == value) return Future.value();
    _settings = _settings.copyWith(transcriptTranslation: value.storageValue);
    notifyListeners();
    return save();
  }

  bool get chunkHighlightActive => _settings.chunkHighlightActive;
  String get chunkDisplayStyle => _settings.chunkDisplayStyle;
  bool get highlightCurrentChunk => _settings.highlightCurrentChunk;
  String get chunkHighlightStyle => _settings.chunkHighlightStyle;
  String get wordHighlightStyle => _settings.wordHighlightStyle;
  double get wordAnimationIntensity => _settings.wordAnimationIntensity;
  String get ruleHintsLevel => _settings.ruleHintsLevel;
  String get phoneticAnalysisPreference => _settings.phoneticAnalysisPreference;
  String get soundPatternDisplayMode => _settings.soundPatternDisplayMode;
  String get phonemeRibbonStyle => _settings.phonemeRibbonStyle;
  String get learningLanguage => _settings.learningLanguage;

  /// Resolves the effective learning language for vocabulary, dictionary,
  /// source-snapshot and diagnosis queries. Priority: user setting > active
  /// subtitle track language > `en` fallback.
  String resolveLearningLanguage(String? trackLanguage) {
    final preferred = _settings.learningLanguage;
    if (preferred != 'auto') return preferred;
    return trackLanguage ?? 'en';
  }

  bool get familiarMaterialSuggestions => _settings.familiarMaterialSuggestions;
  bool get markKeysEnabled => _settings.markKeysEnabled;
  bool get realtimeCaptionVisible => _settings.realtimeCaptionVisible;
  Color get primaryColor => Color(_settings.primaryColor);

  /// Remembers the lobby's caption switch (#85 · S8). The choice is a habit,
  /// not a per-conversation decision, so it survives the app restart.
  Future<void> setRealtimeCaptionVisible(bool value) {
    if (_settings.realtimeCaptionVisible == value) return Future.value();
    _settings = _settings.copyWith(realtimeCaptionVisible: value);
    notifyListeners();
    return save();
  }

  Color get secondaryColor => Color(_settings.secondaryColor);

  // ── Managed asset store location ──

  ManagedStoreState _managedStoreState = ManagedStoreState.appManaged;

  /// The persisted path together with what the disk says about it. Resolved
  /// when the path changes and on demand, never on every read: this is disk
  /// I/O, and a getter that touched the filesystem would run inside `build`.
  ///
  /// When no custom location is stored the pair carries the app-managed
  /// default store ([AppSettings.defaultManagedStorePath]) with the `default`
  /// verdict, so every state shows a real location.
  ManagedStoreLocation get managedStoreLocation => (
    path: _settings.mediaLibraryPath.isEmpty
        ? AppSettings.defaultManagedStorePath
        : _settings.mediaLibraryPath,
    state: _managedStoreState,
  );

  /// The stored custom managed-store path (empty when the default applies).
  String get managedStorePath => _settings.mediaLibraryPath;

  /// Opens the folder chooser and adopts the result. A cancelled picker
  /// returns the location unchanged — cancelling must never clear what the
  /// user had.
  Future<ManagedStoreLocation> chooseManagedStoreLocation({
    required String confirmButtonText,
  }) async {
    final picked = await files.pickDownloadDirectory(
      confirmButtonText: confirmButtonText,
    );
    if (picked == null || picked.isEmpty) return managedStoreLocation;
    return setManagedStorePath(picked);
  }

  /// Records the folder the user picked. Its state is resolved before the
  /// notification so listeners never see a new path next to the old verdict.
  Future<ManagedStoreLocation> setManagedStorePath(String path) async {
    _settings = _settings.copyWith(mediaLibraryPath: path);
    _managedStoreState = await _settings.resolveManagedStoreState();
    notifyListeners();
    await save();
    return managedStoreLocation;
  }

  /// Forgets the custom location, returning the store to the app-managed
  /// default. Distinct from a location that went missing — this is the user
  /// saying they no longer have one.
  Future<ManagedStoreLocation> clearManagedStoreLocation() =>
      setManagedStorePath('');

  /// Re-checks the disk, e.g. after an unmounted volume came back.
  Future<void> refreshManagedStoreState() async {
    final next = await _settings.resolveManagedStoreState();
    if (next == _managedStoreState) return;
    _managedStoreState = next;
    notifyListeners();
  }

  /// Load settings from disk and notify listeners.
  Future<void> load() async {
    _settings = await AppSettings.load();
    _managedStoreState = await _settings.resolveManagedStoreState();
    notifyListeners();
  }

  /// Persist current settings to disk.
  Future<void> save() {
    _saveDebounce?.cancel();
    return _settings.save();
  }

  Timer? _saveDebounce;

  /// Coalesce rapid persistence (drag ratios, playback progress) into a single
  /// disk write so high-frequency updates do not rewrite the settings file on
  /// every event.
  void saveSoon({Duration delay = const Duration(milliseconds: 600)}) {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(delay, () => unawaited(_settings.save()));
  }

  /// Record the currently playing media so the home surface can offer a real
  /// "continue" entry and honest readiness at the next cold start. Updates in
  /// memory silently (no rebuild storm during playback) and persists lazily.
  void recordRecentMedia({
    required String path,
    required String title,
    required int positionMs,
    required int durationMs,
    required int subtitleCount,
  }) {
    if (path.isEmpty) return;
    _settings = _settings.copyWith(
      lastMediaPath: path,
      lastMediaTitle: title,
      lastMediaPositionMs: positionMs < 0 ? 0 : positionMs,
      lastMediaDurationMs: durationMs < 0 ? 0 : durationMs,
      lastMediaSubtitleCount: subtitleCount < 0 ? 0 : subtitleCount,
    );
    saveSoon();
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    super.dispose();
  }

  /// Atomically apply an update, notify listeners, and persist.
  Future<void> update(AppSettings next) async {
    _settings = next;
    notifyListeners();
    await _settings.save();
  }

  /// Replace settings in memory without persisting (for initialization).
  void setSettings(AppSettings value) {
    _settings = value;
    notifyListeners();
  }
}
