import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/services/composition_core_projection.dart';

/// Projects Core's LLTimeline export of one adopted package — where every
/// sentence id is already a global `SubtitleSentenceId` — onto the
/// composition enhancement shapes.
void main() {
  test('projects every package analysis family from the Core document', () {
    final track = SubtitleTrack.fromJson(_trackJson);

    final projection = projectCompositionResourcesFromCore(
      track: track,
      documentJson: _documentJson,
    );

    final timings = projection.timingsBySentence['sentence-global']!;
    expect(timings.map((word) => word.tokenIndex), [0, 2]);
    expect(timings.first.start, const Duration(milliseconds: 120));
    expect(timings.first.end, const Duration(milliseconds: 300));
    expect(timings.first.source, 'forced_aligned');
    expect(timings.first.provider, 'listen-gen');

    final group = projection.senseGroupsBySentence['sentence-global']!.single;
    expect(group.text, 'Hello world');
    expect(group.startTokenIndex, 0);
    expect(group.endTokenIndex, 3);

    final partition = projection.chunkPartitionsBySentence['sentence-global']!;
    final chunk = partition.chunks.single;
    expect(chunk.start, const Duration(milliseconds: 120));
    expect(chunk.end, const Duration(milliseconds: 680));
    expect(chunk.text, 'Hello world');
    expect(partition.timingQuality, 'forced_aligned');

    final acoustic = projection.acousticsBySentence['sentence-global']!.single;
    expect(acoustic.energy['delta_db'], 5.5);
    expect(acoustic.pitch['median_f0_hz'], 182.0);
    expect(acoustic.duration['duration_ms'], 260);
    expect(acoustic.voicedFrameRatio, 0.92);

    final anchor =
        projection.prosodyAnchorsBySentence['sentence-global']!.single;
    expect(anchor.lexicalStress, 'primary');
    expect(anchor.realizedProminence, 0.8);
    expect(anchor.evidence, ['energy', 'pitch']);

    final phones = projection.phonesBySentence['sentence-global']!;
    expect(phones.map((phone) => phone.symbol), ['h', 'ə']);
    expect(phones.first.tokenIndex, 0);
    expect(phones.first.phoneSet, 'ipa');
  });

  test('prefers the package candidate over another track resource', () {
    final documentJson = Map<String, dynamic>.from(_documentJson);
    documentJson['word_timelines'] = [
      {
        'id': 'other-word-timeline',
        'track_id': 'package-track',
        'media_id': 'media-1',
        'algorithm_id': 'other',
        'algorithm_version': 'v1',
        'config_hash': 'other',
        'parent_timeline_id': null,
        'created_by': 'algorithm',
        'status': 'active',
        'metrics_json': <String, dynamic>{},
        'words': [
          {
            'sentence_id': 'sentence-global',
            'token_index': 0,
            'text': 'Hello',
            'start_ms': 999,
            'end_ms': 1000,
            'timing_source': 'estimated',
            'provider_id': 'other',
            'provider_version': 'v1',
          },
        ],
        'created_at_ms': 1,
        'updated_at_ms': 1,
      },
      _documentJson['word_timelines']![0],
    ];
    final projection = projectCompositionResourcesFromCore(
      track: SubtitleTrack.fromJson(_trackJson),
      documentJson: documentJson,
    );

    expect(
      projection.timingsBySentence['sentence-global']!.every(
        (word) => word.provider == 'listen-gen',
      ),
      isTrue,
    );
  });

  test('a chunk no timing covers is dropped rather than given a window', () {
    final documentJson = Map<String, dynamic>.from(_documentJson);
    final prosody = (documentJson['prosody_analyses'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .first;
    prosody['chunks'] = [
      {
        'sentence_id': 'sentence-global',
        'chunk_index': 0,
        'start_token_index': 0,
        'end_token_index': 3,
        'nucleus_token_index': null,
        'confidence': 0.8,
      },
    ];
    documentJson['word_timelines'] = const <Object?>[];
    documentJson['artifacts'] = const <Object?>[];
    documentJson['phone_timelines'] = const <Object?>[];
    documentJson['sense_group_analyses'] = const <Object?>[];

    final projection = projectCompositionResourcesFromCore(
      track: SubtitleTrack.fromJson(_trackJson),
      documentJson: documentJson,
    );

    expect(projection.chunkPartitionsBySentence, isEmpty);
    expect(projection.timingsBySentence, isEmpty);
  });

  test('an empty export projects to nothing, without throwing', () {
    final projection = projectCompositionResourcesFromCore(
      track: SubtitleTrack.fromJson(_trackJson),
      documentJson: {
        'schema': 'llplayer.timeline.v1',
        'metadata': _documentJson['metadata'],
        'active_word_timeline_id': null,
        'active_phone_timeline_id': null,
        'active_prosody_analysis_id': null,
        'prosody_analyses': const <Object?>[],
        'rhythm_frames': const <Object?>[],
        'artifacts': const <Object?>[],
      },
    );

    expect(projection.isEmpty, isTrue);
  });
}

final _trackJson = <String, dynamic>{
  'id': 'package-track',
  'media_id': 'media-1',
  'fingerprint': 'package-track-fingerprint',
  'language': 'en',
  'source': 'package:subtitle_text_track',
  'status': 'available',
  'sentences': [
    {
      'id': 'sentence-global',
      'index': 0,
      'start': 100,
      'end': 900,
      'display_text': 'Hello world.',
      'tokens': [
        {'index': 0, 'kind': 'word', 'text': 'Hello', 'normalized': 'hello'},
        {'index': 1, 'kind': 'whitespace', 'text': ' ', 'normalized': null},
        {'index': 2, 'kind': 'word', 'text': 'world', 'normalized': 'world'},
        {'index': 3, 'kind': 'punctuation', 'text': '.', 'normalized': null},
      ],
    },
  ],
};

final _documentJson = <String, dynamic>{
  'schema': 'llplayer.timeline.v1',
  'metadata': {
    'created_at_ms': 1,
    'generator': {
      'id': 'listen-resource-package',
      'version': 'v3',
      'mode': 'adopted_package',
    },
    'media': {
      'id': 'media-1',
      'fingerprint': 'media-fingerprint',
      'path': null,
      'title': 'Media',
      'duration_ms': 2000,
    },
    'language': 'en',
    'human_reviewed': false,
    'extra': {
      'track_id': 'package-track',
      'track_fingerprint': 'package-track-fingerprint',
      'track_source': 'package:subtitle_text_track',
    },
  },
  'word_timelines': [
    {
      'id': 'package-word-timeline',
      'track_id': 'package-track',
      'media_id': 'media-1',
      'algorithm_id': 'listen-gen',
      'algorithm_version': 'v1',
      'config_hash': 'config',
      'parent_timeline_id': null,
      'created_by': 'algorithm',
      'status': 'candidate',
      'metrics_json': {'exchange_source': 'package:subtitle_text_track'},
      'words': [
        {
          'sentence_id': 'sentence-global',
          'token_index': 2,
          'text': 'world',
          'start_ms': 320,
          'end_ms': 680,
          'confidence': 0.96,
          'timing_source': 'forced_aligned',
          'provider_id': 'listen-gen',
          'provider_version': 'v1',
        },
        {
          'sentence_id': 'sentence-global',
          'token_index': 0,
          'text': 'Hello',
          'start_ms': 120,
          'end_ms': 300,
          'confidence': 0.97,
          'timing_source': 'forced_aligned',
          'provider_id': 'listen-gen',
          'provider_version': 'v1',
        },
      ],
      'created_at_ms': 1,
      'updated_at_ms': 1,
    },
  ],
  'active_word_timeline_id': null,
  'phone_timelines': [
    {
      'id': 'package-phone',
      'track_id': 'package-track',
      'media_id': 'media-1',
      'sentence_id': 'sentence-global',
      'parent_word_timeline_id': 'package-word-timeline',
      'parent_phonetic_analysis_id': null,
      'provider_id': 'listen-gen',
      'provider_version': 'v1',
      'model_id': null,
      'model_revision': 'v1',
      'phone_set': 'ipa',
      'precision': 'detected',
      'created_by': 'algorithm',
      'status': 'candidate',
      'metrics_json': {'exchange_source': 'package:subtitle_text_track'},
      'phones': [
        {
          'symbol': 'h',
          'display_ipa': 'h',
          'phone_set': 'ipa',
          'start_ms': 120,
          'end_ms': 160,
          'confidence': 0.94,
          'token_index': 0,
          'provider_id': 'listen-gen',
          'provider_version': 'v1',
          'model_revision': 'v1',
        },
        {
          'symbol': 'ə',
          'display_ipa': 'ə',
          'phone_set': 'ipa',
          'start_ms': 160,
          'end_ms': 220,
          'confidence': 0.91,
          'token_index': 0,
          'provider_id': 'listen-gen',
          'provider_version': 'v1',
          'model_revision': 'v1',
        },
      ],
      'alignments': const <Object?>[],
      'findings': const <Object?>[],
      'created_at_ms': 1,
      'updated_at_ms': 1,
    },
  ],
  'active_phone_timeline_id': null,
  'sense_group_analyses': [
    {
      'id': 'package-sense-groups',
      'track_id': 'package-track',
      'media_id': 'media-1',
      'parent_word_timeline_id': 'package-word-timeline',
      'provider_id': 'listen-gen',
      'provider_version': 'v1',
      'algorithm': 'listen-resource-package',
      'created_by': 'algorithm',
      'status': 'candidate',
      'metrics_json': {'exchange_source': 'package:subtitle_text_track'},
      'groups': [
        {
          'id': 'group-1',
          'sentence_id': 'sentence-global',
          'group_index': 0,
          'start_token_index': 0,
          'end_token_index': 3,
          'text': 'Hello world',
          'label': null,
          'head_token_index': 0,
          'confidence': 0.9,
          'sources': ['syntax'],
        },
      ],
      'created_at_ms': 1,
      'updated_at_ms': 1,
    },
  ],
  'active_sense_group_analysis_id': null,
  'prosody_analyses': [
    {
      'id': 'package-prosody',
      'track_id': 'package-track',
      'media_id': 'media-1',
      'parent_word_timeline_id': 'package-word-timeline',
      'provider_id': 'listen-gen',
      'provider_version': 'v1',
      'algorithm': 'listen-resource-package',
      'status': 'candidate',
      'created_by': 'algorithm',
      'metrics_json': {'exchange_source': 'package:subtitle_text_track'},
      'chunks': [
        {
          'sentence_id': 'sentence-global',
          'chunk_index': 0,
          'start_token_index': 0,
          'end_token_index': 2,
          'nucleus_token_index': 0,
          'confidence': 0.89,
        },
      ],
      'anchors': [
        {
          'word_ref': {'sentence_id': 'sentence-global', 'token_index': 0},
          'syllable_index': null,
          'lexical_stress': 'primary',
          'realized_prominence': 0.8,
          'utterance_role': 'nucleus',
          'evidence': ['energy', 'pitch'],
          'confidence': 0.75,
        },
      ],
      'created_at_ms': 1,
      'updated_at_ms': 1,
    },
  ],
  'active_prosody_analysis_id': null,
  'rhythm_frames': const <Object?>[],
  'artifacts': [
    {
      'kind': 'rhythm_word_acoustic_cues',
      'provider_id': 'listen-gen',
      'provider_version': 'v1',
      'payload': {
        'status': 'scored',
        'line': 'sound',
        'resource_id': 'package-acoustics',
        'exchange_source': 'package:subtitle_text_track',
        'timeline_id': 'package-word-timeline',
        'sample_rate_hz': 16000,
        'cues': [
          {
            'sentence_id': 'sentence-global',
            'token_index': 0,
            'text': 'Hello',
            'start_ms': 120,
            'end_ms': 300,
            'energy': {
              'rms_dbfs': -22.0,
              'local_baseline_dbfs': -27.5,
              'delta_db': 5.5,
              'prominence': 0.8,
            },
            'pitch': {
              'median_f0_hz': 182.0,
              'local_baseline_f0_hz': 168.0,
              'delta_semitones': 1.4,
              'range_semitones': 2.0,
              'prominence': 0.75,
              'reset_after': 0.2,
            },
            'duration': {'duration_ms': 260, 'local_ratio': 1.25},
            'voiced_frame_ratio': 0.92,
          },
        ],
      },
    },
  ],
};
