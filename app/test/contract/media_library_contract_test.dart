import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/types.dart';

/// Committed fixture contract tests for the media library DTOs (Phase 3.5
/// Slice 5). Validates the Dart shape against the Rust `GET /v1/media`
/// response documented in contracts/openapi/v1.yaml (ADR 0014 discipline).
void main() {
  const fitFixture = {
    'subject_kind': 'media',
    'subject_id': 'media-1',
    'language': 'en',
    'meaning': {
      'fit': 'comprehensible',
      'signals': [
        {'kind': 'unknown_meaning_density', 'value': 0.03, 'decisive': true},
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
      ],
    },
    'assessed_token_ratio': 0.99,
    'evidence_grade': 'initial_estimate',
    'algorithm_version': 'content-fit-v1',
    'computed_at_ms': 1700000000000,
    'input_fingerprint':
        '0000000000000000000000000000000000000000000000000000000000000000',
  };

  const fixture = {
    'media': {
      'id': 'media-1',
      'path': '/tmp/library.mp4',
      'fingerprint': 'library-fp',
      'title': 'Library',
      'kind': 'video',
      'duration': 90000,
      'availability': 'available',
      'created_at_ms': 1700000000000,
      'updated_at_ms': 1700000001000,
    },
    'primary_track_id': 'track-1',
    'fit': fitFixture,
    'triage_intent': null,
    'familiar_material': false,
  };

  group('MediaLibraryEntry', () {
    test('parses the wire shape', () {
      final entry = MediaLibraryEntry.fromJson(fixture);
      expect(entry.media.id, 'media-1');
      expect(entry.media.title, 'Library');
      expect(entry.media.kind, 'video');
      expect(entry.media.durationMs, 90000);
      expect(entry.primaryTrackId, 'track-1');
      expect(entry.fit?.meaning.fit, 'comprehensible');
      expect(entry.triageIntent, isNull);
      expect(entry.familiarMaterial, isFalse);
      expect(entry.isGoldenTarget, isTrue);
    });

    test('tolerates absent fit, track, and duration', () {
      final entry = MediaLibraryEntry.fromJson({
        ...fixture,
        'media': {
          ...(fixture['media']! as Map),
          'duration': null,
        },
        'primary_track_id': null,
        'fit': null,
      });
      expect(entry.fit, isNull);
      expect(entry.primaryTrackId, isNull);
      expect(entry.media.durationMs, isNull);
      expect(entry.isGoldenTarget, isFalse);
      expect(entry.triageQueue(), isNull);
    });

    test('round-trips through toJson', () {
      final entry = MediaLibraryEntry.fromJson(fixture);
      final roundTripped = MediaLibraryEntry.fromJson(entry.toJson());
      expect(roundTripped.toJson(), entry.toJson());
    });
  });

  group('triage queue derivation (heuristic_proxy, presentation view)', () {
    MediaLibraryEntry entry({
      String meaning = 'comprehensible',
      String sound = 'challenging',
      String? intent,
      bool familiar = false,
      bool withFit = true,
    }) => MediaLibraryEntry.fromJson({
      ...fixture,
      'fit': withFit
          ? {
              ...fitFixture,
              'meaning': {'fit': meaning, 'signals': <Object>[]},
              'sound': {'fit': sound, 'signals': <Object>[]},
            }
          : null,
      'triage_intent': intent,
      'familiar_material': familiar,
    });

    test('golden target goes to the intensive queue', () {
      expect(entry().triageQueue(), TriageQueue.intensive);
      expect(
        entry(meaning: 'too_easy', sound: 'too_hard').triageQueue(),
        TriageQueue.intensive,
      );
    });

    test('too-hard dimensions defer, the rest is extensive material', () {
      expect(
        entry(meaning: 'too_hard', sound: 'comprehensible').triageQueue(),
        TriageQueue.deferred,
      );
      expect(
        entry(meaning: 'challenging', sound: 'too_hard').triageQueue(),
        TriageQueue.deferred,
      );
      expect(
        entry(meaning: 'comprehensible', sound: 'comprehensible').triageQueue(),
        TriageQueue.extensive,
      );
      expect(
        entry(meaning: 'challenging', sound: 'challenging').triageQueue(),
        TriageQueue.extensive,
      );
    });

    test('explicit user intent always wins', () {
      expect(
        entry(intent: 'defer').triageQueue(),
        TriageQueue.deferred,
      );
      expect(
        entry(meaning: 'too_hard', intent: 'pin_extensive').triageQueue(),
        TriageQueue.extensive,
      );
      expect(
        entry(withFit: false, intent: 'pin_intensive').triageQueue(),
        TriageQueue.intensive,
      );
    });

    test('familiar material feeds extensive only while the supply is on', () {
      final familiar = entry(familiar: true);
      expect(familiar.triageQueue(), TriageQueue.extensive);
      expect(
        familiar.triageQueue(familiarSupply: false),
        TriageQueue.intensive,
      );
      // Intent still outranks the familiar supply.
      expect(
        entry(familiar: true, intent: 'defer').triageQueue(),
        TriageQueue.deferred,
      );
    });
  });
}
