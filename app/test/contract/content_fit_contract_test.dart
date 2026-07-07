import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/types.dart';

/// Committed fixture contract tests for ContentDifficultyProfile DTOs.
/// Validates that the Dart DTO shape matches the Rust API response shape
/// documented in contracts/openapi/v1.yaml (ADR 0018).
void main() {
  const fixture = {
    'subject_kind': 'media',
    'subject_id': 'media-1',
    'language': 'en',
    'meaning': {
      'fit': 'comprehensible',
      'signals': [
        {'kind': 'unknown_meaning_density', 'value': 0.03, 'decisive': true},
        {'kind': 'unassessed_density', 'value': 0.01, 'decisive': true},
      ],
    },
    'sound': {
      'fit': 'challenging',
      'signals': [
        {
          'kind': 'known_not_recognized_density',
          'value': 0.06,
          'decisive': true,
        },
        {'kind': 'speech_rate_wpm', 'value': 152.0, 'decisive': false},
        {'kind': 'weak_form_density', 'value': 0.12, 'decisive': false},
      ],
    },
    'assessed_token_ratio': 0.99,
    'evidence_grade': 'initial_estimate',
    'algorithm_version': 'content-fit-v1',
    'computed_at_ms': 1700000000000,
    'input_fingerprint':
        '0000000000000000000000000000000000000000000000000000000000000000',
  };

  group('ContentDifficultyProfile', () {
    test('parses the dual-dimension wire shape', () {
      final profile = ContentDifficultyProfile.fromJson(fixture);
      expect(profile.subjectKind, 'media');
      expect(profile.language, 'en');
      expect(profile.meaning.fit, 'comprehensible');
      expect(profile.sound.fit, 'challenging');
      expect(profile.meaning.signals, hasLength(2));
      expect(profile.sound.signals, hasLength(3));
      expect(profile.sound.decisiveSignals.map((s) => s.kind), [
        'known_not_recognized_density',
      ]);
      expect(profile.evidenceGrade, 'initial_estimate');
      expect(profile.usageCalibrated, isFalse);
      expect(profile.algorithmVersion, 'content-fit-v1');
    });

    test('golden target derivation: meaning easy x sound hard', () {
      final profile = ContentDifficultyProfile.fromJson(fixture);
      expect(profile.isIntensiveListeningTarget, isTrue);

      final hardMeaning = ContentDifficultyProfile.fromJson({
        ...fixture,
        'meaning': {'fit': 'too_hard', 'signals': <Object>[]},
      });
      expect(hardMeaning.isIntensiveListeningTarget, isFalse);

      final easySound = ContentDifficultyProfile.fromJson({
        ...fixture,
        'sound': {'fit': 'too_easy', 'signals': <Object>[]},
      });
      expect(easySound.isIntensiveListeningTarget, isFalse);
    });

    test('honesty threshold mirrors backend MIN_ASSESSED_TOKEN_RATIO', () {
      final confident = ContentDifficultyProfile.fromJson(fixture);
      expect(confident.hasSufficientVocabularyProfile, isTrue);

      final degraded = ContentDifficultyProfile.fromJson({
        ...fixture,
        'assessed_token_ratio': 0.2,
      });
      expect(degraded.hasSufficientVocabularyProfile, isFalse);
    });

    test('round-trips through toJson', () {
      final profile = ContentDifficultyProfile.fromJson(fixture);
      final roundTripped = ContentDifficultyProfile.fromJson(profile.toJson());
      expect(roundTripped.toJson(), profile.toJson());
      expect(roundTripped.sound.signals[1].value, closeTo(152.0, 1e-9));
    });

    test('missing signals default to an empty list, not a crash', () {
      final profile = ContentDifficultyProfile.fromJson({
        ...fixture,
        'meaning': {'fit': 'too_easy'},
      });
      expect(profile.meaning.signals, isEmpty);
    });
  });
}
