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
  String get subtitlePreset => _settings.subtitlePreset;
  String get primaryFontFamily => _settings.primaryFontFamily;
  String get secondaryFontFamily => _settings.secondaryFontFamily;
  double get primaryFontSize => _settings.primaryFontSize;
  double get secondaryFontSize => _settings.secondaryFontSize;
  double get subtitlePositionX => _settings.subtitlePositionX;
  double get subtitlePositionY => _settings.subtitlePositionY;
  double get subtitleBackgroundOpacity => _settings.subtitleBackgroundOpacity;
  double get transcriptWidth => _settings.transcriptWidth;
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
  bool get pronunciationVisible => _settings.pronunciationVisible;
  bool get wordSyncVisible => _settings.wordSyncVisible;
  String get phonemeDisplay => _settings.phonemeDisplay;
  String get wordHighlightStyle => _settings.wordHighlightStyle;
  double get wordAnimationIntensity => _settings.wordAnimationIntensity;
  String get ruleHintsLevel => _settings.ruleHintsLevel;
  bool get precomputePronunciation => _settings.precomputePronunciation;
  Color get primaryColor => Color(_settings.primaryColor);
  Color get secondaryColor => Color(_settings.secondaryColor);

  /// Load settings from disk and notify listeners.
  Future<void> load() async {
    _settings = await AppSettings.load();
    notifyListeners();
  }

  /// Persist current settings to disk.
  Future<void> save() => _settings.save();

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
