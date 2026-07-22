part of '../timeline.dart';

// Subtitle tokens, cues, tracks, capabilities
// Split out of timeline.dart (mechanical decomposition).

class SubtitleToken {
  const SubtitleToken({
    required this.index,
    required this.kind,
    required this.text,
    required this.normalized,
  });

  factory SubtitleToken.fromJson(Map<String, dynamic> json) => SubtitleToken(
    index: json['index'] as int,
    kind: json['kind'] as String,
    text: json['text'] as String,
    normalized: json['normalized'] as String?,
  );

  final int index;
  final String kind;
  final String text;
  final String? normalized;
}

class Cue {
  const Cue({
    required this.id,
    required this.index,
    required this.start,
    required this.end,
    required this.text,
    required this.tokens,
  });

  factory Cue.fromJson(Map<String, dynamic> json) => Cue(
    id: json['id'] as String,
    index: json['index'] as int,
    start: Duration(milliseconds: json['start'] as int),
    end: Duration(milliseconds: json['end'] as int),
    text: json['display_text'] as String,
    tokens: (json['tokens'] as List<dynamic>)
        .map((value) => SubtitleToken.fromJson(value as Map<String, dynamic>))
        .toList(growable: false),
  );

  final String id;
  final int index;
  final Duration start;
  final Duration end;
  final String text;
  final List<SubtitleToken> tokens;
}

class SubtitleTrack {
  const SubtitleTrack({
    required this.id,
    required this.cues,
    this.mediaId,
    this.fingerprint,
    this.language,
    this.source = 'subtitle',
    this.status = 'available',
  });

  factory SubtitleTrack.fromJson(Map<String, dynamic> json) => SubtitleTrack(
    id: json['id'] as String,
    mediaId: json['media_id'] as String?,
    fingerprint: json['fingerprint'] as String?,
    language: json['language'] as String?,
    source: json['source'] as String? ?? 'subtitle',
    status: json['status'] as String? ?? 'available',
    cues: (json['sentences'] as List<dynamic>)
        .map((value) => Cue.fromJson(value as Map<String, dynamic>))
        .toList(growable: false),
  );

  final String id;
  final String? mediaId;
  final String? fingerprint;

  /// Learning language of this track (e.g. `en`, `zh`), resolved by the core at
  /// import time. Drives which language the vocabulary/dictionary/diagnosis
  /// queries run under; null when the core could not resolve one.
  final String? language;
  final String source;
  final String status;
  final List<Cue> cues;

  bool get archived => status == 'archived';
}

class SubtitleResourceCapabilities {
  const SubtitleResourceCapabilities({
    required this.sentenceTiming,
    required this.wordTiming,
    required this.chunkTiming,
    required this.phoneTiming,
    this.sentenceCount = 0,
    this.wordTimingCount = 0,
    this.chunkCount = 0,
    this.phoneCount = 0,
    this.error,
  });

  factory SubtitleResourceCapabilities.fromCounts({
    required int sentenceCount,
    required int wordTimingCount,
    required int chunkCount,
    required int phoneCount,
    String? error,
  }) => SubtitleResourceCapabilities(
    sentenceTiming: sentenceCount > 0,
    wordTiming: wordTimingCount > 0,
    chunkTiming: chunkCount > 0,
    phoneTiming: phoneCount > 0,
    sentenceCount: sentenceCount,
    wordTimingCount: wordTimingCount,
    chunkCount: chunkCount,
    phoneCount: phoneCount,
    error: error,
  );

  static const empty = SubtitleResourceCapabilities(
    sentenceTiming: false,
    wordTiming: false,
    chunkTiming: false,
    phoneTiming: false,
  );

  final bool sentenceTiming;
  final bool wordTiming;
  final bool chunkTiming;
  final bool phoneTiming;
  final int sentenceCount;
  final int wordTimingCount;
  final int chunkCount;
  final int phoneCount;
  final String? error;

  bool get hasAnyTiming =>
      sentenceTiming || wordTiming || chunkTiming || phoneTiming;
}
