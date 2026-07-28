import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../settings.dart';

/// Wraps [AppSettings] persistence with [ChangeNotifier] for reactive UI.
class SettingsController extends ChangeNotifier {
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
  String get transcriptionQuality => _settings.transcriptionQuality;
  String get transcriptionLanguage => _settings.transcriptionLanguage;
  String get transcriptionDestination => _settings.transcriptionDestination;
  String get openSubtitlesApiKey => _settings.openSubtitlesApiKey;
  bool get wordSyncVisible => _settings.wordSyncVisible;
  String get groupingMode => _settings.groupingMode;
  bool get chunkHighlightActive => _settings.chunkHighlightActive;
  String get chunkDisplayStyle => _settings.chunkDisplayStyle;
  bool get highlightCurrentChunk => _settings.highlightCurrentChunk;
  String get chunkHighlightStyle => _settings.chunkHighlightStyle;
  String get wordHighlightStyle => _settings.wordHighlightStyle;
  double get wordAnimationIntensity => _settings.wordAnimationIntensity;
  String get ruleHintsLevel => _settings.ruleHintsLevel;
  String get phoneticAnalysisPreference => _settings.phoneticAnalysisPreference;
  bool get phonemeRibbonVisible => _settings.phonemeRibbonVisible;
  bool get soundPatternRibbonVisible => _settings.soundPatternRibbonVisible;
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

  /// Load settings from disk and notify listeners.
  Future<void> load() async {
    _settings = await AppSettings.load();
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
