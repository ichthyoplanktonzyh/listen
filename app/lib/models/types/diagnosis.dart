part of '../types.dart';

// Sentence diagnosis and L1-aware hints.
// Split out of types.dart (mechanical decomposition).

// ──────────────────────────────────────────────
// Diagnosis
// ──────────────────────────────────────────────

class DiagnosisHint {
  const DiagnosisHint({
    required this.kind,
    this.lexicalEntryIds = const [],
    this.reasons = const [],
  });

  factory DiagnosisHint.fromJson(Map<String, dynamic> json) => DiagnosisHint(
    kind: json['kind'] as String,
    lexicalEntryIds: ((json['lexical_entry_ids'] as List<dynamic>?) ?? const [])
        .cast<String>()
        .toList(growable: false),
    reasons: ((json['reasons'] as List<dynamic>?) ?? const [])
        .cast<String>()
        .toList(growable: false),
  );

  final String kind;
  final List<String> lexicalEntryIds;
  final List<String> reasons;
}

/// Replayable audio span behind one L1 difficulty hint (Phase 3.9).
class L1DiagnosisSpan {
  const L1DiagnosisSpan({
    required this.family,
    required this.startMs,
    required this.endMs,
    required this.label,
    required this.surfaceText,
  });

  factory L1DiagnosisSpan.fromJson(Map<String, dynamic> json) =>
      L1DiagnosisSpan(
        family: json['family'] as String,
        startMs: json['start_ms'] as int,
        endMs: json['end_ms'] as int,
        label: json['label'] as String? ?? '',
        surfaceText: json['surface_text'] as String? ?? '',
      );

  final String family;
  final int startMs;
  final int endMs;
  final String label;
  final String surfaceText;
}

class L1DiagnosisHint {
  const L1DiagnosisHint({
    required this.difficultyKind,
    required this.message,
    this.families = const [],
    this.spans = const [],
  });

  factory L1DiagnosisHint.fromJson(Map<String, dynamic> json) =>
      L1DiagnosisHint(
        difficultyKind: json['difficulty_kind'] as String,
        message: json['message'] as String? ?? '',
        families: ((json['families'] as List<dynamic>?) ?? const [])
            .cast<String>()
            .toList(growable: false),
        spans: ((json['spans'] as List<dynamic>?) ?? const [])
            .map(
              (value) =>
                  L1DiagnosisSpan.fromJson(value as Map<String, dynamic>),
            )
            .toList(growable: false),
      );

  final String difficultyKind;
  final String message;
  final List<String> families;
  final List<L1DiagnosisSpan> spans;
}

class L1DiagnosisContext {
  const L1DiagnosisContext({
    required this.l1,
    required this.l2,
    required this.support,
  });

  factory L1DiagnosisContext.fromJson(Map<String, dynamic> json) =>
      L1DiagnosisContext(
        l1: json['l1'] as String,
        l2: json['l2'] as String,
        support: json['support'] as String? ?? 'supported',
      );

  final String l1;
  final String l2;
  final String support;

  bool get supported => support == 'supported';
}

class Diagnosis {
  const Diagnosis({
    this.hints = const [],
    this.l1Hints = const [],
    this.l1Context,
  });

  factory Diagnosis.fromJson(Map<String, dynamic> json) => Diagnosis(
    hints: ((json['hints'] as List<dynamic>?) ?? const [])
        .map((value) => DiagnosisHint.fromJson(value as Map<String, dynamic>))
        .toList(growable: false),
    l1Hints: ((json['l1_hints'] as List<dynamic>?) ?? const [])
        .map((value) => L1DiagnosisHint.fromJson(value as Map<String, dynamic>))
        .toList(growable: false),
    l1Context: json['l1_context'] == null
        ? null
        : L1DiagnosisContext.fromJson(
            json['l1_context'] as Map<String, dynamic>,
          ),
  );

  final List<DiagnosisHint> hints;
  final List<L1DiagnosisHint> l1Hints;
  final L1DiagnosisContext? l1Context;

  Map<String, dynamic> toJson() => {
    'hints': hints
        .map(
          (h) => {
            'kind': h.kind,
            'lexical_entry_ids': h.lexicalEntryIds,
            'reasons': h.reasons,
          },
        )
        .toList(),
    if (l1Context != null)
      'l1_context': {
        'l1': l1Context!.l1,
        'l2': l1Context!.l2,
        'support': l1Context!.support,
      },
    'l1_hints': l1Hints
        .map(
          (h) => {
            'difficulty_kind': h.difficultyKind,
            'message': h.message,
            'families': h.families,
            'spans': h.spans
                .map(
                  (s) => {
                    'family': s.family,
                    'start_ms': s.startMs,
                    'end_ms': s.endMs,
                    'label': s.label,
                    'surface_text': s.surfaceText,
                  },
                )
                .toList(),
          },
        )
        .toList(),
  };
}

// ──────────────────────────────────────────────
// Phrase Candidate
// ──────────────────────────────────────────────
class LearnerProfileView {
  const LearnerProfileView({
    this.l1Language,
    this.uiLanguage,
    this.activeL2Language,
    this.updatedAtMs,
  });

  factory LearnerProfileView.fromJson(Map<String, dynamic> json) =>
      LearnerProfileView(
        l1Language: json['l1_language'] as String?,
        uiLanguage: json['ui_language'] as String?,
        activeL2Language: json['active_l2_language'] as String?,
        updatedAtMs: json['updated_at_ms'] as int?,
      );

  final String? l1Language;
  final String? uiLanguage;
  final String? activeL2Language;
  final int? updatedAtMs;
}

class L1SpecialtyView {
  const L1SpecialtyView({
    required this.difficultyKind,
    required this.families,
    required this.indexed,
    required this.occurrences,
  });

  factory L1SpecialtyView.fromJson(Map<String, dynamic> json) =>
      L1SpecialtyView(
        difficultyKind: json['difficulty_kind'] as String,
        families: ((json['families'] as List<dynamic>?) ?? const [])
            .cast<String>()
            .toList(growable: false),
        indexed: json['indexed'] as bool? ?? false,
        occurrences: ((json['occurrences'] as List<dynamic>?) ?? const [])
            .map(
              (value) =>
                  CorpusOccurrence.fromJson(value as Map<String, dynamic>),
            )
            .toList(growable: false),
      );

  final String difficultyKind;
  final List<String> families;
  final bool indexed;
  final List<CorpusOccurrence> occurrences;
}
