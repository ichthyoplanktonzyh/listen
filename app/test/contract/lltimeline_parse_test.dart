import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/timeline.dart';

Map<String, dynamic> _loadFixture(String name) {
  final file = File('../../testdata/rhythm-frame-qa/$name');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

List<Cue> _segments(Map<String, dynamic> json) =>
    ((json['segments'] as List<dynamic>?) ?? const [])
        .map(
          (value) => _cueFromLLTimelineSegment(value as Map<String, dynamic>),
        )
        .toList(growable: false);

Cue _cueFromLLTimelineSegment(Map<String, dynamic> json) => Cue.fromJson({
  'id': json['id'],
  'index': json['index'],
  'start': json['start_ms'],
  'end': json['end_ms'],
  'display_text': json['display_text'] ?? json['text'],
  'tokens': (json['tokens'] as List<dynamic>?) ?? const [],
});

List<WordTimeline> _wordTimelines(Map<String, dynamic> json) =>
    ((json['word_timelines'] as List<dynamic>?) ?? const [])
        .map((value) => WordTimeline.fromJson(value as Map<String, dynamic>))
        .toList(growable: false);

List<PhoneTimeline> _phoneTimelines(Map<String, dynamic> json) {
  final metadata = json['metadata'] as Map<String, dynamic>;
  final media = metadata['media'] as Map<String, dynamic>;
  return ((json['phone_timelines'] as List<dynamic>?) ?? const [])
      .map(
        (value) => _phoneTimelineFromLLTimelineResource(
          value as Map<String, dynamic>,
          mediaId: media['id'] as String,
          createdAtMs: metadata['created_at_ms'] as int,
        ),
      )
      .toList(growable: false);
}

PhoneTimeline _phoneTimelineFromLLTimelineResource(
  Map<String, dynamic> json, {
  required String mediaId,
  required int createdAtMs,
}) {
  final soundAnalysis = json['sound_analysis'] as Map<String, dynamic>?;
  return PhoneTimeline.fromJson({
    'id': json['id'],
    'track_id': json['track_id'] ?? 'fixture-track',
    'media_id': json['media_id'] ?? mediaId,
    'sentence_id': json['sentence_id'],
    'parent_word_timeline_id': json['parent_word_timeline_id'],
    'parent_phonetic_analysis_id': json['parent_phonetic_analysis_id'],
    'provider_id': json['provider_id'] ?? soundAnalysis?['provider_id'],
    'provider_version':
        json['provider_version'] ?? soundAnalysis?['provider_version'],
    'model_id': json['model_id'],
    'model_revision':
        json['model_revision'] ?? soundAnalysis?['model_revision'],
    'phone_set': json['phone_set'] ?? soundAnalysis?['phone_set'],
    'precision': json['precision'] ?? 'fixture',
    'created_by': json['created_by'] ?? 'fixture',
    'status': json['status'],
    'metrics_json': json['metrics_json'] ?? const {},
    'phones': json['phones'] ?? json['detected_phones'] ?? const [],
    'alignments': json['alignments'] ?? const [],
    'findings': json['findings'] ?? const [],
    'sound_analysis': soundAnalysis == null
        ? null
        : _soundAnalysisFromLLTimelineResource(soundAnalysis),
    'created_at_ms': json['created_at_ms'] ?? createdAtMs,
    'updated_at_ms': json['updated_at_ms'] ?? createdAtMs,
  });
}

Map<String, dynamic> _soundAnalysisFromLLTimelineResource(
  Map<String, dynamic> json,
) {
  final phoneSet = json['phone_set'] as String? ?? 'arpabet';
  return {
    ...json,
    'phone_set': phoneSet,
    'learning_phones': ((json['learning_phones'] as List<dynamic>?) ?? const [])
        .map((value) {
          final phone = Map<String, dynamic>.from(value as Map);
          return {
            ...phone,
            'phone_set': phone['phone_set'] ?? phoneSet,
            'evidence': phone['evidence'] ?? 'fixture',
          };
        })
        .toList(growable: false),
  };
}

void _expectAudibleStructure(RhythmFrame frame) {
  expect(frame.generatedFrom, isNotEmpty);
  expect(frame.references.citation.source, isNotEmpty);
  expect(frame.references.defaultConnected, isNotNull);
  expect(frame.references.defaultConnected!.source, isNotEmpty);
  expect(frame.references.actual.source, isNotEmpty);
  expect(frame.stressAnchors, isNotEmpty);
  expect(frame.nuclei, isNotEmpty);
  expect(frame.weakGroups, isNotEmpty);
  expect(frame.phraseBoundaries, isNotEmpty);
  expect(frame.listeningHotspots, isNotEmpty);
  expect(frame.quality.timingSource, isNotEmpty);
  expect(frame.quality.rhythmConfidence, greaterThan(0));
}

void main() {
  test(
    'committed document-level rhythm fixture parses through typed models',
    () {
      final json = _loadFixture('fixture-no-phone-rhythm.lltimeline.json');
      final document = LLTimelineDocument.fromJson(json);
      final segments = _segments(json);
      final wordTimelines = _wordTimelines(json);

      expect(document.schema, 'llplayer.timeline.v1');
      expect(segments, hasLength(1));
      expect(segments.single.id, 'fixture-no-phone-s1');
      expect(segments.single.text, contains('could have'));
      expect(
        segments.single.tokens.where((token) => token.kind == 'word'),
        isNotEmpty,
      );

      expect(wordTimelines, hasLength(1));
      expect(wordTimelines.single.words, isNotEmpty);
      expect(wordTimelines.single.status, 'active');
      expect(wordTimelines.single.words.first.text, 'I');
      expect(wordTimelines.single.words.first.source, 'forced_aligned');
      expect(wordTimelines.single.words.first.provider, 'fixture-aligner');
      expect(
        wordTimelines.single.words.every((word) => word.start < word.end),
        isTrue,
      );

      expect(document.rhythmFrames, hasLength(1));
      expect(
        document.rhythmFrames.single.parentWordTimelineId,
        wordTimelines.single.id,
      );
      final frame = document.rhythmFrameForSentence(segments.single.id);
      expect(frame, isNotNull);
      _expectAudibleStructure(frame!);
      expect(frame.references.citation.source, 'dictionary_lexical_stress');
      expect(
        frame.references.defaultConnected!.source,
        'english_connected_speech_rules_v1',
      );
      expect(frame.references.actual.source, contains('word_timeline'));
      expect(frame.quality.timingSource, 'word_timeline');
      expect(frame.quality.connectedSpeechSource, 'text_prior');
      expect(frame.quality.phoneEvidenceCoverage, 0.0);
    },
  );

  test(
    'committed phone-timeline rhythm fixture parses fallback sound analysis',
    () {
      final json = _loadFixture('fixture-rhythm.lltimeline.json');
      final document = LLTimelineDocument.fromJson(json);
      final segments = _segments(json);
      final phoneTimelines = _phoneTimelines(json);

      expect(document.schema, 'llplayer.timeline.v1');
      expect(document.rhythmFrames, isEmpty);
      expect(segments.length, greaterThanOrEqualTo(2));
      expect(segments.first.text, contains('could have'));

      expect(phoneTimelines.length, greaterThanOrEqualTo(2));
      for (final timeline in phoneTimelines) {
        expect(timeline.status, isNotEmpty);
        expect(timeline.soundAnalysis, isNotNull);
        expect(timeline.soundAnalysis!.rhythmFrame, isNotNull);
        final frame = timeline.soundAnalysis!.rhythmFrame!;
        _expectAudibleStructure(frame);
        expect(frame.references.actual.source, 'word_timeline_duration_energy');
        expect(frame.quality.timingSource, 'word_timeline');
        expect(frame.quality.prominenceSources, contains('energy'));
        expect(frame.quality.connectedSpeechSource, 'phone_segmental');
        expect(frame.quality.phoneEvidenceCoverage, greaterThan(0));
      }
    },
  );
}
