part of '../types.dart';

// Listening fit estimates, explainability, and calibration samples.

/// One explainability datum behind a listening-fit band. `decisive` marks
/// signals that selected or escalated the band; the rest are context.
class FitSignal {
  const FitSignal({
    required this.kind,
    required this.value,
    required this.decisive,
    this.contribution,
  });

  factory FitSignal.fromJson(Map<String, dynamic> json) => FitSignal(
    kind: json['kind'] as String,
    value: (json['value'] as num).toDouble(),
    decisive: json['decisive'] as bool? ?? false,
    contribution: (json['contribution'] as num?)?.toDouble(),
  );

  final String kind;
  final double value;
  final bool decisive;
  final double? contribution;

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'value': value,
    'decisive': decisive,
    if (contribution != null) 'contribution': contribution,
  };
}

/// One dimension of the media's fit for listening.
class DifficultyDimension {
  DifficultyDimension({
    required this.fit,
    required List<FitSignal> signals,
    this.score,
  }) : signals = List.unmodifiable(signals);

  factory DifficultyDimension.fromJson(Map<String, dynamic> json) =>
      DifficultyDimension(
        fit: json['fit'] as String,
        signals: (json['signals'] as List<dynamic>? ?? const [])
            .map(
              (value) =>
                  FitSignal.fromJson(Map<String, dynamic>.from(value as Map)),
            )
            .toList(growable: false),
        score: (json['score'] as num?)?.toDouble(),
      );

  final String fit;
  final List<FitSignal> signals;
  final double? score;

  List<FitSignal> get decisiveSignals =>
      signals.where((signal) => signal.decisive).toList(growable: false);

  Map<String, dynamic> toJson() => {
    'fit': fit,
    'signals': signals.map((signal) => signal.toJson()).toList(),
    if (score != null) 'score': score,
  };
}

/// Immutable feature values used by Core to explain and calibrate media fit.
/// A null value means the source evidence was unavailable, never zero.
class ContentFitFeatureSnapshot {
  ContentFitFeatureSnapshot(Map<String, dynamic> values)
    : values = Map.unmodifiable(values);

  factory ContentFitFeatureSnapshot.fromJson(Map<String, dynamic> json) =>
      ContentFitFeatureSnapshot(json);

  final Map<String, dynamic> values;

  double? value(String key) => (values[key] as num?)?.toDouble();

  Map<String, dynamic> toJson() => Map<String, dynamic>.from(values);
}

class ContentFitFeatureCoverage {
  ContentFitFeatureCoverage({
    required this.totalFeatures,
    required this.availableFeatures,
    required this.coverageRatio,
    required List<String> missingFeatures,
  }) : missingFeatures = List.unmodifiable(missingFeatures);

  factory ContentFitFeatureCoverage.fromJson(Map<String, dynamic> json) =>
      ContentFitFeatureCoverage(
        totalFeatures: json['total_features'] as int,
        availableFeatures: json['available_features'] as int,
        coverageRatio: (json['coverage_ratio'] as num).toDouble(),
        missingFeatures: (json['missing_features'] as List<dynamic>)
            .cast<String>(),
      );

  final int totalFeatures;
  final int availableFeatures;
  final double coverageRatio;
  final List<String> missingFeatures;

  Map<String, dynamic> toJson() => {
    'total_features': totalFeatures,
    'available_features': availableFeatures,
    'coverage_ratio': coverageRatio,
    'missing_features': missingFeatures,
  };
}

/// Meaning and sound difficulty for one AV learning material. Both dimensions
/// describe listening comprehension: transcript meaning and audio decoding.
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
    this.featureSnapshot,
    this.featureCoverage,
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
        featureSnapshot: json['feature_snapshot'] is Map
            ? ContentFitFeatureSnapshot.fromJson(
                Map<String, dynamic>.from(json['feature_snapshot'] as Map),
              )
            : null,
        featureCoverage: json['feature_coverage'] is Map
            ? ContentFitFeatureCoverage.fromJson(
                Map<String, dynamic>.from(json['feature_coverage'] as Map),
              )
            : null,
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
  final ContentFitFeatureSnapshot? featureSnapshot;
  final ContentFitFeatureCoverage? featureCoverage;

  bool get hasSufficientVocabularyProfile => assessedTokenRatio >= 0.5;
  bool get usageCalibrated => evidenceGrade == 'usage_calibrated';

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
    if (featureSnapshot != null) 'feature_snapshot': featureSnapshot!.toJson(),
    if (featureCoverage != null) 'feature_coverage': featureCoverage!.toJson(),
  };
}

class ContentFitCalibrationSample {
  const ContentFitCalibrationSample({
    required this.subjectKind,
    required this.subjectId,
    required this.language,
    required this.snapshot,
    required this.predictedMeaningScore,
    required this.predictedSoundScore,
    required this.predictedMeaningBand,
    required this.predictedSoundBand,
    required this.v2MeaningBand,
    required this.v2SoundBand,
    required this.observedDifficulty,
    required this.reportsUnderstoodAll,
    required this.reportsGotTheGist,
    required this.reportsUnclear,
    required this.practiceAttempts,
    required this.practiceCorrect,
    required this.sampledAtMs,
  });

  factory ContentFitCalibrationSample.fromJson(Map<String, dynamic> json) =>
      ContentFitCalibrationSample(
        subjectKind: json['subject_kind'] as String,
        subjectId: json['subject_id'] as String,
        language: json['language'] as String,
        snapshot: ContentFitFeatureSnapshot.fromJson(
          Map<String, dynamic>.from(json['snapshot'] as Map),
        ),
        predictedMeaningScore: (json['predicted_meaning_score'] as num)
            .toDouble(),
        predictedSoundScore: (json['predicted_sound_score'] as num).toDouble(),
        predictedMeaningBand: json['predicted_meaning_band'] as String,
        predictedSoundBand: json['predicted_sound_band'] as String,
        v2MeaningBand: json['v2_meaning_band'] as String,
        v2SoundBand: json['v2_sound_band'] as String,
        observedDifficulty: (json['observed_difficulty'] as num?)?.toDouble(),
        reportsUnderstoodAll: json['reports_understood_all'] as int,
        reportsGotTheGist: json['reports_got_the_gist'] as int,
        reportsUnclear: json['reports_unclear'] as int,
        practiceAttempts: json['practice_attempts'] as int,
        practiceCorrect: json['practice_correct'] as int,
        sampledAtMs: json['sampled_at_ms'] as int,
      );

  final String subjectKind;
  final String subjectId;
  final String language;
  final ContentFitFeatureSnapshot snapshot;
  final double predictedMeaningScore;
  final double predictedSoundScore;
  final String predictedMeaningBand;
  final String predictedSoundBand;
  final String v2MeaningBand;
  final String v2SoundBand;
  final double? observedDifficulty;
  final int reportsUnderstoodAll;
  final int reportsGotTheGist;
  final int reportsUnclear;
  final int practiceAttempts;
  final int practiceCorrect;
  final int sampledAtMs;
}
