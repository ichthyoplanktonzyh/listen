import 'dart:convert';
import 'dart:io';

class AppSettings {
  const AppSettings({
    this.version = 6,
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
    this.subtitlePositionX = 0.5,
    this.subtitlePositionY = 0.82,
    this.subtitleBackgroundOpacity = 0.72,
    this.primaryColor = 0xffffffff,
    this.secondaryColor = 0xffb8d8ff,
    this.transcriptWidth = 430,
    this.ffmpegPath = '',
    this.ffprobePath = '',
    this.ytDlpPath = '',
    this.transcriptionQuality = 'balanced',
    this.transcriptionLanguage = 'auto',
    this.transcriptionDestination = 'primary',
    this.openSubtitlesApiKey = '',
  });

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final version = json['version'] as int?;
    if (version != 1 &&
        version != 2 &&
        version != 3 &&
        version != 4 &&
        version != 5 &&
        version != 6) {
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
      primaryFontSize: version == 3 || version == 4 || version == 5 || version == 6
          ? _number(json['primary_font_size'], 1, 0.5, 2)
          : (_number(json['primary_font_size'], 24, 12, 72) / 24).clamp(
              0.5,
              2.0,
            ),
      secondaryFontSize: version == 3 || version == 4 || version == 5 || version == 6
          ? _number(json['secondary_font_size'], 1, 0.5, 2)
          : (_number(json['secondary_font_size'], 18, 10, 64) / 18).clamp(
              0.5,
              2.0,
            ),
      primaryFontFamily: json['primary_font_family'] as String? ?? 'system',
      secondaryFontFamily: json['secondary_font_family'] as String? ?? 'system',
      subtitlePreset: json['subtitle_preset'] as String? ?? 'learning',
      language: json['language'] as String? ?? 'system',
      subtitlePositionX: _number(json['subtitle_position_x'], 0.5, 0, 1),
      subtitlePositionY: version == 4 || version == 5 || version == 6
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
  final double subtitlePositionX;
  final double subtitlePositionY;
  final double subtitleBackgroundOpacity;
  final int primaryColor;
  final int secondaryColor;
  final double transcriptWidth;
  final String ffmpegPath;
  final String ffprobePath;
  final String ytDlpPath;
  final String transcriptionQuality;
  final String transcriptionLanguage;
  final String transcriptionDestination;
  final String openSubtitlesApiKey;

  static File get file => File(
        '${Platform.environment['HOME']}/Library/Application Support/LLPlayerNext/settings-v6.json',
  );

  static Future<AppSettings> load() async {
    for (final candidate in [
      file,
      File(
        '${Platform.environment['HOME']}/Library/Application Support/LLPlayerNext/settings-v5.json',
      ),
      File(
        '${Platform.environment['HOME']}/Library/Application Support/LLPlayerNext/settings-v4.json',
      ),
      File(
        '${Platform.environment['HOME']}/Library/Application Support/LLPlayerNext/settings-v3.json',
      ),
      File(
        '${Platform.environment['HOME']}/Library/Application Support/LLPlayerNext/settings-v2.json',
      ),
      File(
        '${Platform.environment['HOME']}/Library/Application Support/LLPlayerNext/settings-v1.json',
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
        'subtitle_position_x': subtitlePositionX,
        'subtitle_position_y': subtitlePositionY,
        'subtitle_background_opacity': subtitleBackgroundOpacity,
        'primary_color': primaryColor,
        'secondary_color': secondaryColor,
        'transcript_width': transcriptWidth,
        'ffmpeg_path': ffmpegPath,
        'ffprobe_path': ffprobePath,
        'yt_dlp_path': ytDlpPath,
        'transcription_quality': transcriptionQuality,
        'transcription_language': transcriptionLanguage,
        'transcription_destination': transcriptionDestination,
        'opensubtitles_api_key': openSubtitlesApiKey,
      }),
      flush: true,
    );
  }

  static double _number(
    Object? value,
    double fallback,
    double minimum,
    double maximum,
  ) => value is num ? value.toDouble().clamp(minimum, maximum) : fallback;
}
