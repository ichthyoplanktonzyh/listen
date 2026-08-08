import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/backend_event.dart';

/// Consumer side of the SSE payload contract. The committed golden envelopes
/// are copied from the locked core contract artifact; this test parses them
/// through `BackendEvent.fromJson`, so a producer payload change that breaks
/// typed parsing fails during an explicit backend dependency update.
void main() {
  final file = File('test/fixtures/events/examples.json');
  final doc = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final examples = (doc['examples'] as List<dynamic>)
      .cast<Map<String, dynamic>>();
  final parsed = <String, BackendEvent>{
    for (final example in examples)
      example['event'] as String: BackendEvent.fromJson(example),
  };

  test('every golden envelope parses into a typed backend event', () {
    expect(parsed, isNotEmpty);
    for (final entry in parsed.entries) {
      expect(
        entry.value,
        isNot(isA<UnknownBackendEvent>()),
        reason:
            'golden example "${entry.key}" fell through to '
            'UnknownBackendEvent; BackendEvent.fromJson and '
            'locked events/examples.json and BackendEvent.fromJson disagree',
      );
    }
  });

  test('word-timings-completed fields survive the wire shape', () {
    final event = parsed['word-timings-completed'] as WordTimingsCompletedEvent;
    expect(event.trackId, isNotEmpty);
    expect(event.count, greaterThan(0));
    expect(event.line, isNotNull);
    expect(event.timelineId, isNotNull);
  });

  test('sound-line-completed fields survive the wire shape', () {
    final event = parsed['sound-line-completed'] as SoundLineCompletedEvent;
    expect(event.trackId, isNotEmpty);
    expect(event.timelineId, isNotNull);
    expect(event.acousticCueCount, greaterThan(0));
  });

  test('phonetic-analysis-job-changed fields survive the wire shape', () {
    final event =
        parsed['phonetic-analysis-job-changed']
            as PhoneticAnalysisJobChangedEvent;
    expect(event.status, isNot('unknown'));
    expect(event.phaseProgress, greaterThan(0));
    expect(event.trackId, isNotNull);
  });

  test(
    'lexical-entry-changed parses full entry details with capability profile',
    () {
      final event = parsed['lexical-entry-changed'] as LexicalEntryChangedEvent;
      expect(event.entry.normalizedForm, isNotEmpty);
      expect(event.normalizedForm, event.entry.normalizedForm);
      final profile = event.details.capabilityProfile;
      expect(profile, isNotNull);
      expect(
        profile!.reading.effectiveAssessment,
        anyOf('unassessed', 'not_acquired', 'acquired'),
      );
      expect(
        profile.listening.effectiveAssessment,
        anyOf('unassessed', 'not_acquired', 'acquired'),
      );
    },
  );

  test('lexical-capability-changed fields survive the wire shape', () {
    final event =
        parsed['lexical-capability-changed'] as LexicalCapabilityChangedEvent;
    expect(event.lexicalEntryId, isNotEmpty);
    expect(
      event.capability,
      anyOf('reading', 'listening', 'speaking', 'writing'),
    );
    expect(
      event.effectiveAssessment,
      anyOf('unassessed', 'not_acquired', 'acquired'),
    );
  });
}
