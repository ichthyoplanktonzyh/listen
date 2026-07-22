part of '../types.dart';

// Content fit, media items, library/triage.
// Split out of types.dart (mechanical decomposition).

/// One explainability datum behind a content-fit band (ADR 0018). `decisive`
/// marks the signals that selected or escalated the band; the rest are
/// informational context.
class FitSignal {
  const FitSignal({
    required this.kind,
    required this.value,
    required this.decisive,
  });

  factory FitSignal.fromJson(Map<String, dynamic> json) => FitSignal(
    kind: json['kind'] as String,
    value: (json['value'] as num).toDouble(),
    decisive: json['decisive'] as bool? ?? false,
  );

  final String kind;
  final double value;
  final bool decisive;

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'value': value,
    'decisive': decisive,
  };
}

class DifficultyDimension {
  const DifficultyDimension({required this.fit, required this.signals});

  factory DifficultyDimension.fromJson(Map<String, dynamic> json) =>
      DifficultyDimension(
        fit: json['fit'] as String,
        signals: (json['signals'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map(
              (value) => FitSignal.fromJson(Map<String, dynamic>.from(value)),
            )
            .toList(),
      );

  final String fit;
  final List<FitSignal> signals;

  List<FitSignal> get decisiveSignals =>
      signals.where((signal) => signal.decisive).toList();

  Map<String, dynamic> toJson() => {
    'fit': fit,
    'signals': signals.map((signal) => signal.toJson()).toList(),
  };
}

/// Media-level dual-dimension content fit (ADR 0018). Bands are expectation
/// management, never gates: the UI may render them but must not hide, lock,
/// or discourage any material because of them.
class ContentDifficultyProfile {
  const ContentDifficultyProfile({
    required this.subjectKind,
    required this.subjectId,
    required this.language,
    required this.meaning,
    required this.sound,
    required this.assessedTokenRatio,
    required this.evidenceGrade,
    required this.algorithmVersion,
    required this.computedAtMs,
    required this.inputFingerprint,
  });

  factory ContentDifficultyProfile.fromJson(Map<String, dynamic> json) =>
      ContentDifficultyProfile(
        subjectKind: json['subject_kind'] as String,
        subjectId: json['subject_id'] as String,
        language: json['language'] as String,
        meaning: DifficultyDimension.fromJson(
          Map<String, dynamic>.from(json['meaning'] as Map),
        ),
        sound: DifficultyDimension.fromJson(
          Map<String, dynamic>.from(json['sound'] as Map),
        ),
        assessedTokenRatio: (json['assessed_token_ratio'] as num).toDouble(),
        evidenceGrade: json['evidence_grade'] as String,
        algorithmVersion: json['algorithm_version'] as String,
        computedAtMs: json['computed_at_ms'] as int,
        inputFingerprint: json['input_fingerprint'] as String,
      );

  final String subjectKind;
  final String subjectId;
  final String language;
  final DifficultyDimension meaning;
  final DifficultyDimension sound;
  final double assessedTokenRatio;
  final String evidenceGrade;
  final String algorithmVersion;
  final int computedAtMs;
  final String inputFingerprint;

  /// Mirrors the backend honesty threshold (MIN_ASSESSED_TOKEN_RATIO): below
  /// it the bands are a conservative guess and the degraded-estimate state
  /// must be shown instead of confident copy.
  bool get hasSufficientVocabularyProfile => assessedTokenRatio >= 0.5;

  bool get usageCalibrated => evidenceGrade == 'usage_calibrated';

  /// Golden target material: meaning is accessible but decoding is not
  /// (meaning comprehensible-or-easier, sound challenging-or-harder).
  bool get isIntensiveListeningTarget {
    const easier = {'too_easy', 'comprehensible'};
    const harder = {'challenging', 'too_hard'};
    return easier.contains(meaning.fit) && harder.contains(sound.fit);
  }

  Map<String, dynamic> toJson() => {
    'subject_kind': subjectKind,
    'subject_id': subjectId,
    'language': language,
    'meaning': meaning.toJson(),
    'sound': sound.toJson(),
    'assessed_token_ratio': assessedTokenRatio,
    'evidence_grade': evidenceGrade,
    'algorithm_version': algorithmVersion,
    'computed_at_ms': computedAtMs,
    'input_fingerprint': inputFingerprint,
  };
}

class ColdStartWordCandidate {
  const ColdStartWordCandidate({
    required this.displayForm,
    required this.normalizedForm,
    required this.occurrenceCount,
  });

  factory ColdStartWordCandidate.fromJson(Map<String, dynamic> json) =>
      ColdStartWordCandidate(
        displayForm: json['display_form'] as String,
        normalizedForm: json['normalized_form'] as String,
        occurrenceCount: json['occurrence_count'] as int,
      );

  final String displayForm;
  final String normalizedForm;
  final int occurrenceCount;

  Map<String, dynamic> toJson() => {
    'display_form': displayForm,
    'normalized_form': normalizedForm,
    'occurrence_count': occurrenceCount,
  };
}

/// Registered media as served by `GET /v1/media` (nested in
/// [MediaLibraryEntry]).
class MediaItem {
  const MediaItem({
    required this.id,
    required this.path,
    required this.fingerprint,
    required this.title,
    required this.kind,
    required this.durationMs,
    required this.availability,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  factory MediaItem.fromJson(Map<String, dynamic> json) => MediaItem(
    id: json['id'] as String,
    path: json['path'] as String,
    fingerprint: json['fingerprint'] as String,
    title: json['title'] as String,
    kind: json['kind'] as String,
    durationMs: json['duration'] as int?,
    availability: json['availability'] as String,
    createdAtMs: json['created_at_ms'] as int,
    updatedAtMs: json['updated_at_ms'] as int,
  );

  final String id;
  final String path;
  final String fingerprint;
  final String title;
  final String kind;
  final int? durationMs;
  final String availability;
  final int createdAtMs;
  final int updatedAtMs;

  Map<String, dynamic> toJson() => {
    'id': id,
    'path': path,
    'fingerprint': fingerprint,
    'title': title,
    'kind': kind,
    'duration': durationMs,
    'availability': availability,
    'created_at_ms': createdAtMs,
    'updated_at_ms': updatedAtMs,
  };
}

/// Triage queue names derived client-side from [MediaLibraryEntry] facts.
abstract final class TriageQueue {
  static const extensive = 'extensive';
  static const intensive = 'intensive';
  static const deferred = 'deferred';
  static const graduated = 'graduated';
}

/// One media-library row for triage (Phase 3.5 Slice 5): media plus the
/// facts queue grouping derives from. Queues only suggest — ignoring them
/// changes nothing about playback or learning behavior (P3/P5 red lines).
class MediaLibraryEntry {
  const MediaLibraryEntry({
    required this.media,
    required this.primaryTrackId,
    required this.fit,
    required this.triageIntent,
    required this.familiarMaterial,
  });

  factory MediaLibraryEntry.fromJson(Map<String, dynamic> json) =>
      MediaLibraryEntry(
        media: MediaItem.fromJson(
          Map<String, dynamic>.from(json['media'] as Map),
        ),
        primaryTrackId: json['primary_track_id'] as String?,
        fit: json['fit'] == null
            ? null
            : ContentDifficultyProfile.fromJson(
                Map<String, dynamic>.from(json['fit'] as Map),
              ),
        triageIntent: json['triage_intent'] as String?,
        familiarMaterial: json['familiar_material'] as bool? ?? false,
      );

  final MediaItem media;
  final String? primaryTrackId;
  final ContentDifficultyProfile? fit;

  /// 'pin_extensive' | 'pin_intensive' | 'defer' | 'graduated' | null.
  final String? triageIntent;
  final bool familiarMaterial;

  /// Golden target material: readable meaning, hard decoding.
  bool get isGoldenTarget => fit?.isIntensiveListeningTarget ?? false;

  /// Derives the suggested queue (ADR 0018 decision 6, all rules
  /// heuristic_proxy): explicit user intent wins, then the familiar-material
  /// relisten supply (when enabled), then fit bands — golden targets go to
  /// intensive, any too_hard dimension defers, everything else is extensive
  /// material. Returns null when no fact supports a suggestion.
  String? triageQueue({bool familiarSupply = true}) {
    switch (triageIntent) {
      case 'pin_extensive':
        return TriageQueue.extensive;
      case 'pin_intensive':
        return TriageQueue.intensive;
      case 'defer':
        return TriageQueue.deferred;
      case 'graduated':
        return TriageQueue.graduated;
    }
    if (familiarSupply && familiarMaterial) return TriageQueue.extensive;
    final fit = this.fit;
    if (fit == null) return null;
    if (fit.isIntensiveListeningTarget) return TriageQueue.intensive;
    if (fit.meaning.fit == 'too_hard' || fit.sound.fit == 'too_hard') {
      return TriageQueue.deferred;
    }
    return TriageQueue.extensive;
  }

  Map<String, dynamic> toJson() => {
    'media': media.toJson(),
    'primary_track_id': primaryTrackId,
    'fit': fit?.toJson(),
    'triage_intent': triageIntent,
    'familiar_material': familiarMaterial,
  };
}
