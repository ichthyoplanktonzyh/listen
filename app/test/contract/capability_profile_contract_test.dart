import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/types.dart';

/// Committed fixture contract tests for LexicalCapabilityProfile DTOs.
/// Validates that the Dart DTO shape matches the Rust API response shape
/// documented in contracts/openapi/v1.yaml.
void main() {
  group('CapabilityDimensionState', () {
    test('empty JSON yields unassessed', () {
      final state = CapabilityDimensionState.fromJson(const {});
      expect(state.projection, isNull);
      expect(state.userOverride, isNull);
      expect(state.effectiveAssessment, 'unassessed');
    });

    test('projection without override yields projection conclusion', () {
      final state = CapabilityDimensionState.fromJson(const {
        'projection': {
          'conclusion': 'not_acquired',
          'source': 'legacy_migration',
          'algorithm_version': 'v1',
          'updated_at_ms': 1700000000000,
        },
      });
      expect(state.effectiveAssessment, 'not_acquired');
      expect(state.projection!.source, 'legacy_migration');
      expect(state.projection!.algorithmVersion, 'v1');
    });

    test('user override takes precedence over projection', () {
      final state = CapabilityDimensionState.fromJson(const {
        'projection': {
          'conclusion': 'not_acquired',
          'source': 'legacy_migration',
          'algorithm_version': 'v1',
          'updated_at_ms': 1700000000000,
        },
        'user_override': {
          'conclusion': 'acquired',
          'source': 'user_explicit',
          'updated_at_ms': 1700000001000,
        },
      });
      expect(state.effectiveAssessment, 'acquired');
    });

    test('round-trips through toJson', () {
      final state = CapabilityDimensionState.fromJson(const {
        'projection': {
          'conclusion': 'acquired',
          'source': 'evidence_counter',
          'algorithm_version': 'v1',
          'updated_at_ms': 1700000000000,
        },
      });
      final roundTripped = CapabilityDimensionState.fromJson(state.toJson());
      expect(roundTripped.effectiveAssessment, 'acquired');
      expect(roundTripped.projection!.source, 'evidence_counter');
    });
  });

  group('LexicalCapabilityProfile', () {
    test('parses full four-channel profile', () {
      final profile = LexicalCapabilityProfile.fromJson(const {
        'lexical_entry_id': 'entry-1',
        'sense_id': null,
        'reading': {
          'projection': {
            'conclusion': 'not_acquired',
            'source': 'legacy_migration',
            'algorithm_version': 'v1',
            'updated_at_ms': 1700000000000,
          },
        },
        'listening': {
          'projection': {
            'conclusion': 'not_acquired',
            'source': 'legacy_migration',
            'algorithm_version': 'v1',
            'updated_at_ms': 1700000000000,
          },
        },
        'speaking': {},
        'writing': {},
      });
      expect(profile.lexicalEntryId, 'entry-1');
      expect(profile.reading.effectiveAssessment, 'not_acquired');
      expect(profile.listening.effectiveAssessment, 'not_acquired');
      expect(profile.speaking.effectiveAssessment, 'unassessed');
      expect(profile.writing.effectiveAssessment, 'unassessed');
    });

    test('missing channel defaults to empty/unassessed', () {
      final profile = LexicalCapabilityProfile.fromJson(const {
        'lexical_entry_id': 'entry-2',
      });
      expect(profile.reading.effectiveAssessment, 'unassessed');
      expect(profile.listening.effectiveAssessment, 'unassessed');
    });

    test('round-trips through toJson', () {
      final profile = LexicalCapabilityProfile.fromJson(const {
        'lexical_entry_id': 'entry-3',
        'reading': {
          'projection': {
            'conclusion': 'acquired',
            'source': 'evidence_counter',
            'algorithm_version': 'v1',
            'updated_at_ms': 1700000000000,
          },
        },
        'listening': {
          'user_override': {
            'conclusion': 'acquired',
            'source': 'user_explicit',
            'updated_at_ms': 1700000001000,
          },
        },
        'speaking': {},
        'writing': {},
      });
      final json = profile.toJson();
      final roundTripped = LexicalCapabilityProfile.fromJson(json);
      expect(roundTripped.lexicalEntryId, 'entry-3');
      expect(roundTripped.reading.effectiveAssessment, 'acquired');
      expect(roundTripped.listening.effectiveAssessment, 'acquired');
    });
  });

  group('LexicalEntryDetails with capability_profile', () {
    test('parses optional capability_profile field', () {
      final details = LexicalEntryDetails.fromJson(const {
        'entry': {
          'id': 'e-1',
          'normalized_form': 'hello',
          'display_form': 'Hello',
          'kind': 'word',
          'language': 'en',
        },
        'history': [],
        'occurrences': [],
        'capability_profile': {
          'lexical_entry_id': 'e-1',
          'reading': {
            'projection': {
              'conclusion': 'acquired',
              'source': 'legacy_migration',
              'algorithm_version': 'v1',
              'updated_at_ms': 1700000000000,
            },
          },
          'listening': {},
          'speaking': {},
          'writing': {},
        },
      });
      expect(details.capabilityProfile, isNotNull);
      expect(details.capabilityProfile!.reading.effectiveAssessment, 'acquired');
      expect(
        details.capabilityProfile!.listening.effectiveAssessment,
        'unassessed',
      );
    });

    test('null capability_profile is allowed', () {
      final details = LexicalEntryDetails.fromJson(const {
        'entry': {
          'id': 'e-2',
          'normalized_form': 'world',
          'display_form': 'World',
          'kind': 'word',
          'language': 'en',
        },
        'history': [],
        'occurrences': [],
      });
      expect(details.capabilityProfile, isNull);
    });
  });

  group('LearningObservationView', () {
    test('parses the observation-history wire shape (ADR 0017 evidence row)', () {
      final view = LearningObservationView.fromJson(const {
        'id': 'obs-1',
        'lexical_entry_id': 'entry-1',
        'sense_id': null,
        'capability': 'reading',
        'task_type': 'reading_context_marking',
        'outcome': 'success',
        'assistance': 'none',
        'surface_form': 'quakes',
        'sentence_id': 'cue-1',
        'media_id': null,
        'origin': 'user_marking',
        'source_ref': 'reading-marking:cue-1',
        'occurred_at_ms': 1753142400000,
      });
      expect(view.id, 'obs-1');
      expect(view.lexicalEntryId, 'entry-1');
      expect(view.senseId, isNull);
      expect(view.capability, 'reading');
      expect(view.taskType, 'reading_context_marking');
      expect(view.outcome, 'success');
      expect(view.assistance, 'none');
      expect(view.surfaceForm, 'quakes');
      expect(view.sentenceId, 'cue-1');
      expect(view.mediaId, isNull);
      expect(view.origin, 'user_marking');
      expect(view.sourceRef, 'reading-marking:cue-1');
      expect(view.occurredAtMs, 1753142400000);
    });
  });
}
