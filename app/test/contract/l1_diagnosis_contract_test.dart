import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/types.dart';

/// Committed fixture contract test for the Phase 3.9 L1-aware diagnosis
/// additions. Validates that the Dart DTO shape matches the Rust API
/// response shape documented in contracts/openapi/v1.yaml (ADR 0014).
void main() {
  const fixture = {
    'sentence_id': 'sentence-1',
    'hints': [
      {
        'kind': 'other_factors',
        'message': 'Vocabulary does not explain the difficulty.',
        'lexical_entry_ids': <String>[],
        'reasons': <String>[],
      },
    ],
    'unclassified_lemmas': <String>[],
    'l1_context': {'l1': 'zh', 'l2': 'en', 'support': 'supported'},
    'l1_hints': [
      {
        'difficulty_kind': 'weak_function_words',
        'message': 'Function words backgrounded between stresses.',
        'families': ['rhythm.weak_group'],
        'spans': [
          {
            'family': 'rhythm.weak_group',
            'start_ms': 400,
            'end_ms': 900,
            'label': 'and the',
            'surface_text': 'and the',
          },
        ],
      },
    ],
  };

  group('Diagnosis (L1-aware)', () {
    test('parses the wire shape', () {
      final diagnosis = Diagnosis.fromJson(fixture);
      expect(diagnosis.l1Context, isNotNull);
      expect(diagnosis.l1Context!.l1, 'zh');
      expect(diagnosis.l1Context!.l2, 'en');
      expect(diagnosis.l1Context!.supported, isTrue);
      expect(diagnosis.l1Hints, hasLength(1));
      final hint = diagnosis.l1Hints.first;
      expect(hint.difficultyKind, 'weak_function_words');
      expect(hint.families, ['rhythm.weak_group']);
      expect(hint.spans, hasLength(1));
      expect(hint.spans.first.startMs, 400);
      expect(hint.spans.first.endMs, 900);
      expect(hint.spans.first.surfaceText, 'and the');
    });

    test('baseline diagnosis without an L1 stays byte-compatible', () {
      final diagnosis = Diagnosis.fromJson(const {
        'sentence_id': 'sentence-1',
        'hints': <Map<String, dynamic>>[],
        'unclassified_lemmas': <String>[],
      });
      expect(diagnosis.l1Context, isNull);
      expect(diagnosis.l1Hints, isEmpty);
    });

    test('unsupported pair reads as not supported', () {
      final diagnosis = Diagnosis.fromJson(const {
        'sentence_id': 'sentence-1',
        'hints': <Map<String, dynamic>>[],
        'unclassified_lemmas': <String>[],
        'l1_context': {'l1': 'ja', 'l2': 'en', 'support': 'unsupported_pair'},
        'l1_hints': <Map<String, dynamic>>[],
      });
      expect(diagnosis.l1Context!.supported, isFalse);
    });
  });

  group('LearnerProfileView', () {
    test('profile language axes stay independently typed', () {
      final profile = LearnerProfileView.fromJson(const {
        'l1_language': 'ja',
        'ui_language': 'zh',
        'active_l2_language': null,
        'updated_at_ms': 42,
      });
      expect(profile.l1Language, 'ja');
      expect(profile.uiLanguage, 'zh');
      expect(profile.activeL2Language, isNull);
      expect(profile.updatedAtMs, 42);
    });

    test('l1-specialty payload occurrences reuse the corpus DTO', () {
      const payload = {
        'difficulty_kind': 'weak_function_words',
        'families': ['rhythm.weak_group'],
        'indexed': true,
        'occurrences': [
          {
            'id': 'corpus-occurrence-1',
            'language': 'en',
            'kind': 'connected_speech',
            'normalized_key': 'rhythm.weak_group',
            'display_text': 'and the',
            'media_id': 'media-1',
            'track_id': 'track-1',
            'sentence_id': 'sentence-1',
            'start_ms': 400,
            'end_ms': 900,
            'source_snapshot': 'Grab the keys and the phone.',
          },
        ],
      };
      final specialty = L1SpecialtyView.fromJson(payload);
      final occurrence = specialty.occurrences.single;
      expect(specialty.indexed, isTrue);
      expect(occurrence.kind, 'connected_speech');
      expect(occurrence.normalizedKey, 'rhythm.weak_group');
    });
  });
}
