import 'dart:convert';
import 'dart:io';

const _appSupportDirectoryName = 'listen';
const _legacyAppSupportDirectoryName = 'LLPlayerNext';

class AppSettings {
  const AppSettings({
    this.version = 8,
    this.rate = 1,
    this.volume = 100,
    this.primarySubtitleOffsetMs = 0,
    this.secondarySubtitleOffsetMs = 0,
    this.subtitlesVisible = true,
    this.secondarySubtitlesVisible = true,
    this.statusStylesVisible = true,
    this.primaryFontSize = 1,
    this.secondaryFontSize = 1,
    this.primaryFontFamily = 'system',
    this.secondaryFontFamily = 'system',
    this.subtitlePreset = 'learning',
    this.language = 'system',
    this.themeMode = 'dark',
    this.subtitlePositionX = 0.5,
    this.subtitlePositionY = 0.82,
    this.subtitleBackgroundOpacity = 0.72,
    this.primaryColor = 0xffffffff,
    this.secondaryColor = 0xffb8d8ff,
    this.transcriptWidth = 430,
    this.workbenchMediaFraction = 0.42,
    this.lastMediaPath = '',
    this.lastMediaTitle = '',
    this.lastMediaPositionMs = 0,
    this.lastMediaDurationMs = 0,
    this.lastMediaSubtitleCount = 0,
    this.ffmpegPath = '',
    this.ffprobePath = '',
    this.ytDlpPath = '',
    this.transcriptionQuality = 'balanced',
    this.transcriptionLanguage = 'auto',
    this.transcriptionDestination = 'primary',
    this.openSubtitlesApiKey = '',
    this.pronunciationVisible = true,
    this.wordSyncVisible = true,
    this.groupingMode = 'off',
    this.chunkDisplayStyle = 'capsule',
    this.highlightCurrentChunk = false,
    this.chunkHighlightStyle = 'background',
    this.phonemeDisplay = 'ipa',
    this.wordHighlightStyle = 'background',
    this.wordAnimationIntensity = 0.35,
    this.ruleHintsLevel = 'likely',
    this.precomputePronunciation = true,
    this.phoneticProviderId = '',
    this.phoneticModelId = '',
    this.phoneticAnalysisPreference = 'on_demand',
    this.showExperimentalPhoneticResults = false,
    this.phonemeHighlightVisible = true,
    this.phonemeRibbonVisible = false,
    this.soundPatternRibbonVisible = false,
    this.soundPatternDisplayMode = 'actual',
    this.phonemeRibbonStyle = 'window',
    this.phoneticCachePolicy = 'keep_completed',
    this.learningLanguage = 'auto',
    this.familiarMaterialSuggestions = true,
  });

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final version = json['version'] as int?;
    if (version != 1 &&
        version != 2 &&
        version != 3 &&
        version != 4 &&
        version != 5 &&
        version != 6 &&
        version != 7 &&
        version != 8) {
      return const AppSettings();
    }
    final legacyBottomPadding = _number(
      json['subtitle_bottom_padding'],
      48,
      0,
      400,
    );
    return AppSettings(
      rate: _number(json['rate'], 1, 0.25, 4),
      volume: _number(json['volume'], 100, 0, 100),
      primarySubtitleOffsetMs:
          json['primary_subtitle_offset_ms'] as int? ??
          json['subtitle_offset_ms'] as int? ??
          0,
      secondarySubtitleOffsetMs:
          json['secondary_subtitle_offset_ms'] as int? ?? 0,
      subtitlesVisible: json['subtitles_visible'] as bool? ?? true,
      secondarySubtitlesVisible:
          json['secondary_subtitles_visible'] as bool? ?? true,
      statusStylesVisible: json['status_styles_visible'] as bool? ?? true,
      primaryFontSize: version! >= 3
          ? _number(json['primary_font_size'], 1, 0.5, 2)
          : (_number(json['primary_font_size'], 24, 12, 72) / 24).clamp(
              0.5,
              2.0,
            ),
      secondaryFontSize: version >= 3
          ? _number(json['secondary_font_size'], 1, 0.5, 2)
          : (_number(json['secondary_font_size'], 18, 10, 64) / 18).clamp(
              0.5,
              2.0,
            ),
      primaryFontFamily: json['primary_font_family'] as String? ?? 'system',
      secondaryFontFamily: json['secondary_font_family'] as String? ?? 'system',
      subtitlePreset: json['subtitle_preset'] as String? ?? 'learning',
      language: json['language'] as String? ?? 'system',
      themeMode: json['theme_mode'] as String? ?? 'dark',
      subtitlePositionX: _number(json['subtitle_position_x'], 0.5, 0, 1),
      subtitlePositionY: version >= 4
          ? _number(json['subtitle_position_y'], 0.82, 0, 1)
          : (1 - legacyBottomPadding / 600).clamp(0.05, 0.95),
      subtitleBackgroundOpacity: _number(
        json['subtitle_background_opacity'],
        0.72,
        0,
        1,
      ),
      primaryColor: json['primary_color'] as int? ?? 0xffffffff,
      secondaryColor: json['secondary_color'] as int? ?? 0xffb8d8ff,
      transcriptWidth: _number(json['transcript_width'], 430, 260, 900),
      workbenchMediaFraction: _number(
        json['workbench_media_fraction'],
        0.42,
        0.3,
        0.62,
      ),
      lastMediaPath: json['last_media_path'] as String? ?? '',
      lastMediaTitle: json['last_media_title'] as String? ?? '',
      lastMediaPositionMs: json['last_media_position_ms'] as int? ?? 0,
      lastMediaDurationMs: json['last_media_duration_ms'] as int? ?? 0,
      lastMediaSubtitleCount: json['last_media_subtitle_count'] as int? ?? 0,
      ffmpegPath: json['ffmpeg_path'] as String? ?? '',
      ffprobePath: json['ffprobe_path'] as String? ?? '',
      ytDlpPath: json['yt_dlp_path'] as String? ?? '',
      transcriptionQuality:
          json['transcription_quality'] as String? ?? 'balanced',
      transcriptionLanguage:
          json['transcription_language'] as String? ?? 'auto',
      transcriptionDestination:
          json['transcription_destination'] as String? ?? 'primary',
      openSubtitlesApiKey: json['opensubtitles_api_key'] as String? ?? '',
      pronunciationVisible: json['pronunciation_visible'] as bool? ?? true,
      wordSyncVisible: json['word_sync_visible'] as bool? ?? true,
      groupingMode: _groupingMode(
        json['grouping_mode'],
        // Legacy independent toggles (pre-unification). Missing chunk flag
        // preserves the historical default of showing prosodic chunks.
        json['show_chunk_grouping'] as bool? ?? true,
        json['show_sense_grouping'] as bool? ?? false,
      ),
      chunkDisplayStyle: _chunkDisplayStyle(json['chunk_display_style']),
      highlightCurrentChunk: version >= 8
          ? json['highlight_current_chunk'] as bool? ?? false
          : false,
      chunkHighlightStyle: _chunkHighlightStyle(json['chunk_highlight_style']),
      phonemeDisplay: json['phoneme_display'] as String? ?? 'ipa',
      wordHighlightStyle: _wordHighlightStyle(json['word_highlight_style']),
      wordAnimationIntensity: _number(
        json['word_animation_intensity'],
        0.35,
        0,
        1,
      ),
      ruleHintsLevel: json['rule_hints_level'] as String? ?? 'likely',
      precomputePronunciation:
          json['precompute_pronunciation'] as bool? ?? true,
      phoneticProviderId: json['phonetic_provider_id'] as String? ?? '',
      phoneticModelId: json['phonetic_model_id'] as String? ?? '',
      phoneticAnalysisPreference:
          json['phonetic_analysis_preference'] as String? ?? 'on_demand',
      showExperimentalPhoneticResults:
          json['show_experimental_phonetic_results'] as bool? ?? false,
      phonemeHighlightVisible:
          json['phoneme_highlight_visible'] as bool? ?? true,
      phonemeRibbonVisible: json['phoneme_ribbon_visible'] as bool? ?? false,
      soundPatternRibbonVisible:
          json['sound_pattern_ribbon_visible'] as bool? ?? false,
      soundPatternDisplayMode: _soundPatternDisplayMode(
        json['sound_pattern_display_mode'],
      ),
      phonemeRibbonStyle: _phonemeRibbonStyle(json['phoneme_ribbon_style']),
      phoneticCachePolicy:
          json['phonetic_cache_policy'] as String? ?? 'keep_completed',
      learningLanguage: json['learning_language'] as String? ?? 'auto',
      familiarMaterialSuggestions:
          json['familiar_material_suggestions'] as bool? ?? true,
    );
  }

  final int version;
  final double rate;
  final double volume;
  final int primarySubtitleOffsetMs;
  final int secondarySubtitleOffsetMs;
  final bool subtitlesVisible;
  final bool secondarySubtitlesVisible;
  final bool statusStylesVisible;
  final double primaryFontSize;
  final double secondaryFontSize;
  final String primaryFontFamily;
  final String secondaryFontFamily;
  final String subtitlePreset;
  final String language;

  /// Appearance preference: `system`, `light`, or `dark`.
  final String themeMode;
  final double subtitlePositionX;
  final double subtitlePositionY;
  final double subtitleBackgroundOpacity;
  final int primaryColor;
  final int secondaryColor;
  final double transcriptWidth;
  final double workbenchMediaFraction;
  final String lastMediaPath;
  final String lastMediaTitle;
  final int lastMediaPositionMs;
  final int lastMediaDurationMs;
  final int lastMediaSubtitleCount;
  final String ffmpegPath;
  final String ffprobePath;
  final String ytDlpPath;
  final String transcriptionQuality;
  final String transcriptionLanguage;
  final String transcriptionDestination;
  final String openSubtitlesApiKey;
  final bool pronunciationVisible;
  final bool wordSyncVisible;

  /// Unified subtitle grouping presentation. One of:
  /// `off`, `prosodic` (chunk capsules), `semantic` (sense-group capsules),
  /// `compare` (prosodic base + divergence markers). The prosodic and semantic
  /// data layers stay separate per ADR 0016; this only unifies how a single
  /// active grouping is drawn.
  final String groupingMode;
  final String chunkDisplayStyle;
  final bool highlightCurrentChunk;
  final String chunkHighlightStyle;

  /// The live "current group" highlight only tracks prosodic chunks, so it is
  /// active only when chunk-based capsules are on screen (prosodic base, or the
  /// prosodic base of compare mode).
  bool get chunkHighlightActive =>
      (groupingMode == 'prosodic' || groupingMode == 'compare') &&
      highlightCurrentChunk;
  final String phonemeDisplay;
  final String wordHighlightStyle;
  final double wordAnimationIntensity;
  final String ruleHintsLevel;
  final bool precomputePronunciation;
  final String phoneticProviderId;
  final String phoneticModelId;
  final String phoneticAnalysisPreference;
  final bool showExperimentalPhoneticResults;
  final bool phonemeHighlightVisible;
  final bool phonemeRibbonVisible;
  final bool soundPatternRibbonVisible;
  final String soundPatternDisplayMode;
  final String phonemeRibbonStyle;
  final String phoneticCachePolicy;
  final String learningLanguage;

  /// Whether familiar-material marks (3.2) feed the extensive-listening
  /// queue suggestion on the home media library (restrained, off-switchable).
  final bool familiarMaterialSuggestions;

  static String get _home => Platform.environment['HOME'] ?? '';

  static Directory get _supportDirectory =>
      Directory('$_home/Library/Application Support/$_appSupportDirectoryName');

  static Directory get _legacySupportDirectory => Directory(
    '$_home/Library/Application Support/$_legacyAppSupportDirectoryName',
  );

  static File get file => File('${_supportDirectory.path}/settings-v8.json');

  static Future<AppSettings> load() async {
    for (final candidate in [
      file,
      ...List.generate(
        8,
        (index) =>
            File('${_legacySupportDirectory.path}/settings-v${8 - index}.json'),
      ),
    ]) {
      try {
        return AppSettings.fromJson(
          jsonDecode(await candidate.readAsString()) as Map<String, dynamic>,
        );
      } catch (_) {
        // Try the previous settings location, then safe defaults.
      }
    }
    return const AppSettings();
  }

  Future<void> save() async {
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'version': version,
        'rate': rate,
        'volume': volume,
        'primary_subtitle_offset_ms': primarySubtitleOffsetMs,
        'secondary_subtitle_offset_ms': secondarySubtitleOffsetMs,
        'subtitles_visible': subtitlesVisible,
        'secondary_subtitles_visible': secondarySubtitlesVisible,
        'status_styles_visible': statusStylesVisible,
        'primary_font_size': primaryFontSize,
        'secondary_font_size': secondaryFontSize,
        'primary_font_family': primaryFontFamily,
        'secondary_font_family': secondaryFontFamily,
        'subtitle_preset': subtitlePreset,
        'language': language,
        'theme_mode': themeMode,
        'subtitle_position_x': subtitlePositionX,
        'subtitle_position_y': subtitlePositionY,
        'subtitle_background_opacity': subtitleBackgroundOpacity,
        'primary_color': primaryColor,
        'secondary_color': secondaryColor,
        'transcript_width': transcriptWidth,
        'workbench_media_fraction': workbenchMediaFraction,
        'last_media_path': lastMediaPath,
        'last_media_title': lastMediaTitle,
        'last_media_position_ms': lastMediaPositionMs,
        'last_media_duration_ms': lastMediaDurationMs,
        'last_media_subtitle_count': lastMediaSubtitleCount,
        'ffmpeg_path': ffmpegPath,
        'ffprobe_path': ffprobePath,
        'yt_dlp_path': ytDlpPath,
        'transcription_quality': transcriptionQuality,
        'transcription_language': transcriptionLanguage,
        'transcription_destination': transcriptionDestination,
        'opensubtitles_api_key': openSubtitlesApiKey,
        'pronunciation_visible': pronunciationVisible,
        'word_sync_visible': wordSyncVisible,
        'grouping_mode': groupingMode,
        'chunk_display_style': chunkDisplayStyle,
        'highlight_current_chunk': highlightCurrentChunk,
        'chunk_highlight_style': chunkHighlightStyle,
        'phoneme_display': phonemeDisplay,
        'word_highlight_style': wordHighlightStyle,
        'word_animation_intensity': wordAnimationIntensity,
        'rule_hints_level': ruleHintsLevel,
        'precompute_pronunciation': precomputePronunciation,
        'phonetic_provider_id': phoneticProviderId,
        'phonetic_model_id': phoneticModelId,
        'phonetic_analysis_preference': phoneticAnalysisPreference,
        'show_experimental_phonetic_results': showExperimentalPhoneticResults,
        'phoneme_highlight_visible': phonemeHighlightVisible,
        'phoneme_ribbon_visible': phonemeRibbonVisible,
        'sound_pattern_ribbon_visible': soundPatternRibbonVisible,
        'sound_pattern_display_mode': soundPatternDisplayMode,
        'phoneme_ribbon_style': phonemeRibbonStyle,
        'phonetic_cache_policy': phoneticCachePolicy,
        'learning_language': learningLanguage,
        'familiar_material_suggestions': familiarMaterialSuggestions,
      }),
      flush: true,
    );
  }

  AppSettings copyWith({
    double? rate,
    double? volume,
    int? primarySubtitleOffsetMs,
    int? secondarySubtitleOffsetMs,
    bool? subtitlesVisible,
    bool? secondarySubtitlesVisible,
    bool? statusStylesVisible,
    double? primaryFontSize,
    double? secondaryFontSize,
    String? primaryFontFamily,
    String? secondaryFontFamily,
    String? subtitlePreset,
    String? language,
    String? themeMode,
    double? subtitlePositionX,
    double? subtitlePositionY,
    double? subtitleBackgroundOpacity,
    int? primaryColor,
    int? secondaryColor,
    double? transcriptWidth,
    double? workbenchMediaFraction,
    String? lastMediaPath,
    String? lastMediaTitle,
    int? lastMediaPositionMs,
    int? lastMediaDurationMs,
    int? lastMediaSubtitleCount,
    String? ffmpegPath,
    String? ffprobePath,
    String? ytDlpPath,
    String? transcriptionQuality,
    String? transcriptionLanguage,
    String? transcriptionDestination,
    String? openSubtitlesApiKey,
    bool? pronunciationVisible,
    bool? wordSyncVisible,
    String? groupingMode,
    String? chunkDisplayStyle,
    bool? highlightCurrentChunk,
    String? chunkHighlightStyle,
    String? phonemeDisplay,
    String? wordHighlightStyle,
    double? wordAnimationIntensity,
    String? ruleHintsLevel,
    bool? precomputePronunciation,
    String? phoneticProviderId,
    String? phoneticModelId,
    String? phoneticAnalysisPreference,
    bool? showExperimentalPhoneticResults,
    bool? phonemeHighlightVisible,
    bool? phonemeRibbonVisible,
    bool? soundPatternRibbonVisible,
    String? soundPatternDisplayMode,
    String? phonemeRibbonStyle,
    String? phoneticCachePolicy,
    String? learningLanguage,
    bool? familiarMaterialSuggestions,
  }) => AppSettings(
    version: version,
    rate: rate ?? this.rate,
    volume: volume ?? this.volume,
    primarySubtitleOffsetMs:
        primarySubtitleOffsetMs ?? this.primarySubtitleOffsetMs,
    secondarySubtitleOffsetMs:
        secondarySubtitleOffsetMs ?? this.secondarySubtitleOffsetMs,
    subtitlesVisible: subtitlesVisible ?? this.subtitlesVisible,
    secondarySubtitlesVisible:
        secondarySubtitlesVisible ?? this.secondarySubtitlesVisible,
    statusStylesVisible: statusStylesVisible ?? this.statusStylesVisible,
    primaryFontSize: primaryFontSize ?? this.primaryFontSize,
    secondaryFontSize: secondaryFontSize ?? this.secondaryFontSize,
    primaryFontFamily: primaryFontFamily ?? this.primaryFontFamily,
    secondaryFontFamily: secondaryFontFamily ?? this.secondaryFontFamily,
    subtitlePreset: subtitlePreset ?? this.subtitlePreset,
    language: language ?? this.language,
    themeMode: themeMode ?? this.themeMode,
    subtitlePositionX: subtitlePositionX ?? this.subtitlePositionX,
    subtitlePositionY: subtitlePositionY ?? this.subtitlePositionY,
    subtitleBackgroundOpacity:
        subtitleBackgroundOpacity ?? this.subtitleBackgroundOpacity,
    primaryColor: primaryColor ?? this.primaryColor,
    secondaryColor: secondaryColor ?? this.secondaryColor,
    transcriptWidth: transcriptWidth ?? this.transcriptWidth,
    workbenchMediaFraction:
        workbenchMediaFraction ?? this.workbenchMediaFraction,
    lastMediaPath: lastMediaPath ?? this.lastMediaPath,
    lastMediaTitle: lastMediaTitle ?? this.lastMediaTitle,
    lastMediaPositionMs: lastMediaPositionMs ?? this.lastMediaPositionMs,
    lastMediaDurationMs: lastMediaDurationMs ?? this.lastMediaDurationMs,
    lastMediaSubtitleCount:
        lastMediaSubtitleCount ?? this.lastMediaSubtitleCount,
    ffmpegPath: ffmpegPath ?? this.ffmpegPath,
    ffprobePath: ffprobePath ?? this.ffprobePath,
    ytDlpPath: ytDlpPath ?? this.ytDlpPath,
    transcriptionQuality: transcriptionQuality ?? this.transcriptionQuality,
    transcriptionLanguage: transcriptionLanguage ?? this.transcriptionLanguage,
    transcriptionDestination:
        transcriptionDestination ?? this.transcriptionDestination,
    openSubtitlesApiKey: openSubtitlesApiKey ?? this.openSubtitlesApiKey,
    pronunciationVisible: pronunciationVisible ?? this.pronunciationVisible,
    wordSyncVisible: wordSyncVisible ?? this.wordSyncVisible,
    groupingMode: groupingMode ?? this.groupingMode,
    chunkDisplayStyle: chunkDisplayStyle ?? this.chunkDisplayStyle,
    highlightCurrentChunk: highlightCurrentChunk ?? this.highlightCurrentChunk,
    chunkHighlightStyle: chunkHighlightStyle ?? this.chunkHighlightStyle,
    phonemeDisplay: phonemeDisplay ?? this.phonemeDisplay,
    wordHighlightStyle: wordHighlightStyle ?? this.wordHighlightStyle,
    wordAnimationIntensity:
        wordAnimationIntensity ?? this.wordAnimationIntensity,
    ruleHintsLevel: ruleHintsLevel ?? this.ruleHintsLevel,
    precomputePronunciation:
        precomputePronunciation ?? this.precomputePronunciation,
    phoneticProviderId: phoneticProviderId ?? this.phoneticProviderId,
    phoneticModelId: phoneticModelId ?? this.phoneticModelId,
    phoneticAnalysisPreference:
        phoneticAnalysisPreference ?? this.phoneticAnalysisPreference,
    showExperimentalPhoneticResults:
        showExperimentalPhoneticResults ?? this.showExperimentalPhoneticResults,
    phonemeHighlightVisible:
        phonemeHighlightVisible ?? this.phonemeHighlightVisible,
    phonemeRibbonVisible: phonemeRibbonVisible ?? this.phonemeRibbonVisible,
    soundPatternRibbonVisible:
        soundPatternRibbonVisible ?? this.soundPatternRibbonVisible,
    soundPatternDisplayMode:
        soundPatternDisplayMode ?? this.soundPatternDisplayMode,
    phonemeRibbonStyle: phonemeRibbonStyle ?? this.phonemeRibbonStyle,
    phoneticCachePolicy: phoneticCachePolicy ?? this.phoneticCachePolicy,
    learningLanguage: learningLanguage ?? this.learningLanguage,
    familiarMaterialSuggestions:
        familiarMaterialSuggestions ?? this.familiarMaterialSuggestions,
  );

  static double _number(
    Object? value,
    double fallback,
    double minimum,
    double maximum,
  ) => value is num ? value.toDouble().clamp(minimum, maximum) : fallback;

  static String _wordHighlightStyle(Object? value) =>
      value == 'bounce' || value == 'glow' ? value as String : 'background';

  static String _chunkDisplayStyle(Object? value) =>
      value == 'spacing' ? value as String : 'capsule';

  /// Resolves the unified grouping mode, migrating the two legacy independent
  /// booleans when no explicit `grouping_mode` is persisted yet. Precedence
  /// matches the pre-unification stacking rule: sense grouping wins, then chunk
  /// grouping, otherwise off.
  static String _groupingMode(Object? value, bool showChunk, bool showSense) {
    const allowed = {'off', 'prosodic', 'semantic', 'compare'};
    if (value is String && allowed.contains(value)) return value;
    if (showSense) return 'semantic';
    if (showChunk) return 'prosodic';
    return 'off';
  }

  static String _chunkHighlightStyle(Object? value) =>
      value == 'bounce' || value == 'glow' ? value as String : 'background';

  static String _phonemeRibbonStyle(Object? value) =>
      value == 'wave' ? value as String : 'window';

  static String _soundPatternDisplayMode(Object? value) => switch (value) {
    'citation' || 'connected' || 'actual' => value as String,
    // v8 compatibility: both legacy modes now enter the Rhythm C view.
    'rhythm' || 'phones' => 'actual',
    _ => 'actual',
  };
}
